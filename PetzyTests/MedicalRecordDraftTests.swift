import Foundation
@testable import Petzy
import Testing

/// Приём врача хранит жалобу, диагноз и назначения, прививка — партию и
/// защиту, обработка — цель. Форма правки обязана подставить всё это, иначе
/// «Сохранить» без правок стирает то, что врач написал.
@Suite("Медкарта: правка не теряет поля")
struct MedicalRecordDraftTests {
    @Test("Жалоба, диагноз и назначения переносятся в форму")
    func visitKeepsItsText() {
        let draft = MedicalRecordDraft.from(Self.record(kind: .visit, complaint: "Кашель"), petID: "p1")

        #expect(draft.complaint == "Кашель")
        #expect(draft.diagnosis == "Бронхит")
        #expect(draft.recommendations == "Антибиотик")
    }

    /// Партия и защита относятся к прививке: без них в списке и в PDF запись
    /// выглядит как «то же самое, но неизвестно какое».
    @Test("Партия и защита переносятся в форму")
    func vaccinationKeepsBatchAndProtects() {
        let draft = MedicalRecordDraft.from(
            Self.record(kind: .vaccination, batch: "A-12", protects: "rabies"),
            petID: "p1"
        )

        #expect(draft.batch == "A-12")
        #expect(draft.protects == "rabies")
    }

    /// Цель обработки обязательна, и без неё сервер откажется сохранять.
    @Test("Цель обработки переносится в форму")
    func parasiteKeepsTarget() {
        let draft = MedicalRecordDraft.from(
            Self.record(kind: .parasite, target: "fleas_ticks"),
            petID: "p1"
        )

        #expect(draft.target == "fleas_ticks")
    }

    /// Обязательные для сервера поля переносятся все: дата повтора, клиника
    /// и врач терялись бы так же незаметно.
    @Test("Дата повтора, клиника и врач переносятся в форму")
    func commonFieldsAreKept() {
        let draft = MedicalRecordDraft.from(Self.record(kind: .visit, complaint: "Кашель"), petID: "p1")

        #expect(draft.petID == "p1")
        #expect(draft.date == "2026-07-12")
        #expect(draft.title == "Осмотр")
        #expect(draft.nextDue == "2026-10-07")
        #expect(draft.clinic == "Ортовет")
        #expect(draft.vet == "Каримов Д.")
    }

    static func record(
        kind: MedicalKind,
        complaint: String? = nil,
        batch: String? = nil,
        protects: String? = nil,
        target: String? = nil
    ) -> MedicalRecord {
        MedicalRecord(
            id: "r1",
            kind: kind,
            title: "Осмотр",
            date: "2026-07-12",
            nextDue: "2026-10-07",
            status: .fine,
            daysLeft: nil,
            clinic: "Ортовет",
            vet: "Каримов Д.",
            note: nil,
            batch: batch,
            target: target,
            protects: protects,
            complaint: complaint,
            diagnosis: complaint == nil ? nil : "Бронхит",
            recommendations: complaint == nil ? nil : "Антибиотик"
        )
    }
}
