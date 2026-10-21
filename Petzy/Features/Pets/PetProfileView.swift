import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Экран «О питомце»: фото, имя, вид, порода, дата рождения, пол, кастрация и
/// заметки о здоровье. Той же формой заводится новый питомец, только заголовок
/// и кнопки другие.
struct PetProfileView: View {
    @State private var model: PetProfileModel
    let app: AppModel

    @Environment(\.dismiss) private var dismiss

    @State private var picked: UploadFile?
    @State private var removePhoto = false
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @State private var isSaving = false
    @State private var askingDelete = false

    /// Какое поле в фокусе: Return ведёт по полям по порядку.
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case breed
        case notes
    }

    init(client: APIClient, petID: String?, app: AppModel) {
        self.app = app
        _model = State(initialValue: PetProfileModel(client: client, petID: petID, offline: app.offline))
    }

    var body: some View {
        Form {
            if let text = model.errorText {
                Section {
                    Label(text, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            Section { PetPhotoField(model: model, picked: $picked, removePhoto: $removePhoto) }
            Section("Питомец") {
                // Подпись живёт в `LabeledContent`, а не в плейсхолдере поля:
                // плейсхолдер исчезает, как только человек что-то ввёл, и
                // «Рекс» без слова «Имя» на экране ничего не значит.
                LabeledContent("Имя") { TextField("", text: $model.draft.name) }
                    .accessibilityIdentifier("petName")
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .breed }
                Picker("Вид", selection: $model.draft.species) {
                    Text("Не указан").tag(String?.none)
                    ForEach(model.speciesKinds) { kind in
                        Text(kind.title).tag(String?.some(kind.key))
                    }
                }
                LabeledContent(PetSpecies.breedTitle(for: model.draft.species)) {
                    TextField("", text: $model.draft.breed)
                        .submitLabel(.next)
                        .focused($focus, equals: .breed)
                        .onSubmit { focus = .notes }
                }
            }
            PetHealthSection(hasBirthDate: $hasBirthDate, birthDate: $birthDate, draft: $model.draft)
            Section("Заметки") {
                TextField("Важная информация о здоровье", text: $model.draft.healthNotes, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .submitLabel(.done)
                    .focused($focus, equals: .notes)
                    .onSubmit { focus = nil }
            }
            PetAccessSection(profile: model.profile, isNew: model.isNew, model: model)
            if model.profile?.currentUserIsOwner == true {
                Section {
                    Button("Удалить питомца", role: .destructive) {
                        // Вопрос ждёт превью: `alert` читает свой текст в
                        // момент показа и потом не обновляет его, а «пропадёт
                        // питомец» вместо «264 записи в ленте» обмануло бы.
                        Task {
                            await model.prepareDeletion()
                            askingDelete = true
                        }
                    }
                } footer: {
                    Text("Вместе с питомцем пропадут его записи")
                }
            }
        }
        .navigationTitle(model.isNew ? "Новый питомец" : "О питомце")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(!model.canEdit)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if model.isNew {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }
                    .disabled(!canSave)
            }
        }
        .task {
            // Форму наполняет ответ сервера, и делать это надо один раз: при
            // каждом перерисовывании введённое затиралось бы.
            await model.load()
            syncDateControls()
        }
        .alert("Удалить питомца?", isPresented: $askingDelete) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        } message: {
            // Именно alert, а не confirmationDialog: внутри формы тот
            // открывается поповером и без заметной кнопки отмены, а здесь
            // действие необратимое.
            Text(model.impact?.summary.isEmpty == false
                ? "Вместе с ним пропадут: \(model.impact?.summary ?? "")"
                : "Питомца и его записи будет не вернуть")
        }
        .alert("Записано", isPresented: Binding(get: { model.notice != nil }, set: {
            if !$0 {
                model.notice = nil
            }
        })) {
            // Форма закрывается вместе с окном: питомец уже в телефоне, и
            // второй раз нажать «Сохранить» нельзя.
            Button("Понятно") {
                model.notice = nil
                dismiss()
            }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private var canSave: Bool {
        !isSaving && !model.isQueued && !model.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Сохранение

    /// Ползунок даты показывается только когда дата названа: пустой день
    /// рождения без переключателя выглядел бы как «сегодня родился».
    private func syncDateControls() {
        if let iso = model.profile?.birthDate, let parsed = MomentText.date(from: iso) {
            hasBirthDate = true
            birthDate = parsed
        } else {
            birthDate = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        }
    }

    private func save() {
        isSaving = true
        model.draft.birthDate = hasBirthDate ? birthDate : nil
        let wasNew = model.isNew
        Task {
            let saved = await model.save(photo: picked, removePhoto: removePhoto)
            isSaving = false
            guard saved else { return }
            // Питомец записан в телефон: форму закрывает «Понятно» в окне, а
            // не эта строка: сохранить его второй раз нельзя.
            if model.isQueued {
                return
            }
            // Список питомцев пора перечитать: имя поменялось, а нового
            // питомца в списке ещё нет.
            if let created = model.createdID {
                app.select(petID: created)
            }
            await app.loadPets()
            if wasNew || model.isDeleted {
                dismiss()
            }
        }
    }

    /// Питомца удаляют без отмены на сервере, поэтому после ответа закрываем
    /// экран и перечитываем список: оставшийся выбранным удалённый питомец
    /// оставил бы пустую ленту.
    private func delete() {
        Task {
            await model.delete()
            guard model.isDeleted else { return }
            await app.loadPets()
            dismiss()
        }
    }
}

/// Здоровье питомца: дата рождения, пол и кастрация. Отдельным видом, а не
/// частью формы: та с фотографией и удалением в лимит тела типа не влезает.
private struct PetHealthSection: View {
    @Binding var hasBirthDate: Bool
    @Binding var birthDate: Date
    @Binding var draft: PetDraft

    var body: some View {
        Section {
            Toggle("Дата рождения", isOn: $hasBirthDate)
            if hasBirthDate {
                // Год назад, а не сегодня: сервер даты в будущем не принимает,
                // и годовалый щенок не должен ловить ошибку только потому,
                // что человек открыл форму.
                DatePicker(
                    "Родился",
                    selection: $birthDate,
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }
            Picker("Пол", selection: $draft.gender) {
                ForEach(PetGender.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            // Про кастрацию спрашивают не у всякого: у рыбы её не бывает.
            if PetSpecies.asksAboutNeutering(draft.species) {
                Picker(neuteringTitle, selection: $draft.neutering) {
                    ForEach(Neutering.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } header: {
            Text("Здоровье")
        } footer: {
            Text("Аллергии, хронические состояния и прививки вносятся в медкарте")
        }
    }

    /// «Кастрация» у мальчика и «Стерилизация» у девочки, у остальных — оба.
    private var neuteringTitle: String {
        switch draft.gender {
        case .male: "Кастрация"
        case .female: "Стерилизация"
        case .unknown: "Кастрация или стерилизация"
        }
    }
}
