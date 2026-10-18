import Foundation
@testable import Petzy
import Testing

/// «К приёму»: жалоба и семь отметок. Форма шлёт только то, что человек
/// отметил, иначе сервер сохранил бы «кашель: как обычно» у того, кто про
/// кашель не думал.
@Suite("Медкарта: форма «К приёму»")
struct VisitPrepFormTests {
    @Test("Отмеченные пункты уходят, неотмеченные не уходят")
    func onlyMarkedChecksAreSent() {
        let picked = ["cough": "changed", "thirst": "normal", "appetite": ""]

        let sent = VisitPrepDraft.checks(from: picked)

        #expect(sent == ["cough": "changed", "thirst": "normal"])
    }

    @Test("Пустая жалоба и пустые отметки уходят как nil, а не как пустые строки")
    func emptyComplaintIsNil() {
        let sent = VisitPrepDraft(body: "", checks: [:]).body

        #expect(sent.complaint == nil)
        #expect(sent.checks.isEmpty)
    }

    @Test("Жалоба с обрезкой пробелов доезжает текстом, а не пустотой")
    func complaintIsTrimmed() {
        let sent = VisitPrepDraft(body: "  Кашель  ", checks: [:]).body

        #expect(sent.complaint == "Кашель")
    }

    @Test("Пустая форма очищает заметку: сервер так и делает")
    func emptyFormClearsNote() {
        #expect(VisitPrepDraft(body: "   ", checks: ["cough": ""]).isEmpty)
    }

    @Test("Значения отметок остаются серверными: normal и changed")
    func valuesAreServerKeys() {
        // На экране это «Как обычно» и «Изменилось», но в запрос уходят ключи:
        // сервер их проверяет и хранит, свои слова он не поймёт.
        #expect(VisitPrepDraft.values == ["normal", "changed"])
    }

    @Test("Заметка из карты открывается с её отметками")
    func draftFromCardKeepsChecks() {
        let prep = VisitPrep(
            baseVersion: "v5",
            complaint: "Кашель",
            checks: [VisitCheck(id: "cough", title: "Кашель", value: "changed")]
        )

        let draft = VisitPrepDraft(prep: prep, baseVersion: "v5")

        #expect(draft.complaint == "Кашель")
        #expect(draft.picks == ["cough": "changed"])
        #expect(draft.baseVersion == "v5")
    }

    @Test("Пустая заметка открывается пустой формой, а не ошибкой")
    func draftWithoutNoteIsEmpty() {
        let draft = VisitPrepDraft(prep: nil, baseVersion: nil)

        #expect(draft.complaint == "")
        #expect(draft.picks.isEmpty)
        #expect(draft.isEmpty)
    }

    @Test("Отметка без слов сервера не уходит: неизвестное значение прячем")
    func unknownValueIsDropped() {
        let sent = VisitPrepDraft.checks(from: ["cough": "кашель есть", "thirst": "normal"])

        #expect(sent == ["thirst": "normal"])
    }
}
