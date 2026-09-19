import Foundation

/// The ranges used by the Wi-Fi Key Light API and the user-facing controls.
public enum KeyLightLimits {
    public static let brightness: ClosedRange<Int> = 0...100
    /// The lowest useful output while the light is on. Zero is reserved for
    /// the power-off action because the hardware still emits light there.
    public static let minimumVisibleBrightness = 15
    /// User-facing colour temperature, in Kelvin.
    public static let temperature: ClosedRange<Int> = 2_900...7_000
    /// The light protocol represents colour temperature as inverse Kelvin
    /// (approximately mireds), with 143 meaning 7000 K and 344 meaning the
    /// warm end of the device's range.
    public static let apiTemperature: ClosedRange<Int> = 143...344
    public static let apiPort = 9_123
    public static let pairingAddress = "192.168.62.1"

    public static func apiTemperature(forKelvin kelvin: Int) -> Int {
        let clampedKelvin = clamp(kelvin, to: temperature)
        let inverseKelvin = Int((1_000_000.0 / Double(clampedKelvin)).rounded())
        return clamp(inverseKelvin, to: apiTemperature)
    }

    public static func kelvin(forAPITemperature value: Int) -> Int {
        let clampedValue = clamp(value, to: apiTemperature)
        return Int((1_000_000.0 / Double(clampedValue)).rounded())
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

/// The state of one physical light, independent of how it was discovered.
public struct KeyLightState: Codable, Equatable, Sendable {
    public var isOn: Bool
    public var brightness: Int
    public var temperature: Int

    public init(isOn: Bool, brightness: Int, temperature: Int) {
        self.isOn = isOn
        self.brightness = Self.clamp(brightness, to: KeyLightLimits.brightness)
        self.temperature = Self.clamp(temperature, to: KeyLightLimits.temperature)
    }

    public static let sensibleDefault = KeyLightState(isOn: true, brightness: 50, temperature: 4_200)
    /// Full output at the coldest supported colour temperature: a useful
    /// daylight/SAD-lamp preset, still within the light's published range.
    public static let sadLamp = KeyLightState(
        isOn: true,
        brightness: KeyLightLimits.brightness.upperBound,
        temperature: KeyLightLimits.temperature.upperBound
    )

    public func changing(isOn: Bool? = nil,
                         brightness: Int? = nil,
                         temperature: Int? = nil) -> KeyLightState {
        KeyLightState(isOn: isOn ?? self.isOn,
                      brightness: brightness ?? self.brightness,
                      temperature: temperature ?? self.temperature)
    }

    /// Applies the user-facing brightness semantics: zero means power off,
    /// while an on-state never asks this hardware for its still-bright zero
    /// output.
    public func changingForUserBrightness(_ brightness: Int) -> KeyLightState {
        guard brightness > KeyLightLimits.brightness.lowerBound else {
            return changing(isOn: false, brightness: KeyLightLimits.brightness.lowerBound)
        }
        return changing(brightness: max(KeyLightLimits.minimumVisibleBrightness, brightness))
    }

    public func apiPayloadData() throws -> Data {
        try JSONEncoder().encode(KeyLightAPIResponse(lights: [KeyLightAPILight(state: self)]))
    }

    public static func decodeAPIResponse(_ data: Data) throws -> KeyLightState {
        let response = try JSONDecoder().decode(KeyLightAPIResponse.self, from: data)
        guard let light = response.lights.first else { throw KeyLightError.noLightsInResponse }
        return light.state
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

/// A light found through the local `_elg._tcp` Bonjour service.
public struct KeyLightDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int

    public init(id: String, name: String, host: String, port: Int = KeyLightLimits.apiPort) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }

    public var endpointURL: URL? {
        URL(string: "http://\(host):\(port)/elgato/lights")
    }
}

public enum KeyLightError: Error, Equatable, Sendable {
    case noLightsInResponse
    case invalidResponse
    case httpStatus(Int)
}

private struct KeyLightAPIResponse: Codable, Equatable, Sendable {
    let lights: [KeyLightAPILight]

    init(lights: [KeyLightAPILight]) {
        self.lights = lights
    }

    enum CodingKeys: String, CodingKey {
        case numberOfLights
        case lights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int.self, forKey: .numberOfLights)
        lights = try container.decode([KeyLightAPILight].self, forKey: .lights)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lights.count, forKey: .numberOfLights)
        try container.encode(lights, forKey: .lights)
    }
}

private struct KeyLightAPILight: Codable, Equatable, Sendable {
    let on: Int
    let brightness: Int
    let temperature: Int

    init(state: KeyLightState) {
        on = state.isOn ? 1 : 0
        brightness = state.brightness
        temperature = KeyLightLimits.apiTemperature(forKelvin: state.temperature)
    }

    var state: KeyLightState {
        KeyLightState(
            isOn: on != 0,
            brightness: brightness,
            temperature: KeyLightLimits.kelvin(forAPITemperature: temperature)
        )
    }
}
