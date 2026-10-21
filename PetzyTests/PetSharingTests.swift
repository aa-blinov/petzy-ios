import Foundation
@testable import Petzy
import Testing

/// Совместный доступ: один питомец на двоих. На вебе владелец приглашает
/// второго человека, тот видит приглашение и принимает, и дальше оба ведут
/// питомца. Приглашение — не доступ: до ответа питомца у приглашённого нет.
@Suite("Совместный доступ к питомцу")
struct PetSharingTests {
    @Test("Приглашение уходит точным логином")
    func inviteSendsExactUsername() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "Приглашение отправлено"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await PetSharingAPI.invite(client, petID: "p1", username: "family")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/share"])
        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["username"] as? String == "family")
    }

    @Test("Логин с собакой в теле не ломает запрос")
    func inviteEscapesUsername() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "ok"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await PetSharingAPI.invite(client, petID: "p1", username: "a&b")

        let body = TestSupport.body(of: StubURLProtocol.requests.last)
        #expect(body["username"] as? String == "a&b")
    }

    @Test("Отзыв доступа уходит логином в пути")
    func revokePutsUsernameInPath() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "ok"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await PetSharingAPI.revoke(client, petID: "p1", username: "family")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/share/family"])
        #expect(StubURLProtocol.requests.last?.httpMethod == "DELETE")
    }

    @Test("Приглашения приходят с именем питомца и владельцем")
    func invitesDecode() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: [
            "invites": [
                ["pet_id": "p9", "pet_name": "Рекс", "species": "dog", "owner": "family"]
            ]
        ])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        let invites = try await PetSharingAPI.invites(client)

        #expect(invites.count == 1)
        #expect(invites.first?.petID == "p9")
        #expect(invites.first?.petName == "Рекс")
        #expect(invites.first?.owner == "family")
        #expect(invites.first?.species == "dog")
    }

    @Test("Принятие и отказ — два разных маршрута")
    func acceptAndDeclineDiffer() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "ok"])
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "ok"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await PetSharingAPI.accept(client, petID: "p1")
        try await PetSharingAPI.decline(client, petID: "p1")

        #expect(StubURLProtocol.requestedPaths == [
            "/api/pets/p1/invite/accept",
            "/api/pets/p1/invite/decline"
        ])
    }

    @Test("Выход из чужого питомца")
    func leaveHasItsOwnRoute() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(status: 200, json: ["success": true, "message": "ok"])
        let client = await MedicationsTests.client(session: StubURLProtocol.makeSession())

        try await PetSharingAPI.leave(client, petID: "p1")

        #expect(StubURLProtocol.requestedPaths == ["/api/pets/p1/leave"])
    }

    /// Питомец знает, чей он и с кем поделён: от этого зависит, показывать ли
    /// «Пригласить» или «Выйти из питомца».
    @Test("Питомец знает, что он чужой, и с кем поделён")
    func petCarriesOwnership() throws {
        let json = """
        {
          "_id": "p1", "name": "Рекс", "species": "dog",
          "current_user_is_owner": false,
          "shared_with": ["family", "friend"],
          "share_invites": ["waiting"]
        }
        """
        let pet = try JSONDecoder().decode(Pet.self, from: Data(json.utf8))

        #expect(pet.isOwner == false)
        #expect(pet.sharedWith == ["family", "friend"])
        #expect(pet.shareInvites == ["waiting"])
    }

    /// Сервер не отдаёт приглашённых не-владельцу, и отсутствие ключа не
    /// должно ломать разбор.
    @Test("Без полей доступа питомец считается своим по умолчанию")
    func missingOwnershipDefaultsToOwner() throws {
        let pet = try JSONDecoder().decode(Pet.self, from: Data(#"{"_id": "p1", "name": "Рекс"}"#.utf8))

        #expect(pet.isOwner)
        #expect(pet.sharedWith.isEmpty)
        #expect(pet.shareInvites.isEmpty)
    }
}
