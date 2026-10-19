import Foundation
import Observation

/// Состояние раздела «Лекарства». Знает про запросы и порядок показа, но не
/// знает про JSON: разбор лежит в `MedicationsAPI`, а экран рисует то, что
/// здесь. Раздел заведён отдельной моделью, а не частью `AppModel`, потому
/// что лекарства, медкарта и документы переезжают каждый своим куском, и
/// общая модель росла бы в пять экранов.
@MainActor
@Observable
final class MedicationsModel {
    private(set) var medications: [Medication] = []
    private(set) var upcoming: [UpcomingDose] = []
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски: «Остаток закончился» человеку полезнее
    /// «validation_error».
    var errorText: String?
    /// Разовые сообщения об успехе, которые стоит показать и убрать.
    var notice: String?
    var showsEnded = false
    var search = ""

    private let client: APIClient
    private let petID: String

    init(client: APIClient, petID: String) {
        self.client = client
        self.petID = petID
    }

    /// Точка на вкладке: приём просрочен и об этом узнают, не заходя внутрь.
    var hasOverdueDose: Bool {
        overdueCount > 0
    }

    /// Сколько приёмов просрочено. Значок у вкладки в этой версии SDK умеет
    /// только число или подпись, своей точки не рисует, поэтому показываем
    /// количество: «2» полезнее пустого кружка.
    var overdueCount: Int {
        upcoming.filter(\.isOverdue).count
    }

    /// Первый просроченный приём: о нём говорим прямо на экране раздела,
    /// иначе человек видит число на вкладке и не знает, что именно просрочено.
    var overdueDose: UpcomingDose? {
        upcoming.first { $0.isOverdue }
    }

    var endedCount: Int {
        medications.filter { $0.courseStatus == .ended }.count
    }

    /// Курсы в порядке срочности, завершённые спрятаны, пока их не попросили,
    /// и режутся поиском. Поиск снимает спрятанные: ищут в том числе среди
    /// архива, иначе «мне нужен тот старый курс» не находилось ничего.
    var visibleMedications: [Medication] {
        var result = medications
        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) }
        } else if !showsEnded {
            result = result.filter { $0.courseStatus != .ended }
        }
        return result.sorted(by: Medication.byUrgency)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // По очереди, а не одновременно: два запроса подряд дают
            // предсказуемый порядок, и по заглушке видно, кто что получил.
            // Взаимной зависимости между ними нет, ждать обе сразу незачем.
            medications = try await MedicationsAPI.list(client, petID: petID, zone: Self.zone)
            upcoming = try await MedicationsAPI.upcoming(client, petID: petID, zone: Self.zone)
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Отметка приёма. Списку верить нельзя: сколько осталось, сколько
    /// сегодня отмечено и что просрочено — всё это сервер считает заново,
    /// поэтому после записи перечитываем и список, и ближайшие приёмы.
    func markDose(_ medication: Medication, dose: Double?, slot: DoseSlot? = nil, skipped: Bool = false) async {
        errorText = nil
        do {
            let result = try await MedicationsAPI.logIntake(
                client,
                mark: IntakeMark(
                    medicationID: medication.id,
                    moment: Self.now,
                    zone: Self.zone,
                    dose: dose,
                    slot: slot,
                    skipped: skipped
                )
            )
            notice = result.ranOut ? "Остаток кончился, пополните его" : nil
            await load()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Завершить курс или возобновить его. Дату окончания ставит сервер по
    /// сегодняшнему дню человека, а при возобновлении снимает: иначе курс
    /// остался бы помеченным как законченный, но активный.
    func toggleCourse(_ medication: Medication) async {
        let ended = medication.courseStatus == .ended
        do {
            try await MedicationsAPI.setCourseActive(
                client,
                medicationID: medication.id,
                isActive: ended,
                endedOn: ended ? "" : Self.today
            )
            notice = ended ? "Курс «\(medication.name)» возобновлён" : "Курс «\(medication.name)» завершён"
            await load()
        } catch {
            errorText = ended
                ? "Не удалось возобновить курс: \(Self.text(of: error))"
                : "Не удалось завершить курс: \(Self.text(of: error))"
        }
    }

    func restock(_ medication: Medication, amount: Double) async {
        errorText = nil
        do {
            try await MedicationsAPI.restock(client, medicationID: medication.id, amount: amount)
            await load()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    func create(_ draft: MedicationDraft) async -> Bool {
        errorText = nil
        if let problem = Self.problem(in: draft) {
            errorText = problem
            return false
        }
        do {
            _ = try await MedicationsAPI.create(client, draft: draft)
            notice = "Лекарство добавлено"
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    func update(_ medicationID: String, draft: MedicationDraft) async -> Bool {
        errorText = nil
        if let problem = Self.problem(in: draft) {
            errorText = problem
            return false
        }
        do {
            try await MedicationsAPI.update(client, medicationID: medicationID, draft: draft)
            notice = "Лекарство обновлено"
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    func delete(_ medication: Medication) async {
        errorText = nil
        do {
            try await MedicationsAPI.delete(client, medicationID: medication.id)
            // Курс убираем из своей копии только после ответа сервера: иначе он
            // исчез бы с экрана, но остался бы в базе.
            medications.removeAll { $0.id == medication.id }
            await load()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    private static var zone: String {
        TimeZone.current.identifier
    }

    /// Сегодняшний день на часах человека, `ГГГГ-ММ-ДД`.
    static var today: String {
        now.day
    }

    /// Сейчас на часах человека: день `ГГГГ-ММ-ДД` и время `ЧЧ:ММ`.
    private static var now: Moment {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        return Moment(
            day: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
            time: String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        )
    }

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// То, что человек ещё не заполнил, но сервер пропустит. Включённый учёт
    /// остатка без самого остатка принимается, а считать ему нечего: на
    /// следующей правке переключатель вышел бы выключенным, то есть молча
    /// снял бы то, что человек включил. Ноль при этом настоящий остаток,
    /// кончившаяся упаковка, и его пропускать нельзя.
    private static func problem(in draft: MedicationDraft) -> String? {
        if draft.inventoryEnabled, draft.inventoryCurrent == nil {
            return "Укажите остаток: без него учёт не работает"
        }
        return nil
    }
}
