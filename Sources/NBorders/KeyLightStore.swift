import AppKit
import BordersCore
import Combine
import Foundation

/// Discovers and controls Elgato Wi-Fi lights without going through Control
/// Center. The light API is local HTTP; this object never contacts a cloud
/// service and never changes the Mac's Wi-Fi network.
final class KeyLightStore: NSObject, ObservableObject {
    @Published private(set) var devices: [KeyLightDevice] = []
    @Published private(set) var states: [String: KeyLightState] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var isSearching = false
    @Published private(set) var statusMessage = "Not searched yet"

    private let browser = NetServiceBrowser()
    private let session: URLSession
    private var services: [String: NetService] = [:]
    private var devicesByID: [String: KeyLightDevice] = [:]
    private var latestRequestIDs: [String: UUID] = [:]
    private var pendingWrites: [String: DispatchWorkItem] = [:]
    private var pendingStates = KeyLightWriteCoalescer()
    private var searchGeneration = 0
    private let writeDebounceInterval: TimeInterval

    init(writeDebounceInterval: TimeInterval = KeyLightTiming.sliderWriteDebounce) {
        self.writeDebounceInterval = max(0, writeDebounceInterval)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        session = URLSession(configuration: configuration)
        super.init()
        browser.delegate = self
        browser.schedule(in: .main, forMode: .common)
    }

    deinit {
        pendingWrites.values.forEach { $0.cancel() }
        browser.stop()
    }

    func start() {
        refresh()
    }

