import QuickLook
import SwiftUI

/// Медкарта выбранного питомца как документ: читается сверху вниз, в том
/// порядке, в каком спрашивает врач. Плиток больше нет — на вебе карту
/// переписали в документ (коммит `19d9657`), и приложение идёт следом, но
/// по-русски и по-нативному.
struct MedicalCardView: View {
    let model: MedicalCardModel
    let app: AppModel
    // Переключить вкладку: лекарства и документы живут на своих вкладках.

    @State private var form: MedicalFormTarget?
    @State private var weightForm: EventFormTarget?
    @State private var profile = false
    @State private var prep = false
    @State private var sharing = false
    // periphery:ignore
    /// Какой раздел открыт. Переход идёт по пути, а не ссылкой: ссылка внутри
    /// строки списка отдавала переход самой строке, и тап по строке открывал
    /// чужой раздел, а «назад» вёл к следующему разделу вместо медкарты.
    /// Метка выше: замер мёртвого кода не видит путь сквозь `@State`.
    @State private var path: [MedicalKind] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Медкарта")
                .navigationDestination(for: MedicalKind.self) { kind in
                    MedicalKindSectionView(
                        model: model,
                        app: app,
                        kind: kind,
                        onEdit: { form = .edit(app: app, record: $0) },
                        onAdd: { form = .new(app: app, kind: kind) }
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: app) }
                    ToolbarItem(placement: .topBarTrailing) { newRecordMenu }
                    ToolbarItem(placement: .topBarTrailing) { handOver }
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
        .sheet(item: $form) { target in
            MedicalRecordFormView(app: app, model: model, target: target)
        }
        .sheet(item: $weightForm) { target in
            EventFormView(model: app, draft: target.draft, recordID: target.recordID)
        }
        .sheet(isPresented: $profile) {
            MedicalProfileFormView(model: model, card: model.card)
        }
        .sheet(isPresented: $prep) {
            VisitPrepFormView(model: model, card: model.card)
        }
        .sheet(isPresented: $sharing) {
            MedicalShareSheet(model: model)
        }
        .alert("Медкарта не открылась", isPresented: Binding(
            get: { model.errorText != nil && model.card == nil },
            set: {
                if !$0 {
                    model.errorText = nil
                }
            }
        )) {
            Button("Повторить") {
                model.errorText = nil
                Task { await model.load() }
            }
            Button("Отмена") { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
        .alert("Готово", isPresented: Binding(get: { model.notice != nil }, set: {
            if !$0 {
                model.notice = nil
            }
        })) {
            Button("Понятно") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.card == nil {
            ProgressView()
        } else if let card = model.card {
            list(card)
        } else {
            // Как в ленте и истории: неудача выглядит как неудача, а не как
            // значок раздела, в котором она случилась.
            ContentUnavailableView("Медкарта не открылась", systemImage: "exclamationmark.triangle")
        }
    }

    private func list(_ card: MedicalCard) -> some View {
        List {
            if model.isShowingCached {
                Section {
                    CachedNotice()
                }
            }
            if !model.pending.isEmpty {
                Section {
                    ForEach(model.pending) { write in
                        PendingRow(write: write) { model.removePending(write) }
                    }
                } header: {
                    Text("Не отправлено")
                }
            }
            MedicalCardDocumentView(card: card, pet: app.selectedPet, app: app, actions: actions)
            MedicalCardBlocks(card: card, actions: actions)
            MedicalCardRecords(card: card, actions: actions)
        }
        // Плоский список, как в ленте, истории и документах: медкарта — это
        // список записей, и разбивать её на карточки как веб-страницу незачем.
        .listStyle(.plain)
        .refreshable { await model.load() }
        // Документ из медкарты открывается тем же системным просмотрщиком, что
        // и на своей вкладке: у него есть «Поделиться» и печать.
        .quickLookPreview(documentPreview)
    }

    /// Кнопки документа. Документ сам никуда не ведёт: он знает, что
    /// нажали, а ведёт его экран.
    private var actions: MedicalCardActions {
        MedicalCardActions(
            newRecord: { form = .new(app: app, kind: $0) },
            openProfile: { profile = true },
            openVisitPrep: { prep = true },
            readinessStep: readinessStep,
            editRecord: { form = .edit(app: app, record: $0) },
            recordWeight: recordWeight,
            openDocument: openDocument
        )
    }

    /// Пункт готовности ведёт туда, где его и заполняют: аллергии и клиника —
    /// в профиль для врача, прививка и обработка — в запись, вес — в дневник.
    private func readinessStep(_ step: MedicalReadiness) {
        switch step {
        case .allergies, .clinic:
            profile = true
        case .vaccination:
            form = .new(app: app, kind: .vaccination)
        case .parasite:
            form = .new(app: app, kind: .parasite)
        case .weight:
            recordWeight()
        }
    }

    /// Вес — это запись в дневнике, а не в медкарте, и форма у неё общая с
    /// лентой. Без записи о весе врач не посчитает дозу.
    private func recordWeight() {
        guard let type = app.typeInfo(for: "weight") else { return }
        weightForm = EventFormTarget(draft: app.newDraft(for: type), recordID: nil)
    }

    /// «+» в панели: вид записи выбирается, потому что записи четыре и
    /// «прививка» по умолчанию была бы догадкой.
    private var newRecordMenu: some View {
        Menu {
            ForEach(MedicalKind.allCases, id: \.rawValue) { kind in
                Button(kind.title) { form = .new(app: app, kind: kind) }
            }
        } label: {
            Label("Новая запись", systemImage: "plus")
        }
        .disabled(model.card?.canEdit != true)
    }

    /// Что показать в просмотрщике документов медкарты.
    private var documentPreview: Binding<URL?> {
        Binding(
            get: { model.documentFile },
            set: { model.documentFile = $0 }
        )
    }

    /// Документ открывается файлом: сначала скачивается, потом показывается.
    private func openDocument(_ document: CardDocument) {
        Task { await model.openDocument(id: document.id, title: document.title, serverName: nil) }
    }

    /// Передать карту врачу: файлом или ссылкой. Отдельной полосы внизу нет:
    /// на телефоне документ передают кнопкой «Поделиться», а полоса из двух
    /// кнопок под последним блоком — это веб, на телефоне она закрывает
    /// половину экрана и ничего не добавляет.
    @ViewBuilder
    private var handOver: some View {
        if model.isPreparingPDF {
            ProgressView()
        } else {
            Menu {
                if let file = model.pdfFile {
                    ShareLink(item: file) {
                        Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        Task { await model.downloadPDF() }
                    } label: {
                        Label("Скачать PDF", systemImage: "arrow.down.doc")
                    }
                }
                // Ссылку может выдать только владелец: она открывает карту
                // тому, кому адрес дали.
                if model.card?.canEdit == true {
                    Button {
                        sharing = true
                    } label: {
                        Label("Ссылка для врача", systemImage: "link")
                    }
                }
            } label: {
                Label("Передать врачу", systemImage: "square.and.arrow.up")
            }
            // Пока карта пуста, передавать нечем: об этом сказано в блоке
            // готовности, а не отказом в нажатии.
            .disabled((model.card?.readinessDone ?? 0) < 2)
        }
    }
}

/// Что открыть в форме записи: новую или существующую.
enum MedicalFormTarget: Identifiable {
    case new(app: AppModel, kind: MedicalKind)
    case edit(app: AppModel, record: MedicalRecord)

    var id: String {
        switch self {
        case let .new(_, kind):
            // Вид входит в имя: форма открыта и её вид поменяли, лист должен
            // показать новую, а не прежнюю.
            "new-\(kind.rawValue)"
        case let .edit(_, record):
            record.id
        }
    }
}
