import Foundation

/// То, что человек набирает в форме записи. Отдельно от формы, потому что
/// проверка и сборка значений — это логика, и она проверяется тестами, а не
/// глазами на экране.
struct EventDraft {
    let type: EventTypeInfo
    var values: [String: String]
    var comment: String
    /// `yyyy-MM-dd` и `HH:mm`, как их отдаёт сервер.
    var date: String
    var time: String

    /// Инициализатор написан руками, а не оставлен синтезированным: пока в
    /// структуре нет своего `init`, компилятор собирает memberwise сам, а
    /// стоит ему появиться, и memberwise пропадает вместе с ним.
    init(type: EventTypeInfo, values: [String: String], comment: String, date: String, time: String) {
        self.type = type
        self.values = values
        self.comment = comment
        self.date = date
        self.time = time
    }

    /// Что мешает сохранить, по-человечески. `nil` — сохранять можно.
    var problem: String? {
        for field in type.fields {
            let raw = Self.cleaned(values[field.name])
            if raw.isEmpty {
                if field.required {
                    return "Заполните поле «\(field.label)»"
                }
                continue
            }
            guard field.type == "number" else { continue }
            guard let number = Self.number(raw) else {
                return "В поле «\(field.label)» должно быть число"
            }
            if let min = field.min, number < min {
                return "В поле «\(field.label)» меньше \(FieldValue.number(min).display)"
            }
            if let max = field.max, number > max {
                return "В поле «\(field.label)» больше \(FieldValue.number(max).display)"
            }
        }
        return nil
    }

    /// Значения полей в виде для запроса. Пустые необязательные поля уходят
    /// прочь: серверу незачем знать про них.
    var encodedFields: [String: FieldValue] {
        var result: [String: FieldValue] = [:]
        for field in type.fields {
            let raw = Self.cleaned(values[field.name])
            guard !raw.isEmpty else { continue }
            if field.type == "number", let number = Self.number(raw) {
                result[field.name] = .number(number)
            } else {
                result[field.name] = .text(raw)
            }
        }
        return result
    }

    private static func cleaned(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Запятая вместо точки это нормально, так пишут в русской записи, а
    /// телефонная клавиатура в русской раскладке ставит именно её.
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Черновик правки: значения записи в том виде, в каком их видит человек.
    /// Число приходит с запятой, поэтому в поле возвращается «29,3», а не
    /// «29.3», иначе правка выглядела бы как порча записи.
    init(event: PetEvent, type: EventTypeInfo) {
        self.init(
            type: type,
            values: event.fields.mapValues(\.display),
            comment: event.comment,
            date: event.day,
            time: event.time
        )
    }
}
