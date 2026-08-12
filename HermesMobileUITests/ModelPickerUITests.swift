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
            "--model-picker-palette", "warm",
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
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        addScreenshot(named: "provider-context-menu")
        edit.tap()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider-editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields.matching(identifier: "model-picker.provider-name").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "model-picker.choose-image").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Provider ID"].exists)
        addScreenshot(named: "provider-editor")

        let chooseImage = app.descendants(matching: .any)
            .matching(identifier: "model-picker.choose-image").firstMatch
        chooseImage.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose File"].exists)
        addScreenshot(named: "provider-image-menu")
    }

    func testStandardPaletteProviderEditorUsesSameFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--model-picker-capture",
            "--model-picker-palette", "standard",
            "--model-picker-server", "http://100.69.228.58:8787"
        ]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        guard provider.waitForExistence(timeout: 15) else {
            throw XCTSkip("The live catalog did not expose openai-codex.")
        }

        addScreenshot(named: "model-picker-standard")
        provider.press(forDuration: 1.0)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider-editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        addScreenshot(named: "provider-editor-standard")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
