import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Форма нового документа: категория, название, срок и сам файл. Файл
/// обязателен: сервер без него отвечает 422, и проверять это на телефоне
/// дешевле, чем ждать ответа.
struct DocumentFormView: View {
    let model: DocumentsModel
    let app: AppModel

    @Environment(\.dismiss) private var dismiss

    @State private var category: DocumentCategory = .vaccination
    @State private var title = ""
    @State private var note = ""
    @State private var expiresAt = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date.now
    @State private var picked: UploadFile?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var isSaving = false

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
                Section("Файл") {
                    fileRow
                }
                Section("Документ") {
                    Picker("Категория", selection: $category) {
                        ForEach(DocumentCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Название", text: $title)
                    TextField("Заметка", text: $note, axis: .vertical)
                        .lineLimit(1 ... 4)
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
            .navigationTitle("Документ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(!canSave)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                if case let .success(url) = result {
                    load(url: url)
                }
            }
            // Фотографию читаем сразу после выбора: пока она грузится, человек
            // видит, что файл уже выбран, и может назвать документ.
            .onChange(of: photo) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var canSave: Bool {
        picked != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    @ViewBuilder
    private var fileRow: some View {
        if let picked {
            HStack {
                Label(picked.name, systemImage: "doc")
                    .lineLimit(1)
                Spacer()
                Button("Заменить") { importing = true }
                    .font(.subheadline)
            }
        } else {
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Выбрать фотографию", systemImage: "photo")
            }
            Button {
                importing = true
            } label: {
                Label("Выбрать файл", systemImage: "folder")
            }
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
            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
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
            if title.isEmpty {
                title = "Фото документа"
            }
        } catch {
            model.errorText = "Фотография не загрузилась"
        }
    }

    private func save() {
        guard let picked else { return }
        isSaving = true
        let draft = DocumentDraft(
            petID: app.selectedPetID ?? "",
            category: category,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.isEmpty ? nil : note,
            expiresAt: hasExpiry ? MedicalRecordFormView.iso(expiryDate) : nil
        )
        Task {
            let saved = await model.upload(draft, file: picked)
            isSaving = false
            if saved {
                dismiss()
            }
        }
    }
}
