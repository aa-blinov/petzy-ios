import XCTest

/// Настройки разложены по секциям, и секции идут в осмысленном порядке:
/// питомец, записи, новые записи, аккаунт, приложение, выход. Плоский список
/// вперемешку путал: «Справка» стояла между питомцем и аккаунтом, и было не
/// видно, что это вообще разные вещи.
final class SettingsUITests: XCTestCase {
    @MainActor
    func testSettingsSectionsStandInOrder() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        app.buttons["Настройки"].tap()

        let wanted = ["Питомцы", "Записи", "Новые записи", "Аккаунт", "О приложении", "Выход"]
        var seen: [String] = []
        // Секция ниже экрана в дереве доступности не видна, поэтому листаем.
        // Сдвиг меньше экрана: за один жест секция не должна проскочить между
        // двумя замерами.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        for _ in 0 ..< 12 {
            for label in app.staticTexts.allElementsBoundByIndex.map(\.label) {
                if wanted.contains(label), !seen.contains(label) {
                    seen.append(label)
                }
            }
            if seen.count == wanted.count {
                break
            }
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        XCTAssertEqual(seen, wanted, "секции настроек идут не по порядку: \(seen)")

        // Версия стоит в «О приложении»: её называют, когда просят помощи.
        XCTAssertTrue(
            app.staticTexts["Версия"].exists,
            "в настройках нет строки версии: \(app.debugDescription)"
        )
    }
}
