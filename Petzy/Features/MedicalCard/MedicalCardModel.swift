import Foundation
import Observation

/// Состояние вкладки «Медкарта». Знает про запросы и что после них показать,
/// но не знает про JSON: разбор лежит в `MedicalCardAPI`, экран рисует то,
/// что здесь.
@MainActor
@Observable
final class MedicalCardModel {
    private(set) var card: MedicalCard?
    private(set) var isLoading = false
    /// Что ответил сервер, по-русски.
    var errorText: String?
    var notice: String?
    /// Все записи раздела, когда человек раскрыл его целиком. Плитка приносит
    /// по десять, остальное берётся отсюда.
    var allRecords: [MedicalKind: [MedicalRecord]] = [:]
    /// Готовый файл для врача: его открывает системное меню «Поделиться».
    private(set) var pdfFile: URL?
    /// Только что выданная ссылка на медкарту.
    private(set) var share: MedicalShare?
    /// Ссылки, которые сейчас открывают карту.
    private(set) var shares: [LiveShare] = []
    /// Справочник прививок: один и тот же для всех, поэтому читается один раз.
    private(set) var catalog: [VaccineGroup] = []
    private(set) var isPreparingPDF = false

    // Клиент, питомец и очередь нужны соседнему файлу с заметкой «К приёму»,
    // поэтому без `private`.
    let client: APIClient
    let petID: String
    private let offline: OfflineState

    /// На экране копия, а не сеть.
    private(set) var isShowingCached = false

    init(client: APIClient, petID: String, offline: OfflineState) {
        self.client = client
        self.petID = petID
        self.offline = offline
    }

    var overdueCount: Int {
        card?.overdueCount ?? 0
    }

