import Foundation

/// Разговор с сервером про медкарту. Единственное место, где известны пути
/// `/api/pets/<id>/medical-card` и ключи ответа: экран держит в руках
/// `MedicalCard` и про JSON не знает.
enum MedicalCardAPI {
    /// Карта целиком. Один маршрут вместо пяти: плитки, сроки, лекарства и
    /// профиль приходят вместе, и собирать их по одному означало бы мигающий
    /// экран при каждом открытии вкладки.
    static func card(_ client: APIClient, petID: String, zone: String) async throws -> MedicalCard {
        let path = "/api/pets/\(AppModel.query(petID))/medical-card?tz=\(AppModel.query(zone))"
        let response: CardResponse = try await client.get(path)
        return response.card.domain
    }

    /// PDF для врача приходит файлом: приложение открывает готовый, а не
    /// собирает свой. Вместе с телом отдаётся имя файла из заголовка сервера.
    static func pdf(_ client: APIClient, petID: String) async throws -> (data: Data, fileName: String?) {
        try await client.download("/api/pets/\(AppModel.query(petID))/medical-card/pdf")
    }

    /// Все записи вида. Плитка показывает десять, остальное — отсюда.
    static func records(_ client: APIClient, petID: String, kind: MedicalKind) async throws -> [MedicalRecord] {
        let path = "/api/medical-records?pet_id=\(AppModel.query(petID))&kind=\(kind.rawValue)"
        let response: RecordsResponse = try await client.get(path)
        return response.records.map { $0.domain(fallback: kind) }
    }

    static func create(_ client: APIClient, draft: MedicalRecordDraft) async throws {
        let ack: MedicalWriteAck = try await client.post("/api/medical-records", body: RecordBody(draft: draft))
        _ = ack
    }

    static func update(_ client: APIClient, id: String, draft: MedicalRecordDraft) async throws {
        let ack: MedicalWriteAck = try await client.put("/api/medical-records/\(id)", body: RecordBody(draft: draft))
        _ = ack
    }

    static func delete(_ client: APIClient, id: String) async throws {
        try await client.delete("/api/medical-records/\(id)")
    }
}

// MARK: - Тела запросов

/// Запись медкарты в том виде, как её заполняет форма. Поля своего вида
/// сервер отбрасывает сам, поэтому форма шлёт все, а разбирается сервер.
private struct RecordBody: Encodable {
    let petID: String
    let kind: String
    let date: String
    let title: String
    /// Пустая строка значит «убери дату повтора», а `nil` — «не трогай».
    let nextDue: String?
    let clinic: String?
    let vet: String?
    let note: String?
    let batch: String?
    let target: String?
    let protects: String?
    let complaint: String?
    let diagnosis: String?
    let recommendations: String?

    init(draft: MedicalRecordDraft) {
        petID = draft.petID
        kind = draft.kind.rawValue
        date = draft.date
        title = draft.title
        nextDue = draft.nextDue
        clinic = draft.clinic
        vet = draft.vet
        note = draft.note
        batch = draft.batch
        // Обработка без цели сервер не примет: «от кого» здесь обязателен.
        target = draft.target
        protects = draft.protects
        complaint = draft.complaint
        diagnosis = draft.diagnosis
        recommendations = draft.recommendations
    }

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case kind, date, title
        case nextDue = "next_due"
        case clinic, vet, note, batch, target, protects
        case complaint, diagnosis, recommendations
    }
}

private struct MedicalWriteAck: Decodable {
    let id: String?
}

// MARK: - Разобранный ответ

private struct CardResponse: Decodable {
    let card: CardDTO
}

private struct RecordsResponse: Decodable {
    let records: [RecordDTO]
}

private struct CardDTO: Decodable {
    let pet: CardPetDTO
    let records: [String: [RecordDTO]]
    let recordCounts: [String: Int]
    let overdueRecords: [RecordDTO]
    let weight: WeightDTO?
    let medications: [CardMedicationDTO]
    let documents: [CardDocumentDTO]
    let pastCourses: [CardCourseDTO]
    let profile: ProfileDTO?
    let visitPrep: VisitPrepDTO?
    let generatedAt: String
    let canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case pet, records, medications, documents, profile
        case recordCounts = "record_counts"
        case overdueRecords = "overdue_records"
        case weight
        case pastCourses = "past_courses"
        case visitPrep = "visit_prep"
        case generatedAt = "generated_at"
        case canEdit = "can_edit"
    }
}

private struct CardPetDTO: Decodable {
    let name: String
    let breed: String?
    let species: String?
    let ageText: String?
    let neuteredText: String?

    enum CodingKeys: String, CodingKey {
        case name, breed, species
        case ageText = "age_text"
        case neuteredText = "neutered_text"
    }
}

private struct RecordDTO: Decodable {
    let id: String
    let kind: String?
    let title: String
    let date: String
    let nextDue: String?
    let status: String?
    let daysLeft: Int?
    let clinic: String?
    let vet: String?
    let note: String?
    let target: String?
    let protects: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind, title, date
        case nextDue = "next_due"
        case status
        case daysLeft = "days_left"
        case clinic, vet, note, target, protects
    }
}

