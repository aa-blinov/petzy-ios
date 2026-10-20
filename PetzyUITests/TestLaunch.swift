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

    /// Питомец и самый старый день его ленты: дойдя до конца, человек должен
    /// увидеть его сам, без всякой кнопки. Запрос повторяет запрос
    /// приложения, без надгробий: удалённые записи сервер и так не отдаёт, а
    /// страница с надгробиями приносила из ста записей одну живую, и догружать
    /// было нечего.
    static func petWithNextFeedPage() async -> (pet: String, day: String)? {
        guard let base = URL(string: "http://localhost:5002"),
              let token = await token(),
              let pets = try? await get("/api/pets", base: base, token: token),
              let list = pets["pets"] as? [[String: Any]]
        else { return nil }
        let limit = daysAgo(3)
        for pet in list {
            guard let name = pet["name"] as? String,
                  let petID = pet["_id"] as? String
            else { continue }
            var cursor: String?
            var all: Set<String> = []
            var pages = 0
            repeat {
                var path = "/api/events?page_size=100&pet_id=\(petID)"
                if let cursor {
                    path += "&before=\(escaped(cursor))"
                }
                guard let page = try? await get(path, base: base, token: token) else { break }
                all.formUnion(days(page["items"] as? [[String: Any]] ?? []))
                cursor = page["next_cursor"] as? String
                pages += 1
            } while cursor != nil && pages < 12
            // Страниц больше одной: иначе догружать нечего. День берётся тот,
            // который приложение покажет датой, а не «Сегодня» или «Вчера».
            guard pages > 1, let day = all.filter { $0 <= limit }.sorted().first else {
                continue
            }
            return (pet: name, day: displayDay(day))
        }
        return nil
    }

    /// Дни записей в виде «2026-08-17».
    private static func days(_ events: [[String: Any]]) -> Set<String> {
        Set(events.compactMap { ($0["date_time"] as? String)?.prefix(10).description })
    }

    /// Дата так, как её показывает приложение: «17.08.2026».
    private static func displayDay(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// Дата, которая прошла не меньше трёх дней назад. Ближе к сегодня
    /// приложение показывает «Сегодня» и «Вчера», а не дату, и проверка искала
    /// бы не то.
    private static func daysAgo(_ count: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let date = Calendar.current.date(byAdding: .day, value: -count, to: Date()) ?? Date()
        return formatter.string(from: date)
    }

    /// Курсор в строку запроса так же, как это делает приложение.
    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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

    /// Питомец с фото на стенде: имя и порода. Фото есть не у всех, а у
    /// питомца без фото карточка показывает значок вида, и проверять тогда
    /// нечего.
    static func petWithPhoto() async -> (name: String, breed: String?)? {
        guard let base = URL(string: "http://localhost:5002"),
              let token = await token(),
              let pets = try? await get("/api/pets", base: base, token: token),
              let list = pets["pets"] as? [[String: Any]]
        else { return nil }
        for pet in list {
            guard let name = pet["name"] as? String,
                  let photo = pet["photo_url"] as? String, !photo.isEmpty
            else { continue }
            return (name: name, breed: pet["breed"] as? String)
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
