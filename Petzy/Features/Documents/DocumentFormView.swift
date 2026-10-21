import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Форма документа: категория, название, срок и сам файл. Файл обязателен
/// при создании: сервер без него отвечает 422, и проверять это на телефоне
/// дешевле, чем ждать ответа. При правке файл можно не трогать, и тогда
/// остаётся прежний.
struct DocumentFormView: View {
    let model: DocumentsModel
    let app: AppModel
    /// Правка существующего документа. `nil` — новый.
    let document: PetDocument?

    @Environment(\.dismiss) private var dismiss

    @State private var category: DocumentCategory
    @State private var title: String
    @State private var note: String
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
    @State private var picked: UploadFile?

    /// Какое поле в фокусе: Return ведёт по полям по порядку.
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title
        case note
    }

    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var isSaving = false
    /// Галерея и камера открываются по отдельности: у камеры своя форма
    /// представления, и в меню она ведёт себя иначе, чем выбор фото.
    @State private var choosingPhoto = false
    @State private var shooting = false

    init(model: DocumentsModel, app: AppModel, document: PetDocument? = nil) {
        self.model = model
        self.app = app
        self.document = document
        _category = State(initialValue: document?.category ?? .vaccination)
        _title = State(initialValue: document?.title ?? "")
        _note = State(initialValue: document?.note ?? "")
        // Как у даты начала у лекарства: выключатель повторяет то, что пришло
        // с сервера, иначе правка без срока сохранила бы сегодняшний.
        _hasExpiry = State(initialValue: document?.expiresAt != nil)
        _expiryDate = State(initialValue: document?.expiresAt.flatMap(MedicalRecordFormView.date) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let text = model.errorText {
                    Section {
                        Label(text, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                files
                Section("Документ") {
                    Picker("Категория", selection: $category) {
                        ForEach(DocumentCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Название", text: $title)
                        .submitLabel(.next)
                        .focused($focus, equals: .title)
                        .onSubmit { focus = .note }
                    TextField("Заметка", text: $note, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .submitLabel(.done)
                        .focused($focus, equals: .note)
                        .onSubmit { focus = nil }
                }
                Section {
                    Toggle("Задать срок", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Действует до", selection: $expiryDate, in: Date.now..., displayedComponents: .date)
                    }
                } header: {
                    Text("Срок")
                } footer: {
                    Text("Страховка и прививки заканчиваются, и о сроке лучше знать заранее")
                }
            }
            .navigationTitle(document == nil ? "Документ" : "Правка документа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: Self.allowedTypes(scans: model.scanStatus?.scansEnabled == true),
                onCompletion: imported
            )
            // Фотографию читаем сразу после выбора: пока она грузится, человек
            // видит, что файл уже выбран, и может назвать документ.
            .onChange(of: photo) { _, item in
                Task { await loadPhoto(item) }
            }
            .task { await model.loadScanStatus() }
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .fullScreenCover(isPresented: $shooting) {
                CameraPicker(onCapture: takePhoto)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Отмена") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Сохранить") { save() }
                .disabled(!canSave)
        }
    }

    /// Выбор файла из «Файлов». Ровно то, что берёт сервер: «любая картинка»
    /// пускала в форму GIF и SVG, а сервер отвечает на них 422 уже после
    /// загрузки.
    private func imported(_ result: Result<URL, Error>) {
        if case let .success(url) = result {
            load(url: url)
        }
    }

    private var files: some View {
        Section("Файл") {
            if let picked {
                fileRow(name: picked.name, action: "Заменить")
            } else if let document {
                fileRow(name: document.title, size: document.sizeText, action: "Заменить")
            }
            // Камера и галерея — одно действие «приложить фотографию»: в меню
            // они рядом, как в системных приложениях.
            Menu {
                if CameraPicker.isAvailable {
                    Button {
                        shooting = true
                    } label: {
                        Label("Снять фото", systemImage: "camera")
                    }
                }
                Button {
                    choosingPhoto = true
                } label: {
                    Label("Выбрать из галереи", systemImage: "photo")
                }
            } label: {
                Label("Приложить фотографию", systemImage: "photo")
            }
            Button {
                importing = true
            } label: {
                Label("Выбрать файл", systemImage: "folder")
            }
            if model.scanStatus?.scansEnabled == true {
                Text("Снимки МРТ и КТ принимаются архивом: ZIP, 7Z, RAR, TAR, GZ, DICOM, ISO")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fileRow(name: String, size: String? = nil, action: String) -> some View {
        HStack {
            Label(name, systemImage: "doc")
                // Две строки, а не одна: на крупном шрифте длинное имя файла
                // обрезалось многоточием, и было не видно, что это за файл.
                .lineLimit(2)
            Spacer()
            if let size {
                Text(size)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action) { importing = true }
                .font(.subheadline)
        }
    }

    private var canSave: Bool {
        // При правке файл не обязателен: не выбран новый — останется прежний.
        let hasFile = picked != nil || document != nil
        return hasFile && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
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
            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            model.errorText = "Файл не прочитался"
        }
    }

    /// Что пустить в «Файлы»: ровно типы сервера, плюс архивы снимков, если
    /// сервер их принимает.
    static func allowedTypes(scans: Bool) -> [UTType] {
        let base: [UTType] = [.pdf, .jpeg, .png, .webP, .heic, .heif]
        guard scans else { return base }
        let archives = ["zip", "7z", "rar", "tar", "gz", "dcm", "iso"].compactMap {
            UTType(filenameExtension: $0)
        }
        return base + archives
    }

    /// Снимок камеры: всегда JPEG, и в форму он приходит тем же файлом, что и
    /// выбранный из галереи.
    private func takePhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            model.errorText = "Фотография не сохранилась"
            return
        }
        picked = UploadFile(name: "фото.jpg", contentType: "image/jpeg", data: data)
        if title.isEmpty {
            title = "Фото документа"
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            // Библиотека умеет отдать GIF или TIFF, а сервер их не берёт:
            // перегоняем в JPEG вместо отказа после выбора.
            guard let ready = UploadFile.normalizedImage(data, type: type) else {
                model.errorText = "Фотография не загрузилась"
                return
            }
            picked = ready
            if title.isEmpty {
                title = "Фото документа"
            }
        } catch {
            model.errorText = "Фотография не загрузилась"
        }
    }

    private func save() {
        isSaving = true
        let draft = DocumentDraft(
            petID: app.selectedPetID ?? "",
            category: category,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.isEmpty ? nil : note,
            expiresAt: hasExpiry ? MedicalRecordFormView.iso(expiryDate) : nil
        )
        Task {
            let saved: Bool
            if let document {
                saved = await model.update(document, draft: draft, file: picked)
            } else {
                guard let picked else {
                    isSaving = false
                    return
                }
                saved = await model.upload(draft, file: picked)
            }
            isSaving = false
            if saved {
                dismiss()
            }
        }
    }
}