private struct WeightDTO: Decodable {
    let latest: PointDTO?
}

private struct PointDTO: Decodable {
    let date: String
    let value: Double
}

private struct CardMedicationDTO: Decodable {
    let id: String
    let name: String
    let doseText: String?
    let purpose: String?

    enum CodingKeys: String, CodingKey {
        case id, name, purpose
        case doseText = "dose_text"
    }
}

private struct CardDocumentDTO: Decodable {
    let id: String
    let title: String
}

private struct CardCourseDTO: Decodable {
    let id: String
    let name: String
}

private struct ProfileDTO: Decodable {
    let allergies: [AllergyDTO]?
    let allergiesNoneKnown: Bool?
    let bloodType: String?
    let chipNumber: String?
    let clinic: ClinicDTO?
    let conditions: [ConditionDTO]?
    let diet: String?
    let living: String?
    let reproduction: String?

    enum CodingKeys: String, CodingKey {
        case allergies, clinic, conditions, diet, living, reproduction
        case allergiesNoneKnown = "allergies_none_known"
        case bloodType = "blood_type"
        case chipNumber = "chip_number"
    }
}

private struct ConditionDTO: Decodable {
    let name: String
    let note: String?
    let sinceYear: Int?

    enum CodingKeys: String, CodingKey {
        case name, note
        case sinceYear = "since_year"
    }
}

private struct AllergyDTO: Decodable {
    let substance: String?
    let reaction: String?
}

private struct ClinicDTO: Decodable {
    let name: String?
    let phone: String?
    let vet: String?
}

private struct VisitPrepDTO: Decodable {
    let complaint: String?
    let checks: [String: String]?
}

// MARK: - Разбор в домен

private extension CardDTO {
    var domain: MedicalCard {
        var records: [MedicalKind: [MedicalRecord]] = [:]
        for kind in MedicalKind.allCases {
            // Вид может прийти ключом словаря или полем в самой записи: у
            // просроченных вид задан явно, у лежащих в разделе — ключом.
            records[kind] = (self.records[kind.rawValue] ?? []).map { $0.domain(fallback: kind) }
        }
        // Счётчики приходят ключами-строками, а плитки ходят по видам: без
        // переноса плитка всегда показывала бы ноль.
        var counts: [MedicalKind: Int] = [:]
        for kind in MedicalKind.allCases {
            counts[kind] = recordCounts[kind.rawValue] ?? 0
        }
        return MedicalCard(
            pet: CardPet(
                name: pet.name,
                breed: pet.breed ?? "",
                species: pet.species ?? "",
                ageText: pet.ageText ?? "",
                neuteredText: pet.neuteredText ?? ""
            ),
            records: records,
            counts: counts,
            overdueCount: overdueRecords.count,
            weight: weight?.latest.map { WeightPoint(date: $0.date, value: $0.value) },
            medications: medications.map { CardMedication(
                id: $0.id,
                name: $0.name,
                doseText: $0.doseText,
                purpose: $0.purpose
            ) },
            documents: documents.map { CardDocument(id: $0.id, title: $0.title) },
            pastCourses: pastCourses.map { CardCourse(id: $0.id, name: $0.name) },
            profile: profile?.domain,
            visitPrep: visitPrep.map {
                VisitPrep(
                    complaint: $0.complaint,
                    checks: ($0.checks ?? [:]).sorted { $0.key < $1.key }.map { VisitCheck(
                        id: $0.key,
                        title: $0.key,
                        value: $0.value
                    ) }
                )
            },
            generatedAt: generatedAt,
            canEdit: canEdit
        )
    }
}

private extension RecordDTO {
    /// Запись без ключа раздела: в просроченных вид задан полем `kind`.
    func domain(fallback: MedicalKind) -> MedicalRecord {
        MedicalRecord(
            id: id,
            kind: kind.flatMap(MedicalKind.init(rawValue:)) ?? fallback,
            title: title,
            date: date,
            nextDue: nextDue,
            status: status.flatMap(MedicalStatus.init(rawValue:)) ?? .none,
            daysLeft: daysLeft,
            clinic: clinic,
            vet: vet,
            note: note
        )
    }
}

private extension ProfileDTO {
    var domain: MedicalProfile {
        MedicalProfile(
            allergies: (allergies ?? []).compactMap {
                guard let substance = $0.substance, !substance.isEmpty else { return nil }
                return Allergy(substance: substance, reaction: $0.reaction ?? "")
            },
            allergiesNoneKnown: allergiesNoneKnown ?? false,
            bloodType: bloodType,
            chipNumber: chipNumber,
            clinicName: clinic?.name,
            clinicPhone: clinic?.phone,
            vetName: clinic?.vet,
            conditions: (conditions ?? [])
                .map { MedicalCondition(name: $0.name, note: $0.note, sinceYear: $0.sinceYear) },
            diet: diet,
            living: living,
            reproduction: reproduction
        )
    }
}
