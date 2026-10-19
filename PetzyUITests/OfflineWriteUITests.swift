import XCTest

/// Запись без связи. Человек в метро отметил приём: отметка должна пережить
/// обрыв связи, показаться в списке неотправленного и уйти сама, когда связь
/// вернётся. Молча пропасть она не может: человек решит, что лекарство дал.
@MainActor
final class OfflineWriteUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDoseWithoutNetworkWaitsInQueue() async {
        guard let expected = await TestLaunch.petWithCourse() else {
            XCTFail("На стенде нет ни одного курса лекарства")
            return
        }
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        TestLaunch.selectPet(app, named: expected.pet)
        app.buttons["Лекарства"].tap()
        XCTAssertTrue(
            app.staticTexts[expected.course].waitForExistence(timeout: 25),
            "Курс не открылся при связи, копия не прогрелась: \(app.debugDescription)"
        )

        let offline = TestLaunch.offline()
        offline.buttons["Лекарства"].tap()
        XCTAssertTrue(
            offline.staticTexts["Нет связи, показаны сохранённые данные"].waitForExistence(timeout: 30),
            "Раздел не сказал, что показывает копию: \(offline.debugDescription)"
        )
        let giveNow = offline.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
                "Дали сейчас",
                "Записать дополнительный приём"
            )
        ).firstMatch
        XCTAssertTrue(giveNow.waitForExistence(timeout: 20), "На карточке курса нет кнопки приёма")
        giveNow.tap()
        XCTAssertTrue(offline.buttons["Записать"].waitForExistence(timeout: 15), "Лист отметки не открылся")
        offline.buttons["Записать"].tap()

        let saved = offline.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "записана в телефон")
        ).firstMatch
        XCTAssertTrue(
            saved.waitForExistence(timeout: 20),
            "Отметку не сказали, что она ждёт связи: \(offline.debugDescription)"
        )
        offline.buttons["Понятно"].tap()
        XCTAssertTrue(
            offline.staticTexts["отметка приёма ждёт отправки"].waitForExistence(timeout: 15),
            "Отметка не встала в очередь: \(offline.debugDescription)"
        )
        // Очередь чистим: иначе прогон оставит стенду лишний приём, а следующий
        // прогон сети вышлет его на сервер.
        let remove = offline.buttons["Убрать из очереди"].firstMatch
        if remove.waitForExistence(timeout: 10) {
            remove.tap()
        }
    }
}
