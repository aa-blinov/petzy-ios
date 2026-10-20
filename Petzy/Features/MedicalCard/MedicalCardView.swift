import SwiftUI

/// Медкарта выбранного питомца как документ: читается сверху вниз, в том
/// порядке, в каком спрашивает врач. Плиток больше нет — на вебе карту
/// переписали в документ (коммит `19d9657`), и приложение идёт следом, но
/// по-русски и по-нативному.
struct MedicalCardView: View {
    let model: MedicalCardModel
    let app: AppModel
    /// Переключить вкладку: лекарства и документы живут на своих вкладках.
    var showMedications: () -> Void = {}
    var showDocuments: () -> Void = {}

    @State private var form: MedicalFormTarget?
    @State private var weightForm: EventFormTarget?
    @State private var profile = false
    @State private var prep = false
    @State private var sharing = false
    /// Какой раздел открыт. Переход идёт по пути, а не ссылкой: ссылка внутри
    /// строки списка отдавала переход самой строке, и тап по строке открывал
    /// чужой раздел, а «назад» вёл к следующему разделу вместо медкарты.
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
            MedicalCardDocumentView(card: card, actions: actions)
            MedicalCardBlocks(card: card, actions: actions)
            MedicalCardRecords(card: card, actions: actions)
        }
        .listStyle(.plain)
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom) { handover(card) }
    }

    /// Кнопки документа. Документ сам никуда не ведёт: он знает, что
    /// нажали, а ведёт его экран.
    private var actions: MedicalCardActions {
        MedicalCardActions(
            newRecord: { form = .new(app: app, kind: $0) },
            openSection: { path.append($0) },
            openProfile: { profile = true },
            openVisitPrep: { prep = true },
            readinessStep: readinessStep,
            showMedications: showMedications,
            showDocuments: showDocuments,
            editRecord: { form = .edit(app: app, record: $0) }
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

    /// PDF и ссылка для врача: то, ради чего карту и ведут. Показываются, когда
    /// заполнено хотя бы два пункта из пяти: на пустой карте отдавать нечего,
    /// и об этом сказано словами внизу.
    private func handover(_ card: MedicalCard) -> some View {
        VStack(spacing: 0) {
            Divider()
            if card.readinessDone >= 2 {
                HStack(spacing: 8) {
                    pdfButton
                    if card.canEdit {
                        Button {
                            sharing = true
                        } label: {
                            Label("Ссылка для врача", systemImage: "link")
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                Text("Карта почти пуста. Заполните её, и появятся PDF и ссылка для врача")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    /// Кнопка PDF. Когда файл готов, она превращается в системное меню
    /// «Поделиться»: открывать файл руками не нужно.
    @ViewBuilder
    private var pdfButton: some View {
        if let file = model.pdfFile {
            ShareLink(item: file) {
                Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task { await model.downloadPDF() }
            } label: {
                Label(model.isPreparingPDF ? "Готовим файл" : "Скачать PDF", systemImage: "arrow.down.doc")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingPDF)
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

    var app: AppModel {
        switch self {
        case let .new(app, _), let .edit(app, _): app
        }
    }
}
