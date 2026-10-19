import Foundation

extension MedicalCardModel {
    /// «К приёму»: жалоба и семь отметок. Версия та же, что у профиля:
    /// форму открыли из карты, и карта с тех пор могла измениться.
    @discardableResult
    func saveVisitPrep(baseVersion: String?, complaint: String?, checks: [String: String]) async -> Bool {
        errorText = nil
        do {
            try await MedicalCardAPI.saveVisitPrep(
                client, petID: petID, baseVersion: baseVersion, complaint: complaint, checks: checks
            )
            notice = "Записано"
            await load()
            return true
        } catch {
            errorText = Self.text(of: error)
            return false
        }
    }

    /// Заметка «К приёму» после визита: к следующему приёму её пишут заново,
    /// а врач не должен слышать то, что было в прошлый раз. Ошибка тут не
    /// мешает: визит уже записан, и сбивать человека с толку после
    /// сохранения незачем.
    func clearVisitPrep() async {
        guard card?.visitPrep != nil else { return }
        do {
            try await MedicalCardAPI.clearVisitPrep(client, petID: petID)
            await load()
        } catch {
            // Заметка осталась: визит-то записан.
        }
    }
}
