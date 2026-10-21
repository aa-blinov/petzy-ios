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
    /// Отмеченные приёмы: по ним видно, что уже дали, и их можно поправить.
    /// Приём — не форма и не запись дневника, поэтому он живёт здесь, а не в
    /// ленте: лента про события, приёмы считает сервер своими слотами.
    private(set) var intakes: [MedicationIntake] = []
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски: «Остаток закончился» человеку полезнее
    /// «validation_error».
    var errorText: String?
    /// Разовые сообщения об успехе, которые стоит показать и убрать.
    var notice: String?
    var showsEnded = false
    var search = ""

    private let client: APIClient
    /// Питомец и очередь нужны офлайн-части модели из соседнего файла,
    /// поэтому без `private`.
    let petID: String
    let offline: OfflineState

    /// На экране копия, а не сеть. Лекарство дают по часам, и ждать интернета
    /// ради того, чтобы увидеть расписание, нельзя.
    private(set) var isShowingCached = false

    init(client: APIClient, petID: String, offline: OfflineState) {
        self.client = client
        self.petID = petID
        self.offline = offline
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
            let data = try await MedicationsAPI.raw(client, petID: petID, zone: Self.zone)
            medications = try MedicationsAPI.decode(data)
            offline.cacheMedications(data, petID: petID)
            upcoming = try await MedicationsAPI.upcoming(client, petID: petID, zone: Self.zone)
            errorText = nil
            isShowingCached = false
        } catch {
            // Копия, а не ошибка: человек открыл раздел без сети и должен
            // увидеть свои курсы. Показывать ошибку вместо них незачем.
            if let decoded = medicationsFromCopy() {
                medications = decoded
                isShowingCached = true
                return
            }
            errorText = Self.text(of: error)
        }
    }

    /// Отмеченные приёмы. Читаются отдельно от курсов: они нужны одной секции
    /// внизу раздела, и второй запрос на каждое перечитывание списка был бы
    /// платой ни за что. Без ответа остаётся то, что уже есть.
    func loadIntakes() async {
        guard let found = try? await MedicationsAPI.intakes(client, petID: petID) else { return }
        intakes = found
    }

    /// Перенести отмеченный приём на другое время: отметили «сейчас», а дали
    /// утром, или ошиблись часом. Доза и остаток не трогаются.
    func moveIntake(_ intake: MedicationIntake, to moment: Moment) async {
        errorText = nil
        do {
            try await MedicationsAPI.moveIntake(
                client,
                intakeID: intake.id,
                date: moment.day,
                time: moment.time,
                zone: Self.zone
            )
            notice = "Время приёма изменено"
            await load()
            await loadIntakes()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Отменить отмеченный приём: ошибочную отметку не должно быть видно как
    /// факт, а остаток должен вернуться.
    func deleteIntake(id: String) async {
        errorText = nil
        do {
            try await MedicationsAPI.deleteIntake(client, intakeID: id)
            notice = "Приём отменён"
            await load()
            await loadIntakes()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Отметка приёма. Списку верить нельзя: сколько осталось, сколько
    /// сегодня отмечено и что просрочено — всё это сервер считает заново,
    /// поэтому после записи перечитываем и список, и ближайшие приёмы.
    /// `moment` — время, которое выбрал человек; без него отметка идёт «сейчас».
    func markDose(
        _ medication: Medication,
        dose: Double?,
        slot: DoseSlot? = nil,
        skipped: Bool = false,
        moment: Moment? = nil
    ) async {
        errorText = nil
        let mark = IntakeMark(
            medicationID: medication.id,
            moment: moment ?? Self.now,
            zone: Self.zone,
            dose: dose,
            slot: slot,
            skipped: skipped
        )
        do {
            let result = try await MedicationsAPI.logIntake(client, mark: mark)
            notice = result.ranOut ? "Остаток кончился, пополните его" : nil
            await load()
        } catch {
            // Отметка без связи не пропадает: она встаёт в очередь под своим
            // именем, и повтор отправки не спишет дозу второй раз.
            if (error as? APIError)?.isTransport == true {
                queueIntake(mark, medication: medication)
                notice = "Отметка записана в телефон, уйдёт на сервер, когда появится связь"
                return
            }
            // Отказ пришёл от сервера: слот мог закрыть кто-то другой, и без
            // перечитывания он остался бы висеть открытым, а следующее нажатие
            // дало бы тот же отказ. Текст ставим после: `load()` его снимает.
            let message = Self.text(of: error)
            if Self.answered(error) {
                await load()
            }
            errorText = message
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
            // Сервер сказал «упаковка не записана, остаток как был»: на экране
            // должен остаться тот остаток, который он посчитал, а не тот,
            // который человек собирался получить.
            let message = Self.text(of: error)
            if Self.answered(error) {
                await load()
            }
            errorText = message
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
            // Без связи курс встаёт в очередь под своим именем: сервер на
            // повтор ответит тем же курсом, а не создаст второй.
            if (error as? APIError)?.isTransport == true {
                queueCourse(draft)
                notice = "Лекарство записано в телефон, уйдёт на сервер, когда появится связь"
                return true
            }
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
            try await MedicationsAPI.update(
                client,
                medicationID: medicationID,
                draft: draft,
                baseVersion: medications.first { $0.id == medicationID }?.updatedAt
            )
            notice = "Лекарство обновлено"
            await load()
            return true
        } catch {
            // Правка без сети не теряется: она ждёт в очереди и уходит сама.
            if (error as? APIError)?.isTransport == true {
                queueUpdate(medicationID: medicationID, draft: draft)
                notice = "Правка сохранена в телефон, уйдёт на сервер, когда появится связь"
                return true
            }
            // Курс поменяли, пока человек его правил. Остаётся версия сервера,
            // и её надо показать, а не держать на экране старую.
            if (error as? APIError)?.code == "conflict" {
                await load()
            }
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

    /// Курсы из копии, если она есть и разбирается. `nil` — показывать нечего,
    /// и тогда человек должен увидеть ошибку, а не пустоту.
    private func medicationsFromCopy() -> [Medication]? {
        guard let copy = offline.medicationsCopy(petID: petID),
              let decoded = try? MedicationsAPI.decode(copy), !decoded.isEmpty else { return nil }
        return decoded
    }

    /// Отказ пришёл от сервера, а не от сети. Разница важна: на ответе сервера
    /// состояние могло уехать вперёд и пора перечитать, а при обрыве связи
    /// перечитывать нечего и незачем ждать второго таймаута.
    private static func answered(_ error: Error) -> Bool {
        if case .server = error as? APIError {
            return true
        }
        return false
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
