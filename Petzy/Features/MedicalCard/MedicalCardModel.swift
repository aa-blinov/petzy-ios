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
    private(set) var isPreparingPDF = false

    private let client: APIClient
    private let petID: String

    init(client: APIClient, petID: String) {
        self.client = client
        self.petID = petID
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
            card = try await MedicalCardAPI.card(client, petID: petID, zone: Self.zone)
            errorText = nil
        } catch {
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
}
