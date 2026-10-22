import XCTest

/// Все маршруты приложения открываются: пять вкладок, их листы и формы, листы
/// настроек, экраны входа. Тест только открывает и закрывает — ни одного
/// сохранения, удаления и выхода в нём нет, стенд после него тот же, что до.
///
/// Отдельные тесты проверяют поведение внутри экранов; здесь проверяется, что
/// каждый путь вообще ведёт куда-то, а не в пустоту.
@MainActor
final class RoutesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTabsOpen() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        for tab in ["Лента", "Лекарства", "Медкарта", "Документы", "Настройки"] {
            app.buttons[tab].tap()
            XCTAssertTrue(
                app.staticTexts[tab].waitForExistence(timeout: 20),
                "вкладка «\(tab)» не открылась: \(app.debugDescription)"
            )
        }
    }

    /// Медкарта: раздел, обе формы и передача врачу.
    func testMedicalCardRoutes() throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        app.buttons["Медкарта"].tap()
        XCTAssertTrue(app.staticTexts["Медкарта"].waitForExistence(timeout: 20))

        // Раздел прививок и назад.
        try openRow(app, title: "Все прививки")
        XCTAssertTrue(app.navigationBars["Прививки"].waitForExistence(timeout: 15))
        back(app)

        // Форма «К приёму»: её «Изменить» не единственный на карте, поэтому
        // берётся кнопка под заголовком раздела, а не первая попавшаяся.
        try openEditBelow(app, header: "К приёму")
        XCTAssertTrue(app.navigationBars["К приёму"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()

        // Форма профиля для врача.
        try openEditBelow(app, header: "Данные для врача")
        XCTAssertTrue(app.navigationBars["Профиль"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()

        // Передача врачу: меню, ссылка, лист, назад.
        app.buttons["Передать врачу"].tap()
        app.buttons["Ссылка для врача"].tap()
        XCTAssertTrue(app.navigationBars["Ссылка для врача"].waitForExistence(timeout: 15))
        app.buttons["Готово"].tap()
    }

    /// Лекарства: новый курс и лист отметки, оба без записи. Курс берётся с
    /// открытым слотом, иначе кнопки приёма на карточке может не быть.
    func testMedicationsSheets() async throws {
        guard let expected = await TestLaunch.petWithCourse() else {
            throw XCTSkip("На стенде нет ни одного курса лекарства")
        }
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        TestLaunch.selectPet(app, named: expected.pet)
        app.buttons["Лекарства"].tap()
        XCTAssertTrue(app.staticTexts[expected.course].waitForExistence(timeout: 25))

        app.buttons["Новое лекарство"].tap()
        XCTAssertTrue(app.navigationBars["Новое лекарство"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()

        // Лист отметки открывается и закрывается без записи.
        let give = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Дали сейчас",
            "Записать дополнительный приём"
        )).firstMatch
        XCTAssertTrue(give.waitForExistence(timeout: 20), "на карточке курса нет кнопки приёма")
        give.tap()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()
    }

    /// Документы: форма загрузки, правка и просмотр файла.
    func testDocumentsRoutes() {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        app.buttons["Документы"].tap()
        XCTAssertTrue(app.staticTexts["Документы"].waitForExistence(timeout: 20))

        let add = app.buttons["Новый документ"].firstMatch
        if add.waitForExistence(timeout: 10) {
            add.tap()
        } else {
            app.buttons["Добавить документ"].tap()
        }
        XCTAssertTrue(app.navigationBars["Документ"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "document-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "в документах нет строк: \(app.debugDescription)")

        // Правка открывается свайпом и закрывается без сохранения.
        row.swipeLeft()
        app.buttons["Изменить"].tap()
        XCTAssertTrue(app.navigationBars["Правка документа"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()

        // Тап по строке скачивает файл и показывает его системным
        // просмотрщиком; закрывается его же кнопкой.
        row.tap()
        // Кнопка закрытия системная, с техническим именем вместо подписи:
        // крестик в углу, а не «Готово». Имя стабильнее подписи.
        let close = app.buttons.matching(NSPredicate(
            format: "identifier == 'QLOverlayDoneButtonAccessibilityIdentifier'"
        )).firstMatch
        XCTAssertTrue(
            close.waitForExistence(timeout: 25),
            "просмотр файла не открылся: \(app.debugDescription)"
        )
        close.tap()
    }

    /// Настройки, которых нет в отдельных тестах: питомец, значения по
    /// умолчанию, аккаунт, справка, политика, выгрузка, новый питомец.
    func testSettingsRoutes() throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")
        app.buttons["Настройки"].tap()

        try openRow(app, title: "О питомце")
        XCTAssertTrue(app.navigationBars["О питомце"].waitForExistence(timeout: 15))
        // «Типы на „+“» живут в форме питомца и ведут в редактор набора.
        try openRow(app, title: "Типы на «+»")
        XCTAssertTrue(
            app.navigationBars["Типы на «+»"].waitForExistence(timeout: 15),
            "редактор набора не открылся: \(app.debugDescription)"
        )
        back(app, to: "О питомце")
        back(app, to: "Настройки")

        try openRow(app, title: "Добавить питомца")
        XCTAssertTrue(app.navigationBars["Новый питомец"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()

        try openRow(app, title: "Значения по умолчанию")
        XCTAssertTrue(app.navigationBars["Значения по умолчанию"].waitForExistence(timeout: 15))
        back(app, to: "Настройки")

        try openRow(app, title: "Аккаунт")
        XCTAssertTrue(app.navigationBars["Аккаунт"].waitForExistence(timeout: 15))
        back(app, to: "Настройки")

        try openRow(app, title: "Справка")
        XCTAssertTrue(app.navigationBars["Справка"].waitForExistence(timeout: 15))
        back(app, to: "Настройки")

        try openRow(app, title: "Политика обработки данных")
        XCTAssertTrue(app.navigationBars["Политика"].waitForExistence(timeout: 15))
        back(app, to: "Настройки")

        try openRow(app, title: "Экспорт записей")
        XCTAssertTrue(app.navigationBars["Экспорт записей"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()
    }

    /// Вход: регистрация и восстановление пароля открываются, ничего не
    /// отправляя. Отдельным прогоном без входа, чтобы было откуда открыть.
    /// Если сервер закрыл регистрацию, кнопки нет — и это тоже правда стенда,
    /// а не поломка: тогда проверяется только восстановление.
    func testAuthRoutes() {
        let app = TestLaunch.signedOut()

        if app.buttons["Создать аккаунт"].waitForExistence(timeout: 10) {
            app.buttons["Создать аккаунт"].tap()
            XCTAssertTrue(app.navigationBars["Новый аккаунт"].waitForExistence(timeout: 15))
            app.buttons["Отмена"].tap()
        }

        app.buttons["Забыли пароль?"].tap()
        XCTAssertTrue(app.navigationBars["Забыли пароль"].waitForExistence(timeout: 15))
        app.buttons["Отмена"].tap()
    }

    // MARK: - Ходьба

    /// Строка настроек: после закрытия предыдущего экрана список стоит где
    /// угодно, поэтому листаем сначала вниз, потом вверх.
    private func openRow(_ app: XCUIApplication, title: String) throws {
        let row = app.buttons.containing(.staticText, identifier: title).firstMatch
        for _ in 0 ..< 4 where !row.exists {
            app.swipeUp()
        }
        for _ in 0 ..< 8 where !row.exists {
            app.swipeDown()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "нет строки «\(title)»: \(app.debugDescription)")
        row.tap()
    }

    /// Кнопка «Изменить» под заголовком раздела: на карте их несколько, и
    /// первая попавшаяся ведёт не туда.
    private func openEditBelow(_ app: XCUIApplication, header: String) throws {
        let title = app.staticTexts[header]
        for _ in 0 ..< 4 where !title.exists {
            app.swipeUp()
        }
        for _ in 0 ..< 8 where !title.exists {
            app.swipeDown()
        }
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "нет раздела «\(header)»: \(app.debugDescription)"
        )
        let top = title.frame.minY
        let buttons = app.buttons.matching(identifier: "Изменить").allElementsBoundByIndex
            .filter { $0.frame.minY > top }
        guard let edit = buttons.first else {
            throw XCTSkip("под «\(header)» нет кнопки правки")
        }
        edit.tap()
    }

    private func back(_ app: XCUIApplication, to title: String = "Медкарта") {
        // Тап иногда уходит в анимацию перехода и теряется: тогда остаёмся на
        // месте и тапаем ещё раз. Проверка перед тапом защищает от двойного
        // возврата, когда первый тап просто опоздал.
        for _ in 0 ..< 3 {
            if app.navigationBars[title].exists {
                return
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            _ = app.navigationBars[title].waitForExistence(timeout: 6)
        }
        XCTAssertTrue(
            app.navigationBars[title].exists,
            "назад в «\(title)» не вернулся: \(app.debugDescription)"
        )
    }
}
