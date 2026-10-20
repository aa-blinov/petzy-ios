import SwiftUI

/// Карточка курса: чем он называется, как и когда давать, сколько осталось и
/// что можно сделать прямо здесь. Карточка не знает ни путей, ни ключей
/// сервера — всё, что ей нужно, уже посчитано в `Medication`.
struct MedicationCard: View {
    let med: Medication
    let now: String
    let onGiveNow: () -> Void
    let onRestock: () -> Void
    let onEdit: () -> Void
    let onToggleCourse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Label(med.scheduleText, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let period = med.coursePeriod {
                Text(period).font(.subheadline).foregroundStyle(.secondary)
            }
            if med.scheduledToday, !med.asNeeded {
                Text(med.todayProgress(at: now))
                    .font(.subheadline)
                    .foregroundStyle(med.isDoneToday ? .secondary : .primary)
            }
            if let stock = med.stockText {
                // Остаток и кнопка пополнения своими кнопками: тап по этой
                // строке не должен открывать форму курса.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stock)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(med.stock?.isLow == true ? .red : .primary)
                        if let sub = med.stockSubtext {
                            Text(sub).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Пополнить", action: onRestock)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if let last = med.lastTakenText {
                Text("Последний приём: \(last)").font(.subheadline)
            }
            if med.courseStatus == .active {
                actions
            }
            if med.courseStatus != .planned {
                Button(med.courseStatus == .ended ? "Возобновить курс" : "Завершить курс", action: onToggleCourse)
                    .font(.subheadline)
                    .padding(.top, 2)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(med.name).font(.headline)
                    if let tag = med.courseTag {
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text("\(med.strength ?? med.kind), по \(med.doseText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            // Отметка приёма отдельной кнопкой, а не тапом по карточке:
            // тап открывает правку курса, и это разные вещи.
            Button {
                onGiveNow()
            } label: {
                Text(med.isDoneToday ? "Записать дополнительный приём" : "Дали сейчас (\(med.doseText))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.top, 2)
    }
}

/// Пополнение остатка. Одно число и одна кнопка: сколько купили.
struct RestockSheet: View {
    let model: MedicationsModel
    let medication: Medication

    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    /// У поля с цифровой клавиатурой нет клавиши Return, и без кнопки
    /// «Готово» над ней её нечем убрать.
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Сколько добавить", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                } footer: {
                    if let text = parsed, text <= 0 {
                        Text("Количество должно быть больше нуля")
                            .foregroundStyle(.red)
                    } else {
                        Text("Упаковка прибавится к остатку курса")
                    }
                }
            }
            .navigationTitle(medication.name)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDone { amountFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Пополнить") {
                        guard let value = parsed, value > 0 else { return }
                        Task {
                            await model.restock(medication, amount: value)
                            dismiss()
                        }
                    }
                    .disabled(parsed == nil || parsed ?? 0 <= 0)
                }
            }
        }
    }

    private var parsed: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }
}

/// Отметка приёма: сейчас, другим временем или с пропуском слота.
struct DoseSheet: View {
    let model: MedicationsModel
    let medication: Medication

    @Environment(\.dismiss) private var dismiss
    @State private var dose = ""
    @State private var date = Date.now
    @State private var time = Date.now
    @State private var skipped = false
    /// У поля с цифровой клавиатурой нет клавиши Return, и без кнопки
    /// «Готово» над ней её нечем убрать.
    @FocusState private var doseFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Название курса в листе: без него «Отметить приём» от
                    // трёх карточек подряд не отличить друг от друга.
                    Text(medication.name).font(.headline)
                    TextField("Сколько дали", text: $dose)
                        .keyboardType(.decimalPad)
                        .focused($doseFocused)
                    DatePicker("Когда", selection: $date, displayedComponents: .date)
                    DatePicker("Во сколько", selection: $time, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Приём")
                } footer: {
                    Text("По умолчанию отмечается ближайший приём по расписанию")
                }
                Section {
                    Toggle("Пропустить приём", isOn: $skipped)
                } footer: {
                    Text("Слот считается закрытым, но из остатка ничего не вычитается")
                }
            }
            .navigationTitle("Отметить приём")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDone { doseFocused = false }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Записать") {
                        Task {
                            await model.markDose(
                                medication,
                                dose: parsed,
                                slot: nil,
                                skipped: skipped,
                                moment: Moment(day: date, time: time)
                            )
                            dismiss()
                        }
                    }
                    .disabled(!skipped && parsed == nil)
                }
            }
        }
    }

    private var parsed: Double? {
        dose.isEmpty ? medication.defaultDose : Double(dose.replacingOccurrences(of: ",", with: "."))
    }
}
