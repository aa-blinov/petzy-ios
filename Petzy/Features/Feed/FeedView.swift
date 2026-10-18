import SwiftUI

/// Лента записей выбранного питомца, по дням. Содержимое читается по курсору:
/// запись, написанная другим человеком прямо сейчас, не сдвинет выборку и не
/// потеряется между страницами.
struct FeedView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Лента")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { PetSwitcher(model: model) }
                }
        }
        // Питомца сменили — лента должна перечитаться, а не остаться от прежнего.
        .task(id: model.selectedPetID) {
            await model.loadFeed()
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
        } else if model.days.isEmpty {
            ContentUnavailableView("Пока нет записей", systemImage: "list.bullet")
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(model.days) { day in
                Section(Feed.dayHeader(day.date, today: .now, calendar: .current)) {
                    ForEach(day.events) { event in
                        FeedRow(event: event, model: model)
                    }
                }
            }
            if model.hasMoreEvents {
                Button(model.isLoadingFeed ? "Загружаем" : "Загрузить ещё") {
                    Task { await model.loadMore() }
                }
                .disabled(model.isLoadingFeed)
            }
        }
        .listStyle(.plain)
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
            }
        }
        .padding(.vertical, 4)
    }

    /// Значения полей через запятую: точка-разделитель «·» в интерфейсе не
    /// используем, как в веб-приложении.
    private var details: String {
        event.fields
            .sorted { $0.key < $1.key }
            .map { "\(model.fieldLabel($0.key, of: event.type)): \($0.value.display)" }
            .joined(separator: ", ")
    }
}
