import Foundation
@testable import Petzy
import Testing

/// Напоминания о приёмах: что и когда показать. Считается по расписанию курсов,
/// без сети и без системы уведомлений, поэтому и проверяется как чистая функция.
@Suite("Напоминания о приёмах")
struct DoseRemindersTests {
    /// Понедельник, 21 октября 2026, 08:00 по местному времени.
    private var monday: Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 21
        parts.hour = 8
        parts.minute = 0
        return Calendar.current.date(from: parts) ?? .now
    }

    private func course(
        _ name: String,
        days: [Int] = Array(0 ... 6),
        times: [String] = ["09:00"],
        asNeeded: Bool = false,
        status: CourseStatus = .active,
        id: String = "c1"
    ) -> Medication {
        Medication(
            id: id,
            petID: "p1",
            name: name,
            kind: "Таблетка",
            strength: nil,
            doseUnit: "таб",
            defaultDose: 1,
            schedule: DoseSchedule(days: days, times: times),
            asNeeded: asNeeded,
            isActive: status == .active,
            courseStatus: status,
            startedOn: nil,
            endedOn: nil,
            stock: nil,
            openSlotsToday: [],
            scheduledToday: true,
            lastTakenAt: nil,
            lastTakenBy: nil,
            comment: nil,
            purpose: nil,
            prescribedBy: nil,
            updatedAt: nil
        )
    }

    @Test("Ежедневный курс напоминает на неделю вперёд")
    func dailyCoursePlansAWeek() {
        let plan = DoseReminders.plan(
            courses: [course("Мелоксидил", times: ["09:00"])],
            petName: "Рекс",
            from: monday
        )

        #expect(plan.count == 7)
        #expect(plan.first?.body == "Рекс: Мелоксидил, 09:00")
        #expect(plan.first?.title == "Пора дать лекарство")
    }

    /// Время, которое уже прошло, напоминать поздно: оно всплыло бы сразу.
    @Test("Прошедшее сегодня не напоминается")
    func pastTimeIsSkipped() {
        let plan = DoseReminders.plan(
            courses: [course("Мелоксидил", times: ["07:00", "21:00"])],
            petName: "Рекс",
            from: monday
        )

        // Семь дней по два времени — четырнадцать, но сегодняшние 07:00 уже
        // прошли, и их в плане нет.
        #expect(plan.count == 13)
        #expect(plan.first?.moment == Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: monday))
    }

    @Test("По необходимости не напоминается")
    func asNeededIsSilent() {
        let plan = DoseReminders.plan(
            courses: [course("Мелоксидил", asNeeded: true)],
            petName: "Рекс",
            from: monday
        )

        #expect(plan.isEmpty)
    }

    @Test("Завершённый курс не напоминается")
    func endedIsSilent() {
        let plan = DoseReminders.plan(
            courses: [course("Глюкозамин", status: .ended)],
            petName: "Рекс",
            from: monday
        )

        #expect(plan.isEmpty)
    }

    /// «Дронтал Плюс» дают по субботам: в остальные дни напоминания нет.
    /// Дни недели сервер считает с понедельника, как и приложение.
    @Test("Только выбранные дни недели")
    func weekdaysAreRespected() throws {
        let plan = DoseReminders.plan(
            courses: [course("Дронтал Плюс", days: [5], times: ["10:00"])],
            petName: "Рекс",
            from: monday
        )

        let calendar = Calendar.current
        #expect(plan.count == 1)
        #expect(try calendar.component(.weekday, from: #require(plan.first?.moment)) == 7)
    }

    /// Два лекарства в один час — это одно «пора дать», а не два звонка подряд.
    @Test("Два курса в один час — одно напоминание")
    func sameHourIsOneNotification() {
        let plan = DoseReminders.plan(
            courses: [
                course("Мелоксидил", times: ["09:00"], id: "c1"),
                course("Глюкозамин", times: ["09:00"], id: "c2")
            ],
            petName: "Рекс",
            from: monday
        )

        #expect(plan.count == 7)
        #expect(plan.first?.body == "Рекс: Мелоксидил, Глюкозамин, 09:00")
        #expect(plan.first?.title == "Пора дать лекарства")
    }

    /// У iOS не больше 64 запланированных уведомлений на приложение: план
    /// обрезается, иначе система молча выбросит часть.
    @Test("Больше предела не планируется")
    func planIsCapped() {
        let plan = DoseReminders.plan(
            courses: [course("Мелоксидил", times: ["09:00", "13:00", "21:00"])],
            petName: "Рекс",
            from: monday,
            days: 30,
            limit: 20
        )

        #expect(plan.count == 20)
    }

    @Test("Имя запроса не повторяется")
    func identifiersAreUnique() {
        let plan = DoseReminders.plan(
            courses: [
                course("Мелоксидил", times: ["09:00"], id: "c1"),
                course("Глюкозамин", times: ["09:00"], id: "c2")
            ],
            petName: "Рекс",
            from: monday
        )

        #expect(Set(plan.map(\.identifier)).count == plan.count)
    }
}
