import Foundation

/// Запись медкарты в том виде, как её заполняет форма. Экран отдаёт
/// черновик, а названия полей сервера здесь не встречаются.
struct MedicalRecordDraft: Sendable {
    var petID: String
    var kind: MedicalKind
    var date: String
    var title: String
    /// Дата повтора. Пустая строка на сервере значит «убери», `nil` — «не трогай».
    var nextDue: String?
    var clinic: String?
    var vet: String?
    var note: String?
    /// Номер партии прививки.
    var batch: String?
    /// Кого закрывает обработка: обязателен для `parasite`.
    var target: String?
    /// От чего защищает прививка.
    var protects: String?
    var complaint: String?
    var diagnosis: String?
    var recommendations: String?

    init(
        petID: String,
        kind: MedicalKind,
        date: String,
        title: String,
        nextDue: String? = nil,
        clinic: String? = nil,
        vet: String? = nil,
        note: String? = nil,
        batch: String? = nil,
        target: String? = nil,
        protects: String? = nil,
        complaint: String? = nil,
        diagnosis: String? = nil,
        recommendations: String? = nil
    ) {
        self.petID = petID
        self.kind = kind
        self.date = date
        self.title = title
        self.nextDue = nextDue
        self.clinic = clinic
        self.vet = vet
        self.note = note
        self.batch = batch
        self.target = target
        self.protects = protects
        self.complaint = complaint
        self.diagnosis = diagnosis
        self.recommendations = recommendations
    }
}

extension MedicalRecordDraft {
    /// Что человек должен поправить до запроса, своими словами. `nil` — можно
    /// отправлять. Проверка здесь, а не только на сервере: человек видит
    /// подсказку у поля, а не ошибку после похода туда и обратно.
    static func problem(_ draft: MedicalRecordDraft) -> String? {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите название"
        }
        if draft.date.isEmpty {
            return "Укажите дату"
        }
        // Обработка без цели сервер не примет: «от кого» здесь обязателен.
        if draft.kind == .parasite, (draft.target ?? "").isEmpty {
            return "Выберите, от кого обработка"
        }
        return nil
    }
}
