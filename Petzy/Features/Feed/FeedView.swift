import SwiftUI

/// Лента записей выбранного питомца, по дням. Содержимое читается по курсору:
/// запись, написанная другим человеком прямо сейчас, не сдвинет выборку и не
/// потеряется между страницами.
struct FeedView: View {
    let model: AppModel

    @State private var pickingType = false
    @State private var form: EventFormTarget?
    @State private var pendingDelete: PetEvent?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Лента")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: model) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            pickingType = true
                        } label: {
                            Label("Новая запись", systemImage: "plus")
                        }
                    }
                }
        }
        // Питомца сменили — лента должна перечитаться, а не остаться от прежнего.
        // Потянуть ленту вниз — обновить: без этого запись, созданная на
        // другом устройстве, появлялась бы только после перезапуска.
        .refreshable { await model.loadFeed() }
        .task(id: model.selectedPetID) {
            await model.loadFeed()
        }
        .sheet(isPresented: $pickingType) {
            NavigationStack {
                EventCatalogView(model: model) { type in
                    pickingType = false
                    form = EventFormTarget(draft: model.newDraft(for: type), recordID: nil)
                }
            }
        }
        .sheet(item: $form) { target in
            EventFormView(model: model, draft: target.draft, recordID: target.recordID)
        }
        .confirmationDialog(
            "Удалить запись?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { event in
            Button("Удалить", role: .destructive) {
                Task { await model.deleteEvent(id: event.id) }
            }
            Button("Отмена") { pendingDelete = nil }
        } message: { _ in
            Text("Запись пропадёт из дневника")
        }
        .alert("Запись сохранена", isPresented: noticeBinding) {
            Button("Понятно") { model.feedNotice = nil }
        } message: {
            Text(model.feedNotice ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.feedErrorText {
            ContentUnavailableView {
                Label("Лента не загрузилась", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Повторить") { Task { await model.loadFeed() } }
            }
        } else if model.isLoadingFeed, model.days.isEmpty {
            ProgressView()
        } else {
            list
        }
    }

    /// Карточка питомца: фото, имя и кто он. Тап открывает «О питомце», где
    /// всё это и правят. В вебе та же карточка стоит над лентой.
    @ViewBuilder
    private var card: some View {
        if let pet = model.selectedPet {
            NavigationLink {
                PetProfileView(client: model.client, petID: pet.id, app: model)
            } label: {
                PetSummaryCard(pet: pet)
            }
            // Без `.plain` вся строка красится в акцент и читается как ссылка,
            // а не как карточка питомца.
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
        }
    }

    /// Приглашения к чужим питомцам. Стоят над лентой, потому что ответить на
    /// них больше негде, а без ответа питомца у человека нет.
    @ViewBuilder
    private var invites: some View {
        if !model.invites.isEmpty {
            Section {
                ForEach(model.invites) { invite in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Вас пригласили к питомцу «\(invite.petName)»",
                            systemImage: PetSpecies.icon(for: invite.species)
                        )
                        .font(.subheadline.weight(.medium))
                        Text("Владелец: \(invite.owner)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Принять") {
                                Task { await model.acceptInvite(invite) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button("Отклонить") {
                                Task { await model.declineInvite(invite) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Приглашения")
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                card
                invites
                if model.offline.isShowingCached {
                    Section {
                        Label("Нет связи, показаны сохранённые записи", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.offline.pendingCount > 0 {
                    Section {
                        HStack {
                            Label(
                                Words.text(
                                    model.offline.pendingCount,
                                    one: "запись ждёт отправки",
                                    few: "записи ждут отправки",
                                    many: "записей ждут отправки"
                                ),
                                systemImage: "arrow.up.circle"
                            )
                            .font(.subheadline)
                            Spacer()
                            Button("Отправить") {
                                Task { await model.flushQueue() }
                            }
                            .font(.subheadline)
                        }
                    }
                }
                if !model.queueRefusals.isEmpty {
                    Section {
                        ForEach(model.queueRefusals, id: \.self) { text in
                            Label(text, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                        }
                    }
                }
                if model.days.isEmpty {
                    // Пустая лента это тоже про питомца: карточка над этим
                    // текстом остаётся, и видно, чей дневник пуст.
                    ContentUnavailableView("Пока нет записей", systemImage: "list.bullet")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.days) { day in
                        Section(Feed.dayHeader(day.date, today: .now, calendar: .current)) {
                            ForEach(day.events) { event in
                                row(event)
                            }
                        }
                    }
                    if model.hasMoreEvents {
                        // Лента догружается сама, когда человек дошёл до конца,
                        // как в системных приложениях. Кнопка «Загрузить ещё»
                        // тут была лишней, а страница с надгробиями удалённых
                        // записей и вовсе приводила к пустому списку.
                        HStack {
                            if model.isLoadingMore {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .onAppear { Task { await model.loadMore() } }
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: model.feedScrollToTop) { _, _ in
                // Отдельной прокрутки «наверх» у списка нет: верх это начало
                // первого дня.
                if let first = model.days.first {
                    proxy.scrollTo(first.id)
                }
            }
        }
    }

    /// Запись с датой в прошлом в загруженную ленту не попадает, и после
    /// сохранения её не видно. Говорим словами, за какой день она.
    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { model.feedNotice != nil },
            set: {
                if !$0 {
                    model.feedNotice = nil
                }
            }
        )
    }

    private func row(_ event: PetEvent) -> some View {
        // Кнопка, а не жест: строкой без кнопки голос её не откроет, а на
        // iPad и на Mac по ней нельзя перейти клавишей. Как в документах и
        // своих типах записей.
        Button {
            openEditor(event)
        } label: {
            FeedRow(event: event, model: model)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Изменить") { openEditor(event) }
            // Полный свайп выключен: удаление на сервере жёсткое, и одна
            // подтверждённая кнопка лучше случайного жеста.
            // В iOS 26 кнопки свайпа берут цвет из тинта: одной роли
            // `.destructive` недостаточно, «Удалить» вышла бы того же
            // коричневого цвета, что «Изменить». Роль оставлена тоже: по ней
            // доступность читает действие как разрушающее.
            Button("Удалить", role: .destructive) { pendingDelete = event }
                .tint(.red)
        }
    }

    private func openEditor(_ event: PetEvent) {
        guard let type = model.typeInfo(for: event.type) else { return }
        form = EventFormTarget(draft: EventDraft(event: event, type: type), recordID: event.id)
    }
}

/// Одна запись: чем она называется, во сколько и с какими значениями.
private struct FeedRow: View {
    let event: PetEvent
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.icon(for: event.type))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.label(for: event.type))
                        .font(.headline)
                    Spacer()
                    Text(event.time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !event.comment.isEmpty {
                    Text(event.comment)
                        .font(.subheadline)
                }
                if model.offline.pendingIDs.contains(event.id) {
                    // Запись лежит в телефоне и ещё не на сервере. Без этой
                    // подписи человек решил бы, что она пропала.
                    Label("не отправлено", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Значения полей через запятую: точка-разделитель «·» в интерфейсе не
    /// используем, как в веб-приложении.
    private var details: String {
        model.fieldValues(event.fields, of: event.type)
            .map { "\($0.label): \($0.value)" }
            .joined(separator: ", ")
    }
}
