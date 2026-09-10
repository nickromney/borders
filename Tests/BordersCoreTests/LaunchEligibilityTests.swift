import XCTest
@testable import BordersCore

final class LaunchEligibilityTests: XCTestCase {
    private func eligible(_ path: String) -> Bool {
        LaunchEligibility.canManageLaunchAtLogin(bundleURL: URL(fileURLWithPath: path))
    }

    func testAnInstalledAppMayRegisterItself() {
        XCTAssertTrue(eligible("/Users/someone/Applications/Borders.app"))
        XCTAssertTrue(eligible("/Applications/Borders.app"))
    }

    func testADeveloperBuildMayNot() {
        XCTAssertFalse(eligible("/Users/someone/code/borders/.build/Debug/Borders.app"))
    }

    func testTheDirectoryNameMustMatchExactly() {
        XCTAssertFalse(eligible("/Users/someone/MyApplications/Borders.app"))
        XCTAssertFalse(eligible("/Users/someone/applications/Borders.app"))
    }
}
