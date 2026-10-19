import XCTest

/// Питомец без связи. Человек заводит питомца в метро: он должен остаться в
/// телефоне, показаться в списке неотправленного и уйти на сервер сам, когда
/// связь вернётся. Пропасть молча он не может: человек решит, что питомца
/// нет.
@MainActor
final class OfflinePetUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testNewPetWithoutNetworkWaitsInQueue() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")

        let offline = TestLaunch.offline()
        offline.buttons["Настройки"].tap()
        let add = offline.buttons.containing(.staticText, identifier: "Добавить питомца").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "Кнопка «Добавить питомца» не найдена")
        add.tap()

        // Имя латиницей: кириллица в этом симуляторе не набирается, а проверке
        // важно только, что питомец назван.
        let name = offline.textFields["petName"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "Поле имени не найдено")
        name.tap()
        name.typeText("Test")
        offline.buttons["Сохранить"].tap()

        let saved = offline.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Питомец записан в телефон")
        ).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 20), "Питомца не сказали, что он ждёт связи")
        offline.buttons["Понятно"].tap()
        XCTAssertTrue(
            offline.staticTexts["питомец ждёт отправки"].waitForExistence(timeout: 15),
            "Питомец не встал в очередь: \(offline.debugDescription)"
        )
        // Очередь чистим: иначе прогон оставит стенду лишнего питомца, а
        // следующий прогон сети вышлет его на сервер.
        let remove = offline.buttons["Убрать из очереди"].firstMatch
        if remove.waitForExistence(timeout: 10) {
            remove.tap()
        }
    }
}
