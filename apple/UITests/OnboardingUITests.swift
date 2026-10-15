import XCTest

final class OnboardingUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testFirstRunEnglishToKorean() {
        exerciseFirstRun(startKorean: false)
    }

    func testFirstRunKoreanToEnglish() {
        exerciseFirstRun(startKorean: true)
    }

    private func exerciseFirstRun(startKorean: Bool) {
        app.launchArguments = ["--demo", "--reset-setup-test",
                               startKorean ? "--language-ko-preview" : "--language-en-preview"]
        app.launch()
        heading(startKorean ? "다음 프롬프트 전에, 사용량을 한눈에." : "A little clarity before your next prompt.")
        capture(startKorean ? "KO-welcome" : "EN-welcome")
        tap(app.buttons["setup-continue"])
        heading(startKorean ? "시작 방법을 선택하세요." : "Choose how to get started.")
        XCTAssertFalse(app.buttons["setup-continue"].isEnabled, "A connection choice is required")
        capture(startKorean ? "KO-connection" : "EN-connection")
        tap(app.buttons["setup-route-demo"])
        XCTAssertTrue(app.buttons["setup-continue"].isEnabled)
        tap(app.buttons["setup-continue"])
        heading(startKorean ? "원하는 방식으로 설정하세요." : "Make it work your way.")
        let toggle = app.switches["setup-foreground-refresh"]
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        capture(startKorean ? "KO-preferences" : "EN-preferences")

        // Language is changed through the public menu, not by relaunching or a preview step.
        tap(app.buttons[startKorean ? "뒤로" : "Back"])
        tap(app.buttons[startKorean ? "뒤로" : "Back"])
        tap(app.buttons["interface-language"])
        tap(app.buttons[startKorean ? "English" : "한국어"])
        let korean = !startKorean
        heading(korean ? "다음 프롬프트 전에, 사용량을 한눈에." : "A little clarity before your next prompt.")
        capture(korean ? "KO-welcome-switched" : "EN-welcome-switched")
        tap(app.buttons["setup-continue"])
        heading(korean ? "시작 방법을 선택하세요." : "Choose how to get started.")
        XCTAssertTrue(app.buttons["setup-route-demo"].isSelected, "Switching language must retain the route")
        capture(korean ? "KO-connection-switched" : "EN-connection-switched")
        tap(app.buttons["setup-continue"])
        heading(korean ? "원하는 방식으로 설정하세요." : "Make it work your way.")
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "0", "Switching language must retain the draft preference")
        capture(korean ? "KO-preferences-switched" : "EN-preferences-switched")
        tap(app.buttons["setup-continue"])
        let demo = app.staticTexts[korean ? "DEMO · 내 계정이 아닌 샘플 데이터" : "DEMO · sample data, not your account"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["setup-heading"].exists)
        capture(korean ? "KO-dashboard" : "EN-dashboard")

        openSettings(korean: korean)
        assertSavedRefresh(korean: korean, value: "0")
        tap(app.buttons[korean ? "초기 설정 다시 보기" : "Review setup"])
        heading(korean ? "다음 프롬프트 전에, 사용량을 한눈에." : "A little clarity before your next prompt.")
        tap(app.buttons["setup-continue"])
        tap(app.buttons["setup-route-later"])
        tap(app.buttons["setup-continue"])
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap() // Cancel must discard this change, not save it.
        XCTAssertEqual(toggle.value as? String, "1")
        tap(app.buttons[korean ? "취소" : "Cancel"])
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        openSettings(korean: korean)
        assertSavedRefresh(korean: korean, value: "0")

        app.terminate()
        // Crucially omit --demo too: it otherwise bypasses setup even if completion was lost.
        // Foreground refresh was disabled, so this launch does not request a network refresh.
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.navigationBars["QuotaDock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["setup-heading"].exists, "Completion must survive Cancel and relaunch")
        openSettings(korean: korean)
        assertSavedRefresh(korean: korean, value: "0")
    }

    private func openSettings(korean: Bool) {
        tap(app.buttons[korean ? "설정" : "Settings"])
        XCTAssertTrue(app.buttons[korean ? "초기 설정 다시 보기" : "Review setup"].waitForExistence(timeout: 5))
    }

    private func assertSavedRefresh(korean: Bool, value: String) {
        let toggle = app.switches[korean ? "앱을 열 때 새로고침" : "Refresh when I open the app"]
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, value)
    }

    private func heading(_ title: String) {
        let element = app.staticTexts["setup-heading"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertEqual(element.label, title)
    }

    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Element must be reachable by scrolling: \(element)")
    }

    private func tap(_ element: XCUIElement) {
        reveal(element)
        element.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