    var hasOverdue: Bool {
        overdueCount > 0
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await MedicalCardAPI.raw(client, petID: petID, zone: Self.zone)
            card = try MedicalCardAPI.decode(data)
            offline.cacheCard(data, petID: petID)
            errorText = nil
            isShowingCached = false
        } catch {
            // Копия, а не ошибка: медкарту открывают без связи чаще, чем
            // кажется, и пустой раздел в этом месте бесполезен.
            if let decoded = cardFromCopy() {
                card = decoded
                isShowingCached = true
                return
            }
            errorText = Self.text(of: error)
        }
    }

    /// Показать раздел целиком. Плитки приносят по десять записей, а человек
    /// ищет прошлые прививки, и без этого раздела он их не найдёт.
    func loadAllRecords(of kind: MedicalKind) async {
        guard allRecords[kind] == nil else { return }
        do {
            allRecords[kind] = try await MedicalCardAPI.records(client, petID: petID, kind: kind)
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Записи для показа: раздел раскрыт — все, иначе те, что пришли с картой.
    func records(of kind: MedicalKind) -> [MedicalRecord] {
        if let all = allRecords[kind] {
            return all.sorted(by: urgency)
        }
        return (card?.records[kind] ?? []).sorted(by: urgency)
    }

    /// Сохранение. После успеха карта перечитывается: сроки и счётчики на
    /// плитках считает сервер, и оставленная старая карта врала бы про
    /// просрочки.
    @discardableResult
    func save(_ draft: MedicalRecordDraft) async -> Bool {
        if let problem = MedicalRecordDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            try await MedicalCardAPI.create(client, draft: draft)
            notice = "Запись добавлена"
            await load()
            if draft.kind == .visit {
                await clearVisitPrep()
            }
            return true
        } catch {
            // Без связи запись встаёт в очередь под своим именем: сервер на
            // повтор ответит той же записью, а не создаст вторую.
            if (error as? APIError)?.isTransport == true {
                queueRecord(draft)
                notice = "Запись сохранена в телефоне, уйдёт на сервер, когда появится связь"
                return true
            }
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Неотправленные записи раздела: человек сделал их без связи.
    var pending: [PendingWrite] {
        offline.pendingWrites(kind: .medicalRecord, petID: petID)
    }

    /// Убирает неотправленное: человек передумал, и запись не должна уйти.
    func removePending(_ write: PendingWrite) {
        offline.removePending(write.localID)
    }

    /// Ставит правку записи в очередь. Запись на сервере уже есть, поэтому идёт
    /// запрос на её адрес, но с версией, которую человек видел.
    private func queueUpdate(id: String, draft: MedicalRecordDraft) {
        let version = allRecords.values.flatMap(\.self).first { $0.id == id }?.updatedAt
        guard let payload = MedicalCardAPI.updatePayload(draft, baseVersion: version) else { return }
        offline.enqueue(PendingWrite(
            localID: id,
            petID: petID,
            kind: .medicalRecord,
            title: draft.title,
            method: "PUT",
            path: "/api/medical-records/\(id)",
            payload: payload
        ))
    }

    /// Ставит запись в очередь под своим именем.
    private func queueRecord(_ draft: MedicalRecordDraft) {
        let localID = "local-" + UUID().uuidString
        guard let payload = MedicalCardAPI.payload(draft, localID: localID) else { return }
        offline.enqueue(PendingWrite(
            localID: localID,
            petID: petID,
            kind: .medicalRecord,
            title: draft.title,
            method: "POST",
            path: "/api/medical-records",
            payload: payload
        ))
    }

    func update(_ id: String, draft: MedicalRecordDraft) async -> Bool {
        if let problem = MedicalRecordDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            try await MedicalCardAPI.update(
                client,
                id: id,
                draft: draft,
                baseVersion: allRecords.values.flatMap(\.self).first { $0.id == id }?.updatedAt
            )
            notice = "Запись сохранена"
            allRecords = [:]
            await load()
            return true
        } catch {
            // Правка без сети не теряется: она ждёт в очереди и уходит сама.
            if (error as? APIError)?.isTransport == true {
                queueUpdate(id: id, draft: draft)
                notice = "Правка сохранена в телефон, уйдёт на сервер, когда появится связь"
                return true
            }
            // Запись поменяли, пока человек её правил. Остаётся версия
            // сервера, и её надо показать, а не держать на экране старую.
            if (error as? APIError)?.code == "conflict" {
                allRecords = [:]
                await load()
            }
            errorText = Self.text(of: error)
            return false
        }
    }

    func delete(_ record: MedicalRecord) async {
        errorText = nil
        do {
            try await MedicalCardAPI.delete(client, id: record.id)
            // Убираем из своей копии только после ответа сервера: иначе запись
            // исчезла бы с экрана, но осталась бы в базе.
            allRecords[record.kind]?.removeAll { $0.id == record.id }
            await load()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Профиль для врача. Ответ 409 (правку изменили, пока форма была
    /// открыта) показывается текстом сервера: молча переписать чужое нельзя.
    @discardableResult
    func saveProfile(_ draft: MedicalProfileDraft) async -> Bool {
        errorText = nil
        do {
            try await MedicalCardAPI.saveProfile(client, petID: petID, profile: draft)
            notice = "Профиль сохранён"
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Ссылка для врача. Секрет приходит один раз и больше не хранится,
    /// поэтому адрес держится в модели, пока человек его не отправит.
    /// Уведомления тут нет намеренно: оно висит на экране медкарты и закрыло
    /// бы лист, а секрет из ссылки показывают один раз.
    func createShare(days: Int) async {
        errorText = nil
        do {
            share = try await MedicalCardAPI.createShare(client, petID: petID, days: days)
            // Без перечитывания список врал бы: ссылка есть, а в нём пусто.
            await loadShares()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Какие ссылки сейчас работают. Отозванные и истёкшие сервер сам не
    /// присылает, поэтому список всегда про то, что ещё открывает карту.
    func loadShares() async {
        do {
            shares = try await MedicalCardAPI.shares(client, petID: petID)
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Отзыв ссылки: адрес перестаёт открывать карту сразу, а сам список
    /// перечитывается, чтобы у человека не осталось мысли, что он работает.
    func revoke(_ share: LiveShare) async {
        errorText = nil
        do {
            try await MedicalCardAPI.revokeShare(client, petID: petID, shareID: share.id)
            // Готовый адрес тоже убираем: поделиться отозванной ссылкой
            // человек может прямо с этого экрана, а она уже ничего не открывает.
            if self.share?.id == share.id {
                self.share = nil
            }
            await loadShares()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Справочник прививок. Пустой ответ не ошибка: прививку заводят и без него,
    /// а вот второй запрос того же списка — лишний.
    func loadCatalog() async {
        guard catalog.isEmpty, let found = try? await MedicalCardAPI.vaccineCatalog(client) else { return }
        catalog = found
    }

    /// Файл для врача. Кладётся во временную папку: телефон не умеет
    /// разбирать PDF, а системное меню умеет его отправить.
    func downloadPDF() async {
        isPreparingPDF = true
        defer { isPreparingPDF = false }
        do {
            let file = try await MedicalCardAPI.pdf(client, petID: petID)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                file.fileName ?? "медкарта.pdf"
            )
            try file.data.write(to: url, options: .atomic)
            pdfFile = url
            errorText = nil
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Просроченные выше остальных: о них человек узнаёт из уведомления, и
    /// поставить их в конец списка он не сможет.
    private func urgency(_ lhs: MedicalRecord, _ rhs: MedicalRecord) -> Bool {
        urgencyRank(lhs) < urgencyRank(rhs)
    }

    private func urgencyRank(_ record: MedicalRecord) -> (Int, String) {
        switch record.status {
        case .overdue: (0, record.nextDue ?? "")
        case .soon: (1, record.nextDue ?? "")
        case .fine: (2, record.nextDue ?? "")
        case .none: (3, record.date)
        }
    }

    private static var zone: String {
        TimeZone.current.identifier
    }

    static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Карточка из копии, если она есть и разбирается.
    private func cardFromCopy() -> MedicalCard? {
        guard let copy = offline.cardCopy(petID: petID) else { return nil }
        return try? MedicalCardAPI.decode(copy)
    }
}
