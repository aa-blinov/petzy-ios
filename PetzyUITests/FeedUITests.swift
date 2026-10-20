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

    /// Лента догружается сама, когда человек дошёл до конца: кнопки
    /// «Загрузить ещё» в ней больше нет, а страница приезжает без всякого
    /// нажатия, и в ленте появляются дни, которых на первой странице не было.
    ///
    /// Страница есть не у каждого питомца, и это не поломка: страницу
    /// приложение берёт по сто записей, и когда у питомца их меньше, сервер не
    /// отдаёт курсор. Поэтому питомец для проверки выбирается по стенду, а
    /// выбранный по умолчанию может быть тем, у кого догружать нечего.
    func testFeedLoadsNextPageOnItsOwn() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        guard let (pet, day) = await TestLaunch.petWithNextFeedPage() else {
            throw XCTSkip("на стенде нет питомца, чья следующая страница приносит новые записи, догружать нечего")
        }
        TestLaunch.selectPet(app, named: pet)

        XCTAssertFalse(
            app.buttons["Загрузить ещё"].exists,
            "в ленте осталась кнопка догрузки: \(app.debugDescription)"
        )

        // Листаем до конца: страница должна приехать сама, без кнопки. День
        // берём самый старый: он в самом низу ленты, и мимо него прокрутка не
        // проскакивает, а середину пролистать можно между двумя замерами.
        var seen: Set<String> = []
        for _ in 0 ..< 120 {
            seen.formUnion(dateHeaders(app))
            if seen.contains(day) {
                break
            }
            app.swipeUp()
        }
        seen.formUnion(dateHeaders(app))

        XCTAssertTrue(
            seen.contains(day),
            "страница не подгрузилась сама: дня \(day) так и не появилось"
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

        // Заголовок формы — название типа записи: «Правка» и «Новая запись»
        // ничего не говорили о том, что человек правит.
        XCTAssertTrue(
            app.navigationBars["Кашель или чихание"].waitForExistence(timeout: 20),
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

        // Заголовок формы называет тип записи, а он у каждой строки свой,
        // поэтому форма опознаётся кнопкой сохранения, а не заголовком.
        XCTAssertTrue(
            app.buttons["Сохранить"].waitForExistence(timeout: 20),
            "правка не открылась: \(app.debugDescription)"
        )
        // У поля записи есть значение: без него правка стёрла бы запись.
        // Подписи поля в плейсхолдере больше нет (он исчезал при вводе), она
        // стоит рядом отдельной подписью.
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "в форме правки нет поля")
        XCTAssertFalse(field.value as? String ?? "" == "", "поле правки пустое, запись при переходе потерялась")
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

    /// Строка записи ленты. Ищем кнопку, а не текст: строка должна быть
    /// кнопкой, иначе голос её не откроет, а тап по тексту внутри кнопки с
    /// `.plain` ничего не делает. Отбор по времени внутри подписи кнопки, а не
    /// по названию типа: заголовок дня с одним текстом под это не попадает, а
    /// любая запись время в себе содержит. Типовой состав ленты меняется от
    /// прогона к прогону, и проверка на конкретном типе ломалась о чужие
    /// записи сверху.
    private func recordRow(_ app: XCUIApplication) -> XCUIElement {
        let time = NSPredicate(format: "label MATCHES %@", ".*\\d{2}:\\d{2}.*")
        return app.buttons.matching(time).firstMatch
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
