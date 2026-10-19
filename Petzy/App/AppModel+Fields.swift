import Foundation

/// Порядок и подписи значений записи. Отдельный файл от ядра модели по
/// размеру, а не по архитектуре.
extension AppModel {
    /// Значения записи в порядке полей типа: главное значение, которое
    /// человек вносит первым, стоит первым, а не по алфавиту внутренних имён.
    /// Поле, которого нет в справочнике, дописывается в конец: терять
    /// пришедшие данные нельзя.
    func fieldValues(_ fields: [String: FieldValue], of type: String) -> [(label: String, value: String)] {
        let known = typeInfo(for: type)?.fields ?? []
        let ordered = known.compactMap { field -> (label: String, value: String)? in
            guard let value = fields[field.name] else { return nil }
            return (field.label, value.display)
        }
        let rest = fields
            .filter { key, _ in !known.contains { $0.name == key } }
            .sorted { $0.key < $1.key }
            .map { (fieldLabel($0.key, of: type), $0.value.display) }
        return ordered + rest
    }
}
