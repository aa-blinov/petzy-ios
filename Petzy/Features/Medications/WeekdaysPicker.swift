import SwiftUI

/// Дни недели для расписания приёма. В один ряд семь кнопок не помещаются на
/// крупном шрифте: каждой достаётся по сорок точек, и «Пн» рвётся по буквам.
/// Тогда они идут сеткой, как плитки медкарты.
struct WeekdaysPicker: View {
    /// Выбранные дни по индексу: 0 — понедельник.
    @Binding var days: Set<Int>

    /// Крупный шрифт человека.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                buttons
            }
        } else {
            HStack(spacing: 6) {
                buttons
            }
        }
    }

    private var buttons: some View {
        ForEach(0 ..< 7, id: \.self) { index in
            let picked = days.contains(index)
            Button {
                if picked {
                    days.remove(index)
                } else {
                    days.insert(index)
                }
            } label: {
                Text(Self.names[index])
                    .font(.subheadline.weight(picked ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(picked ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            // Выбранный день виден цветом, а голос о нём молчит.
            .accessibilityAddTraits(picked ? .isSelected : [])
        }
    }

    static let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
}
