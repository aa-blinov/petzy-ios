import XCTest

/// Разделы без связи. Человек в метро должен увидеть свои курсы и должен
/// понимать, что видит копию, а не свежие данные: принять отменённое
/// лекарство хуже, чем увидеть пустоту.
@MainActor
final class OfflineSectionsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testMedicationCourseSurvivesLossOfNetwork() async {
        guard let expected = await TestLaunch.petWithCourse() else {
            XCTFail("На стенде нет ни одного курса лекарства")
            return
        }
        let app = TestLaunch.signedOut()
        XCTAssertTrue(TestLaunch.logIn(app), "Не удалось войти")
        TestLaunch.selectPet(app, named: expected.pet)
        app.buttons["Лекарства"].tap()
        XCTAssertTrue(
            app.staticTexts[expected.course].waitForExistence(timeout: 25),
            "Курс не открылся при связи, копия не прогрелась: \(app.debugDescription)"
        )

        let offline = TestLaunch.offline()
        offline.buttons["Лекарства"].tap()
        XCTAssertTrue(
            offline.staticTexts["Нет связи, показаны сохранённые данные"].waitForExistence(timeout: 30),
            "Раздел не сказал, что показывает копию: \(offline.debugDescription)"
        )
        XCTAssertTrue(
            offline.staticTexts[expected.course].waitForExistence(timeout: 20),
            "Без связи раздел не показал сохранённый курс: \(offline.debugDescription)"
        )
    }
}
