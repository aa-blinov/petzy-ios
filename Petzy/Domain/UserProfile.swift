import Foundation

/// Страница другого человека: кто он и какие питомцы у вас общие. Сервер отдаёт
/// соседу по питомцу только это: ни почты, ни прав, ни чужих питомцев.
struct UserProfile: Decodable, Sendable, Equatable {
    let username: String
    let fullName: String?
    let createdAt: String
    /// Питомцы, доступные обоим: имя ведёт на медкарту.
    let sharedPets: [SharedPet]

    struct SharedPet: Decodable, Sendable, Equatable, Identifiable {
        let id: String
        let name: String
    }

    /// Заголовок экрана: имя, а если его нет — логин. Пустая строка выглядела
    /// бы поломкой.
    var title: String {
        guard let fullName, !fullName.isEmpty else { return username }
        return fullName
    }

    enum CodingKeys: String, CodingKey {
        case username
        case fullName = "full_name"
        case createdAt = "created_at"
        case sharedPets = "shared_pets"
    }
}

extension UserProfile {
    /// «На Petzy с»: день регистрации по-русски. Полный момент приходит
    /// строкой, и день берётся из него там же, где и везде.
    var sinceText: String {
        MomentText.russianDay(createdAt)
    }
}
