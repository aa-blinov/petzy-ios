import SwiftUI

/// Профиль для врача. Читает его другой человек на приёме, поэтому вопросы
/// те же, что задаёт врач: на что аллергия, чем обостряется, кого лечили.
struct MedicalProfileFormView: View {
    let model: MedicalCardModel
    let card: MedicalCard?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MedicalProfileDraft
    /// Годы набраны текстом: пустое поле это «год не указан», а не ноль.
    @State private var years: [Int: String]
    /// Какое поле сейчас в фокусе. У поля с цифровой клавиатурой нет клавиши
    /// Return, и без кнопки «Готово» над ней её нечем убрать.
    @FocusState private var focus: String?

    init(model: MedicalCardModel, card: MedicalCard?) {
        self.model = model
        self.card = card
        let base = card?.profile.map { MedicalProfileDraft(baseVersion: $0.baseVersion, profile: $0) } ?? .empty()
        _draft = State(initialValue: base)
        _years = State(initialValue: Dictionary(
            uniqueKeysWithValues: base.conditions.enumerated().map { (
                $0.offset,
                $0.element.sinceYear.map(String.init) ?? ""
            ) }
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                failure
                allergies
                conditions
                Section("Питомец") {
                    field("blood", "Группа крови", $draft.bloodType)
                    field("chip", "Номер чипа", $draft.chipNumber)
                }
                Section("Клиника") {
                    field("clinic", "Название", $draft.clinicName)
                    field("phone", "Телефон", $draft.clinicPhone)
                    field("vet", "Врач", $draft.vetName)
                }
                Section("Условия") {
                    field("diet", "Чем кормят", $draft.diet)
                    field("living", "Где живёт", $draft.living)
                    field("reproduction", "Роды и течка", $draft.reproduction)
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDone { focus = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(MedicalProfileDraft.problem(draft) != nil)
                }
            }
        }
    }

    /// Ошибка сохранения показывается здесь, а не на экране медкарты: тот
    /// показывает её только когда карта не открылась, и о отказе сервера
    /// человек не узнал бы ничего.
    @ViewBuilder
    private var failure: some View {
        if let text = model.errorText {
            Section {
                Label(text, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private var allergies: some View {
        Section {
            ForEach(draft.allergies.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("На что", text: $draft.allergies[index].substance)
                        .focused($focus, equals: "allergy-\(index)-substance")
                    TextField("Как проявляется", text: $draft.allergies[index].reaction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .focused($focus, equals: "allergy-\(index)-reaction")
                }
            }
            .onDelete { draft.allergies.remove(atOffsets: $0) }
            Button("Добавить аллергию") {
                draft.allergies.append(Allergy(substance: "", reaction: ""))
            }
            Toggle("Аллергий нет", isOn: $draft.allergiesNoneKnown)
        } header: {
            Text("Аллергии")
        } footer: {
            // Отметка «аллергий нет» заменяет список: сервер такую пару
            // отклоняет. Сам список при этом не стирается — он вернётся на
            // место, если человек передумает.
            Text(draft.allergiesNoneKnown
                ? "Список уйдёт пустым, отметка заменит его"
                : "На что и как проявляется")
        }
    }

    private var conditions: some View {
        Section {
            ForEach(draft.conditions.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Название", text: $draft.conditions[index].name)
                        .focused($focus, equals: "condition-\(index)-name")
                    TextField("Чем обостряется", text: note(index))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .focused($focus, equals: "condition-\(index)-note")
                    TextField("С какого года", text: Binding(
                        get: { years[index] ?? "" },
                        set: { value in
                            years[index] = value
                            draft.conditions[index].sinceYear = MedicalCondition.year(from: value)
                        }
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: "condition-\(index)-year")
                }
            }
            .onDelete { removeConditions(at: $0) }
            Button("Добавить заболевание") {
                draft.conditions.append(MedicalCondition(name: "", note: nil, sinceYear: nil))
                years[draft.conditions.count - 1] = ""
            }
        } header: {
            Text("Хронические заболевания")
        } footer: {
            Text("Что болит, с какого года и чем обостряется")
        }
    }

    /// Заметка приходит пустой строкой, а в черновике это `nil`: «не указано»
    /// и «пусто» здесь разные вещи.
    private func note(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft.conditions[index].note ?? "" },
            set: { draft.conditions[index].note = $0.isEmpty ? nil : $0 }
        )
    }

    /// Год живёт и в черновике, и в словаре набранного: удаление строки сдвигает
    /// индексы, и без этого «с какого года» осталось бы от другой болезни.
    private func removeConditions(at offsets: IndexSet) {
        draft.conditions.remove(atOffsets: offsets)
        let keys = offsets.sorted()
        for (offset, key) in keys.enumerated() {
            years.removeValue(forKey: key - offset)
        }
    }

    private func field(_ id: String, _ title: String, _ value: Binding<String?>) -> some View {
        TextField(title, text: Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        ))
        .focused($focus, equals: id)
    }

    private func save() {
        Task {
            if await model.saveProfile(draft) {
                dismiss()
            }
        }
    }
}
