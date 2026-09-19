@preconcurrency import AVFoundation
import BordersCore
import Foundation

/// Runs the explicit, opt-in camera-assisted Key Light verification command.
/// It is kept outside the normal app lifecycle so a test run never starts the
/// Borders overlays or installs another menu-bar item.
func runKeyLightHardwareTest(arguments: [String]) -> Int32 {
    if arguments.contains("--help") {
        print(KeyLightHardwareTestOptions.usage)
        return 0
    }

    do {
        let options = try KeyLightHardwareTestOptions.parse(arguments)
        try KeyLightHardwareTestRunner(options: options).run()
        return 0
    } catch {
        FileHandle.standardError.write(Data("keylight-hardware-test: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

private struct KeyLightHardwareTestOptions {
    let host: String?
    let port: Int
    let cameraID: String?
    let discoveryTimeout: TimeInterval
    let configuration: KeyLightHardwareTestConfiguration
    let jsonPath: String?

    static let usage = """
    Usage: make keylight-hardware-test ARGS="[options]"

      --host HOST       Skip Bonjour and use this light host or IP address
      --port PORT       Light API port (default: 9123)
      --camera-id ID    Use this AVFoundation camera unique ID
      --settle SECONDS  Wait after each light change (default: 1.0)
      --samples COUNT   Camera samples per step (default: 5)
      --interval SEC    Minimum time between camera samples (default: 0.3)
      --tolerance VALUE Luminance tolerance from 0 to 1 (default: 0.05)
      --timeout SECONDS Bonjour discovery timeout (default: 5)
      --json PATH       Write observations and failures as JSON
      --help            Show this help

    The test drives power off, user-facing 0%, minimum, midpoint, and maximum
    brightness. It restores the original Key Light state before exiting.
    """

    static func parse(_ arguments: [String]) throws -> KeyLightHardwareTestOptions {
        var values = ParsedValues()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument != "--keylight-hardware-test" else {
                index += 1
                continue
            }
            let value = try argumentValue(for: argument, arguments: arguments, index: &index)
            try values.apply(argument: argument, value: value)
            index += 1
        }
        return KeyLightHardwareTestOptions(
            host: values.host,
            port: values.port,
            cameraID: values.cameraID,
            discoveryTimeout: values.discoveryTimeout,
            configuration: KeyLightHardwareTestConfiguration(
                settleInterval: values.settleInterval,
                sampleCount: values.sampleCount,
                sampleInterval: values.sampleInterval,
                tolerance: values.tolerance
            ),
            jsonPath: values.jsonPath
        )
    }

    private static func argumentValue(for argument: String,
                                     arguments: [String],
                                     index: inout Int) throws -> String {
        guard argument != "--keylight-hardware-test" else { return "" }
        index += 1
        guard index < arguments.count else {
            throw KeyLightHardwareTestError.invalidArgument("\(argument) needs a value")
        }
        return arguments[index]
    }
}

private struct ParsedValues {
    private static let stringArguments = ["--host", "--camera-id", "--json"]
    private static let integerArguments = ["--port", "--samples"]
    private static let decimalArguments = ["--settle", "--interval", "--tolerance", "--timeout"]

    var host: String?
    var port = KeyLightLimits.apiPort
    var cameraID: String?
    var discoveryTimeout = 5.0
    var settleInterval = 1.0
    var sampleCount = 5
    var sampleInterval = 0.3
    var tolerance = 0.05
    var jsonPath: String?

    mutating func apply(argument: String, value: String) throws {
        if Self.stringArguments.contains(argument) {
            applyString(value, for: argument)
            return
        }
        if Self.integerArguments.contains(argument) {
            try applyInteger(value, for: argument)
            return
        }
        if Self.decimalArguments.contains(argument) {
            try applyDecimal(value, for: argument)
            return
        }
        throw KeyLightHardwareTestError.invalidArgument("unknown option \(argument)")
    }

    private mutating func applyString(_ value: String, for argument: String) {
        switch argument {
        case "--host": host = value
        case "--camera-id": cameraID = value
        case "--json": jsonPath = value
        default: break
        }
    }

    private mutating func applyInteger(_ value: String, for argument: String) throws {
        let parsed = try integer(value, for: argument)
        if argument == "--port" {
            port = parsed
        } else {
            sampleCount = parsed
        }
    }

    private mutating func applyDecimal(_ value: String, for argument: String) throws {
        let parsed = try decimal(value, for: argument)
        switch argument {
        case "--settle": settleInterval = parsed
        case "--interval": sampleInterval = parsed
        case "--tolerance": tolerance = parsed
        case "--timeout": discoveryTimeout = parsed
        default: break
        }
    }

    private func integer(_ value: String, for argument: String) throws -> Int {
        guard let result = Int(value) else {
            throw KeyLightHardwareTestError.invalidArgument("\(argument) must be an integer")
        }
        return result
    }

    private func decimal(_ value: String, for argument: String) throws -> Double {
        guard let result = Double(value), result.isFinite else {
            throw KeyLightHardwareTestError.invalidArgument("\(argument) must be a finite number")
        }
        return result
    }
}

private final class KeyLightHardwareTestRunner {
    private let options: KeyLightHardwareTestOptions
    private let client = KeyLightHTTPClient()
    private let camera = HardwareTestCameraSession()

    init(options: KeyLightHardwareTestOptions) {
        self.options = options
    }

    func run() throws {
        let device = try resolveDevice()
        let cameraDevice = try resolveCamera()
        print("Key Light: \(device.name) (\(device.host):\(device.port))")
        print("Camera: \(cameraDevice.name) (\(cameraDevice.id))")

        let original = try client.read(from: device)
        defer {
            camera.stop()
            restore(original, to: device)
        }

        try camera.start(deviceID: cameraDevice.id, sampleInterval: options.configuration.sampleInterval)
        camera.settle(for: max(1, options.configuration.settleInterval))
        let observations = try runSteps(device: device, base: original)
        let failures = KeyLightHardwareTestEvaluator.failures(
            in: observations,
            tolerance: options.configuration.tolerance
        )
        try writeJSONIfRequested(
            device: device,
            camera: cameraDevice,
            original: original,
            observations: observations,
            failures: failures
        )
        report(failures: failures)
        if !failures.isEmpty {
            throw KeyLightHardwareTestError.verificationFailed
        }
    }

    private func resolveDevice() throws -> KeyLightDevice {
        if let host = options.host {
            return KeyLightDevice(
                id: host,
                name: "Key Light at \(host)",
                host: host,
                port: options.port
            )
        }

        let devices = KeyLightServiceDiscovery().find(timeout: options.discoveryTimeout)
        guard let device = devices.first(where: { isKeyLight($0) }) ?? devices.first else {
            throw KeyLightHardwareTestError.noLight
        }
        return device
    }

    private func resolveCamera() throws -> BrightnessCameraDevice {
        let devices = camera.availableDevices()
        guard !devices.isEmpty else { throw KeyLightHardwareTestError.noCamera }
        if let cameraID = options.cameraID {
            guard let selected = devices.first(where: { $0.id == cameraID }) else {
                throw KeyLightHardwareTestError.cameraNotFound(cameraID)
            }
            return selected
        }
        return devices[0]
    }

    private func runSteps(device: KeyLightDevice,
                          base: KeyLightState) throws -> [KeyLightHardwareObservation] {
        try KeyLightHardwareTestPlan.steps.enumerated().map { index, step in
            let requested = KeyLightHardwareTestPlan.command(for: step, basedOn: base)
            try client.write(requested, to: device)
            camera.settle(for: options.configuration.settleInterval)
            let confirmed = try client.read(from: device)
            let measured = try camera.averageSamples(
                count: options.configuration.sampleCount,
                timeout: sampleTimeout
            )
            printStep(index: index, step: step, state: confirmed, luminance: measured)
            return KeyLightHardwareObservation(
                step: step,
                confirmedState: confirmed,
                measuredLuminance: measured
            )
        }
    }

    private var sampleTimeout: TimeInterval {
        max(5, Double(options.configuration.sampleCount) * options.configuration.sampleInterval * 3)
    }

    private func printStep(index: Int,
                          step: KeyLightHardwareTestStep,
                          state: KeyLightState,
                          luminance: Double) {
        let power = state.isOn ? "on" : "off"
        let reading = String(format: "%.3f", luminance)
        print("[\(index + 1)/\(KeyLightHardwareTestPlan.steps.count)] \(step.title): \(power), \(state.brightness)% · luminance \(reading)")
    }

    private func restore(_ state: KeyLightState, to device: KeyLightDevice) {
        do {
            try client.write(state, to: device)
            print("Restored original Key Light state.")
        } catch {
            FileHandle.standardError.write(
                Data("keylight-hardware-test: could not restore the original light state: \(error.localizedDescription)\n".utf8)
            )
        }
    }

    private func report(failures: [String]) {
        if failures.isEmpty {
            print("PASS: user 0% is off and the measured brightness sequence is monotonic.")
        } else {
            print("FAIL: hardware observations did not satisfy the Key Light contract.")
            failures.forEach { print("  - \($0)") }
        }
    }

    private func writeJSONIfRequested(device: KeyLightDevice,
                                     camera: BrightnessCameraDevice,
                                     original: KeyLightState,
                                     observations: [KeyLightHardwareObservation],
                                     failures: [String]) throws {
        guard let jsonPath = options.jsonPath else { return }
        let output = KeyLightHardwareTestOutput(
            device: device,
            camera: camera,
            original: original,
            configuration: options.configuration,
            observations: observations,
            failures: failures
        )
        let data = try JSONEncoder().encode(output)
        do {
            try data.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
        } catch {
            throw KeyLightHardwareTestError.jsonWriteFailed(jsonPath, error.localizedDescription)
        }
        print("Wrote \(jsonPath)")
    }

    private func isKeyLight(_ device: KeyLightDevice) -> Bool {
        device.name.localizedCaseInsensitiveContains("key light")
    }
}

private struct KeyLightHardwareTestOutput: Codable {
    let deviceName: String
    let host: String
    let port: Int
    let cameraName: String
    let cameraID: String
    let original: KeyLightState
    let configuration: KeyLightHardwareTestConfiguration
    let observations: [KeyLightHardwareObservation]
    let failures: [String]
    let passed: Bool

    init(device: KeyLightDevice,
         camera: BrightnessCameraDevice,
         original: KeyLightState,
         configuration: KeyLightHardwareTestConfiguration,
         observations: [KeyLightHardwareObservation],
         failures: [String]) {
        deviceName = device.name
        host = device.host
        port = device.port
        cameraName = camera.name
        cameraID = camera.id
        self.original = original
        self.configuration = configuration
        self.observations = observations
        self.failures = failures
        passed = failures.isEmpty
    }
}

private final class HardwareTestCameraSession {
    private let sampler = WebcamLuminanceSampler(deliversCallbacksOnMain: false)
    private let stateLock = NSLock()
    private var status = ""
    private var failure: String?
    private var samples: [Double] = []
    private var collecting = false

    init() {
        sampler.onStatus = { [weak self] message in
            self?.recordStatus(message)
        }
        sampler.onLuminance = { [weak self] value in
            self?.recordLuminance(value)
        }
    }

    func availableDevices() -> [BrightnessCameraDevice] {
        sampler.availableDevices()
    }

    func start(deviceID: String, sampleInterval: TimeInterval) throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            throw KeyLightHardwareTestError.cameraPermission
        case .authorized, .notDetermined:
            break
        @unknown default:
            throw KeyLightHardwareTestError.cameraPermission
        }
        stateLock.lock()
        status = ""
        failure = nil
        stateLock.unlock()
        sampler.start(
            deviceID: deviceID,
            sampleInterval: sampleInterval,
            locksCameraExposure: true
        )
        try waitUntil(timeout: 15) {
            self.stateSnapshot().status.lowercased().hasPrefix("monitoring ")
        }
    }

    func settle(for interval: TimeInterval) {
        runMainLoop(until: Date().addingTimeInterval(max(0, interval)))
    }

    func averageSamples(count: Int, timeout: TimeInterval) throws -> Double {
        stateLock.lock()
        samples.removeAll()
        collecting = true
        stateLock.unlock()
        defer {
            stateLock.lock()
            collecting = false
            stateLock.unlock()
        }
        try waitUntil(timeout: timeout) { self.stateSnapshot().sampleCount >= count }
        let capturedSamples = stateSamples()
        return capturedSamples.prefix(count).reduce(0, +) / Double(count)
    }

    func stop() {
        stateLock.lock()
        collecting = false
        stateLock.unlock()
        sampler.stopAndWait()
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), stateSnapshot().failure == nil, Date() < deadline {
            RunLoop.main.run(mode: .common, before: Date().addingTimeInterval(0.05))
        }
        if let failure = stateSnapshot().failure {
            throw KeyLightHardwareTestError.camera(failure)
        }
        guard condition() else {
            throw KeyLightHardwareTestError.camera("Timed out waiting for camera samples (\(stateSnapshot().status))")
        }
    }

    private func recordStatus(_ message: String) {
        stateLock.lock()
        status = message
        let lowercased = message.lowercased()
        if lowercased.contains("denied") ||
            lowercased.contains("no longer available") ||
            lowercased.contains("could not be configured") {
            failure = message
        }
        stateLock.unlock()
    }

    private func recordLuminance(_ value: Double) {
        guard value.isFinite else { return }
        stateLock.lock()
        if collecting {
            samples.append(value)
        }
        stateLock.unlock()
    }

    private func stateSnapshot() -> (status: String, failure: String?, sampleCount: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (status, failure, samples.count)
    }

    private func stateSamples() -> [Double] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return samples
    }
}

