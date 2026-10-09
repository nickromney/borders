import Darwin
import Foundation

public enum SocketAddress {
    /// The largest path a Unix domain socket address can hold, including its
    /// terminating null byte.
    public static let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    /// Copy `path` into `sun_path`, refusing a path that would not fit.
    ///
    /// `sun_path` is a fixed buffer. Copying a longer path used to overrun the
    /// surrounding struct.
    public static func fill(_ address: inout sockaddr_un, with path: String) -> Bool {
        let bytes = Array(path.utf8CString)
        guard bytes.count <= pathCapacity else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        return true
    }

    public static func make(path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard fill(&address, with: path) else { return nil }
        return address
    }

    public static func withSockaddr<T>(_ address: inout sockaddr_un,
                                       _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

/// The bytes a request or reply may occupy on the control socket.
public enum SocketMessage {
    public static let bufferSize = 512

    /// How long either side waits for the other before giving up.
    ///
    /// Without this a wedged peer holds the caller open indefinitely, which
    /// for a command-line client means a shell that never returns.
    public static let timeoutSeconds = 2.0

    /// Apply the read and write timeout to one socket.
    @discardableResult
    public static func applyTimeout(to descriptor: Int32, seconds: Double = timeoutSeconds) -> Bool {
        // A positive value smaller than one microsecond truncates to zero,
        // which disables the kernel timeout instead of shortening it.
        guard seconds.isFinite, seconds >= 0.000001, seconds < Double(Int.max) else { return false }
        let whole = Int(seconds)
        var value = timeval(tv_sec: whole, tv_usec: Int32((seconds - Double(whole)) * 1_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, size) == 0 else { return false }
        return setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, size) == 0
    }

    public static func decode(_ buffer: [UInt8], count: Int) -> String {
        String(bytes: buffer.prefix(max(0, count)), encoding: .utf8) ?? ""
    }
}

/// A local Unix-socket control channel.
///
/// The handler is called once per connection with the request text, and its
/// return value is written back as the reply.
public final class CommandChannel {
    public let path: String
    private let handler: (String) -> String
    private var listener: DispatchSourceRead?

    public init(path: String, handler: @escaping (String) -> String) {
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    /// Bind and start accepting, reporting whether the channel came up.
    ///
    /// A failed bind used to be ignored, which left an accept loop spinning on
    /// an unusable descriptor and burning a core for the life of the app.
    @discardableResult
    public func start() -> Bool {
        guard listener == nil else { return false }
        Darwin.unlink(path)
        guard var address = SocketAddress.make(path: path) else { return false }
        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        // mutation:skip - socket() returns -1 or a valid descriptor, so a
        // boundary change here only differs for descriptor 0, which a test
        // cannot arrange.
        guard socketDescriptor >= 0 else { return false } // mutation:skip
        let bound = SocketAddress.withSockaddr(&address) { pointer, length in
            Darwin.bind(socketDescriptor, pointer, length)
        }
        guard bound == 0, Darwin.listen(socketDescriptor, 4) == 0,
              fcntl(socketDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
            Darwin.close(socketDescriptor)
            return false
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor,
                                                   queue: .global(qos: .utility))
        source.setEventHandler { [handler] in
            Self.acceptReady(socketDescriptor, handler: handler)
        }
        // Cancellation drains any active handler before closing. The old
        // source can never accept on a descriptor recycled for a new listener.
        source.setCancelHandler { Darwin.close(socketDescriptor) }
        listener = source
        source.resume()
        return true
    }

    public func stop() {
        guard let source = listener else { return }
        listener = nil
        source.cancel()
        Darwin.unlink(path)
    }

    private static func acceptReady(_ listening: Int32, handler: (String) -> String) {
        let client = Darwin.accept(listening, nil, nil)
        guard client >= 0 else { return }
        serve(client, handler: handler)
    }

    private static func serve(_ client: Int32, handler: (String) -> String) {
        defer { Darwin.close(client) }
        // Darwin inherits O_NONBLOCK from the listener. Requests still use the
        // bounded blocking read, so do not treat data not yet sent as empty.
        let flags = fcntl(client, F_GETFL)
        guard flags >= 0, fcntl(client, F_SETFL, flags & ~O_NONBLOCK) == 0 else { return }
        SocketMessage.applyTimeout(to: client)
        var buffer = [UInt8](repeating: 0, count: SocketMessage.bufferSize)
        let count = Darwin.read(client, &buffer, buffer.count)
        let reply = handler(SocketMessage.decode(buffer, count: count))
        _ = reply.withCString { Darwin.write(client, $0, strlen($0)) }
    }
}

/// The outcome of sending one command to a running app.
public enum ChannelReply: Equatable {
    case reply(String)
    case notRunning
    case unusablePath
    case timedOut
    case noResponse
    case communicationFailed
}

/// Send one command over the control socket and read the reply.
public func sendCommand(_ command: String, path: String,
                        timeoutSeconds: Double = SocketMessage.timeoutSeconds) -> ChannelReply {
    guard var address = SocketAddress.make(path: path) else { return .unusablePath }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    // mutation:skip - see CommandChannel.start; only descriptor 0 would differ.
    guard descriptor >= 0 else { return .notRunning } // mutation:skip
    defer { Darwin.close(descriptor) }
    let connected = SocketAddress.withSockaddr(&address) { pointer, length in
        Darwin.connect(descriptor, pointer, length)
    }
    guard connected == 0 else { return .notRunning }
    guard SocketMessage.applyTimeout(to: descriptor, seconds: timeoutSeconds) else {
        return .communicationFailed
    }
    return exchange(command, descriptor: descriptor)
}

private func exchange(_ command: String, descriptor: Int32) -> ChannelReply {
    let written = command.withCString { Darwin.write(descriptor, $0, strlen($0)) }
    guard written == command.utf8.count else { return .communicationFailed }
    var buffer = [UInt8](repeating: 0, count: SocketMessage.bufferSize)
    let count = Darwin.read(descriptor, &buffer, buffer.count)
    if count < 0 {
        // Darwin defines EWOULDBLOCK as EAGAIN.
        return errno == EAGAIN ? .timedOut : .communicationFailed
    }
    guard count > 0 else { return .noResponse }
    return .reply(SocketMessage.decode(buffer, count: count))
}
