import Foundation
import XCTest
@testable import BordersCore

final class KeyLightTests: XCTestCase {
    func testSensibleDefaultStartsTheLightOnAtAComfortableSetting() {
        XCTAssertEqual(KeyLightState.sensibleDefault, KeyLightState(isOn: true, brightness: 50, temperature: 4_200))
    }

    func testAPIResponseDecodesTheFirstLight() throws {
        let data = Data(#"{"numberOfLights":2,"lights":[{"on":1,"brightness":73,"temperature":213},{"on":0,"brightness":10,"temperature":300}]}"#.utf8)

        let state = try KeyLightState.decodeAPIResponse(data)

        XCTAssertEqual(state, KeyLightState(isOn: true, brightness: 73, temperature: 4_695))
    }

    func testAPIResponseRejectsAnEmptyLightList() throws {
        let data = Data(#"{"numberOfLights":0,"lights":[]}"#.utf8)

        XCTAssertThrowsError(try KeyLightState.decodeAPIResponse(data)) { error in
            XCTAssertEqual(error as? KeyLightError, .noLightsInResponse)
        }
    }

    func testAPIResponseRoundTripsThePayloadShape() throws {
        let state = KeyLightState(isOn: false, brightness: 42, temperature: 4_200)

        let decoded = try KeyLightState.decodeAPIResponse(state.apiPayloadData())

        XCTAssertEqual(decoded.brightness, state.brightness)
        XCTAssertEqual(decoded.temperature, 4_202)
    }

    func testStateClampsUIValuesToDeviceLimits() {
        let state = KeyLightState(isOn: true, brightness: 120, temperature: 1_000)

        XCTAssertEqual(state.brightness, 100)
        XCTAssertEqual(state.temperature, 2_900)
    }

    func testUserBrightnessZeroMeansPowerOffAndSmallOnValuesUseTheVisibleMinimum() {
        let state = KeyLightState(isOn: true, brightness: 60, temperature: 4_200)

        XCTAssertEqual(state.changingForUserBrightness(0), KeyLightState(isOn: false, brightness: 0, temperature: 4_200))
        XCTAssertEqual(state.changingForUserBrightness(5), KeyLightState(isOn: true, brightness: 5, temperature: 4_200))
    }

    func testSADLampPresetStaysWithinPublishedLimits() {
        XCTAssertEqual(KeyLightState.sadLamp, KeyLightState(isOn: true, brightness: 100, temperature: 7_000))
    }

    func testPayloadUsesTheDeviceTemperatureEncoding() throws {
        let warm = try JSONSerialization.jsonObject(
            with: KeyLightState(isOn: true, brightness: 50, temperature: 2_900).apiPayloadData()
        ) as? [String: Any]
        let warmTemperature = (((warm?["lights"] as? [[String: Any]])?.first)?["temperature"] as? Int)

        XCTAssertEqual(warmTemperature, 344)
        XCTAssertEqual(KeyLightLimits.apiTemperature(forKelvin: 7_000), 143)
    }

    func testDeviceBuildsTheLocalAPIEndpoint() {
        let device = KeyLightDevice(id: "key-light", name: "Key Light", host: "192.168.50.44")

        XCTAssertEqual(device.endpointURL?.absoluteString, "http://192.168.50.44:9123/elgato/lights")
    }
}
