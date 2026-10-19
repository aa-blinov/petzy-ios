import XCTest

/// Смена питомца на ходу. Модели разделов пересоздаются на каждого питомца, и
/// экран, который грузит по прежнему питомцу, показывает пустоту до
/// перезапуска приложения: человек видит «Лекарств нет» у питомца с курсами и
/// верит этому.
@MainActor
final class PetSwitchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSwitchingPetShowsItsMedications() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")

        let stand = try await Stand()
        guard let target = stand.petWithMedications else {
            throw XCTSkip("На стенде нет питомца с курсами: проверять нечего")
        }
        // Раздел открываем до смены питомца: дефект живёт именно в этом
        // порядке. Когда раздел открывают уже после смены, он и так грузит
        // нужного питомца с первого раза, и проверка ничего не поймала бы.
        app.buttons["Лекарства"].tap()
        XCTAssertTrue(app.searchFields["Найти лекарство"].waitForExistence(timeout: 25))

        // Сначала уходим на другого питомца: если выбранный уже нужный, смены
        // не происходит и проверка ничего не поймала бы.
        if let other = stand.pet(without: target.id) {
            TestLaunch.selectPet(app, named: other.name)
        }
        TestLaunch.selectPet(app, named: target.name)

        XCTAssertTrue(
            app.staticTexts[target.medication].waitForExistence(timeout: 25),
            "После смены питомца его курс «\(target.medication)» не показан: \(app.debugDescription)"
        )
    }

    /// Снимок стенда для теста: кто есть и у кого что. Читается напрямую, как
    /// в остальных прогонах против живого стека.
    private struct Stand {
        struct Pet {
            let id: String
            let name: String
        }

        /// Питомец, у которого есть хоть один курс, и название этого курса.
        let petWithMedications: (id: String, name: String, medication: String)?
        let pets: [Pet]

        func pet(without id: String) -> Pet? {
            pets.first { $0.id != id }
        }

        init() async throws {
            let base = URL(string: "http://localhost:5002")!
            guard let token = await Self.token() else {
                throw XCTSkip("Стенд не отдал токен: \(base)")
            }
            let list = try await Self.get("/api/pets", base: base, token: token)
            let all = (list["pets"] as? [[String: Any]] ?? []).compactMap { row -> Pet? in
                guard let id = row["_id"] as? String, let name = row["name"] as? String else { return nil }
                return Pet(id: id, name: name)
            }
            pets = all
            var found: (id: String, name: String, medication: String)?
            for pet in all {
                guard let page = try? await Self.get(
                    "/api/medications?pet_id=\(pet.id)",
                    base: base,
                    token: token
                ), let medications = page["medications"] as? [[String: Any]],
                // Законченные курсы приложение прячет, и искать их на экране
                // бессмысленно: берём тот, который человек видит.
                let shown = medications.first(where: { ($0["is_active"] as? Bool) != false }),
                let name = shown["name"] as? String
                else { continue }
                found = (pet.id, pet.name, name)
                break
            }
            petWithMedications = found
        }

        private static func token() async -> String? {
            var request = URLRequest(url: URL(string: "http://localhost:5002/api/auth/login")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "username": TestLaunch.demoLogin, "password": TestLaunch.demoPassword
            ])
            let answer = try? await URLSession.shared.data(for: request)
            let json = answer.flatMap { try? JSONSerialization.jsonObject(with: $0.0) as? [String: Any] }
            return json?["access_token"] as? String
        }

        private static func get(_ path: String, base: URL, token: String) async throws -> [String: Any] {
            guard let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let answer = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: answer.0) as? [String: Any]
            else {
                throw URLError(.badServerResponse)
            }
            return json
        }
    }
}
