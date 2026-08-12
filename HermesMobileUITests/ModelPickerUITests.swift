import XCTest

final class ModelPickerUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testProviderLongPressOffersAppearanceEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--model-picker-capture",
            "--model-picker-server", "http://100.69.228.58:8787"
        ]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        guard provider.waitForExistence(timeout: 15) else {
            throw XCTSkip("The live catalog did not expose openai-codex.")
        }

        addScreenshot(named: "model-picker")

        provider.press(forDuration: 1.0)
        let editAppearance = app.buttons["Edit Appearance"]
        XCTAssertTrue(editAppearance.waitForExistence(timeout: 5))
        addScreenshot(named: "provider-context-menu")
        editAppearance.tap()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider-editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Provider ID"].exists)
        XCTAssertTrue(app.staticTexts["openai-codex"].exists)
        addScreenshot(named: "provider-editor")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
