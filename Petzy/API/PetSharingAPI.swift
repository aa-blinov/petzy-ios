import Foundation

/// Совместный доступ к питомцу: приглашение, отзыв, ответ на приглашение и
/// выход. Приглашение не даёт доступа: пока человек не принял, питомца у него
/// нет, и сервер отвечает на его id как на чужой.
enum PetSharingAPI {
    /// Пригласить человека точным логином. Сервер сам решает, что ответить:
    /// себя пригласить нельзя, уже приглашённого — тоже.
    static func invite(_ client: APIClient, petID: String, username: String) async throws {
        let ack: Ack = try await client.post(
            "/api/pets/\(AppModel.query(petID))/share",
            body: ["username": username]
        )
        _ = ack
    }

    /// Забрать доступ или непрочитанное приглашение. Питомец и записи остаются
    /// у владельца.
    static func revoke(_ client: APIClient, petID: String, username: String) async throws {
        try await client.delete("/api/pets/\(AppModel.query(petID))/share/\(AppModel.query(username))")
    }

    /// Питомцы, к которым пригласили этого человека.
    static func invites(_ client: APIClient) async throws -> [PetInvite] {
        let response: InvitesResponse = try await client.get("/api/pets/invites")
        return response.invites
    }

    static func accept(_ client: APIClient, petID: String) async throws {
        let ack: Ack = try await client.post("/api/pets/\(AppModel.query(petID))/invite/accept", body: EmptyBody())
        _ = ack
    }

    static func decline(_ client: APIClient, petID: String) async throws {
        let ack: Ack = try await client.post("/api/pets/\(AppModel.query(petID))/invite/decline", body: EmptyBody())
        _ = ack
    }

    /// Выйти из чужого питомца: он пропадёт из списка, а у владельца останется.
    static func leave(_ client: APIClient, petID: String) async throws {
        let ack: Ack = try await client.post("/api/pets/\(AppModel.query(petID))/leave", body: EmptyBody())
        _ = ack
    }
}

/// Приглашение к чужому питомцу: только имя, вид и владелец — больше сервер до
/// ответа не отдаёт.
struct PetInvite: Decodable, Sendable, Identifiable, Equatable {
    let petID: String
    let petName: String
    let species: String?
    let owner: String

    var id: String {
        petID
    }

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case petName = "pet_name"
        case species
        case owner
    }
}

private struct InvitesResponse: Decodable, Sendable {
    let invites: [PetInvite]
}

/// Ответ сервера на действие без данных.
private struct Ack: Decodable, Sendable {
    let success: Bool
}
