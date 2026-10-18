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

        XCTAssertTrue(
            app.staticTexts["Вес"].waitForExistence(timeout: 30),
            "записи ленты не показаны: \(app.debugDescription)"
        )
        XCTAssertTrue(
            dateHeaders(app).isEmpty == false,
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

    /// Заголовки дней в виде «04.10.2026».
    private func dateHeaders(_ app: XCUIApplication) -> [String] {
        let pattern = #"^\d{2}\.\d{2}\.\d{4}$"#
        return app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { $0.range(of: pattern, options: .regularExpression) != nil }
    }
}
