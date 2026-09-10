import XCTest
@testable import BordersCore

final class AppBindingTests: XCTestCase {
    func testSummaryPrefersTheDisplayName() {
        let binding = AppBinding(boundBundleID: "com.apple.Safari", boundName: "Safari")
        XCTAssertEqual(binding.summary, "Safari")
    }

    func testSummaryFallsBackToTheBundleIdentifier() {
        XCTAssertEqual(AppBinding(boundBundleID: "com.apple.Safari").summary, "com.apple.Safari")
    }

    func testUnboundSummaryReadsAnyApp() {
        XCTAssertEqual(AppBinding(boundName: "Safari").summary, "Any app")
    }

    func testLastExternalSummaryFallsBackTwice() {
        XCTAssertEqual(AppBinding(lastExternalBundleID: "com.a", lastExternalName: "A").lastExternalSummary, "A")
        XCTAssertEqual(AppBinding(lastExternalBundleID: "com.a").lastExternalSummary, "com.a")
        XCTAssertEqual(AppBinding().lastExternalSummary, "last active app")
    }

    func testBindingToTheLastExternalApp() {
        var binding = AppBinding(lastExternalBundleID: "com.apple.Safari", lastExternalName: "Safari")
        XCTAssertTrue(binding.bindToLastExternal())
        XCTAssertEqual(binding.boundBundleID, "com.apple.Safari")
        XCTAssertEqual(binding.boundName, "Safari")
    }

    func testBindingUsesTheBundleIdentifierWhenNoNameIsKnown() {
        var binding = AppBinding(lastExternalBundleID: "com.apple.Safari")
        XCTAssertTrue(binding.bindToLastExternal())
        XCTAssertEqual(binding.boundName, "com.apple.Safari")
    }

    func testBindingWithNothingRememberedChangesNothing() {
        var binding = AppBinding(boundBundleID: "com.apple.Mail", boundName: "Mail")
        XCTAssertFalse(binding.bindToLastExternal())
        XCTAssertEqual(binding.boundBundleID, "com.apple.Mail")
        XCTAssertEqual(binding.boundName, "Mail")
    }

    func testClearingDropsBothFields() {
        var binding = AppBinding(boundBundleID: "com.apple.Mail", boundName: "Mail")
        binding.clear()
        XCTAssertNil(binding.boundBundleID)
        XCTAssertNil(binding.boundName)
    }

    func testRememberingRecordsTheBundleIdentifierAndName() {
        var binding = AppBinding()
        binding.rememberExternal(bundleID: "com.apple.Safari", name: "Safari")
        XCTAssertEqual(binding.lastExternalBundleID, "com.apple.Safari")
        XCTAssertEqual(binding.lastExternalName, "Safari")
    }

    func testRememberingWithoutANameUsesTheBundleIdentifier() {
        var binding = AppBinding()
        binding.rememberExternal(bundleID: "com.apple.Safari", name: nil)
        XCTAssertEqual(binding.lastExternalName, "com.apple.Safari")
    }

    func testRememberingNothingKeepsThePreviousApp() {
        var binding = AppBinding(lastExternalBundleID: "com.apple.Safari", lastExternalName: "Safari")
        binding.rememberExternal(bundleID: nil, name: "Ghost")
        XCTAssertEqual(binding.lastExternalBundleID, "com.apple.Safari")
        XCTAssertEqual(binding.lastExternalName, "Safari")
    }

    func testAnUnboundLightIsAlwaysActive() {
        let binding = AppBinding()
        XCTAssertTrue(binding.isActive(frontmostBundleID: "com.anything", frontmostIsSelf: false))
        XCTAssertTrue(binding.isActive(frontmostBundleID: nil, frontmostIsSelf: true))
    }

    func testABoundLightFollowsTheFrontmostApp() {
        let binding = AppBinding(boundBundleID: "com.apple.Safari")
        XCTAssertTrue(binding.isActive(frontmostBundleID: "com.apple.Safari", frontmostIsSelf: false))
        XCTAssertFalse(binding.isActive(frontmostBundleID: "com.apple.Mail", frontmostIsSelf: false))
        XCTAssertFalse(binding.isActive(frontmostBundleID: nil, frontmostIsSelf: false))
    }

    func testOwnMenuFallsBackToTheRememberedApp() {
        var binding = AppBinding(boundBundleID: "com.apple.Safari",
                                 lastExternalBundleID: "com.apple.Safari")
        XCTAssertTrue(binding.isActive(frontmostBundleID: "com.nickromney.borders", frontmostIsSelf: true))
        binding.lastExternalBundleID = "com.apple.Mail"
        XCTAssertFalse(binding.isActive(frontmostBundleID: "com.nickromney.borders", frontmostIsSelf: true))
    }

    func testStoredBindingWinsOverTheConfigurationBaseline() {
        let resolved = AppBinding.resolveBinding(storedBundleID: "com.apple.Mail",
                                                 storedName: "Mail",
                                                 configuredBundleID: "com.apple.Safari")
        XCTAssertEqual(resolved.bundleID, "com.apple.Mail")
        XCTAssertEqual(resolved.name, "Mail")
    }

    func testAnEmptyStoredBindingIsAnIntentionalClear() {
        let resolved = AppBinding.resolveBinding(storedBundleID: "", storedName: "Mail",
                                                 configuredBundleID: "com.apple.Safari")
        XCTAssertNil(resolved.bundleID)
        XCTAssertNil(resolved.name)
    }

    func testAnAbsentStoredBindingTakesTheConfigurationBaseline() {
        let resolved = AppBinding.resolveBinding(storedBundleID: nil, storedName: "Mail",
                                                 configuredBundleID: "com.apple.Safari")
        XCTAssertEqual(resolved.bundleID, "com.apple.Safari")
        XCTAssertNil(resolved.name)
    }

    func testNoStoredBindingAndNoBaselineLeavesTheLightUnbound() {
        let resolved = AppBinding.resolveBinding(storedBundleID: nil, storedName: nil,
                                                 configuredBundleID: nil)
        XCTAssertNil(resolved.bundleID)
        XCTAssertNil(resolved.name)
    }
}
