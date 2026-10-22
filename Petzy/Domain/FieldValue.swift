import Foundation

enum FieldValue: Codable, Sendable, Equatable {
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .number(container.decode(Double.self))
    }

    /// Число без хвостовых нулей: вес 29,30 это тот же вес, что 29,3, и в ленте
    /// человек видит 29,3. Разделитель запятой, как в русской записи.
    var display: String {
        switch self {
        case let .text(text):
            return text
        case let .number(number):
            let rounded = (number * 10).rounded() / 10
            return String(format: "%g", rounded).replacingOccurrences(of: ".", with: ",")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text):
            try container.encode(text)
        case let .number(number):
            try container.encode(number)
        }
    }
}

// Тело запроса записи. У создания есть тип и питомец, у правки их нет: тип у
// записи не меняется, а питомца менять нельзя. Один тип на оба случая, чтобы
// не держать два одинаковых описания.
