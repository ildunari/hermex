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
            "--model-picker-fixture",
            "--model-picker-palette", "warm",
        ]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))

        addScreenshot(named: "model-picker")

        provider.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Add to Favorites"].waitForExistence(timeout: 5))
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

        app.buttons["Provider Details"].tap()
        XCTAssertTrue(app.staticTexts["Provider ID"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["openai-codex"].exists)

        let chooseImage = app.descendants(matching: .any)
            .matching(identifier: "model-picker.choose-image").firstMatch
        chooseImage.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose File"].exists)
        addScreenshot(named: "provider-image-menu")
    }

    func testProviderFavoriteFiltersProviderRailAndModels() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--model-picker-capture",
            "--model-picker-fixture",
            "--model-picker-palette", "warm",
        ]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        provider.press(forDuration: 1.0)
        let addProviderFavorite = app.buttons["Add to Favorites"]
        XCTAssertTrue(addProviderFavorite.waitForExistence(timeout: 5))
        addProviderFavorite.tap()

        let model = app.descendants(matching: .any)
            .matching(identifier: "model-picker.model.openai-codex.gpt-5.5-codex").firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        app.buttons["Add GPT-5.5 Codex to favorites"].tap()

        let favorites = app.buttons["Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()

        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.fireworks").firstMatch.exists)
        addScreenshot(named: "model-picker-provider-favorites")
    }

    func testProviderRailIgnoresVerticalDragAndStillScrollsHorizontally() {
        let app = XCUIApplication()
        app.launchArguments = ["--model-picker-capture", "--model-picker-fixture"]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        let originalFrame = provider.frame

        provider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: provider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertEqual(provider.frame.minY, originalFrame.minY, accuracy: 1)

        provider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: provider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        let customProvider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.custom-private-provider").firstMatch
        XCTAssertTrue(customProvider.waitForExistence(timeout: 5))
        XCTAssertTrue(customProvider.isHittable)
    }

    func testStandardPaletteProviderEditorUsesSameFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--model-picker-capture",
            "--model-picker-fixture",
            "--model-picker-palette", "standard",
        ]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))

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

    func testProviderCardsRemainUsableAtLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--model-picker-capture",
            "--model-picker-fixture",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let provider = app.descendants(matching: .any)
            .matching(identifier: "model-picker.provider.openai-codex").firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        XCTAssertTrue(provider.isHittable)
        XCTAssertGreaterThan(provider.frame.width, 170)
        provider.tap()
        XCTAssertTrue(provider.isSelected)
        addScreenshot(named: "model-picker-accessibility-xxxl")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
