import Foundation

/// Разговор с сервером про медкарту. Единственное место, где известны пути
/// `/api/pets/<id>/medical-card` и ключи ответа: экран держит в руках
/// `MedicalCard` и про JSON не знает.
enum MedicalCardAPI {
    /// Карта целиком. Один маршрут вместо пяти: плитки, сроки, лекарства и
    /// профиль приходят вместе, и собирать их по одному означало бы мигающий
    /// экран при каждом открытии вкладки.
    static func card(_ client: APIClient, petID: String, zone: String) async throws -> MedicalCard {
        try await decode(raw(client, petID: petID, zone: zone))
    }

    /// Ответ карточки как пришёл: его же кладут в копию для работы без сети.
    static func raw(_ client: APIClient, petID: String, zone: String) async throws -> Data {
        try await client.getRaw("/api/pets/\(AppModel.query(petID))/medical-card?tz=\(AppModel.query(zone))")
    }

    /// Разбор ответа карточки. Один и тот же и для сети, и для копии.
    static func decode(_ data: Data) throws -> MedicalCard {
        try JSONDecoder().decode(CardResponse.self, from: data).card.domain
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

    static func update(
        _ client: APIClient,
        id: String,
        draft: MedicalRecordDraft,
        baseVersion: String? = nil
    ) async throws {
        let ack: MedicalWriteAck = try await client.put(
            "/api/medical-records/\(id)",
            body: RecordBody(draft: draft, baseVersion: baseVersion)
        )
        _ = ack
    }

    /// Тело запроса как байты: очередь офлайн-записей хранит его, чтобы
    /// отправить ровно то же, что ушло бы в сеть.
    static func payload(_ draft: MedicalRecordDraft, localID: String) -> Data? {
        try? JSONEncoder().encode(RecordBody(draft: draft, localID: localID))
    }

    /// Тело правки как байты: очередь офлайн-правок хранит его вместе с
    /// версией, которую человек видел, иначе сервер не заметил бы, что запись
    /// поменяли.
    static func updatePayload(_ draft: MedicalRecordDraft, baseVersion: String?) -> Data? {
        try? JSONEncoder().encode(RecordBody(draft: draft, baseVersion: baseVersion))
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
    /// Сервер заменяет запись целиком: без этого поля правка отвязала бы
    /// документы от записи.
    let documentIDs: [String]
    /// Имя, которым устройство назвало запись, если её создавали без сети. По
    /// нему же сервер узнаёт повтор и не создаёт вторую запись.
    let localID: String?
    /// Версия записи, которую человек правил. Сервер отвечает отказом, если
    /// запись поменяли с тех пор: остаётся версия сервера.
    let baseVersion: String?

    init(draft: MedicalRecordDraft, localID: String? = nil, baseVersion: String? = nil) {
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
        documentIDs = draft.documentIDs
        self.localID = localID
        self.baseVersion = baseVersion
    }

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case kind, date, title
        case nextDue = "next_due"
        case clinic, vet, note, batch, target, protects
        case complaint, diagnosis, recommendations
        case documentIDs = "document_ids"
        case localID = "local_id"
        case baseVersion = "base_version"
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
    /// Список клиник — источник правды на сервере, а `clinic` он собирает сам
    /// из первой. Отправка только зеркала схлопывала бы список в одну клинику.
    let clinics: [ClinicEntryBody]
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
        clinics = Self.clinics(of: profile)
        conditions = profile.conditions.map { ConditionBody(name: $0.name, note: $0.note, sinceYear: $0.sinceYear) }
        diet = profile.diet
        living = profile.living
        reproduction = profile.reproduction
    }

    /// Клиника без имени — не клиника, и сервер такой объект не примет.
    private static func clinics(of profile: MedicalProfileDraft) -> [ClinicEntryBody] {
        let main = ProfileClinic(
            name: profile.clinicName,
            phone: profile.clinicPhone?.isEmpty == false ? profile.clinicPhone : nil,
            doctors: [ProfileDoctor(
                name: profile.vetName?.isEmpty == false ? profile.vetName : nil,
                specialty: profile.clinics.first?.doctors.first?.specialty
            )]
        )
        let all = [main] + profile.clinics.dropFirst()
        return all
            .filter { ($0.name?.isEmpty == false) }
            .map(ClinicEntryBody.init(clinic:))
    }

    enum CodingKeys: String, CodingKey {
        case allergies, clinics, conditions, diet, living, reproduction
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

/// Клиника со списком врачей, как их держит сервер. Враг без имени сервер не
/// примет, поэтому такие отбрасываются целиком.
private struct ClinicEntryBody: Encodable {
    let name: String?
    let phone: String?
    let doctors: [DoctorBody]

    init(clinic: ProfileClinic) {
        name = clinic.name
        phone = clinic.phone
        doctors = clinic.doctors.compactMap { doctor in
            guard let name = doctor.name, !name.isEmpty else { return nil }
            return DoctorBody(name: name, specialty: doctor.specialty)
        }
    }
}

private struct DoctorBody: Encodable {
    let name: String
    let specialty: String?
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
