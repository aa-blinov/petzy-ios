import Foundation

/// Вид поля своего типа. Названия те же, что у сервера: `text`, `number`,
/// `select`, `textarea`.
enum CustomFieldKind: String, CaseIterable, Sendable {
    case text
    case number
    case select
    case textarea

    var title: String {
        switch self {
        case .text: "Текст"
        case .number: "Число"
        case .select: "Выбор"
        case .textarea: "Заметка"
        }
    }
}

/// Как рисуется график типа в истории: столбиками по количеству записей или
/// линией по величине.
enum CustomChartKind: String, CaseIterable, Sendable {
    case count
    case value

    var title: String {
        switch self {
        case .count: "Сколько записей"
        case .value: "По величине"
        }
    }
}

/// График типа в том виде, как его выбирает человек.
struct CustomChart: Sendable, Equatable {
    var kind: CustomChartKind = .count
    /// Имя числового поля, по которому считается линия. У счётного графика оно
    /// не нужно, и сервер его не примет.
    var field = ""
    /// Подпись оси с единицами измерения: «Вес (кг)».
    var valueLabel = ""
}

/// Поле своего типа в том виде, как его заполняет человек.
struct CustomFieldDraft: Identifiable, Sendable, Equatable {
    var id = UUID()
    var label = ""
    /// Имя латиницей: по нему сервер и приложение узнают поле в записи. Если
    /// человек его не трогал, он получается из подписи сам.
    var name = ""
    var nameEdited = false
    var kind: CustomFieldKind = .text
    var required = false
    /// Варианты выбора, по одному в строке, в виде «значение=Подпись». Так их
    /// набирает человек, а не машина.
    var options = ""

    /// Что поправить до запроса. `nil` — можно отправлять.
    static func problem(_ field: CustomFieldDraft, index: Int, existing: [String]) -> String? {
        let place = "Поле \(index + 1)"
        if field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(place): введите подпись"
        }
        if field.name.isEmpty {
            return "\(place): подпись не превратилась в имя"
        }
        if reservedNames.contains(field.name) {
            return "\(place): имя \(field.name) сервер оставил за собой"
        }
        if existing.contains(field.name) {
            return "\(place): имя \(field.name) уже есть в этом типе"
        }
        if field.kind == .select, parseOptions(field.options).isEmpty {
            return "\(place): для выбора нужны варианты, по одному в строке"
        }
        return nil
    }

    /// Имена, которые сервер использует под запись: такое поле он не примет.
    static let reservedNames: Set<String> = ["pet_id", "date", "time", "comment", "type", "fields"]

    /// «Мало=Немного, Много=Очень» в массив пар. Строки без «=» считаются
    /// подписью и значением одновременно.
    static func parseOptions(_ text: String) -> [[String: String]] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                return parts.count == 2 ? ["value": parts[0], "text": parts[1]] : ["value": parts[0], "text": parts[0]]
            }
    }

    /// Поле из справочника в то, чем его правят. `options` склеиваются обратно
    /// в строки, потому что человек их и набирает в строке.
    static func from(_ field: EventFieldInfo) -> CustomFieldDraft {
        var draft = CustomFieldDraft()
        draft.label = field.label
        draft.name = field.name
        draft.nameEdited = true
        draft.kind = CustomFieldKind(rawValue: field.type) ?? .text
        draft.required = field.required
        draft.options = (field.options ?? []).map { "\($0.value)=\($0.text)" }.joined(separator: "\n")
        return draft
    }
}

/// Свой тип записи в том виде, как его заполняет человек. `key` пустой у нового:
/// его назначает сервер.
struct CustomTypeDraft: Sendable {
    var key: String?
    var label = ""
    var icon = CustomIcon.paw
    var color = CustomColor.blue
    var fields: [CustomFieldDraft] = [CustomFieldDraft()]
    var chart = CustomChart()

    /// Поля, в которые есть что вписать. Человек добавляет поле заранее и
    /// заполняет потом, а пустое имя сервер не примет, поэтому и проверка, и
    /// запрос смотрят только на эти.
    var filledFields: [CustomFieldDraft] {
        fields.filter { !$0.label.isEmpty || !$0.name.isEmpty }
    }

