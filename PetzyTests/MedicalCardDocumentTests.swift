import Foundation
@testable import Petzy
import Testing

/// Медкарта как документ. Пять пунктов готовности, строка статуса и слова о
/// сроках: на экране всё это читает человек, и читать он должен понимать,
/// а не разбирать ключи.
@Suite("Медкарта: документ")
struct MedicalCardDocumentTests {
    @Test("Готовность — это пять пунктов, а не четыре плитки")
    func readinessHasFiveSteps() {
        #expect(MedicalReadiness.allCases.count == 5)
        #expect(MedicalReadiness.allCases.map(\.title) == [
            "Аллергии", "Прививки", "Обработки от паразитов", "Клиника", "Вес"
        ])
    }

    /// Готовность читается по карте: аллергии сказаны, прививка записана, вес
    /// есть. Клиники и обработок нет — их и не хватает.
    @Test("Готовность считается по тому, что в карте есть")
    func readinessCountsWhatIsThere() {
        let card = Self.card(
            allergies: ["Пенициллин"],
            vaccinations: 2,
            parasites: 0,
            clinics: 0,
            weight: true
        )

        #expect(card.readinessDone == 3)
        #expect(card.readinessMissing == ["обработки от паразитов", "клиника"])
    }

    /// «Аллергий нет» — тоже ответ: отсутствие аллергий врачу важно знать.
    @Test("Отметка «аллергий нет» считается ответом")
    func allergiesNoneKnownCounts() {
        let card = Self.card(allergies: [], allergiesNoneKnown: true)

        #expect(card.readiness[.allergies] == true)
        #expect(card.readinessDone == 1)
    }

    /// Чего не хватает — словами, как человек их скажет: «аллергии, прививки и
    /// вес». Разделитель «·» в интерфейсе не используется.
    @Test("Не хватает читается словами")
    func missingReadsInWords() {
        let card = Self.card(allergies: [], vaccinations: 0, parasites: 0, clinics: 0, weight: false)

        #expect(card.readinessMissingText == "аллергии, прививки, обработки от паразитов, клиника и вес")
    }

    /// Кнопка первого шага — тот пункт, который ещё не сделан, и его название.
    @Test("Первый шаг — тот, что не сделан")
    func firstStepIsTheMissingOne() {
        let card = Self.card(allergies: [], vaccinations: 0, parasites: 0, clinics: 0, weight: false)

        #expect(card.readinessNext?.step == .allergies)
        #expect(card.readinessNext?.action == "Указать аллергии")
    }

    /// Когда всё готово, первого шага нет: предлагать нечего.
    @Test("Когда всё готово, шага нет")
    func noStepWhenEverythingIsReady() {
        let card = Self.card(allergies: ["Пенициллин"], vaccinations: 1, parasites: 1, clinics: 1, weight: true)

        #expect(card.readinessDone == 5)
        #expect(card.readinessNext == nil)
    }

    /// Строка под «Медкартой»: что просрочено важнее, чем сколько готово.
    @Test("Просроченное важнее готовности")
    func overdueWinsOverReadiness() {
        let card = Self.card(
            allergies: ["Пенициллин"], vaccinations: 1, parasites: 1, clinics: 1, weight: true,
            overdue: [.vaccination]
        )

        #expect(card.statusLine == "Прививка просрочена")
    }

    @Test("Просрочены обе — говорим обе")
    func bothOverdue() {
        let card = Self.card(
            allergies: ["Пенициллин"], vaccinations: 1, parasites: 1, clinics: 1, weight: true,
            overdue: [.vaccination, .parasite]
        )

        #expect(card.statusLine == "Прививка и обработка просрочены")
    }

    /// Когда просроченного нет, строка говорит, сколько готово.
    @Test("Когда всё в срок, строка говорит о готовности")
    func statusLineCountsReadiness() {
        let card = Self.card(allergies: ["Пенициллин"], vaccinations: 1, parasites: 0, clinics: 0, weight: true)

        #expect(card.statusLine == "Заполнено 3 из 5")
    }

    @Test("Когда готово всё, строка говорит об этом")
    func statusLineWhenAllReady() {
        let card = Self.card(allergies: ["Пенициллин"], vaccinations: 1, parasites: 1, clinics: 1, weight: true)

        #expect(card.statusLine == "Всё заполнено")
    }

    /// Статус записи читается словами и с числом дней: «Просрочено на 11 дней»,
    /// «Через 5 дней», «Сегодня», «Завтра», «В срок».
    @Test("Статус записи читается словами")
    func recordStatusReadsInWords() {
        #expect(Self.record(status: .overdue, daysLeft: -11).statusText == "Просрочено на 11 дней")
        #expect(Self.record(status: .soon, daysLeft: 5).statusText == "Через 5 дней")
        #expect(Self.record(status: .soon, daysLeft: 0).statusText == "Сегодня")
        #expect(Self.record(status: .soon, daysLeft: 1).statusText == "Завтра")
        #expect(Self.record(status: .fine, daysLeft: 30).statusText == "В срок")
    }

    /// У записи без даты повтора срока нет, и выдумывать его нельзя.
    @Test("У записи без срока нет и статуса")
    func recordWithoutRepeatHasNoStatus() {
        #expect(Self.record(status: .none, daysLeft: nil).statusText == nil)
    }

    /// Статус сертификата: «Действует», «Скоро истекает», «Истекла 3 дня назад»,
    /// «Срок не указан».
    @Test("Статус сертификата читается словами")
    func certificateStatusReadsInWords() {
        #expect(Self.certificate(status: .valid, daysLeft: 26).statusText == "Действует")
        #expect(Self.certificate(status: .soon, daysLeft: 9).statusText == "Скоро истекает")
        #expect(Self.certificate(status: .expired, daysLeft: -3).statusText == "Истекла 3 дня назад")
        #expect(Self.certificate(status: .none, daysLeft: nil).statusText == "Срок не указан")
    }

    /// Что требует внимания: сначала самое горящее, а запись, заменённая более
    /// новой, не зовёт вовсе — её уже сделали заново.
    @Test("Требует внимания: горячее вперёд, заменённое не зовёт")
    func attentionIsSortedByUrgency() {
        let card = Self.card(
            allergies: [], vaccinations: 0, parasites: 0, clinics: 0, weight: false,
            overdue: [.parasite],
            supersededOverdue: true
        )

        #expect(card.attention.count == 1, "заменённая запись не должна звать")
        #expect(card.attention.first?.record?.status == .overdue)
    }

    // MARK: - Заготовки

    static func record(
        kind: MedicalKind = .parasite,
        status: MedicalStatus,
        daysLeft: Int?,
        superseded: Bool = false
    ) -> MedicalRecord {
        MedicalRecord(
            id: "r-\(kind.rawValue)",
            kind: kind,
            title: "Бравекто",
            date: "2026-07-12",
            nextDue: "2026-10-07",
            status: status,
            daysLeft: daysLeft,
            clinic: nil,
            vet: nil,
            note: nil,
            batch: nil,
            target: "fleas_ticks",
            protects: nil,
            complaint: nil,
            diagnosis: nil,
            recommendations: nil,
            documentIDs: [],
            updatedAt: nil,
            superseded: superseded
        )
    }

    static func certificate(status: CertificateStatus, daysLeft: Int?) -> CardCertificate {
        CardCertificate(
            id: "c1",
            title: "Сертификат прививки",
            expiresAt: "2026-11-15",
            status: status,
            daysLeft: daysLeft,
            note: nil
        )
    }

    static func card(
        allergies: [String],
        allergiesNoneKnown: Bool = false,
        vaccinations: Int = 0,
        parasites: Int = 0,
        clinics: Int = 0,
        weight: Bool = false,
        overdue: [MedicalKind] = [],
        supersededOverdue: Bool = false
    ) -> MedicalCard {
        var records: [MedicalKind: [MedicalRecord]] = [:]
        if vaccinations > 0 {
            records[.vaccination] = [record(status: .fine, daysLeft: 30)]
        }
        if parasites > 0 {
            records[.parasite] = [record(status: .fine, daysLeft: 30)]
        }
        var overdueRecords: [MedicalRecord] = []
        for kind in overdue {
            let entry = record(kind: kind, status: .overdue, daysLeft: -11)
            records[kind, default: []].append(entry)
            overdueRecords.append(entry)
        }
        if supersededOverdue {
            overdueRecords.append(record(kind: .vaccination, status: .overdue, daysLeft: -30, superseded: true))
        }
        let profile = MedicalProfile(
            baseVersion: nil,
            allergies: allergies.map { Allergy(substance: $0, reaction: "") },
            allergiesNoneKnown: allergiesNoneKnown,
            bloodType: nil,
            chipNumber: nil,
            clinicName: clinics > 0 ? "Ортовет" : nil,
            clinicPhone: nil,
            vetName: nil,
            clinics: clinics > 0 ? [ProfileClinic(name: "Ортовет", phone: nil, doctors: [])] : [],
            conditions: [],
            diet: nil,
            living: nil,
            reproduction: nil
        )
        // Счётчики — по числу записей: готовность смотрит на них, как и веб.
        var counts: [MedicalKind: Int] = [:]
        for (kind, items) in records {
            counts[kind] = items.count
        }
        return MedicalCard(
            pet: CardPet(name: "Рекс", breed: "Лабрадор", species: "Собака", ageText: "5 лет", neuteredText: ""),
            records: records,
            counts: counts,
            overdueCount: overdueRecords.count,
            weight: weight ? WeightPoint(date: "2026-10-04", value: 29.3) : nil,
            medications: [],
            documents: [],
            pastCourses: [],
            profile: profile,
            visitPrep: nil,
            generatedAt: "2026-10-20",
            canEdit: true,
            overdueRecords: overdueRecords
        )
    }
}
