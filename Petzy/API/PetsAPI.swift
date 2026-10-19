import Foundation

/// Разговор с сервером про питомцев. Единственное место, где известны пути
/// `/api/pets` и ключи ответа: экран держит в руках `PetProfile` и про JSON
/// не знает.
enum PetsAPI {
    /// Карточка питомца по своему адресу, а не весь список: правка открывает
    /// одного питомца, и тянуть ради этого всех остальных незачем.
    static func card(_ client: APIClient, id: String) async throws -> PetProfile {
        let response: PetCardResponse = try await client.get("/api/pets/\(AppModel.query(id))")
        return response.pet.domain
    }

    /// Новый питомец. Тело multipart'ом всегда: с файлом и без него форма
    /// собирается одинаково, а значит и ведёт себя одинаково.
    static func create(_ client: APIClient, draft: PetDraft, photo: UploadFile?) async throws -> PetProfile {
        let body = form(draft: draft, photo: photo, removePhoto: false)
        let response: PetCardResponse = try await client.postMultipart(
            "/api/pets",
            body: body.data,
            contentType: body.contentType
        )
        return response.pet.domain
    }

    /// Тело нового питомца для очереди: то же, что уходит на сервер, но под
    /// своим именем. Имя это `local_id`: по нему сервер узнаёт повтор и не
    /// заводит второго питомца.
    static func createBody(draft: PetDraft, photo: UploadFile?, localID: String) -> MultipartBody {
        form(draft: draft, photo: photo, removePhoto: false, localID: localID)
    }

    /// Тело правки для очереди. Версия та, что человек видел: сервер откажет,
    /// если карточку поменяли с тех пор, и останется версия сервера.
    static func updateBody(
        draft: PetDraft,
        photo: UploadFile?,
        removePhoto: Bool,
        baseVersion: String?
    ) -> MultipartBody {
        form(draft: draft, photo: photo, removePhoto: removePhoto, baseVersion: baseVersion)
    }

    /// Правка питомца. Ответа с карточкой сервер не присылает, только
    /// «Данные питомца обновлены», поэтому вызывающий перечитывает карточку
    /// сам — иначе на экране осталось бы то, что человек правил до сохранения.
    static func update(
        _ client: APIClient,
        id: String,
        draft: PetDraft,
        photo: UploadFile?,
        removePhoto: Bool,
        baseVersion: String? = nil
    ) async throws {
        let body = form(draft: draft, photo: photo, removePhoto: removePhoto, baseVersion: baseVersion)
        let ack: PetAck = try await client.putMultipart(
            "/api/pets/\(AppModel.query(id))",
            body: body.data,
            contentType: body.contentType
        )
        _ = ack
    }

    /// Что пропадёт вместе с питомцем. Считает сервер, и пересчитывать это
    /// на телефоне по своему списку записей нельзя: список тут не весь.
    static func deletionImpact(_ client: APIClient, id: String) async throws -> PetDeletionImpact {
        let response: ImpactDTO = try await client.get("/api/pets/\(AppModel.query(id))/deletion-impact")
        return response.domain
    }

    /// Значения по умолчанию лежат на питомце, а не в справочнике типов: ими
    /// пользуется всякий, кто добавляет этому питомцу записи, включая
    /// соавторов.
    static func formDefaults(_ client: APIClient, id: String) async throws -> FormDefaults {
        let response: PetCardResponse = try await client.get("/api/pets/\(AppModel.query(id))")
        // Поля у питомца без единого сохранённого значения сервер не отдаёт.
        return response.pet.formDefaults ?? [:]
    }

    /// Набор заменяется целиком: сервер не дополняет его, а переписывает. Поэтому
    /// убрать значение можно только явным сохранением без него.
    static func saveFormDefaults(
        _ client: APIClient,
        id: String,
        defaults: FormDefaults
    ) async throws -> FormDefaults {
        let response: FormDefaultsResponse = try await client.put(
            "/api/pets/\(AppModel.query(id))/form-defaults",
            body: FormDefaultsBody(formDefaults: defaults)
        )
        return response.formDefaults
    }

    static func delete(_ client: APIClient, id: String) async throws {
        try await client.delete("/api/pets/\(AppModel.query(id))")
    }

