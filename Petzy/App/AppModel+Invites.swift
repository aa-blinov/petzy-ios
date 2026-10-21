import Foundation

extension AppModel {
    /// Приглашения к чужим питомцам. Читаются при запуске и после ответа:
    /// ошибку здесь молчим, приглашение — не то, ради чего стоит показывать
    /// тревогу поверх ленты.
    func loadInvites() async {
        guard let answer = try? await PetSharingAPI.invites(client) else { return }
        invites = answer
    }

    /// Принять приглашение: питомец появляется в списке и сразу открывается —
    /// человек принимал его, чтобы увидеть.
    func acceptInvite(_ invite: PetInvite) async {
        do {
            try await PetSharingAPI.accept(client, petID: invite.petID)
            invites.removeAll { $0.id == invite.id }
            await loadPets()
            select(petID: invite.petID)
        } catch {
            report(error)
        }
    }

    /// Отклонить: приглашение пропадает, у владельца ничего не меняется.
    func declineInvite(_ invite: PetInvite) async {
        do {
            try await PetSharingAPI.decline(client, petID: invite.petID)
            invites.removeAll { $0.id == invite.id }
        } catch {
            report(error)
        }
    }

    /// Ошибка ответа на приглашение: сессию кончаем там же, где и везде, а
    /// остальное показываем словами.
    private func report(_ error: Error) {
        if let apiError = error as? APIError, apiError.isAuthProblem {
            endSession()
            return
        }
        errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
