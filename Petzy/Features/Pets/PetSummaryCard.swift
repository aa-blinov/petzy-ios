import SwiftUI

/// Карточка питомца на главном экране: фото (или значок вида, если фото нет),
/// имя и строка «возраст, порода, пол». В вебе карточка такая же
/// (`PetSummaryCard`), но без рамок, цветной подложки и рукописного шрифта:
/// это украшение веба, а данные о питомце остаются.
struct PetSummaryCard: View {
    let pet: Pet

    var body: some View {
        HStack(spacing: 16) {
            photo
            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let meta = pet.metaLine {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    /// Фото питомца. Пока оно грузится и если его нет, на его месте значок
    /// вида: пустой квадрат смотрелся бы поломкой экрана.
    private var photo: some View {
        ZStack {
            Image(systemName: PetSpecies.icon(for: pet.species))
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            if let url = pet.photoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    // Пока фото едет, виден значок вида под ним.
                    Color.clear
                }
                .accessibilityIdentifier("petPhoto")
            }
        }
        .frame(width: 72, height: 72)
        .background(.quaternary)
        .clipped()
        .clipShape(.rect(cornerRadius: 12))
    }
}

/// Возраст питомца словами: «5 лет», «2 месяца», «3 дня». Формат тот же, что
/// в вебе (`computePetAge`), а числа склоняются по-русски.
enum PetAge {
    static func text(birthDate: String?, today: Date = .now, calendar: Calendar = .current) -> String? {
        guard let parts = birthDate?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        var born = DateComponents()
        born.year = parts[0]
        born.month = parts[1]
        born.day = parts[2]
        guard let first = calendar.date(from: born) else { return nil }
        let now = calendar.dateComponents([.year, .month, .day], from: today)
        // Неполный месяц не считается: питомцу, которому два месяца и двадцать
        // дней, два месяца, а не двадцать один.
        var months = ((now.year ?? 0) - parts[0]) * 12 + ((now.month ?? 0) - parts[1])
        if (now.day ?? 0) < parts[2] {
            months -= 1
        }
        guard months >= 0 else { return nil }
        if months < 1 {
            let days = max(0, calendar.dateComponents([.day], from: first, to: today).day ?? 0)
            if days < 7 {
                return Words.text(days, one: "день", few: "дня", many: "дней")
            }
            return Words.text(days / 7, one: "неделя", few: "недели", many: "недель")
        }
        if months < 12 {
            return Words.text(months, one: "месяц", few: "месяца", many: "месяцев")
        }
        return Words.text(months / 12, one: "год", few: "года", many: "лет")
    }
}

extension Pet {
    /// Строка под именем в карточке: возраст, порода и пол через запятую, как
    /// в вебе. Если про питомца ничего не известно, показываем вид: пустая
    /// строка под именем выглядела бы поломкой экрана.
    var metaLine: String? {
        var parts: [String] = []
        if let age = PetAge.text(birthDate: birthDate) {
            parts.append(age)
        }
        if let breed, !breed.isEmpty {
            parts.append(breed)
        }
        let petGender = PetGender.known(gender)
        if petGender != .unknown {
            parts.append(petGender.title)
        }
        if parts.isEmpty, let species = PetSpecies.label(for: species) {
            parts.append(species)
        }
        guard !parts.isEmpty else { return nil }
        // Порода и пол в русском не имена собственные: с заглавной они читались
        // бы ошмёткой, как в вебе.
        return parts.joined(separator: ", ").lowercased()
    }
}
