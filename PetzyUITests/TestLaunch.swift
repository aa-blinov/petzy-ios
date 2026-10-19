import XCTest

/// Общий запуск приложения на локальном стенде petzy.
///
/// Учётные данные передаются переменными окружения, а не набираются `typeText`:
/// софтурная клавиатура симулятора в этом окружении рисуется неполностью (три
/// клавиши вместо тридцати) и буквы в поле пароля теряет. Само нажатие «Войти»
/// при этом настоящее.
enum TestLaunch {
    /// Тот же пароль, что в `scripts/seed_demo.py` репозитория petzy (строка с
    /// `DEMO_PASSWORD`). Держим здесь копию: раннер UI-теста не видит файловую
    /// систему Mac и переменные окружения xcodebuild до него не доходят.
    /// Локальные стенды и демо-аккаунты только для них.
    static let demoLogin = "demo"
    static let demoPassword = "petzy-demo-2026"

    /// Открывает приложение с экрана входа с уже подставленными данными.
    static func signedOut() -> XCUIApplication {
        launch(extraArguments: ["-uiTestSignedOut"])
    }

    /// Открывает приложение на первом экране знакомства: сессия сброшена, а
    /// знакомство показано. Порядок аргументов важен: `-uiTestSignedOut`
    /// знакомство пропускает, `-uiTestOnboarding` показывает.
    static func onboarding() -> XCUIApplication {
        launch(extraArguments: ["-uiTestSignedOut", "-uiTestOnboarding"])
    }

    /// Запуск без сервера. Адрес указывает на порт, где никто не слушает:
    /// приложение получает обрыв связи, а не пустой ответ. Ключи входа не
    /// трогаем намеренно — сессия из Keychain должна восстановиться, иначе
    /// проверялась бы форма входа, а не копия.
    static func offline() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-petzyBaseURL", "http://127.0.0.1:5999"]
        app.launch()
        return app
    }

    private static func launch(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extraArguments
        app.launchEnvironment = [
            "PETZY_TEST_LOGIN": demoLogin,
            "PETZY_TEST_PASSWORD": demoPassword
        ]
        app.launch()
        return app
    }

    /// Входит настоящей кнопкой «Войти» и ждёт оболочку.
    ///
    /// Попытка вторая: сервер пускает пять входов в минуту с одного адреса,
    /// а прогон UI-тестов входит в приложение в каждом тесте, и на седьмом
    /// месте ложное падение выглядит как поломка приложения. Пауза перед
    /// повтором длиннее минуты, поэтому успевает сойти окно.
    @discardableResult
    static func logIn(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        guard app.buttons["Войти"].waitForExistence(timeout: timeout) else { return false }
        app.buttons["Войти"].tap()
        if app.buttons["Лента"].waitForExistence(timeout: timeout) {
            return true
        }

        Thread.sleep(forTimeInterval: 65)
        guard app.buttons["Войти"].waitForExistence(timeout: timeout) else { return false }
        app.buttons["Войти"].tap()
        return app.buttons["Лента"].waitForExistence(timeout: timeout)
    }

    /// Имя питомца, у которого лента не помещается в одну страницу, то есть у
    /// которого кнопка догрузки вообще появится. Приложение берёт страницу по
    /// сто записей, и у питомца с пятнадцатью записями догруживать нечего —
    /// без такой справки проверка падала бы из-за накопленных на стенде данных,
    /// а не из-за приложения.
    static func petWithNextFeedPage() async -> String? {
        guard let base = URL(string: "http://localhost:5002"),
              let token = await token(),
              let pets = try? await get("/api/pets", base: base, token: token),
              let list = pets["pets"] as? [[String: Any]]
        else { return nil }
        for pet in list {
            guard let name = pet["name"] as? String,
                  let petID = pet["_id"] as? String,
                  let page = try? await get("/api/events?page_size=100&pet_id=\(petID)", base: base, token: token),
                  let cursor = page["next_cursor"] as? String
            else { continue }
            if !cursor.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Питомец с курсом лекарства и название этого курса. Спрашивается у
    /// стенда, а не зашивается: проверка без сети имеет убедиться, что на
    /// экране та же запись, что и при связи, и не должна падать от того, что
    /// данные стенда изменились.
    ///
    /// Курс берётся активный, а не первый: завершённые приложение прячет под
    /// «Завершённые курсы», и искать их на экране бессмысленно. Из активных
    /// предпочитается курс «по необходимости»: у него кнопка приёма есть
    /// всегда, а у курса по расписанию к концу дня она превращается в
    /// «Записать дополнительный приём».
    static func petWithCourse() async -> (pet: String, course: String)? {
        guard let base = URL(string: "http://localhost:5002"),
              let token = await token(),
              let pets = try? await get("/api/pets", base: base, token: token),
              let list = pets["pets"] as? [[String: Any]]
        else { return nil }
        for pet in list {
            guard let name = pet["name"] as? String,
                  let petID = pet["_id"] as? String,
                  let page = try? await get(
                      "/api/medications?pet_id=\(petID)&tz=Asia/Almaty",
                      base: base,
                      token: token
                  ),
                  let courses = page["medications"] as? [[String: Any]]
            else { continue }
            let active = courses.filter { $0["is_active"] as? Bool == true }
            let chosen = active.first { $0["as_needed"] as? Bool == true } ?? active.first
            guard let course = chosen?["name"] as? String else { continue }
            return (pet: name, course: course)
        }
        return nil
    }

    /// Переключает приложение на питомца с именем `name`.
    static func selectPet(_ app: XCUIApplication, named name: String) {
        let switcher = app.buttons["petSwitcher"]
        guard switcher.waitForExistence(timeout: 20) else { return }
        switcher.tap()
        let item = app.buttons[name]
        _ = item.waitForExistence(timeout: 10)
        item.tap()
    }

    private static func token() async -> String? {
        var request = URLRequest(url: URL(string: "http://localhost:5002/api/auth/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": demoLogin, "password": demoPassword
        ])
        let answer = try? await URLSession.shared.data(for: request)
        let json = answer.flatMap { try? JSONSerialization.jsonObject(with: $0.0) as? [String: Any] }
        return json?["access_token"] as? String
    }

    private static func get(_ path: String, base: URL, token: String) async throws -> [String: Any] {
        // Именно `URL(string:relativeTo:)`, а не `appendingPathComponent`:
        // тот кодирует слеши и даёт запрос на `/api%2Fpets`.
        guard let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let page = json as? [String: Any] else { throw URLError(.badServerResponse) }
        return page
    }
}
