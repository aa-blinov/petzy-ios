import SwiftUI

/// «К приёму»: что беспокоит и что изменилось. Отметки двухполюсные — «как
/// обычно» или «изменилось», — потому что врачу важно второе, а первое он
/// узнаёт из молчания.
struct VisitPrepFormView: View {
    let model: MedicalCardModel
    let card: MedicalCard?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VisitPrepDraft

    init(model: MedicalCardModel, card: MedicalCard?) {
        self.model = model
        self.card = card
        _draft = State(initialValue: VisitPrepDraft(prep: card?.visitPrep, baseVersion: card?.visitPrep?.baseVersion))
    }

    var body: some View {
        NavigationStack {
            Form {
                failure
                Section {
                    TextField("Что беспокоит", text: $draft.complaint, axis: .vertical)
                        .lineLimit(2 ... 6)
                } header: {
                    Text("Жалоба")
                } footer: {
                    Text("Врач увидит это первой строкой")
                }
                Section {
                    ForEach(VisitChecks.order, id: \.self) { key in
                        Picker(VisitChecks.title(key), selection: pick(key)) {
                            Text("Не отмечено").tag("")
                            Text("Как обычно").tag("normal")
                            Text("Изменилось").tag("changed")
                        }
                    }
                } header: {
                    Text("Что изменилось")
                } footer: {
                    Text("Не отмеченное остаётся как было, а не как «изменилось»")
                }
            }
            .navigationTitle("К приёму")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                }
            }
        }
    }

    /// Ошибка сохранения показывается здесь, а не на экране медкарты: тот
    /// показывает её только когда карта не открылась, и о 409 человек
    /// не узнал бы ничего.
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

    private func pick(_ key: String) -> Binding<String> {
        Binding(
            get: { draft.picks[key] ?? "" },
            set: { draft.picks[key] = $0 }
        )
    }

    private func save() {
        Task {
            let sent = draft.body
            if await model.saveVisitPrep(
                baseVersion: draft.baseVersion,
                complaint: sent.complaint,
                checks: sent.checks
            ) {
                dismiss()
            }
        }
    }
}
