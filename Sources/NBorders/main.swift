import AppKit
import BordersCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--keylight-hardware-test") {
    exit(runKeyLightHardwareTest(arguments: arguments))
}
if let request = arguments.first, Command.isClientCommand(request) {
    exit(runClient(request))
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let engine = BorderEngine()
let menuController = MenuController(engine: engine)
let keyLightStatusItemController = KeyLightStatusItemController(engine: engine)
keyLightStatusItemController.keyLightsStateAction = { [weak menuController] areOff in
    menuController?.setKeyLightsAreOff(areOff)
}
menuController.keyLightsAction = { [weak keyLightStatusItemController] anchor in
    keyLightStatusItemController?.showPopoverFromBordersMenu(anchor: anchor)
}
menuController.keyLightsOnAction = { [weak keyLightStatusItemController] in
    keyLightStatusItemController?.turnOnAllAtMinimum()
}
menuController.keyLightsOffAction = { [weak keyLightStatusItemController] in
    keyLightStatusItemController?.turnOffAll()
}
let socketServer = SocketServer(engine: engine)
socketServer.start()
engine.start()
keyLightStatusItemController.install()
application.run()
