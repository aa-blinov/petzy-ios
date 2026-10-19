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

    private let client: APIClient
    private let petID: String
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
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    func update(_ id: String, draft: MedicalRecordDraft) async -> Bool {
        if let problem = MedicalRecordDraft.problem(draft) {
            errorText = problem
            return false
        }
        errorText = nil
        do {
            try await MedicalCardAPI.update(client, id: id, draft: draft)
            notice = "Запись сохранена"
            allRecords = [:]
            await load()
            return true
        } catch {
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

    /// «К приёму»: жалоба и семь отметок. Версия та же, что у профиля:
    /// форму открыли из карты, и карта с тех пор могла измениться.
    @discardableResult
    func saveVisitPrep(baseVersion: String?, complaint: String?, checks: [String: String]) async -> Bool {
        errorText = nil
        do {
            try await MedicalCardAPI.saveVisitPrep(
                client, petID: petID, baseVersion: baseVersion, complaint: complaint, checks: checks
            )
            notice = "Записано"
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

    private static func text(of error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Карточка из копии, если она есть и разбирается.
    private func cardFromCopy() -> MedicalCard? {
        guard card == nil, let copy = offline.cardCopy(petID: petID) else { return nil }
        return try? MedicalCardAPI.decode(copy)
    }
}
