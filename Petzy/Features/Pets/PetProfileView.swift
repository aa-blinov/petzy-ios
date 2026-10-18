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

    @State private var photo: PhotosPickerItem?
    @State private var picked: UploadFile?
    @State private var preview: Data?
    @State private var removePhoto = false
    @State private var importing = false
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now
    @State private var isSaving = false
    @State private var askingDelete = false

    init(client: APIClient, petID: String?, app: AppModel) {
        self.app = app
        _model = State(initialValue: PetProfileModel(client: client, petID: petID))
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
            Section { picture }
            Section("Питомец") {
                // Подпись живёт в `LabeledContent`, а не в плейсхолдере поля:
                // плейсхолдер исчезает, как только человек что-то ввёл, и
                // «Рекс» без слова «Имя» на экране ничего не значит.
                LabeledContent("Имя") { TextField("", text: $model.draft.name) }
                Picker("Вид", selection: $model.draft.species) {
                    Text("Не указан").tag(String?.none)
                    ForEach(model.speciesKinds) { kind in
                        Text(kind.title).tag(String?.some(kind.key))
                    }
                }
                LabeledContent(PetSpecies.breedTitle(for: model.draft.species)) {
                    TextField("", text: $model.draft.breed)
                }
            }
            Section {
                Toggle("Дата рождения", isOn: $hasBirthDate)
                if hasBirthDate {
                    // Год назад, а не сегодня: сервер даты в будущем не
                    // принимает, и годовалый щенок не должен ловить ошибку
                    // только потому, что человек открыл форму.
                    DatePicker(
                        "Родился",
                        selection: $birthDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
                Picker("Пол", selection: $model.draft.gender) {
                    ForEach(PetGender.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                // Про кастрацию спрашивают не у всякого: у рыбы её не бывает.
                if PetSpecies.asksAboutNeutering(model.draft.species) {
                    Picker(neuteringTitle, selection: $model.draft.neutering) {
                        ForEach(Neutering.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Здоровье")
            } footer: {
                Text("Аллергии, хронические состояния и прививки вносятся в медкарте")
            }
            Section("Заметки") {
                TextField("Важная информация о здоровье", text: $model.draft.healthNotes, axis: .vertical)
                    .lineLimit(2 ... 5)
            }
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
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                load(url: url)
            }
        }
        .onChange(of: photo) { _, item in
            Task { await loadPhoto(item) }
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
    }

    private var canSave: Bool {
        !isSaving && !model.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// «Кастрация» у мальчика и «Стерилизация» у девочки, у остальных — оба.
    private var neuteringTitle: String {
        switch model.draft.gender {
        case .male: "Кастрация"
        case .female: "Стерилизация"
        case .unknown: "Кастрация или стерилизация"
        }
    }

    // MARK: - Фото

    /// Фото питомца. Показывается подписанная ссылка: она открыта без входа и
    /// живёт 1–2 часа, а токен в заголовок обычная загрузка картинок не
    /// подставит и показала бы пустое место.
    private var picture: some View {
        HStack(spacing: 16) {
            photoView
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 8) {
                if picked == nil {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(serverPhoto ? "Заменить фото" : "Выбрать фото", systemImage: "photo")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Выбрать файл", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }
                if picked != nil || removePhoto || serverPhoto {
                    // Пока выбрано новое фото, кнопка отменяет именно выбор;
                    // когда на сервере лежит своё, она помечает фото на
                    // удаление и тем же нажатием отменяет пометку.
                    Button(picked != nil || !removePhoto ? "Убрать фото" : "Оставить фото", role: .destructive) {
                        if picked != nil {
                            picked = nil
                            preview = nil
                            photo = nil
                            removePhoto = false
                        } else {
                            removePhoto.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    /// Фото, лежащее на сервере: его показывает подписанная ссылка, пока
    /// человек не выбрал своё.
    private var serverPhoto: Bool {
        model.profile?.photoURL != nil
    }

    @ViewBuilder
    private var photoView: some View {
        if let preview, let image = UIImage(data: preview) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let url = model.profile?.photoURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
        } else {
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(20)
                .foregroundStyle(.secondary)
        }
    }

    /// Файл из «Файлов»: он лежит в песочнице приложения, и пока не сказано
    /// системе, что он нужен, до него не добраться.
    private func load(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            picked = UploadFile(
                name: url.lastPathComponent,
                contentType: UploadFile.contentType(of: url),
                data: data
            )
            preview = data
            removePhoto = false
        } catch {
            model.errorText = "Файл не прочитался"
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            picked = UploadFile(name: "фото.jpg", contentType: type, data: data)
            preview = data
            removePhoto = false
        } catch {
            model.errorText = "Фотография не загрузилась"
        }
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
            // Список питомцев пора перечитать: имя поменялось, а нового
            // питомца в списке ещё нет.
            if let created = model.createdID {
                app.select(petID: created)
            }
            if wasNew || model.isDeleted {
                await app.loadPets()
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
