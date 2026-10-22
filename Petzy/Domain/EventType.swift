import Foundation

/// Типы записей в том виде, в каком их видит приложение: ярлыки,
/// поля, значки. Ключи ответа сервера сюда не проникают, и разбор
/// лежит в `EventTypesAPI`.
///
struct EventFieldOption: Codable, Sendable, Equatable {
    let text: String
    let value: String
}

// Поле типа записи: как оно называется в записи и как подписано для человека.
// Подпись нужна для показа: ключ `weight` в ленте читаться не должен. Вид,
// обязательность и границы нужны форме добавления, чтобы собрать запись из
// того, что человек набрал, и не отправить на сервер ерунду.

struct EventFieldInfo: Codable, Sendable, Identifiable, Equatable {
    let name: String
    let label: String
    /// `number`, `text` или `choice`.
    let type: String
    let required: Bool
    let min: Double?
    let max: Double?
    let options: [EventFieldOption]?

    /// У поля уже есть имя, оно и есть его identity в списке.
    var id: String {
        name
    }
}

// Тип записи: как она называется, каким значком рисуется и какие у неё поля.
// `category` приходит `null` у своих типов, их форма выбора не спрашивает.
// `color` есть только у своих: встроенным он не нужен, а правке своего типа
// без него цвет молча сбросился бы на первый в списке.

struct EventTypeInfo: Codable, Sendable, Identifiable {
    let key: String
    let label: String
    let icon: String?
    let category: String?
    let color: String?
    let fields: [EventFieldInfo]
    let chart: EventChart?

    var id: String {
        key
    }

    /// Инициализатор написан руками: `color` есть не у всех типов, а
    /// синтезированный такую подпись не делает.
    init(
        key: String,
        label: String,
        icon: String?,
        category: String?,
        color: String? = nil,
        fields: [EventFieldInfo],
        chart: EventChart?
    ) {
        self.key = key
        self.label = label
        self.icon = icon
        self.category = category
        self.color = color
        self.fields = fields
        self.chart = chart
    }
}

// Как рисуется график типа: `value` — линия по величине записи, `count` —
// столбцы по количеству записей. Без него график показывал бы среднее там,
// где нужен счёт.

struct EventChart: Codable, Sendable, Equatable {
    let kind: String
    let valueField: String?
    /// Подпись величины с единицами измерения: «Вес (кг)». Без неё на оси
    /// были бы голые числа.
    let valueLabel: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case valueField = "value_field"
        case valueLabel = "value_label"
    }
}

// Типы, записи о которых у питомца есть. Ими заполняется фильтр истории.
