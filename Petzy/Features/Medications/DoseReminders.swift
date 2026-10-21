import Foundation

/// Напоминания о приёмах лекарств: что и когда показать.
///
/// Считается по расписанию курсов, без сети и без системы уведомлений: так это
/// проверяется тестом, а не секундомером. Система получает уже готовый список.
enum DoseReminders {
    /// Одно напоминание: момент, слова и имя запроса, по которому план
    /// заменяется целиком.
    struct Item: Equatable, Sendable {
        let identifier: String
        let moment: Date
        let title: String
        let body: String
    }

    static let oneTitle = "Пора дать лекарство"
    static let manyTitle = "Пора дать лекарства"

    /// Что напомнить в ближайшие дни.
    ///
    /// Напоминают только курсы по расписанию, которые идут сейчас: «по
    /// необходимости» дают когда дадут, а завершённый курс уже не нужен.
    /// Время, которое сегодня уже прошло, не напоминается — оно всплыло бы
    /// сразу. Два лекарства в один час дают одно напоминание, а не два звонка
    /// подряд.
    ///
    /// `limit` — предел системы: у iOS не больше 64 запланированных
    /// уведомлений на приложение, и лишние она молча выбрасывает.
    static func plan(
        courses: [Medication],
        petName: String?,
        from now: Date = .now,
        days: Int = 7,
        limit: Int = 60,
        calendar: Calendar = .current
    ) -> [Item] {
        let scheduled = courses.filter(scheduled(_:))
        guard !scheduled.isEmpty else { return [] }
        let start = calendar.startOfDay(for: now)
        // Момент один, а лекарств в нём может быть несколько: их имена и есть
        // текст напоминания.
        var slots: [Date: [String]] = [:]
        for offset in 0 ..< days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekday = mondayFirst(day, calendar: calendar)
            for course in scheduled where course.schedule.days.contains(weekday) {
                for time in course.schedule.times {
                    guard let moment = moment(day: day, time: time, calendar: calendar), moment > now else {
                        continue
                    }
                    slots[moment, default: []].append(course.name)
                }
            }
        }
        let pet = petName.flatMap { $0.isEmpty ? false : true } == true ? petName ?? "" : "Питомец"
        return slots
            .sorted { $0.key < $1.key }
            .prefix(limit)
            .map { moment, names in
                Item(
                    identifier: "dose-" + MomentText.isoDay(moment, calendar: calendar)
                        + "-" + timeText(moment, calendar: calendar),
                    moment: moment,
                    title: names.count == 1 ? oneTitle : manyTitle,
                    body: "\(pet): \(names.joined(separator: ", ")), \(timeText(moment, calendar: calendar))"
                )
            }
    }

    /// Напоминает ли курс вообще: по часам, не «по необходимости» и не
    /// завершённый.
    private static func scheduled(_ course: Medication) -> Bool {
        !course.asNeeded
            && course.courseStatus == .active
            && !course.schedule.times.isEmpty
            && !course.schedule.days.isEmpty
    }

    /// День недели так, как его считает сервер и приложение: 0 — понедельник.
    private static func mondayFirst(_ day: Date, calendar: Calendar) -> Int {
        // `weekday` считает с воскресенья: 1 — вс, 2 — пн, 7 — сб.
        (calendar.component(.weekday, from: day) + 5) % 7
    }

    private static func moment(day: Date, time: String, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    private static func timeText(_ moment: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
