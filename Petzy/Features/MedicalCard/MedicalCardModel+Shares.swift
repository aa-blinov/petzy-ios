import Foundation

/// Ссылки для врача: создать, перечитать живые, отозвать. Отдельный файл, как
/// и документы медкарты: сама модель и без этого длинная.
///
/// Секрет ссылки приходит один раз и больше не хранится, поэтому адрес держится
/// в модели, пока человек его не отправит.
extension MedicalCardModel {
    func createShare(days: Int) async {
        errorText = nil
        do {
            share = try await MedicalCardAPI.createShare(
                client,
                petID: petID,
                days: days,
                webBase: webBase
            )
            // Без перечитывания список врал бы: ссылка есть, а в нём пусто.
            await loadShares()
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Какие ссылки сейчас работают. Отозванные и истёкшие сервер сам не
    /// присылает, поэтому список всегда про то, что ещё открывает карту.
    func loadShares() async {
        do {
            shares = try await MedicalCardAPI.shares(client, petID: petID)
        } catch {
            errorText = Self.text(of: error)
        }
    }

    /// Отзыв ссылки: адрес перестаёт открывать карту сразу, а сам список
    /// перечитывается, чтобы у человека не осталось мысли, что он работает.
    func revoke(_ share: LiveShare) async {
        errorText = nil
        do {
            try await MedicalCardAPI.revokeShare(client, petID: petID, shareID: share.id)
            // Готовый адрес тоже убираем: поделиться отозванной ссылкой
            // человек может прямо с этого экрана, а она уже ничего не открывает.
            if self.share?.id == share.id {
                self.share = nil
            }
            await loadShares()
        } catch {
            errorText = Self.text(of: error)
        }
    }
}