    /// Тело формы питомца. Пустые значения уходят пустыми: на сервере пустая
    /// строка значит «убери», а отсутствие поля — «не трогай». Исключение
    /// одно, `is_neutered`: пустую строку сервер не понимает вовсе и
    /// отвечает 422, поэтому «не указано» просто не отправляется.
    private static func form(
        draft: PetDraft,
        photo: UploadFile?,
        removePhoto: Bool,
        baseVersion: String? = nil,
        localID: String? = nil
    ) -> MultipartBody {
        var body = MultipartBody()
        body.addField(name: "name", value: draft.name)
        body.addField(name: "species", value: draft.species ?? "", includeEmpty: true)
        body.addField(name: "breed", value: draft.breed, includeEmpty: true)
        body.addField(name: "gender", value: draft.gender.key ?? "", includeEmpty: true)
        body.addField(name: "health_notes", value: draft.healthNotes, includeEmpty: true)
        if let birthDate = draft.birthDate {
            body.addField(name: "birth_date", value: MomentText.isoDay(birthDate, calendar: .current))
        }
        if let flag = draft.neutering.flag {
            body.addField(name: "is_neutered", value: flag)
        }
        if removePhoto {
            body.addField(name: "remove_photo", value: "true")
        }
        if let baseVersion {
            body.addField(name: "base_version", value: baseVersion)
        }
        if let localID {
            body.addField(name: "local_id", value: localID)
        }
        if let photo {
            body.addFile(name: "photo_file", fileName: photo.name, contentType: photo.contentType, data: photo.data)
        }
        return body
    }
}

// MARK: - Разобранный ответ

private struct PetCardResponse: Decodable {
    let pet: PetDTO
}

private struct PetAck: Decodable {
    let success: Bool?
}

private struct FormDefaultsBody: Encodable {
    let formDefaults: FormDefaults

    enum CodingKeys: String, CodingKey {
        case formDefaults = "form_defaults"
    }
}

private struct FormDefaultsResponse: Decodable {
    let formDefaults: FormDefaults

    enum CodingKeys: String, CodingKey {
        case formDefaults = "form_defaults"
    }
}

/// Карточка питомца с сервера. Оформление `look` и медицинский профиль сюда не
/// входят: их показывает медкарта, а держать лишнее в каждой копии карточки
/// незачем.
private struct PetDTO: Decodable {
    let id: String
    let name: String
    let species: String?
    let breed: String?
    let birthDate: String?
    let gender: String?
    let isNeutered: Bool?
    let healthNotes: String?
    let photoURL: String?
    let currentUserIsOwner: Bool?
    let formDefaults: FormDefaults?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, breed, gender
        case species, birthDate = "birth_date"
        case isNeutered = "is_neutered"
        case healthNotes = "health_notes"
        case photoURL = "photo_url"
        case currentUserIsOwner = "current_user_is_owner"
        case formDefaults = "form_defaults"
        case updatedAt = "updated_at"
    }

    var domain: PetProfile {
        PetProfile(
            id: id,
            name: name,
            // Пустой вид это «не указан», а не значение: в списке выбора вида
            // пустая строка не совпала бы ни с одним пунктом и строка осталась
            // бы незаполненной безо всякой подписи.
            species: species.flatMap { $0.isEmpty ? nil : $0 },
            breed: breed ?? "",
            birthDate: birthDate,
            gender: PetGender.known(gender),
            neutering: isNeutered.map { $0 ? .done : .notYet } ?? .unknown,
            healthNotes: healthNotes ?? "",
            photoURL: photoURL.flatMap(URL.init(string:)),
            currentUserIsOwner: currentUserIsOwner ?? false,
            updatedAt: updatedAt
        )
    }
}

private struct ImpactDTO: Decodable {
    let events: Int
    let medications: Int
    let documents: Int
    let medicalRecords: Int

    enum CodingKeys: String, CodingKey {
        case events, medications, documents
        case medicalRecords = "medical_records"
    }

    var domain: PetDeletionImpact {
        PetDeletionImpact(
            events: events,
            medications: medications,
            documents: documents,
            medicalRecords: medicalRecords
        )
    }
}
