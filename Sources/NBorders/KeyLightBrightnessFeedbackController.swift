import AVFoundation
import BordersCore
import Combine
import Foundation

/// Coordinates the camera adapter, pure feedback policy, and Key Light store.
/// The feature is opt-in and its tuning survives reinstall-safe app rebuilds in
/// the user's normal Borders preferences.
final class KeyLightBrightnessFeedbackController: ObservableObject {
    @Published private(set) var cameraDevices: [BrightnessCameraDevice] = []
    @Published private(set) var selectedCameraID: String?
    @Published private(set) var isEnabled = false
    @Published private(set) var currentLuminance: Double?
    @Published private(set) var status = "Camera feedback is off"
    @Published private(set) var configuration: BrightnessFeedbackConfiguration

    private let store: KeyLightStore
    private let sampler = WebcamLuminanceSampler()
    private let defaults: UserDefaults
    private var policy: BrightnessFeedbackPolicy

    private static let configurationKey = "studioLights.brightnessFeedback.configuration"
    private static let cameraKey = "studioLights.brightnessFeedback.cameraID"

    init(store: KeyLightStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let loadedConfiguration = Self.loadConfiguration(from: defaults)
        self.configuration = loadedConfiguration
        self.policy = BrightnessFeedbackPolicy(configuration: loadedConfiguration)
        selectedCameraID = defaults.string(forKey: Self.cameraKey)

        sampler.onLuminance = { [weak self] value in
            self?.receive(luminance: value)
        }
        sampler.onStatus = { [weak self] message in
            DispatchQueue.main.async {
                self?.status = message
            }
        }
        refreshCameras()
    }

    deinit {
        sampler.stop()
    }

    var selectedCameraName: String? {
        cameraDevices.first { $0.id == selectedCameraID }?.name
    }

    var targetPercent: Int {
        Int((configuration.targetLuminance * 100).rounded())
    }

    func refreshCameras() {
        cameraDevices = sampler.availableDevices()
        guard let selectedCameraID,
              cameraDevices.contains(where: { $0.id == selectedCameraID }) else {
            self.selectedCameraID = cameraDevices.first?.id
            persistCameraSelection()
            return
        }
    }

    func selectCamera(_ cameraID: String) {
        guard cameraDevices.contains(where: { $0.id == cameraID }) else { return }
        selectedCameraID = cameraID
        persistCameraSelection()
        guard isEnabled else { return }
        restartSampler(using: cameraID)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        policy.reset()
        currentLuminance = nil
        if enabled {
            startSampler()
        } else {
            sampler.stop()
            status = "Camera feedback is off"
        }
    }

    func setTargetLuminance(_ value: Double) {
        updateConfiguration(
            BrightnessFeedbackConfiguration(
                targetLuminance: value,
                deadband: configuration.deadband,
                sampleCount: configuration.sampleCount,
                cooldown: configuration.cooldown,
                maximumStep: configuration.maximumStep,
                sampleInterval: configuration.sampleInterval,
                locksCameraExposure: configuration.locksCameraExposure
            )
        )
    }

    func setLocksCameraExposure(_ locks: Bool) {
        updateConfiguration(
            BrightnessFeedbackConfiguration(
                targetLuminance: configuration.targetLuminance,
                deadband: configuration.deadband,
                sampleCount: configuration.sampleCount,
                cooldown: configuration.cooldown,
                maximumStep: configuration.maximumStep,
                sampleInterval: configuration.sampleInterval,
                locksCameraExposure: locks
            )
        )
        if isEnabled { startSampler() }
    }

    private func updateConfiguration(_ newConfiguration: BrightnessFeedbackConfiguration) {
        configuration = newConfiguration
        policy = BrightnessFeedbackPolicy(configuration: newConfiguration)
        persistConfiguration()
    }

    private func startSampler() {
        refreshCameras()
        guard let cameraID = selectedCameraID else {
            status = "No camera is available"
            return
        }
        status = "Requesting Camera access…"
        sampler.start(
            deviceID: cameraID,
            sampleInterval: configuration.sampleInterval,
            locksCameraExposure: configuration.locksCameraExposure
        )
    }

    private func restartSampler(using cameraID: String) {
        sampler.stop()
        let cameraName = cameraDevices.first { $0.id == cameraID }?.name ?? "camera"
        status = "Switching to \(cameraName)…"
        sampler.start(
            deviceID: cameraID,
            sampleInterval: configuration.sampleInterval,
            locksCameraExposure: configuration.locksCameraExposure
        )
    }

    private func receive(luminance: Double) {
        guard isEnabled else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.receive(luminance: luminance)
            }
            return
        }

        currentLuminance = luminance
        guard let activeLight = activeLights().first else {
            status = readingStatus() + " · no light is on"
            return
        }
        guard let nextBrightness = policy.nextBrightness(
            for: luminance,
            currentBrightness: activeLight.state.brightness,
            at: Date()
        ) else {
            status = readingStatus()
            return
        }

        let change = nextBrightness - activeLight.state.brightness
        activeLights().forEach { light in
            store.setBrightness(light.state.brightness + change, for: light.device)
        }
        status = "Adjusting lights towards \(targetPercent)% · next \(nextBrightness)%"
    }

    private func activeLights() -> [(device: KeyLightDevice, state: KeyLightState)] {
        store.devices.compactMap { device in
            guard let state = store.state(for: device), state.isOn else { return nil }
            return (device, state)
        }
    }

    private func readingStatus() -> String {
        guard let currentLuminance else { return status }
        let reading = Int((currentLuminance * 100).rounded())
        return "Camera \(reading)% · target \(targetPercent)%"
    }

    private func persistConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.configurationKey)
    }

    private func persistCameraSelection() {
        defaults.set(selectedCameraID, forKey: Self.cameraKey)
    }

    private static func loadConfiguration(from defaults: UserDefaults) -> BrightnessFeedbackConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(BrightnessFeedbackConfiguration.self, from: data) else {
            return BrightnessFeedbackConfiguration()
        }
        return configuration
    }
}