    func refresh() {
        cancelPendingWrites()
        latestRequestIDs.removeAll()
        searchGeneration += 1
        let generation = searchGeneration
        browser.stop()
        services.removeAll()
        devicesByID.removeAll()
        devices.removeAll()
        states.removeAll()
        errors.removeAll()
        isSearching = true
        statusMessage = "Searching for Key Lights…"
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_elg._tcp.", inDomain: "local.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.searchGeneration == generation else { return }
            self.isSearching = false
            if self.devices.isEmpty {
                self.statusMessage = "No Key Lights found on this network"
            }
        }
    }

    func state(for device: KeyLightDevice) -> KeyLightState? {
        states[device.id]
    }

    func setPower(_ isOn: Bool, for device: KeyLightDevice) {
        let current = states[device.id] ?? .sensibleDefault
        let brightness = isOn ? minimumOnBrightness(current.brightness) : current.brightness
        send(current.changing(isOn: isOn, brightness: brightness), to: device)
    }

    func setBrightness(_ brightness: Int, for device: KeyLightDevice) {
        let current = states[device.id] ?? .sensibleDefault
        let next = current.changingForUserBrightness(brightness)
        if next.isOn {
            schedule(next, to: device)
        } else {
            send(next, to: device)
        }
    }

    func setTemperature(_ temperature: Int, for device: KeyLightDevice) {
        let current = states[device.id] ?? .sensibleDefault
        schedule(current.changing(temperature: temperature), to: device)
    }

    func turnOffAll() {
        devices.forEach { device in
            let current = states[device.id] ?? .sensibleDefault
            send(current.changing(isOn: false), to: device)
        }
    }

    func turnOnAll() {
        devices.forEach { device in
            let current = states[device.id] ?? .sensibleDefault
            send(current.changing(isOn: true, brightness: minimumOnBrightness(current.brightness)), to: device)
        }
    }

    func activateSADLamp() {
        devices.forEach { send(.sadLamp, to: $0) }
    }

    func openWiFiSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the light's own setup page after the user has joined its
    /// temporary `Key Light XXXX` network. This is intentionally a local URL;
    /// no account, cloud service, or Elgato app is involved.
    func openPairingPage() {
        guard let url = URL(string: "http://\(KeyLightLimits.pairingAddress):\(KeyLightLimits.apiPort)/") else { return }
        NSWorkspace.shared.open(url)
    }

    private func minimumOnBrightness(_ brightness: Int) -> Int {
        max(KeyLightLimits.minimumVisibleBrightness, brightness)
    }

    private func schedule(_ state: KeyLightState, to device: KeyLightDevice) {
        cancelPendingWrite(for: device)
        states[device.id] = state
        errors[device.id] = nil
        pendingStates.replace(state, for: device.id)

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let state = self.pendingStates.takeLatest(for: device.id) else { return }
            self.pendingWrites[device.id] = nil
            self.send(state, to: device)
        }
        pendingWrites[device.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDebounceInterval, execute: work)
    }

    private func send(_ state: KeyLightState, to device: KeyLightDevice) {
        cancelPendingWrite(for: device)
        states[device.id] = state
        errors[device.id] = nil
        guard let url = device.endpointURL else {
            errors[device.id] = "The light address is invalid"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? state.apiPayloadData()

        let requestID = UUID()
        latestRequestIDs[device.id] = requestID
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleWriteResult(
                    data: data,
                    response: response,
                    error: error,
                    for: device,
                    requestID: requestID
                )
            }
        }.resume()
    }

    private func cancelPendingWrite(for device: KeyLightDevice) {
        pendingWrites[device.id]?.cancel()
        pendingWrites[device.id] = nil
        pendingStates.remove(for: device.id)
    }

    private func cancelPendingWrites() {
        pendingWrites.values.forEach { $0.cancel() }
        pendingWrites.removeAll()
        pendingStates.removeAll()
    }

    private func handleWriteResult(data: Data?, response: URLResponse?, error: Error?,
                                   for device: KeyLightDevice, requestID: UUID) {
        guard latestRequestIDs[device.id] == requestID else { return }
        latestRequestIDs[device.id] = nil
        if let error {
            failWrite(for: device, message: error.localizedDescription)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            failWrite(for: device, message: "The light returned HTTP \(status)")
            return
        }
        guard let data, let confirmed = try? KeyLightState.decodeAPIResponse(data) else { return }
        states[device.id] = confirmed
    }

    private func failWrite(for device: KeyLightDevice, message: String) {
        errors[device.id] = message
        refresh(device)
    }

    private func refresh(_ device: KeyLightDevice) {
        guard let url = device.endpointURL else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.errors[device.id] = error.localizedDescription
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let data,
                      let state = try? KeyLightState.decodeAPIResponse(data) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.errors[device.id] = "Could not read the light (HTTP \(status))"
                    return
                }
                self.states[device.id] = state
                self.errors[device.id] = nil
            }
        }
        task.resume()
    }

    private func serviceID(_ service: NetService) -> String {
        "\(service.name).\(service.domain)"
    }

    private func install(_ service: NetService) {
        guard let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else {
            errors[serviceID(service)] = "The light resolved without a host name"
            return
        }
        let id = serviceID(service)
        let device = KeyLightDevice(id: id, name: service.name, host: host,
                                    port: service.port > 0 ? service.port : KeyLightLimits.apiPort)
        devicesByID[id] = device
        devices = devicesByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isSearching = false
        statusMessage = devices.count == 1 ? "1 Key Light found" : "\(devices.count) Key Lights found"
        refresh(device)
    }
}

extension KeyLightStore: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {}

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let id = serviceID(service)
        services[id] = service
        service.delegate = self
        service.resolve(withTimeout: 3)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = serviceID(service)
        pendingWrites[id]?.cancel()
        pendingWrites[id] = nil
        pendingStates.remove(for: id)
        latestRequestIDs[id] = nil
        services[id] = nil
        devicesByID[id] = nil
        states[id] = nil
        errors[id] = nil
        devices = devicesByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if devices.isEmpty {
            statusMessage = "No Key Lights found on this network"
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        isSearching = false
        statusMessage = "Bonjour discovery is unavailable"
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {}
}

extension KeyLightStore: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        install(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        errors[serviceID(sender)] = "Could not resolve the light on the local network"
    }
}