private final class KeyLightServiceDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]
    private var devices: [KeyLightDevice] = []

    func find(timeout: TimeInterval) -> [KeyLightDevice] {
        browser.delegate = self
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_elg._tcp.", inDomain: "local.")
        runMainLoop(until: Date().addingTimeInterval(max(0.5, timeout)))
        browser.stop()
        return devices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        let id = "\(service.name).\(service.domain)"
        guard services[id] == nil else { return }
        services[id] = service
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 3)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else { return }
        let device = KeyLightDevice(
            id: "\(sender.name).\(sender.domain)",
            name: sender.name,
            host: host,
            port: sender.port > 0 ? sender.port : KeyLightLimits.apiPort
        )
        guard !devices.contains(where: { $0.id == device.id }) else { return }
        devices.append(device)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didRemove service: NetService,
                           moreComing: Bool) {
        services["\(service.name).\(service.domain)"] = nil
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didNotSearch errorDict: [String: NSNumber]) {}

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {}
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {}
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}
}

private final class KeyLightHTTPClient {
    private let session: URLSession
    private let timeout: TimeInterval = 5

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 1
        session = URLSession(configuration: configuration)
    }

    func read(from device: KeyLightDevice) throws -> KeyLightState {
        let data = try request(method: "GET", state: nil, device: device)
        do {
            return try KeyLightState.decodeAPIResponse(data)
        } catch {
            throw KeyLightHardwareTestError.network("The light returned an invalid state")
        }
    }

    func write(_ state: KeyLightState, to device: KeyLightDevice) throws {
        let data = try state.apiPayloadData()
        _ = try request(method: "PUT", state: data, device: device)
    }

    private func request(method: String, state: Data?, device: KeyLightDevice) throws -> Data {
        guard let url = device.endpointURL else {
            throw KeyLightHardwareTestError.network("The light address is invalid")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let state {
            request.httpBody = state
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        session.dataTask(with: request) { data, response, error in
            result = Self.responseResult(data: data, response: response, error: error)
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + timeout + 1) == .success else {
            throw KeyLightHardwareTestError.network("The light request timed out")
        }
        do {
            return try result!.get()
        } catch {
            throw KeyLightHardwareTestError.network(error.localizedDescription)
        }
    }

    private static func responseResult(data: Data?,
                                      response: URLResponse?,
                                      error: Error?) -> Result<Data, Error> {
        if let error { return .failure(error) }
        guard let response = response as? HTTPURLResponse else {
            return .failure(KeyLightHardwareTestError.network("The light returned no HTTP response"))
        }
        guard (200..<300).contains(response.statusCode) else {
            return .failure(KeyLightHardwareTestError.network("The light returned HTTP \(response.statusCode)"))
        }
        return .success(data ?? Data())
    }
}

private enum KeyLightHardwareTestError: LocalizedError {
    case invalidArgument(String)
    case noLight
    case noCamera
    case cameraNotFound(String)
    case cameraPermission
    case camera(String)
    case network(String)
    case jsonWriteFailed(String, String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        case .noLight: return "No Key Light was found through Bonjour"
        case .noCamera: return "No camera is available to AVFoundation"
        case .cameraNotFound(let id): return "Camera \(id) is not available"
        case .cameraPermission:
            return "Camera access is denied; approve Borders in System Settings → Privacy & Security → Camera"
        case .camera(let message): return message
        case .network(let message): return message
        case .jsonWriteFailed(let path, let message): return "Could not write \(path): \(message)"
        case .verificationFailed: return "hardware verification failed"
        }
    }
}

private func runMainLoop(until deadline: Date) {
    while Date() < deadline {
        RunLoop.main.run(mode: .common, before: Date().addingTimeInterval(0.05))
    }
}
