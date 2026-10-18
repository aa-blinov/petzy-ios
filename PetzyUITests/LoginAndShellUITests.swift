import XCTest

/// Прогон против живого локального стека petzy: `make backend` должен быть поднят.
///
/// Учётные данные передаются через переменные окружения запуска, а не набираются
/// `typeText`: софтурная клавиатура симулятора в этом окружении рисуется
/// неполностью (три клавиши вместо тридцати) и буквы в поле пароля теряет.
/// Само нажатие «Войти» при этом настоящее, проверяется весь путь целиком:
/// вход, разбор ответа, токены в Keychain, запрос списка питомцев.
@MainActor
final class LoginAndShellUITests: XCTestCase {
    private let demoLogin = "demo"
    /// Тот же пароль, что в `scripts/seed_demo.py` репозитория petzy (строка с
    /// `DEMO_PASSWORD`). Держим здесь копию: раннер UI-теста не видит файловую
    /// систему Mac и переменные окружения xcodebuild до него не доходят.
    /// Локальные стенды и демо-аккаунты только для них.
    private let demoPassword = "petzy-demo-2026"

    override func setUp() {
        continueAfterFailure = false
    }

    func testLoginOpensShell() {
        let app = launchSignedOut()
        XCTAssertTrue(
            app.buttons["Войти"].waitForExistence(timeout: 30),
            "Экран входа не появился"
        )
        app.buttons["Войти"].tap()

        XCTAssertTrue(
            app.buttons["Лента"].waitForExistence(timeout: 30),
            "После входа оболочка не открылась: \(app.debugDescription)"
        )
        // Кнопки, а не app.tabBars: на iPhone Duo панель вкладок уходит в боковую
        // полосу и отдельного элемента tabBar в дереве не остаётся. Сама кнопка
        // есть на любом расположении.
        for tab in ["Лекарства", "Медкарта", "Документы", "Настройки"] {
            XCTAssertTrue(app.buttons[tab].exists, "Вкладка «\(tab)» пропала")
        }
        XCTAssertTrue(
            app.buttons["Рекс"].waitForExistence(timeout: 15),
            "Выбранный питомец из демо-данных не показан"
        )
    }

    /// Токен, сохранённый в Keychain, должен переживать перезапуск: без этого
    /// человеку пришлось бы вводить пароль при каждом открытии приложения.
    func testSessionSurvivesRelaunch() {
        let app = launchSignedOut()
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 30))
        app.buttons["Войти"].tap()
        XCTAssertTrue(
            app.buttons["Лента"].waitForExistence(timeout: 30),
            "Первый вход не прошёл: \(app.debugDescription)"
        )

        app.terminate()
        // Флаг сбрасываем: с ним приложение на старте само стирает токены,
        // и проверка перезапуска проверяла бы не то, а запуск с нуля.
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(
            app.buttons["Лента"].waitForExistence(timeout: 30),
            "После перезапуска снова спросили пароль"
        )
    }

    /// Без верного пароля приложение обязано остаться на экране входа и показать
    /// текст бэкенда, а не молча провалиться.
    func testWrongPasswordStaysOnLogin() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSignedOut"]
        app.launchEnvironment = [
            "PETZY_TEST_LOGIN": demoLogin,
            "PETZY_TEST_PASSWORD": "точно неверный"
        ]
        app.launch()

        app.buttons["Войти"].tap()

        XCTAssertTrue(
            app.staticTexts["Неверный логин или пароль"].waitForExistence(timeout: 30),
            "Текст ошибки от бэкенда не показан"
        )
        XCTAssertFalse(app.buttons["Лента"].exists, "Оболочка открылась с чужим паролем")
    }

    private func launchSignedOut() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSignedOut"]
        app.launchEnvironment = [
            "PETZY_TEST_LOGIN": demoLogin,
            "PETZY_TEST_PASSWORD": demoPassword
        ]
        app.launch()
        return app
    }
}
