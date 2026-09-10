import XCTest
@testable import BordersCore

final class CommandTests: XCTestCase {
    func testEveryAcceptedSpelling() {
        XCTAssertEqual(Command.parse("on"), .setMode(.focused))
        XCTAssertEqual(Command.parse("focused"), .setMode(.focused))
        XCTAssertEqual(Command.parse("ring"), .setMode(.ringLight))
        XCTAssertEqual(Command.parse("ring-light"), .setMode(.ringLight))
        XCTAssertEqual(Command.parse("off"), .setMode(.off))
        XCTAssertEqual(Command.parse("reload"), .reload)
        XCTAssertEqual(Command.parse("reconcile"), .reload)
        XCTAssertEqual(Command.parse("status"), .status)
        XCTAssertEqual(Command.parse("quit"), .quit)
    }

    func testWhitespaceAndCaseAreTolerated() {
        XCTAssertEqual(Command.parse("  status\n"), .status)
        XCTAssertEqual(Command.parse("OFF"), .setMode(.off))
    }

    func testQuitIsDistinctFromEveryOtherCommand() {
        XCTAssertNotEqual(Command.parse("quit"), .status)
        XCTAssertNotEqual(Command.parse("quit"), .reload)
        XCTAssertNotEqual(Command.parse("quit"), .setMode(.off))
        XCTAssertEqual(Command.parse("QUIT "), .quit)
    }

    func testUnknownInputIsRejected() {
        XCTAssertNil(Command.parse(""))
        XCTAssertNil(Command.parse("onn"))
        XCTAssertNil(Command.parse("quitter"))
        XCTAssertNil(Command.parse("status extra"))
    }

    func testEveryAdvertisedNameParses() {
        for name in Command.names {
            XCTAssertNotNil(Command.parse(name), "\(name) should parse")
            XCTAssertTrue(Command.isClientCommand(name))
        }
    }

    func testIsClientCommandRejectsUnknownInput() {
        XCTAssertFalse(Command.isClientCommand("launch"))
    }
}
