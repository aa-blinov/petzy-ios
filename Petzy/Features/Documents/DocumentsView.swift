import SwiftUI

/// Документы питомца: список с фильтром по категории и сроком. Срок важнее
/// названия: человек ищет «когда закончится страховка», а не «как называется
/// файл».
struct DocumentsView: View {
    let model: DocumentsModel
    let app: AppModel

    @State private var adding = false
    @State private var editing: PetDocument?
    @State private var pendingDelete: PetDocument?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Документы")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: app) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            adding = true
                        } label: {
                            Label("Новый документ", systemImage: "plus")
                        }
                    }
                }
        }
        // Ключ здесь — сама модель, а не выбранный питомец: оболочка
        // пересоздаёт её на каждого питомца и делает это позже смены питомца.
        // По `selectedPetID` задача перезапускалась бы на старой модели, а на
        // экране уже была бы новая и пустая: раздел врал, что данных нет.
        .task(id: app.queueFlushCount) {
            // Раздел перечитывается, когда очередь ушла на сервер. При запуске
            // счётчик ноль, и второй раз читать незачем: раздел и так открыт
            // своим task, а вторая загрузка без сети кончилась бы ошибкой
            // поверх копии.
            guard app.queueFlushCount > 0 else { return }
            await model.load()
        }
        .task(id: ObjectIdentifier(model)) {
            await model.load()
        }
        .sheet(isPresented: $adding) {
            DocumentFormView(model: model, app: app)
        }
        .sheet(item: $editing) { document in
            DocumentFormView(model: model, app: app, document: document)
        }
        .confirmationDialog(
            "Удалить документ?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { document in
            Button("Удалить", role: .destructive) {
                Task { await model.delete(document) }
            }
            // Без роли `.cancel`: в iOS 26 такая кнопка выносится из карточки
            // и в поповере не рисуется, а закрыть диалог становится нечем.
            Button("Отмена") { pendingDelete = nil }
        } message: { _ in
            Text("Файл пропадёт из документов питомца")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.documents.isEmpty {
            ProgressView()
        } else if let text = model.errorText, model.documents.isEmpty {
            // Ошибка важнее пустого списка: пустой список читается как «у
            // питомца нет документов», а на самом деле документы не прочитались.
            ContentUnavailableView {
                Label("Не загрузилось", systemImage: "exclamationmark.triangle")
            } description: {
                Text(text)
            } actions: {
                Button("Повторить") { Task { await model.load() } }
            }
        } else if model.documents.isEmpty {
            ContentUnavailableView {
                Label("Документов нет", systemImage: "doc")
            } description: {
                Text("Прививки, анализы и страховка хранятся здесь файлами")
            } actions: {
                Button("Добавить документ") { adding = true }
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if model.isShowingCached {
                Section {
                    CachedNotice()
                }
            }
            filter
            ForEach(model.visible) { document in
                row(document)
            }
            .onDelete { offsets in
                if let index = offsets.first {
                    pendingDelete = model.visible[safe: index]
                }
            }
            if let file = model.file {
                Section {
                    ShareLink(item: file) {
                        Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.load() }
    }

    /// Фильтр по категориям. Показываются только те, в которых что-то есть:
    /// пустая категория в фильтре это шум.
    private var filter: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(title: "Все", count: model.documents.count, category: nil)
                    ForEach(model.counts, id: \.category) { item in
                        chip(title: item.category.title, count: item.count, category: item.category)
                    }
                }
                .padding(.horizontal, 16)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    private func chip(title: String, count: Int, category: DocumentCategory?) -> some View {
        let chosen = model.filter == category
        return Button {
            model.filter = category
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(chosen ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ document: PetDocument) -> some View {
        // Тап по документу открывает его файл, как в вебе: там тап и свайп
        // ведут в скачивание. Кнопка, а не жест: так строка остаётся кнопкой
        // и для голоса, и для подсказки кнопки.
        Button {
            Task { await model.download(document) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(document.title, systemImage: document.category.symbol)
                        .font(.headline)
                    Spacer()
                }
                Text(MomentText.humanDay(MomentText.day(of: document.createdAt)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let expiry = document.expiryText {
                    Text(expiry)
                        .font(.subheadline)
                        .foregroundStyle(expiry.hasPrefix("Срок истёк") ? .red : .secondary)
                }
                if let linked = document.linkedText {
                    Text(linked).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(document.sizeText).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Удалить", role: .destructive) { pendingDelete = document }
                .tint(.red)
            Button("Изменить") { editing = document }
            Button("Открыть") { Task { await model.download(document) } }
        }
    }
}

private extension Array {
    /// Элемент по индексу, если он есть: свайп присылает индексы, а список
    /// мог поменяться между жестом и обработкой.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
