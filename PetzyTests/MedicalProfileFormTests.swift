import Foundation
@testable import Petzy
import Testing

/// Логика формы профиля для врача. Сам экран проверяется глазами, а решения,
/// которые сервер принимает или отклоняет, — здесь: пустая строка в том или
/// ином поле уехала бы запросом и вернулась бы ошибкой после похода туда и
/// обратно.
@Suite("Медкарта: форма профиля")
struct MedicalProfileFormTests {
    @Test("Пустая аллергия не уходит: сервер требует, на что именно")
    func blankAllergyIsCaught() {
        var draft = MedicalProfileTests.profile
        draft.allergies = [Allergy(substance: "", reaction: "зуд")]

        #expect(MedicalProfileDraft.problem(draft) == "Укажите, на что аллергия")
    }

    @Test("Аллергия без реакции уходит: реакция на сервере необязательная")
    func allergyWithoutReactionIsFine() {
        var draft = MedicalProfileTests.profile
        draft.allergies = [Allergy(substance: "Курица", reaction: "")]

        #expect(MedicalProfileDraft.problem(draft) == nil)
    }

    @Test("Заболевание без названия не уходит")
    func blankConditionIsCaught() {
        var draft = MedicalProfileTests.profile
        draft.conditions = [MedicalCondition(name: "  ", note: nil, sinceYear: nil)]

        #expect(MedicalProfileDraft.problem(draft) == "Укажите название заболевания")
    }

    @Test("Год вне 1950...2100 не уходит: сервер его отвергает")
    func impossibleYearIsCaught() {
        var draft = MedicalProfileTests.profile
        draft.conditions = [MedicalCondition(name: "Дисплазия", note: nil, sinceYear: 1800)]

        #expect(MedicalProfileDraft.problem(draft) == "Год должен быть от 1950 до 2100")
    }

    @Test("Отметка «аллергий нет» заменяет список и не мешает сохранить")
    func noneKnownReplacesList() {
        var draft = MedicalProfileTests.profile
        draft.allergiesNoneKnown = true

        // Список при этом остаётся в форме: человек мог передумать, и
        // снятая отметка вернёт его на место.
        #expect(MedicalProfileDraft.problem(draft) == nil)
        #expect(draft.allergies.count == 1)
    }

    @Test("«Аллергий нет» без списка уходит: это и есть ответ врачу")
    func noneKnownAloneIsFine() {
        var draft = MedicalProfileTests.profile
        draft.allergies = []
        draft.allergiesNoneKnown = true

        #expect(MedicalProfileDraft.problem(draft) == nil)
    }

    @Test("Заполненный профиль не имеет замечаний")
    func filledProfileHasNoProblem() {
        #expect(MedicalProfileDraft.problem(MedicalProfileTests.profile) == nil)
    }

    @Test("Добавленная аллергия требует названия: пустая строка не уедет")
    func addingAllergyGivesBlankRow() {
        var draft = MedicalProfileTests.profile
        draft.allergies = []

        draft.allergies.append(Allergy(substance: "", reaction: ""))

        #expect(draft.allergies.count == 1)
        #expect(MedicalProfileDraft.problem(draft) == "Укажите, на что аллергия")
    }

    @Test("Отметка «аллергий нет» не стирает список: человек передумал на миллисекунду")
    func noneKnownKeepsList() {
        var draft = MedicalProfileTests.profile
        let before = draft.allergies

        draft.allergiesNoneKnown = true

        #expect(draft.allergiesNoneKnown)
        #expect(draft.allergies == before)
    }

    @Test("Пустой профиль отправляется без версии: его ещё никто не сохранял")
    func emptyProfileHasNoVersion() {
        let draft = MedicalProfileDraft.empty()

        #expect(draft.baseVersion == nil)
        #expect(draft.allergies.isEmpty)
        #expect(draft.conditions.isEmpty)
        #expect(MedicalProfileDraft.problem(draft) == nil)
    }

    @Test("Профиль из карты несёт её версию, иначе правка чужого профиля затрётся")
    func draftFromCardCarriesVersion() {
        let profile = MedicalProfile(
            baseVersion: "v3",
            allergies: [Allergy(substance: "Курица", reaction: "зуд")],
            allergiesNoneKnown: false,
            bloodType: nil,
            chipNumber: nil,
            clinicName: nil,
            clinicPhone: nil,
            vetName: nil,
            conditions: [],
            diet: nil,
            living: nil,
            reproduction: nil
        )

        let draft = MedicalProfileDraft(baseVersion: "v3", profile: profile)

        #expect(draft.baseVersion == "v3")
        #expect(draft.allergies.first?.substance == "Курица")
    }

    @Test("«Год» из пустой строки это отсутствие года, а ноль")
    func emptyYearIsNoYear() {
        var draft = MedicalProfileTests.profile
        draft.conditions = [MedicalCondition(name: "Дисплазия", note: nil, sinceYear: nil)]

        draft.conditions[0].sinceYear = MedicalCondition.year(from: "")

        #expect(draft.conditions[0].sinceYear == nil)
    }

    @Test("Год из четырёх цифр читается числом")
    func typedYearIsNumber() {
        #expect(MedicalCondition.year(from: "2023") == 2023)
        // Негод цифр человек напечатать может, и сервер такой год не примет.
        #expect(MedicalCondition.year(from: "23") == nil)
    }
}
