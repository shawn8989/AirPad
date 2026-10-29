import XCTest

final class AppReviewAccessTests: XCTestCase {
    @MainActor
    func testOnboardingAndProAreAccessibleWithoutPairing() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Local network permission") { alert in
            let deny = alert.buttons["Don’t Allow"]
            if deny.exists {
                deny.tap()
                return true
            }
            return false
        }

        // CI installs onto a fresh simulator. No preview state, host, trial
        // override, or StoreKit fixture is used: this tests actual navigation.
        let app = XCUIApplication()
        app.launch()
        let done = app.navigationBars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        capture(app, "Onboarding with Done")
        done.tap()

        let pro = app.buttons["connection.pro"]
        XCTAssertTrue(pro.waitForExistence(timeout: 10))
        XCTAssertTrue(pro.isHittable)
        capture(app, "Pro entry before pairing")
        pro.tap()
        XCTAssertTrue(app.navigationBars["Wield Pro"].waitForExistence(timeout: 10))

        let restore = app.buttons["pro.restore"]
        for _ in 0..<5 where !restore.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["pro.purchase"].exists)
        XCTAssertTrue(restore.isHittable)
        capture(app, "Purchase and restore without pairing")

        app.terminate()
        app.launch()
        XCTAssertTrue(pro.waitForExistence(timeout: 10))
        XCTAssertFalse(done.exists, "Completing onboarding must persist across launches")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
