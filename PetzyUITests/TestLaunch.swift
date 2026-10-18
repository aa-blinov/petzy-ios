import XCTest

/// Общий запуск приложения на локальном стенде petzy.
///
/// Учётные данные передаются переменными окружения, а не набираются `typeText`:
/// софтурная клавиатура симулятора в этом окружении рисуется неполностью (три
/// клавиши вместо тридцати) и буквы в поле пароля теряет. Само нажатие «Войти»
/// при этом настоящее.
enum TestLaunch {
    /// Тот же пароль, что в `scripts/seed_demo.py` репозитория petzy (строка с
    /// `DEMO_PASSWORD`). Держим здесь копию: раннер UI-теста не видит файловую
    /// систему Mac и переменные окружения xcodebuild до него не доходят.
    /// Локальные стенды и демо-аккаунты только для них.
    static let demoLogin = "demo"
    static let demoPassword = "petzy-demo-2026"

    /// Открывает приложение с экрана входа с уже подставленными данными.
    static func signedOut() -> XCUIApplication {
        launch(extraArguments: ["-uiTestSignedOut"])
    }

    private static func launch(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extraArguments
        app.launchEnvironment = [
            "PETZY_TEST_LOGIN": demoLogin,
            "PETZY_TEST_PASSWORD": demoPassword
        ]
        app.launch()
        return app
    }

    /// Входит настоящей кнопкой «Войти» и ждёт оболочку.
    @discardableResult
    static func logIn(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        guard app.buttons["Войти"].waitForExistence(timeout: timeout) else { return false }
        app.buttons["Войти"].tap()
        return app.buttons["Лента"].waitForExistence(timeout: timeout)
    }
}
