import AppKit
import BordersCore
import Foundation

/// Wires the control channel to the engine on the main thread.
final class SocketServer {
    private let engine: BorderEngine
    private let channel: CommandChannel

    init(engine: BorderEngine, path: String = socketPath) {
        self.engine = engine
        var handler: ((String) -> String)?
        channel = CommandChannel(path: path) { handler?($0) ?? "" }
        // The channel accepts clients on a utility queue, but every engine
        // command can ultimately manipulate AppKit windows. Keep that work on
        // the main thread; AppKit deliberately traps when a window is ordered
        // from anywhere else.
        handler = { [weak self] request in
            guard let self else { return "" }
            return DispatchQueue.main.sync { self.execute(request) }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard channel.start() else {
            FileHandle.standardError.write(Data("borders: could not listen on \(channel.path)\n".utf8))
            return false
        }
        return true
    }

    func execute(_ request: String) -> String {
        guard let command = Command.parse(request) else { return "unknown command" }
        switch command {
        case .setMode(let mode): engine.setMode(mode)
        case .reload: engine.reload()
        case .status: break
        case .quit:
            // Terminating here would kill the process before the reply is
            // written, so let this call return first. A graceful exit lets
            // AppKit tear the overlay windows down itself, which a signal
            // does not.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.terminate(nil)
            }
            return "quitting"
        }
        return engine.status()
    }
}

/// Send one command to a running app and print its reply.
func runClient(_ command: String, path: String = socketPath) -> Int32 {
    switch sendCommand(command, path: path) {
    case .reply(let reply):
        print(reply)
        return 0
    case .notRunning, .unusablePath:
        FileHandle.standardError.write(Data("borders: app is not running\n".utf8))
        return 1
    }
}
