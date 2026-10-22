import SwiftUI

/// Отмеченный приём: что дали, когда, и что с этим можно сделать. Время
/// переносится, приём отменяется вместе с возвратом остатка — ошибочная
/// отметка не должна оставаться фактом.
///
/// Формой приём не правится: дозу и остаток двигает отдельный маршрут, а здесь
/// меняется только время, как и на вебе.
struct IntakeSheet: View {
    let intake: MedicationIntake
    /// Перенести время приёма. Замыкание, а не модель: лист открывается и из
    /// раздела лекарств, и из ленты, а экраны после правки обновляются по-своему.
    let onMove: (MedicationIntake, Moment) async -> Void
    /// Отменить приём: отметка пропадёт, списанное вернётся в остаток.
    let onCancel: (MedicationIntake) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now
    @State private var time = Date.now
    @State private var askingDelete = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intake.medicationName).font(.headline)
                    LabeledContent("Дали", value: "\(MomentText.humanDay(intake.day)) в \(intake.time)")
                } footer: {
                    Text("Меняется только время: доза и остаток остаются как были")
                }
                Section {
                    DatePicker("Дата", selection: $day, displayedComponents: .date)
                    DatePicker("Во сколько", selection: $time, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Время приёма")
                }
                Section {
                    Button("Отменить приём", role: .destructive) { askingDelete = true }
                } footer: {
                    Text("Отметка пропадёт, а списанное вернётся в остаток")
                }
            }
            .navigationTitle("Приём")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task { await save() }
                    }
                    .disabled(saving)
                }
            }
            .alert("Отменить приём?", isPresented: $askingDelete) {
                Button("Отменить приём", role: .destructive) {
                    Task {
                        await onCancel(intake)
                        dismiss()
                    }
                }
                Button("Оставить", role: .cancel) {}
            } message: {
                Text("Отметка пропадёт, а списанное вернётся в остаток")
            }
            .task {
                // Поля открываются на том времени, что записано: человек
                // поправляет его, а не вводит заново.
                guard let moment = Self.moment(of: intake) else { return }
                day = moment
                time = moment
            }
        }
    }

    /// День и время приёма одним `Date`: сервер отдаёт их по отдельности, а
    /// ползунки хотят один.
    private static func moment(of intake: MedicationIntake) -> Date? {
        guard let day = MomentText.date(from: intake.day) else { return nil }
        let parts = intake.time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        await onMove(intake, Moment(day: day, time: time))
        dismiss()
    }
}
