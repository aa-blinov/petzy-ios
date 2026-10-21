import Foundation

/// Напоминания о приёмах: включение, разрешение и постановка плана.
///
/// Сервер шлёт их через Web Push браузеру, а приложению нужен свой путь:
/// локальные уведомления по расписанию курсов. Они работают без сети и без
/// сервера, а расписание к тому же известно с последнего чтения раздела.
extension AppModel {
    /// Спросить разрешение и запомнить выбор. `false` — разрешения нет, и
    /// экран говорит об этом словами, а не оставляет переключатель включённым.
    @discardableResult
    func setReminders(_ enabled: Bool) async -> Bool {
        guard enabled else {
            remindersEnabled = false
            remindersProblem = nil
            nextReminderText = nil
            defaults.set(false, forKey: Self.remindersKey)
            await LocalReminders.cancelAll()
            return true
        }
        guard await LocalReminders.requestPermission() else {
            remindersEnabled = false
            remindersProblem = "Уведомления запрещены в настройках телефона"
            nextReminderText = nil
            defaults.set(false, forKey: Self.remindersKey)
            return false
        }
        remindersEnabled = true
        remindersProblem = nil
        defaults.set(true, forKey: Self.remindersKey)
        // План ставится сразу: человек включил напоминания здесь, и держать их
        // до первого захода в «Лекарства» было бы обманом.
        await refreshRemindersFromServer()
        return true
    }

    /// План по расписанию, прочитанному с сервера: он нужен и тогда, когда
    /// раздел лекарств ещё не открывали.
    func refreshRemindersFromServer() async {
        guard remindersEnabled, let petID = selectedPetID, let raw = try? await MedicationsAPI.raw(
            client,
            petID: petID,
            zone: TimeZone.current.identifier
        ),
            let courses = try? MedicationsAPI.decode(raw) else { return }
        await applyReminders(courses: courses, petName: selectedPet?.name)
    }

    /// План по уже прочитанному расписанию: экран лекарств отдаёт его без
    /// второго запроса.
    func refreshReminders(courses: [Medication], petName: String?) async {
        guard remindersEnabled else { return }
        await applyReminders(courses: courses, petName: petName)
    }

    private func applyReminders(courses: [Medication], petName: String?) async {
        let plan = DoseReminders.plan(courses: courses, petName: petName)
        await LocalReminders.apply(plan)
        // Ближайшее напоминание показывается словами: у уведомлений нет
        // экрана, и без этой строки человек не знает, что план вообще есть.
        nextReminderText = plan.first.map { Self.reminderText($0.moment) }
    }

    /// «Сегодня в 21:00», «24.10.2026 в 09:00»: словами, как везде в
    /// приложении. Сравнение идёт с сегодняшним днём, а не с самим
    /// напоминанием: иначе любое из них называлось бы «Сегодня».
    private static func reminderText(_ moment: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = MomentText.isoDay(moment, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return "\(MomentText.humanDay(day, today: now, calendar: calendar)) в \(time)"
    }
}
