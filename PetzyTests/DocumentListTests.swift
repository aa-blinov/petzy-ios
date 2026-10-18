import Foundation
@testable import Petzy
import Testing

/// Список документов: как он читается по-русски и что из него приложение
/// показывает. Сервер отдаёт категорию ключом (`lab_result`), а человек читает
/// «Анализы», и без перевода список был бы списком ключей.
@Suite("Документы: список")
struct DocumentListTests {
    @Test("Категория читается словом, а не ключом")
    func categoryReadsInWords() {
        #expect(DocumentCategory.vaccination.title == "Прививки")
        #expect(DocumentCategory.labResult.title == "Анализы")
        #expect(DocumentCategory.conclusion.title == "Заключения")
        #expect(DocumentCategory.imaging.title == "Снимки")
        #expect(DocumentCategory.insurance.title == "Страховка")
        #expect(DocumentCategory.other.title == "Другое")
    }

    @Test("Категории идут в порядке экрана, а не как пришли")
    func categoriesAreInScreenOrder() {
        #expect(DocumentCategory.allCases.map(\.rawValue) == [
            "vaccination", "lab_result", "conclusion", "imaging", "insurance", "other"
        ])
    }

    @Test("Неизвестная категория читается как «Другое», а не ломает список")
    func unknownCategoryBecomesOther() {
        #expect(DocumentCategory.known("что-то новое") == .other)
    }

    @Test("Документ без срока не показывает срок")
    func noExpiryNoText() {
        let document = Self.document(expiresAt: nil)

        #expect(document.expiryText == nil)
    }

    @Test("Срок документа читается по-русски и говорит, что он прошёл")
    func expiryReadsInWords() {
        let document = Self.document(expiresAt: "2020-04-21")

        #expect(document.expiryText == "Срок истёк 21.04.2020")
    }

    @Test("Документ, привязанный к записи медкарты, это говорит")
    func linkedRecordIsMentioned() {
        let document = Self.document(expiresAt: nil, kinds: ["vaccination"])

        #expect(document.linkedText == "В медкарте: Прививки")
    }

    @Test("Документ без привязки не упоминает медкарту")
    func noLinkNoText() {
        let document = Self.document(expiresAt: nil)

        #expect(document.linkedText == nil)
    }

    @Test("Размер файла читается по-русски")
    func sizeReadsInWords() {
        #expect(Self.document(expiresAt: nil, size: 2_400_000).sizeText == "2,4 МБ")
        #expect(Self.document(expiresAt: nil, size: 601).sizeText == "601 Б")
        #expect(Self.document(expiresAt: nil, size: 15000).sizeText == "15 КБ")
        // Маленький файл не должен превращаться в «0 КБ».
        #expect(Self.document(expiresAt: nil, size: 9).sizeText == "9 Б")
    }

    // MARK: - Заготовки

    static func document(
        expiresAt: String?,
        kinds: [String] = [],
        size: Int = 601
    ) -> PetDocument {
        PetDocument(
            id: "d1",
            category: .vaccination,
            title: "Паспорт, прививки 2025",
            note: nil,
            expiresAt: expiresAt,
            createdAt: "2026-10-03T07:52:00Z",
            contentType: "application/pdf",
            fileSize: size,
            fileURL: nil,
            recordKinds: kinds,
            recordReminds: false
        )
    }
}
