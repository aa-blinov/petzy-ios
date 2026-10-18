import XCTest

/// Лента против живого локального стенда petzy: `make backend` должен быть поднят.
///
/// Здесь проверяется проводка, а не логика разбора: логику разбора держат
/// юнит-тесты, где она выполняется за миллисекунды.
@MainActor
final class FeedUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Лента показывает записи настоящего питомца.
    func testFeedShowsRecords() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        // Ищем строку записи по времени в ней, а не по названию типа: стенд
        // копится от прогонов, конкретный тип наверху ленты не держится, а
        // проверять тут надо то, что лента вообще показывает записи питомца.
        XCTAssertTrue(
            recordRow(app).waitForExistence(timeout: 30),
            "записи ленты не показаны: \(app.debugDescription)"
        )
        // Заголовок дня это «Сегодня», «Вчера» или дата: на первом экране
        // сегодняшняя дата не обязана стоять, и требование только числовой
        // даты ломалось о число сегодняшних записей.
        XCTAssertTrue(
            dayHeader(app).waitForExistence(timeout: 30),
            "дни в ленте без заголовков: \(app.debugDescription)"
        )
    }

    /// Кнопка «Загрузить ещё» реально дочитывает следующую страницу: после
    /// неё в ленте появляются дни, которых на первой странице не было.
    func testLoadMoreReadsNextPage() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        var seen: Set<String> = []
        _ = scrollToEnd(of: app, collectingDaysInto: &seen)
        XCTAssertTrue(
            app.buttons["Загрузить ещё"].exists,
            "в ленте 263 записи, а кнопки догрузки нет: \(app.debugDescription)"
        )

        app.buttons["Загрузить ещё"].tap()

        var after = seen
        _ = scrollToEnd(of: app, collectingDaysInto: &after)
        XCTAssertTrue(
            after.count > seen.count,
            "после догрузки новых дней не появилось: было \(seen.count), стало \(after.count)"
        )
    }

    /// Запись, созданная приложением, доходит до сервера и появляется в ленте,
    /// а удаление через свайп убирает её и оттуда, и оттуда же с экрана.
    /// Тип выбран без полей, чтобы проверка не зависела от набора текста:
    /// софтверная клавиатура симулятора в этом окружении буквы теряет.
    func testCreateAndDeleteEvent() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        app.buttons["Новая запись"].tap()
        XCTAssertTrue(
            app.navigationBars["Добавить запись"].waitForExistence(timeout: 20),
            "каталог типов не открылся: \(app.debugDescription)"
        )
        // Тип взят из третьей группы: на узком экране он ниже первого экрана и
        // в дереве доступности появляется только после прокрутки.
        let cough = app.staticTexts["Кашель или чихание"]
        for _ in 0 ..< 6 where !cough.exists {
            app.swipeUp()
        }
        XCTAssertTrue(cough.waitForExistence(timeout: 20), "в каталоге нет типа записи: \(app.debugDescription)")
        cough.tap()

        XCTAssertTrue(
            app.navigationBars["Новая запись"].waitForExistence(timeout: 20),
            "форма новой записи не открылась: \(app.debugDescription)"
        )
        app.buttons["Сохранить"].tap()

        let row = app.staticTexts["Кашель или чихание"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 30),
            "созданная запись не появилась в ленте: \(app.debugDescription)"
        )

        row.swipeLeft()
        attach(app, "17-swipe-actions")
        let remove = app.buttons["Удалить"]
        XCTAssertTrue(remove.waitForExistence(timeout: 20), "свайп не открыл действия: \(app.debugDescription)")
        remove.tap()

        // Удаление на сервере жёсткое, поэтому перед ним стоит подтверждение.
        attach(app, "18-delete-confirm")
        let confirm = app.buttons["Удалить"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 20),
            "подтверждение удаления не спросили: \(app.debugDescription)"
        )
        confirm.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: row)
        waitForExpectations(timeout: 30)
    }

    /// Тап по записи открывает правку с её значениями: пустая форма выглядела бы
    /// как потеря записи, а с пустыми полями правка стёрла бы её.
    func testTapRecordOpensEditWithValues() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        // Берём любую строку записи: запись с полем у всех типов своё, а
        // конкретный тип наверху ленты от прогонов не удерживается.
        let row = recordRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 30), "записи ленты не показаны: \(app.debugDescription)")
        row.tap()

        XCTAssertTrue(
            app.navigationBars["Правка"].waitForExistence(timeout: 20),
            "правка не открылась: \(app.debugDescription)"
        )
        // У поля записи есть подпись и значение: без подписи человек не поймёт,
        // что правит, а без значения правка стёрла бы запись.
        let field = app.textFields.firstMatch
        XCTAssertFalse(field.value as? String ?? "" == "", "поле правки пустое, запись при переходе потерялась")
        let placeholder = field.placeholderValue ?? ""
        XCTAssertFalse(placeholder.isEmpty, "у поля правки нет подписи: \(app.debugDescription)")
    }

    /// Снимок экрана в отчёт прогона. Жест свайпа через `idb` строку не
    /// открывает, а `XCUITest` открывает, поэтому глазами этот кусок смотрится
    /// только так: снимок снимается внутри теста.
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Заголовок дня: «Сегодня», «Вчера» или дата.
    private func dayHeader(_ app: XCUIApplication) -> XCUIElement {
        let day = NSPredicate(format: "label MATCHES %@", "^(Сегодня|Вчера|\\d{2}\\.\\d{2}\\.\\d{4})$")
        return app.staticTexts.matching(day).firstMatch
    }

    /// Строка записи ленты. Отбор по времени внутри ячейки, а не по названию
    /// типа: заголовок дня с одним текстом под это не попадает, а любая запись
    /// время в себе содержит. Типовой состав ленты меняется от прогона к
    /// прогону, и проверка на конкретном типе ломалась о чужие записи сверху.
    private func recordRow(_ app: XCUIApplication) -> XCUIElement {
        let time = NSPredicate(format: "label MATCHES %@", "^\\d{2}:\\d{2}$")
        return app.staticTexts.matching(time).firstMatch
    }

    /// Листает до конца ленты, попутно собирая заголовки дней.
    /// Возвращает то, что собрано, и заодно докладывает про кнопку догрузки.
    private func scrollToEnd(of app: XCUIApplication, collectingDaysInto days: inout Set<String>) -> Set<String> {
        // Страховка на 80 жестов: лента длинная, а бесконечно скроллить нельзя.
        for _ in 0 ..< 80 {
            days.formUnion(dateHeaders(app))
            if app.buttons["Загрузить ещё"].exists {
                return days
            }
            app.swipeUp()
        }
        days.formUnion(dateHeaders(app))
        return days
    }

    /// Заголовки дней в виде «04.10.2026». Отбор идёт предикатом, а не
    /// фильтром по всем подписям: список пересобирается на каждом жесте, и
    /// элемент под индексом успевает исчезнуть, и прогон падает на «No matches
    /// found for Element at index» без всякой связи с приложением.
    private func dateHeaders(_ app: XCUIApplication) -> [String] {
        let pattern = #"^\d{2}\.\d{2}\.\d{4}$"#
        return app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", pattern))
            .allElementsBoundByIndex
            .map(\.label)
    }
}
