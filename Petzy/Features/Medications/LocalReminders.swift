import UserNotifications

/// Системные уведомления о приёмах. Тонкая обёртка: что и когда напомнить,
/// решает `DoseReminders`, а здесь только разрешение и очередь системы.
///
/// Свои запросы помечены префиксом `dose-`: план заменяется целиком, а чужие
/// уведомления (если появятся) снимать нельзя.
enum LocalReminders {
    private static let prefix = "dose-"

    private static var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    /// Разрешены ли уведомления сейчас.
    static func isAllowed() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Спросить разрешение. `false` — человек отказал или система не дала:
    /// тогда напоминаний не будет, и экран говорит об этом словами.
    static func requestPermission() async -> Bool {
        if await isAllowed() {
            return true
        }
        return await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Поставить план. Старые наши запросы снимаются: расписание поменялось, и
    /// прежние времена больше не верны.
    static func apply(_ plan: [DoseReminders.Item]) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.moment)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
        // Что именно стоит в очереди, видно в логе: у уведомлений нет экрана,
        // по которому это можно проверить глазами.
        NSLog("[reminders] поставлено: %d", plan.count)
    }

    /// Снять все наши напоминания: человек выключил их или курсов больше нет.
    static func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
    }
}
