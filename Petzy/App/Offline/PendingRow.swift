import SwiftUI

/// Строка неотправленного: человек сделал это без связи, и запись ждёт.
/// Без такой строки он сделал бы то же самое ещё раз, когда связь появится.
struct PendingRow: View {
    let write: PendingWrite
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(write.title, systemImage: "clock")
                .font(.subheadline)
            Spacer()
            Text(write.waiting)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Убрать из очереди")
        }
    }
}
