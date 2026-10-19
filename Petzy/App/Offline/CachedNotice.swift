import SwiftUI

/// Строка «нет связи, показаны сохранённые данные». Раздел отдаёт копию и
/// обязан сказать об этом: иначе человек примет старые данные за свежие и
/// примет лекарство, которое уже отменили.
struct CachedNotice: View {
    var body: some View {
        Label("Нет связи, показаны сохранённые данные", systemImage: "wifi.slash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
