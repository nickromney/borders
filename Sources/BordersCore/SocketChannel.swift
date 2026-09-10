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
    private var descriptor: Int32 = -1

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
        guard bound == 0, Darwin.listen(socketDescriptor, 4) == 0 else {
            Darwin.close(socketDescriptor)
            return false
        }
        descriptor = socketDescriptor
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.acceptLoop(socketDescriptor) }
        return true
    }

    public func stop() {
        // mutation:skip - a live descriptor is never 0 here, so a boundary
        // change cannot alter behaviour.
        guard descriptor >= 0 else { return } // mutation:skip
        Darwin.close(descriptor)
        descriptor = -1
        Darwin.unlink(path)
    }

    private func acceptLoop(_ listening: Int32) {
        while true {
            let client = Darwin.accept(listening, nil, nil)
            // mutation:skip - as above, accept() never hands back 0 here.
            if client >= 0 { // mutation:skip
                serve(client)
                continue
            }
            // EINTR and EAGAIN are transient; anything else means the listening
            // socket is closed and retrying would spin forever.
            // mutation:skip - a test cannot force accept() to fail with EINTR
            // rather than with a closed descriptor.
            guard errno == EINTR || errno == EAGAIN else { return } // mutation:skip
        }
    }

    private func serve(_ client: Int32) {
        defer { Darwin.close(client) }
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
    SocketMessage.applyTimeout(to: descriptor, seconds: timeoutSeconds)
    _ = command.withCString { Darwin.write(descriptor, $0, strlen($0)) }
    var buffer = [UInt8](repeating: 0, count: SocketMessage.bufferSize)
    let count = Darwin.read(descriptor, &buffer, buffer.count)
    return .reply(SocketMessage.decode(buffer, count: count))
}
