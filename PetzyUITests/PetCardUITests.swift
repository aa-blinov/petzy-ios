import XCTest

/// Карточка питомца на главном экране: фото и строка «возраст, порода, пол»
/// приходят с сервера, и карточка показывает то, что он прислал.
@MainActor
final class PetCardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFeedShowsPetCardWithPhoto() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        guard let pet = await TestLaunch.petWithPhoto() else {
            throw XCTSkip("на стенде нет питомца с фото: проверять нечего")
        }
        TestLaunch.selectPet(app, named: pet.name)

        // Сначала строка под именем: по ней видно, что карточка уже про того
        // питомца, которого выбрали, а не про прежнего.
        if let breed = pet.breed, !breed.isEmpty {
            let meta = app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", breed))
                .firstMatch
            XCTAssertTrue(
                meta.waitForExistence(timeout: 25),
                "порода питомца в карточке не показана: \(app.debugDescription)"
            )
        }
        XCTAssertTrue(
            app.images["petPhoto"].waitForExistence(timeout: 25),
            "фото питомца не показано: \(app.debugDescription)"
        )
    }

    /// По карточке открывается «О питомце»: тап по ней ведёт туда, где всё
    /// это и правят.
    func testPetCardOpensPetProfile() async throws {
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "не удалось войти и открыть оболочку")

        guard let pet = await TestLaunch.petWithPhoto() else {
            throw XCTSkip("на стенде нет питомца с фото: проверять нечего")
        }
        TestLaunch.selectPet(app, named: pet.name)

        let photo = app.images["petPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 25), "фото питомца не показано: \(app.debugDescription)")
        photo.tap()

        XCTAssertTrue(
            app.navigationBars["О питомце"].waitForExistence(timeout: 20),
            "карточка не открыла «О питомце»: \(app.debugDescription)"
        )
    }
}
