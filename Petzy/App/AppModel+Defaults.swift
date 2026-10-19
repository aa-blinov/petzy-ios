import Foundation

/// Значения по умолчанию: значения лежат на питомце, а методы их читают и
/// подкладывают в форму новой записи.
extension AppModel {
    /// Черновик новой записи выбранного типа. Пустая форма, поверх которой
    /// кладутся сохранённые значения: без них человек вводит одно и то же
    /// каждый день, например один и тот же корм.
    func newDraft(for type: EventTypeInfo) -> EventDraft {
        let draft = EventFormView.emptyDraft(type: type)
        guard let fields = formDefaults[type.key] else { return draft }
        return EventDraft(
            type: type,
            // Пустое сохранённое значение не подставляется: иначе поле пришло бы
            // с курсором в строке и выглядело бы так, будто человек что-то ввёл.
            values: fields.filter { _, value in !value.isEmpty },
            comment: "",
            date: draft.date,
            time: draft.time
        )
    }

    /// Читаются при выборе питомца, а не хранятся между запусками: значения
    /// принадлежат питомцу и меняются вместе с ним.
    func loadFormDefaults() async {
        guard let petID = selectedPetID else { return }
        do {
            formDefaults = try await PetsAPI.formDefaults(client, id: petID)
        } catch {
            // Набор намеренно не трогаем: сервер заменяет его целиком, и если
            // человек откроет настройки при упавшей загрузке и сохранит одно
            // значение, пропадут все остальные. Ошибку тут показывать негде:
            // экран настроек покажет её сам.
        }
    }
}
