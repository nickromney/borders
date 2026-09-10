import XCTest
@testable import BordersCore

final class ConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        let configuration = Configuration()
        XCTAssertEqual(configuration.color, 0xfff5_f543)
        XCTAssertEqual(configuration.width, 5)
        XCTAssertEqual(configuration.gap, 0)
        XCTAssertEqual(configuration.radius, 10)
        XCTAssertNil(configuration.ringAppBundleID)
    }

    func testEntriesSkipsBlankAndCommentLines() {
        let text = """

        # a comment
          # an indented comment
        width = 12
        """
        XCTAssertEqual(ConfigurationParser.entries(in: text),
                       [ConfigurationEntry(key: "width", value: "12")])
    }

    func testCommentsAreRecognisedOnlyAtTheStartOfALine() {
        XCTAssertEqual(ConfigurationParser.entries(in: "#width=99"), [])
        XCTAssertEqual(ConfigurationParser.entries(in: "width=99 #"),
                       [ConfigurationEntry(key: "width", value: "99 #")])
    }

    func testEntriesSkipsLinesWithoutSeparatorOrKey() {
        XCTAssertEqual(ConfigurationParser.entries(in: "width\n=12\nradius=3"),
                       [ConfigurationEntry(key: "radius", value: "3")])
    }

    func testEntriesTrimsAroundTheFirstSeparatorOnly() {
        XCTAssertEqual(ConfigurationParser.entries(in: "  ring_app  =  com.a=b  "),
                       [ConfigurationEntry(key: "ring_app", value: "com.a=b")])
    }

    func testParsesEveryKnownKey() {
        let text = """
        width=12
        gap=3
        radius=7
        color=0xff112233
        ring_app=com.apple.Safari
        """
        let configuration = ConfigurationParser.parse(text)
        XCTAssertEqual(configuration.width, 12)
        XCTAssertEqual(configuration.gap, 3)
        XCTAssertEqual(configuration.radius, 7)
        XCTAssertEqual(configuration.color, 0xff11_2233)
        XCTAssertEqual(configuration.ringAppBundleID, "com.apple.Safari")
    }

    func testRingAppAcceptsBothSpellings() {
        XCTAssertEqual(ConfigurationParser.parse("ring-app=com.apple.Terminal").ringAppBundleID,
                       "com.apple.Terminal")
    }

    func testEmptyRingAppClearsTheBinding() {
        let base = Configuration(ringAppBundleID: "com.apple.Safari")
        XCTAssertNil(ConfigurationParser.parse("ring_app=", base: base).ringAppBundleID)
    }

    func testUnknownKeyLeavesConfigurationUnchanged() {
        let base = Configuration(color: 7, width: 11)
        XCTAssertEqual(ConfigurationParser.parse("nonsense=4", base: base), base)
    }

    func testLaterEntryWinsForTheSameKey() {
        XCTAssertEqual(ConfigurationParser.parse("width=12\nwidth=20").width, 20)
    }

    func testUnparsableNumberKeepsThePreviousValue() {
        let base = Configuration(width: 11, gap: 4, radius: 9)
        let configuration = ConfigurationParser.parse("width=wide\ngap=\nradius=nan", base: base)
        XCTAssertEqual(configuration.width, 11)
        XCTAssertEqual(configuration.gap, 4)
        XCTAssertEqual(configuration.radius, 9)
    }

    func testNegativeAndFractionalLengthsAreAccepted() {
        let configuration = ConfigurationParser.parse("width=2.5\ngap=-1")
        XCTAssertEqual(configuration.width, 2.5)
        XCTAssertEqual(configuration.gap, -1)
    }

    func testInfiniteLengthIsRejected() {
        XCTAssertEqual(ConfigurationParser.parse("width=inf", base: Configuration(width: 6)).width, 6)
    }

    func testColourAcceptsBareAndPrefixedHex() {
        XCTAssertEqual(ConfigurationParser.parse("color=ff00ff00").color, 0xff00_ff00)
        XCTAssertEqual(ConfigurationParser.parse("color=0XFF00FF00").color, 0xff00_ff00)
    }

    func testUnparsableColourKeepsThePreviousValue() {
        let base = Configuration(color: 0x1234_5678)
        XCTAssertEqual(ConfigurationParser.parse("color=mauve", base: base).color, 0x1234_5678)
        XCTAssertEqual(ConfigurationParser.parse("color=", base: base).color, 0x1234_5678)
    }

    func testColourStripsOnlyALeadingPrefix() {
        let base = Configuration(color: 0x1234_5678)
        XCTAssertEqual(ConfigurationParser.parse("color=ff0x00", base: base).color, 0x1234_5678)
    }
}
