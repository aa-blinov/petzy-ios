import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Фото питомца в форме: выбрать, снять файлом или убрать. Отдельная вьюха,
/// потому что «О питомце» и без неё длинный, а правило тут одно: пока фото не
/// выбрано, видно то, что лежит на сервере.
struct PetPhotoField: View {
    let model: PetProfileModel
    /// Выбранный файл: его отправляет сохранение формы.
    @Binding var picked: UploadFile?
    /// Фото помечено на удаление.
    @Binding var removePhoto: Bool

    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    /// Байты выбранного фото: показываются сразу, не дожидаясь ответа сервера.
    @State private var preview: Data?

    var body: some View {
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
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                load(url: url)
            }
        }
        .onChange(of: photo) { _, item in
            Task { await loadPhoto(item) }
        }
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
}
