import XCTest

/// Доступ к питомцу: владелец приглашает второго человека логином, а сервер
/// отвечает словами, если такого логина нет. Проверяется проводка, а не логика:
/// сам запрос и разбор ответа покрыты юнит-тестами.
@MainActor
final class PetAccessUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Раздел «Доступ» лежит ниже формы, поэтому до него прокручивают.
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        var tries = 0
        while !element.exists, tries < 12 {
            app.swipeUp()
            tries += 1
        }
        return element.exists
    }

    func testInviteUnknownLoginShowsServerAnswer() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        // Карточка питомца открывает «О питомце»; фото есть не у всех, поэтому
        // берём питомца со стенда того, у кого оно есть.
        guard let pet = await TestLaunch.petWithPhoto() else {
            throw XCTSkip("на стенде нет питомца с фото: проверять нечего")
        }
        TestLaunch.selectPet(app, named: pet.name)
        let photo = app.images["petPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 25), "фото питомца не показано")
        photo.tap()
        XCTAssertTrue(
            app.navigationBars["О питомце"].waitForExistence(timeout: 20),
            "карточка не открыла «О питомце»: \(app.debugDescription)"
        )

        let invite = app.buttons["Пригласить человека"]
        XCTAssertTrue(scrollTo(app, invite), "в «О питомце» нет раздела «Доступ»: \(app.debugDescription)")
        invite.tap()

        let login = app.alerts.textFields.firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 10), "вопрос о логине не открылся: \(app.debugDescription)")
        login.typeText("nobody_\(Int.random(in: 1000 ... 9999))")
        app.alerts.buttons["Пригласить"].tap()

        // Сервер отвечает словами, и они видны на экране: «Пользователь не
        // найден». Это и есть проводка целиком — от формы до ответа.
        let answer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'не найден'")
        ).firstMatch
        XCTAssertTrue(
            answer.waitForExistence(timeout: 20),
            "ответ сервера на приглашение не показан: \(app.debugDescription)"
        )
    }
}
