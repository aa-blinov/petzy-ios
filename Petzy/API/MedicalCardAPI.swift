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

    /// Профиль для врача. `base_version` уходит вместе с полями: сервер
    /// сверяет его с сохранённым и отвечает 409, если правка была устаревшей.
    static func saveProfile(_ client: APIClient, petID: String, profile: MedicalProfileDraft) async throws {
        let ack: MedicalWriteAck = try await client.put(
            "/api/pets/\(AppModel.query(petID))/medical-profile",
            body: ProfileBody(profile: profile)
        )
        _ = ack
    }

    /// «К приёму»: жалоба и отметки по семи пунктам.
    static func saveVisitPrep(
        _ client: APIClient,
        petID: String,
        baseVersion: String?,
        complaint: String?,
        checks: [String: String]
    ) async throws {
        let ack: MedicalWriteAck = try await client.put(
            "/api/pets/\(AppModel.query(petID))/visit-prep",
            body: VisitPrepBody(baseVersion: baseVersion, complaint: complaint, checks: checks)
        )
        _ = ack
    }

    /// Создать ссылку для врача. Секрет приходит один раз и больше не
    /// хранится, поэтому адрес показывается сразу и его надо сохранить.
    static func createShare(_ client: APIClient, petID: String, days: Int) async throws -> MedicalShare {
        let response: ShareResponse = try await client.post(
            "/api/pets/\(AppModel.query(petID))/medical-card/shares",
            body: ShareBody(days: days)
        )
        let path = response.path ?? "/share/medical/\(response.token)"
        return MedicalShare(
            id: response.share.id,
            token: response.token,
            // Ссылка открывается без входа, поэтому это адрес, а не путь
            // внутри приложения: поделиться ею можно прямо из системного меню.
            url: URL(string: path, relativeTo: client.baseURL)?.absoluteURL,
            expiresAt: response.share.expiresAt
        )
    }

    static func shares(_ client: APIClient, petID: String) async throws -> [LiveShare] {
        let response: SharesResponse = try await client.get("/api/pets/\(AppModel.query(petID))/medical-card/shares")
        return response.shares.map(\.domain)
    }

    static func revokeShare(_ client: APIClient, petID: String, shareID: String) async throws {
        try await client.delete(
            "/api/pets/\(AppModel.query(petID))/medical-card/shares/\(AppModel.query(shareID))"
        )
    }

    /// Справочник прививок. Пустой ответ не ошибка: прививки заводят и без него.
    static func vaccineCatalog(_ client: APIClient) async throws -> [VaccineGroup] {
        let response: CatalogResponse = try await client.get("/api/vaccines/catalog")
        return response.groups.map(\.domain)
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

private struct ProfileBody: Encodable {
    let baseVersion: String?
    let allergies: [AllergyBody]
    let allergiesNoneKnown: Bool
    let bloodType: String?
    let chipNumber: String?
    let clinic: ClinicBody?
    let conditions: [ConditionBody]
    let diet: String?
    let living: String?
    let reproduction: String?

    init(profile: MedicalProfileDraft) {
        baseVersion = profile.baseVersion
        // Отметка «аллергий нет» и список рядом сервер отклоняет 422: это два
        // разных утверждения об одном и том же. Отметка заменяет список, и
        // набранное остаётся в форме на случай, если человек передумает.
        allergies = profile.allergiesNoneKnown ? [] : profile.allergies.map { AllergyBody(
            substance: $0.substance,
            reaction: $0.reaction.isEmpty ? nil : $0.reaction
        ) }
        allergiesNoneKnown = profile.allergiesNoneKnown
        bloodType = profile.bloodType
        chipNumber = profile.chipNumber
        // Клиника без телефона или врача — это не клиника, и сервер такой
        // объект не примет: отправляем только когда есть имя.
        clinic = profile.clinicName.flatMap { name in
            name.isEmpty ? nil : ClinicBody(
                name: name,
                phone: profile.clinicPhone?.isEmpty == false ? profile.clinicPhone : nil,
                vet: profile.vetName?.isEmpty == false ? profile.vetName : nil
            )
        }
        conditions = profile.conditions.map { ConditionBody(name: $0.name, note: $0.note, sinceYear: $0.sinceYear) }
        diet = profile.diet
        living = profile.living
        reproduction = profile.reproduction
    }

    enum CodingKeys: String, CodingKey {
        case allergies, clinic, conditions, diet, living, reproduction
        case baseVersion = "base_version"
        case allergiesNoneKnown = "allergies_none_known"
        case bloodType = "blood_type"
        case chipNumber = "chip_number"
    }
}

private struct AllergyBody: Encodable {
    let substance: String
    let reaction: String?
}

private struct ClinicBody: Encodable {
    let name: String
    let phone: String?
    let vet: String?
}

private struct ConditionBody: Encodable {
    let name: String
    let note: String?
    let sinceYear: Int?

    enum CodingKeys: String, CodingKey {
        case name, note
        case sinceYear = "since_year"
    }
}

private struct VisitPrepBody: Encodable {
    let baseVersion: String?
    let complaint: String?
    let checks: [String: String]

    enum CodingKeys: String, CodingKey {
        case complaint, checks
        case baseVersion = "base_version"
    }
}

private struct ShareBody: Encodable {
    let days: Int
}

private struct ShareResponse: Decodable {
    let share: LiveShareDTO
    let token: String
    let path: String?
}

private struct SharesResponse: Decodable {
    let shares: [LiveShareDTO]
}

private struct LiveShareDTO: Decodable {
    let id: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case expiresAt = "expires_at"
    }

    var domain: LiveShare {
        LiveShare(id: id, expiresAt: expiresAt)
    }
}

private struct CatalogResponse: Decodable {
    let groups: [VaccineGroupDTO]
}

private struct VaccineGroupDTO: Decodable {
    let key: String
    let label: String
    let detail: String?
    let species: [String]

    var domain: VaccineGroup {
        VaccineGroup(key: key, label: label, detail: detail, species: species)
    }
}