    /// Что поправить до запроса. Сервер проверяет формат имён полей, но за
    /// двадцать строк текста на телефоне легко набрать не то, и отказ приходит
    /// уже после отправки.
    static func problem(_ draft: CustomTypeDraft) -> String? {
        if draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите название типа"
        }
        let real = draft.filledFields
        if real.isEmpty {
            return "Добавьте хотя бы одно поле"
        }
        var taken: [String] = []
        for (index, field) in real.enumerated() {
            if let problem = CustomFieldDraft.problem(field, index: index, existing: taken) {
                return problem
            }
            taken.append(field.name)
        }
        if draft.chart.kind == .value, !real.contains(where: { $0.kind == .number && $0.name == draft.chart.field }) {
            return "Выберите числовое поле для графика"
        }
        return nil
    }

    /// Правка открывается тем, что уже заведено. Что не перенеслось, то
    /// пропало бы при сохранении без единой правки. Фабрикой, а не `init`:
    /// свой инициализатор у structs съедает членосообразующий.
    static func from(_ saved: EventTypeInfo) -> CustomTypeDraft {
        var draft = CustomTypeDraft()
        draft.key = saved.key
        draft.label = saved.label
        draft.icon = CustomIcon(rawValue: saved.icon ?? "") ?? .paw
        draft.color = CustomColor(rawValue: saved.color ?? "") ?? .blue
        draft.fields = saved.fields.map(CustomFieldDraft.from)
        draft.chart = CustomChart(
            kind: saved.chart?.kind == CustomChartKind.value.rawValue ? .value : .count,
            field: saved.chart?.valueField ?? "",
            valueLabel: saved.chart?.valueLabel ?? ""
        )
        return draft
    }
}

/// Значок типа. Сервер принимает имя из латиницы, а рисуется значком системы,
/// поэтому набор здесь конечный: выбирать из сотни иконок незачем.
enum CustomIcon: String, CaseIterable, Sendable {
    case paw
    case heart
    case moon
    case sparkles
    case leaf
    case figure
    case utensils
    case drop
    case thermometer
    case book

    var title: String {
        switch self {
        case .paw: "Лапа"
        case .heart: "Сердце"
        case .moon: "Луна"
        case .sparkles: "Искры"
        case .leaf: "Лист"
        case .figure: "Фигура"
        case .utensils: "Тарелка"
        case .drop: "Капля"
        case .thermometer: "Термометр"
        case .book: "Книга"
        }
    }

    var symbol: String {
        EventIcon.symbol(for: rawValue)
    }
}

/// Цвет типа. Сервер принимает свои одиннадцать названий, а не любой оттенок,
/// поэтому выбирать приходится из них.
enum CustomColor: String, CaseIterable, Sendable {
    case brown
    case orange
    case red
    case green
    case purple
    case teal
    case cyan
    case yellow
    case blue
    case pink
    case gray

    var title: String {
        switch self {
        case .brown: "Коричневый"
        case .orange: "Оранжевый"
        case .red: "Красный"
        case .green: "Зелёный"
        case .purple: "Фиолетовый"
        case .teal: "Бирюзовый"
        case .cyan: "Голубой"
        case .yellow: "Жёлтый"
        case .blue: "Синий"
        case .pink: "Розовый"
        case .gray: "Серый"
        }
    }
}

/// Имя поля латиницей из подписи. Сервер требует `^[a-z][a-z0-9_]{0,49}$`,
/// а человек пишет «Длительность (мин)», поэтому переводим сами, как в вебе.
enum FieldName {
    private static let map: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
        "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"
    ]

    static func from(_ label: String, existing: [String]) -> String {
        let transliterated = String(
            label.lowercased().map { map[$0] ?? String($0) }.joined()
        )
        var slug = transliterated
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: "_")
        slug = String(slug.prefix(50))
        if slug.isEmpty {
            slug = "field"
        } else if !(slug.first?.isLetter ?? false) {
            slug = String(("field_" + slug).prefix(50))
        }
        var candidate = slug
        var suffix = 2
        while existing.contains(candidate) {
            candidate = String((slug + "_" + String(suffix)).prefix(50))
            suffix += 1
        }
        return candidate
    }
}
