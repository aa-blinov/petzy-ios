import XCTest

/// Выгрузка записей: выбор типа и формата, файл и системное меню.
///
/// Выбор идёт через тест, а не глазами: тап по всплывающему списку через
/// `idb` не срабатывает, меню просто закрывается, и такой прогон ничего не
/// проверял бы.
@MainActor
final class ExportUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testExportOfOneTypeReachesShare() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        app.buttons["Настройки"].tap()
        // Пункт это Button с .plain, и в дереве он не кнопка, а текст.
        let export = app.staticTexts["Экспорт записей"]
        XCTAssertTrue(export.waitForExistence(timeout: 20), "пункта экспорта нет: \(app.debugDescription)")
        export.tap()

        XCTAssertTrue(
            app.navigationBars["Экспорт записей"].waitForExistence(timeout: 20),
            "лист выгрузки не открылся: \(app.debugDescription)"
        )
        // Типы приходят отдельным запросом: из «Настроек» история могла и не
        // открываться, и без них в списке остаётся одно «Все».
        let picker = app.descendants(matching: .any).matching(identifier: "Записи").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "выбор типа не показан: \(app.debugDescription)")
        picker.tap()

        let weight = app.buttons["Вес"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 20), "в списке типов нет «Вес»: \(app.debugDescription)")
        weight.tap()

        XCTAssertTrue(
            app.staticTexts["Вес"].firstMatch.waitForExistence(timeout: 10),
            "выбранный тип не закрепился: \(app.debugDescription)"
        )

        let prepare = app.buttons["Подготовить файл"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 20), "кнопки выгрузки нет: \(app.debugDescription)")
        prepare.tap()

        let share = app.buttons["Поделиться файлом"]
        XCTAssertTrue(
            share.waitForExistence(timeout: 30),
            "файл не скачался или не предложен к отправке: \(app.debugDescription)"
        )
    }
}
