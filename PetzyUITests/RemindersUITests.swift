import XCTest

/// Напоминания о приёмах: переключатель в настройках просит разрешение у системы
/// и ставит план по расписанию курсов. Сам план проверен юнит-тестами, здесь —
/// проводка: разрешение, переключатель и строка о ближайшем напоминании.
@MainActor
final class RemindersUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTogglePlansReminders() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        app.buttons["Настройки"].tap()

        let toggle = app.switches["remindersToggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 20),
            "нет переключателя напоминаний: \(app.debugDescription)"
        )
        // Тест не должен оставлять включённые напоминания: стенд после него
        // такой же, как до него.
        defer { turnOff(app, toggle) }

        if (toggle.value as? String) != "1" {
            // Тап в центр строки попадает в подпись, выключатель лежит справа.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            allowNotifications()
        }

        let next = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Ближайшее:'")
        ).firstMatch
        XCTAssertTrue(
            next.waitForExistence(timeout: 25),
            "план напоминаний не поставлен: \(app.debugDescription)"
        )
        // Снимок включённого состояния: у уведомлений нет своего экрана, и
        // увидеть план можно только этой строкой.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reminders-on"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Системный вопрос о разрешении живёт вне приложения: его кнопка ищется в
    /// `springboard`, и подпись зависит от языка системы.
    private func allowNotifications() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Разрешить", "Allow"] {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: 5) {
                button.tap()
                return
            }
        }
    }

    private func turnOff(_: XCUIApplication, _ toggle: XCUIElement) {
        guard toggle.exists, (toggle.value as? String) == "1" else { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
}
