import XCTest

/// Медкарта как документ: карточка питомца, тревога, готовность и блоки.
/// Раздел открывается строкой с шевроном внизу блока, а не плиткой, и «назад»
/// возвращает на медкарту, а не в соседний раздел.
@MainActor
final class MedicalCardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Дверь в разделе лежит ниже экрана: список длинный, и прокрутка нужна.
    /// Прокрутка идёт по шагам и проверяет каждый: свайп может перешагнуть
    /// нужную строку, и тогда она «пропала» бы совсем.
    private func scrollTo(_ app: XCUIApplication, _ label: String) -> Bool {
        let button = app.buttons[label]
        var tries = 0
        while !button.exists, tries < 12 {
            app.swipeUp()
            tries += 1
        }
        return button.exists
    }

    /// Верх документа: карточка питомца и готовность. Отдельного паспорта с
    /// фактами больше нет: личность питомца показывает карточка, а его данные
    /// живут в «О питомце», куда карточка ведёт.
    func testCardShowsPetAndReadiness() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        app.buttons["Медкарта"].tap()
        XCTAssertTrue(app.buttons["petSwitcher"].waitForExistence(timeout: 20), "Медкарта не открылась")

        XCTAssertTrue(
            app.buttons["petCard"].waitForExistence(timeout: 20),
            "В медкарте нет карточки питомца: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.staticTexts["Готовность к приёму"].exists,
            "В медкарте нет готовности к приёму: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.staticTexts["Данные для врача"].exists,
            "В медкарте нет данных для врача: \(app.debugDescription)"
        )
    }

    func testSectionOpensAndBackReturnsToCard() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        app.buttons["Медкарта"].tap()
        XCTAssertTrue(app.buttons["petSwitcher"].waitForExistence(timeout: 20), "Медкарта не открылась")

        let door = app.buttons["Все визиты"]
        XCTAssertTrue(scrollTo(app, "Все визиты"), "Дверь в раздел визитов не найдена: \(app.debugDescription)")
        door.tap()
        XCTAssertTrue(
            app.navigationBars["Приёмы врача"].waitForExistence(timeout: 20),
            "Дверь открыла не тот раздел: \(app.debugDescription)"
        )

        app.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.buttons["petSwitcher"].waitForExistence(timeout: 20),
            "«Назад» не вернул на медкарту: \(app.debugDescription)"
        )
    }

    /// В веб-приложении у каждой части медкарты своя кнопка «+»: в разделе
    /// «Приёмы врача» она открывает форму визита, а не общую форму записи.
    func testSectionAddsItsOwnKind() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        app.buttons["Медкарта"].tap()
        XCTAssertTrue(app.buttons["petSwitcher"].waitForExistence(timeout: 20), "Медкарта не открылась")

        let door = app.buttons["Все визиты"]
        XCTAssertTrue(scrollTo(app, "Все визиты"), "Дверь в раздел визитов не найдена: \(app.debugDescription)")
        door.tap()
        XCTAssertTrue(app.navigationBars["Приёмы врача"].waitForExistence(timeout: 20), "Раздел не открылся")

        let add = app.buttons["Новая запись"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "В разделе нет кнопки «+»")
        add.tap()
        // У визита свои поля: жалобы, диагноз, назначения. Остался бы вид
        // прививки — их бы не было. Ищем по заголовку раздела, а не по
        // подсказке поля: жалоба из заметки «К приёму» подставляется заранее,
        // и подсказка тогда исчезает.
        XCTAssertTrue(
            app.staticTexts["Жалобы"].waitForExistence(timeout: 20),
            "Форма открылась не с визитом: \(app.debugDescription)"
        )
    }
}
