import AppKit
import BordersCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
if let request = arguments.first, Command.isClientCommand(request) {
    exit(runClient(request))
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let engine = BorderEngine()
let menuController = MenuController(engine: engine)
let socketServer = SocketServer(engine: engine)
socketServer.start()
engine.start()
application.run()
