import SwiftUI

/// История: все записи питомца за всё время, фильтр по типу и график тренда.
/// Отдельный экран от ленты, а не второй такой же: лента это сегодня и
/// вчера, здесь всё сразу и по типам.
struct HistoryView: View {
    let model: AppModel

    @State private var pickingType = false
    @State private var addingType = false
    @State private var form: EventFormTarget?
    @State private var period = 30

    var body: some View {
        List {
            trends
            records
        }
        .listStyle(.plain)
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { filterButton }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingType = true
                } label: {
                    Label("Новая запись", systemImage: "plus")
                }
            }
        }
        // Питомца сменили — история его, а не прежнего.
        // Потянуть вниз — обновить, как в ленте, лекарствах и медкарте.
        .refreshable { await model.loadHistory(type: model.historyType) }
        .task(id: model.selectedPetID) {
            await model.loadHistory(type: model.historyType)
        }
        .sheet(isPresented: $pickingType) {
            NavigationStack {
                HistoryFilterSheet(model: model, onPick: { type in
                    pickingType = false
                    model.selectHistoryType(type)
                })
            }
        }
        .sheet(isPresented: $addingType) {
            NavigationStack {
                EventCatalogView(model: model) { type in
                    addingType = false
                    form = EventFormTarget(draft: model.newDraft(for: type), recordID: nil)
                }
            }
        }
        .sheet(item: $form) { target in
            EventFormView(model: model, draft: target.draft, recordID: target.recordID)
        }
    }

    /// Фильтр одной кнопкой, а не рельсом чипов: типов у питомца бывает
    /// двадцать, а рельс из них не помещается и не показывает, что
    /// прокручивается.
    private var filterButton: some View {
        Button {
            pickingType = true
        } label: {
            HStack(spacing: 4) {
                if let type = model.historyType {
                    Image(systemName: model.icon(for: type))
                }
                Text(model.historyTypeLabel)
                Image(systemName: "chevron.down")
            }
        }
    }

    /// График появляется, только когда выбран конкретный тип: смесь всех типов
    /// на одной оси ничего не значит, а пустой график прямо над пустым
    /// списком это два «ничего нет» подряд.
    @ViewBuilder
    private var trends: some View {
        if model.historyType != nil, !model.statsBuckets.isEmpty {
            Section("Тренды") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Период", selection: $period) {
                        Text("Месяц").tag(30)
                        Text("3 месяца").tag(90)
                        Text("Год").tag(365)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { _, days in
                        guard let type = model.historyType else { return }
                        Task { await model.loadStats(type: type, days: days) }
                    }
                    TrendChart(
                        buckets: model.statsBuckets,
                        byValue: model.statsIsValued,
                        unitLabel: model.statsUnitLabel
                    )
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Словами о том, что график вообще говорит: картинка тренда не читается
    /// как чтение, а «с 28,4 до 29,3, плюс 0,9» читается.
    private var summary: String {
        EventStats.trendSummary(model.statsBuckets, isValued: model.statsIsValued)
    }

    @ViewBuilder
    private var records: some View {
        if let error = model.historyErrorText {
            ContentUnavailableView {
                Label("История не загрузилась", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Повторить") {
                    Task { await model.loadHistory(type: model.historyType) }
                }
            }
        } else if model.isLoadingHistory, model.historyDays.isEmpty {
            ProgressView()
        } else if model.historyDays.isEmpty {
            ContentUnavailableView {
                Label("Записей пока нет", systemImage: "clock.arrow.circlepath")
            } description: {
                Text(model.historyType == nil
                    ? "Кормления, вес, лекарства и прививки появятся здесь, как только вы их добавите"
                    : "Они появятся здесь, как только вы их добавите. Другие записи видны, если выбрать «Все»")
            } actions: {
                Button("Записать событие") { addingType = true }
            }
        } else {
            ForEach(model.historyDays) { day in
                Section(Feed.dayHeader(day.date, today: .now, calendar: .current)) {
                    ForEach(day.events) { event in
                        HistoryRow(event: event, model: model)
                            .onTapGesture { openEditor(event) }
                    }
                }
            }
            if model.hasMoreHistory {
                Button(model.isLoadingHistory ? "Загружаем" : "Загрузить ещё") {
                    Task { await model.loadMoreHistory() }
                }
                .disabled(model.isLoadingHistory)
            }
        }
    }

    private func openEditor(_ event: PetEvent) {
        guard let type = model.typeInfo(for: event.type) else { return }
        form = EventFormTarget(draft: EventDraft(event: event, type: type), recordID: event.id)
    }
}

/// Строка записи в истории. Отдельная от строки ленты только подписью: тот же
/// значок, то же время и те же значения полей.
private struct HistoryRow: View {
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

    private var details: String {
        model.fieldValues(event.fields, of: event.type)
            .map { "\($0.label): \($0.value)" }
            .joined(separator: ", ")
    }
}

/// Выбор типа записи для фильтра. Типов показываются только те, записи о
/// которых у питомца есть: питомцу без температуры «Температура» в фильтре
/// не нужна.
private struct HistoryFilterSheet: View {
    let model: AppModel
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(key: nil, label: "Все", icon: "line.3.horizontal.decrease.circle")
                ForEach(model.historyFilterTypes) { type in
                    row(key: type.key, label: type.label, icon: model.icon(for: type.key))
                }
            }
        }
        .navigationTitle("Фильтр")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }

    private func row(key: String?, label: String, icon: String) -> some View {
        Button {
            onPick(key)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(label)
                Spacer()
                if model.historyType == key {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private extension Double {
    var roundedToRussianTenths: String {
        let rounded = (self * 10).rounded() / 10
        return String(format: "%g", rounded).replacingOccurrences(of: ".", with: ",")
    }
}
