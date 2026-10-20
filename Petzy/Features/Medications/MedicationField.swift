/// Поля формы курса. Return ведёт от поля к полю, а «Готово» над цифровой
/// клавиатурой снимает фокус.
enum MedicationField: Hashable {
    case name, strength, dose, unit
    case current, total, warning
    case purpose, prescribedBy, comment

    /// Следующее поле по порядку формы. Остатка в форме может не быть: раздел
    /// появляется, только когда человек его включил.
    func next(inventory: Bool) -> MedicationField? {
        var order: [MedicationField] = [.name, .strength, .dose, .unit]
        if inventory {
            order += [.current, .total, .warning]
        }
        order += [.purpose, .prescribedBy, .comment]
        guard let index = order.firstIndex(of: self) else { return nil }
        return index + 1 < order.count ? order[index + 1] : nil
    }
}
