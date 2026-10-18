import Foundation

/// Аккаунт человека: логин, имя и состояние почты для восстановления пароля.
struct AccountInfo: Sendable, Equatable {
    let username: String
    let fullName: String
    /// Подтверждённая почта. Пока её нет, пароль восстановить нечем.
    let email: String
    let emailVerified: Bool
    /// Указана, но письмо ещё не подтвердили.
    let pendingEmail: String
    /// Настроена ли отправка писем на сервере. Если нет, менять почту
    /// бессмысленно: письмо о подтверждении не уйдёт.
    let mailEnabled: Bool
    let privacyConsentNeeded: Bool

    /// «demo» или пусто, если имени нет: пустым логином строку не заполняют.
    var fullNameText: String? {
        fullName.isEmpty ? nil : fullName
    }

    /// «Указана, но не подтверждена: demo@example.com». Пустая строка, когда
    /// письмо либо ушло, либо его никто не просил.
    var pendingText: String? {
        pendingEmail.isEmpty ? nil : "Указана, но не подтверждена: \(pendingEmail)"
    }
}

/// Питомец в превью удаления аккаунта.
struct DeletionPet: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    /// Другой человек рядом с питомцем: у передаваемого это новый владелец,
    /// у оставленного прежний. Сервер зовёт их по-разному, а чем именно этот
    /// человек станет, показывает раздел, а не поле.
    let person: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case newOwner = "new_owner"
        case owner
    }

    init(id: String, name: String, person: String?) {
        self.id = id
        self.name = name
        self.person = person
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        // Условие в одну строку: многострочный `if let` swiftformat раскрывает
        // скобкой на новой строке, а swiftlint это запрещает.
        person = try container.decodeIfPresent(String.self, forKey: .newOwner)
            ?? container.decodeIfPresent(String.self, forKey: .owner)
    }
}

/// Что случится с питомцами, если удалить аккаунт.
struct AccountDeletionPlan: Decodable, Sendable, Equatable {
    /// Администратора удалить нельзя, и превью об этом говорит само: без этого
    /// поля экран предлагал бы кнопку, которая всегда откажет.
    let canDelete: Bool
    /// Удалятся вместе со своими записями.
    let deleted: [DeletionPet]
    /// Перейдут первому, с кем ими поделились.
    let transferred: [DeletionPet]
    /// Чужие питомцы, к которым пропадёт доступ.
    let left: [DeletionPet]

    enum CodingKeys: String, CodingKey {
        case deleted, transferred, left
        case canDelete = "can_delete"
    }

    /// Пишется руками: свой `init(from:)` убивает тот, что синтезирует
    /// компилятор, а без него превью не собрать в тесте.
    init(canDelete: Bool, deleted: [DeletionPet], transferred: [DeletionPet], left: [DeletionPet]) {
        self.canDelete = canDelete
        self.deleted = deleted
        self.transferred = transferred
        self.left = left
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canDelete = try container.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
        deleted = try container.decodeIfPresent([DeletionPet].self, forKey: .deleted) ?? []
        transferred = try container.decodeIfPresent([DeletionPet].self, forKey: .transferred) ?? []
        left = try container.decodeIfPresent([DeletionPet].self, forKey: .left) ?? []
    }

    /// Питомцев, чья судьба меняется. Пусто, когда менять нечего.
    var isEmpty: Bool {
        deleted.isEmpty && transferred.isEmpty && left.isEmpty
    }

    /// Что скажет вопрос об удалении. Пусто, когда превью ещё не пришло: пустой
    /// список читался бы как «ничего не пропадёт», а пропадёт сам аккаунт.
    var warning: String {
        var parts: [String] = []
        if !deleted.isEmpty {
            parts.append("удалятся \(names(deleted))")
        }
        if !transferred.isEmpty {
            parts.append("перейдут \(heirs(transferred))")
        }
        if !left.isEmpty {
            parts.append("пропадёт доступ к \(names(left))")
        }
        guard !parts.isEmpty else { return "Аккаунт удалится безвозвратно" }
        return "Вместе с аккаунтом: \(parts.joined(separator: ", "))"
    }

    /// «к family: Рекс и Мурзик». После «к» идёт человек, а питомцы уже за ним,
    /// поэтому «перейдут к Рекс» было бы не по-русски. Питомцы могут уйти к
    /// разным людям, и тогда названы все.
    private func heirs(_ pets: [DeletionPet]) -> String {
        let byPerson = Dictionary(grouping: pets) { $0.person ?? "" }
        let chunks = byPerson.keys.sorted().map { key in
            "к \(key): \(names(byPerson[key] ?? []))"
        }
        return chunks.joined(separator: ", ")
    }

    /// «Рекс и Мурзик»: имена через запятую, а последнее через «и».
    private func names(_ pets: [DeletionPet]) -> String {
        let titles = pets.map(\.name)
        guard titles.count > 1 else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " и " + (titles.last ?? "")
    }
}
