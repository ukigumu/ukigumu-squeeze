import XCTest

struct MainWindowPage {
    let app: XCUIApplication

    var compressButton: XCUIElement { app.buttons["compressButton"] }
    var cancelButton: XCUIElement { app.buttons["cancelButton"] }
    var formatPicker: XCUIElement { app.popUpButtons["formatPicker"] }
    var progress: XCUIElement { app.progressIndicators["batchProgress"] }
    var errorMessage: XCUIElement { app.staticTexts["errorMessage"] }
}
