import Darwin
import XCTest
@testable import BordersCore

final class SocketAddressTests: XCTestCase {
    func testAPathThatFitsIsCopiedWithItsTerminator() {
        var address = sockaddr_un()
        XCTAssertTrue(SocketAddress.fill(&address, with: "/tmp/borders.sock"))
        let copied = withUnsafeBytes(of: &address.sun_path) { bytes -> String in
            String(cString: bytes.bindMemory(to: CChar.self).baseAddress!)
        }
        XCTAssertEqual(copied, "/tmp/borders.sock")
    }

    func testTheLongestFittingPathIsAccepted() {
        var address = sockaddr_un()
        let path = String(repeating: "a", count: SocketAddress.pathCapacity - 1)
        XCTAssertTrue(SocketAddress.fill(&address, with: path))
    }

    func testAnOverlongPathIsRefusedRatherThanTruncated() {
        var address = sockaddr_un()
        let path = String(repeating: "a", count: SocketAddress.pathCapacity)
        XCTAssertFalse(SocketAddress.fill(&address, with: path))
        XCTAssertNil(SocketAddress.make(path: path))
    }

    func testMakeSetsTheUnixFamily() {
        let address = SocketAddress.make(path: "/tmp/borders.sock")
        XCTAssertEqual(address?.sun_family, sa_family_t(AF_UNIX))
    }
}

final class SocketMessageTests: XCTestCase {
    func testDecodeReadsOnlyTheBytesReceived() {
        var buffer = [UInt8](repeating: 0, count: 8)
        buffer.replaceSubrange(0..<6, with: Array("status".utf8))
        XCTAssertEqual(SocketMessage.decode(buffer, count: 6), "status")
    }

    func testDecodeToleratesAFailedRead() {
        XCTAssertEqual(SocketMessage.decode([UInt8](repeating: 0, count: 4), count: -1), "")
    }
}

final class CommandChannelTests: XCTestCase {
    private var path = ""

    override func setUp() {
        super.setUp()
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("borders-test-\(UUID().uuidString.prefix(8)).sock").path
    }

    func testCommandsRoundTripOverTheSocket() throws {
        let channel = CommandChannel(path: path) { "seen:\($0)" }
        XCTAssertTrue(channel.start())
        defer { channel.stop() }
        XCTAssertEqual(sendCommand("status", path: path), .reply("seen:status"))
        XCTAssertEqual(sendCommand("off", path: path), .reply("seen:off"))
    }

    func testTheChannelReplacesAStaleSocketFile() throws {
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        let channel = CommandChannel(path: path) { _ in "ok" }
        XCTAssertTrue(channel.start())
        defer { channel.stop() }
        XCTAssertEqual(sendCommand("status", path: path), .reply("ok"))
    }

    func testAnUnbindablePathFailsToStart() {
        let channel = CommandChannel(path: "/does/not/exist/borders.sock") { _ in "ok" }
        XCTAssertFalse(channel.start())
    }

    func testAnOverlongPathFailsToStart() {
        let channel = CommandChannel(path: String(repeating: "a", count: 400)) { _ in "ok" }
        XCTAssertFalse(channel.start())
    }

    func testSendingToNothingReportsTheAppIsNotRunning() {
        XCTAssertEqual(sendCommand("status", path: path), .notRunning)
    }

    func testSendingToAnOverlongPathReportsAnUnusablePath() {
        XCTAssertEqual(sendCommand("status", path: String(repeating: "a", count: 400)), .unusablePath)
    }

    func testStoppingRemovesTheSocketAndStopsAnswering() {
        let channel = CommandChannel(path: path) { _ in "ok" }
        XCTAssertTrue(channel.start())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        channel.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(sendCommand("status", path: path), .notRunning)
    }

    func testStoppingTwiceIsHarmless() {
        let channel = CommandChannel(path: path) { _ in "ok" }
        XCTAssertTrue(channel.start())
        channel.stop()
        channel.stop()
    }
}

final class SocketTimeoutTests: XCTestCase {
    func testTimeoutIsAppliedToASocket() {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { Darwin.close(descriptor) }
        XCTAssertTrue(SocketMessage.applyTimeout(to: descriptor, seconds: 1.5))
        var value = timeval()
        var size = socklen_t(MemoryLayout<timeval>.size)
        XCTAssertEqual(getsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, &size), 0)
        XCTAssertEqual(value.tv_sec, 1)
        XCTAssertEqual(value.tv_usec, 500_000)
    }

    func testTimeoutOnAClosedSocketIsReported() {
        XCTAssertFalse(SocketMessage.applyTimeout(to: -1))
    }

    func testAServerThatNeverAnswersDoesNotHangTheClient() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("borders-silent-\(UUID().uuidString.prefix(8)).sock").path
        let listening = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try XCTUnwrap(SocketAddress.make(path: path))
        let bound = SocketAddress.withSockaddr(&address) { pointer, length in
            Darwin.bind(listening, pointer, length)
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(Darwin.listen(listening, 1), 0)
        defer {
            Darwin.close(listening)
            try? FileManager.default.removeItem(atPath: path)
        }
        // Nothing ever accepts or replies; the client must still return.
        let started = Date()
        let reply = sendCommand("status", path: path, timeoutSeconds: 0.2)
        XCTAssertEqual(reply, .reply(""))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
