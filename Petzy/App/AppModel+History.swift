import Foundation

/// История записей питомца: всё сразу за всё время, фильтр по типу и график
/// тренда. Отдельный файл от ядра модели по размеру, а не по архитектуре: в
/// одном файле AppModel переставал влезать в лимит линтера.
extension AppModel {
    // MARK: - История

    /// История по дням. Пусто, пока грузится или грузить нечего.
    var historyDays: [EventDay] {
        Feed.group(historyRaw, knownTypes: Set(eventTypes.keys))
    }

    /// Корзины графика для выбранного типа и периода.
    var statsBuckets: [EventStatsBucket] {
        guard let type = statsType else { return [] }
        return EventStats.buckets(
            statsPoints,
            granularity: EventStats.granularity(days: statsPeriodDays),
            averaged: eventTypes[type]?.chart?.kind == "value"
        )
    }

    /// Тип, по которому грузились точки: у него свой вид графика.
    var statsIsValued: Bool {
        statsType.map { eventTypes[$0]?.chart?.kind == "value" } ?? false
    }

    /// Единицы измерения с сервера: «Вес (кг)». У счётного типа, у которого
    /// величины нет, подписью остаётся сам счёт.
    var statsUnitLabel: String {
        guard let statsType else { return "Количество" }
        return eventTypes[statsType]?.chart?.valueLabel ?? "Количество"
    }

    /// Типы для фильтра истории: те, записи о которых есть, и в порядке
    /// справочника. Пустой список, пока справочник не пришёл.
    var historyFilterTypes: [EventTypeInfo] {
        usedTypes.compactMap { eventTypes[$0] }
    }

    /// Подпись выбранного фильтра для кнопки на экране.
    var historyTypeLabel: String {
        guard let historyType else { return "Все" }
        return eventTypes[historyType]?.label ?? historyType
    }

    func loadHistory(type: String?) async {
        guard let petID = selectedPetID else { return }
        historyType = type
        historyRaw = []
        historyCursor = nil
        hasMoreHistory = false
        historyErrorText = nil
        statsPoints = []
        statsType = nil
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let used = try await client.get(
                "/api/events/used-types?pet_id=" + Self.query(petID),
                as: UsedTypesResponse.self
            )
            usedTypes = used.types
            // Справочник нужен и для названий в списке, и для вида графика.
            // Без него запись неизвестного типа молча выпала бы из истории.
            if eventTypes.isEmpty {
                let types = try await client.get("/api/event-types", as: EventTypesResponse.self)
                eventTypes = Self.index(types.eventTypes)
            }
            try await applyHistory(fetchHistoryPage(petID: petID, before: nil), appending: false)
            if let type {
                await loadStats(type: type, days: statsPeriodDays)
            }
        } catch {
            handleHistoryError(error)
        }
    }

    /// Смена фильтра: список и график относятся к разным типам, и старые
    /// точки графика остались бы от предыдущего фильтра.
    func selectHistoryType(_ type: String?) {
        guard type != historyType else { return }
        Task { await loadHistory(type: type) }
    }

    func loadMoreHistory() async {
        guard hasMoreHistory, let cursor = historyCursor, let petID = selectedPetID else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            try await applyHistory(fetchHistoryPage(petID: petID, before: cursor), appending: true)
        } catch {
            handleHistoryError(error)
        }
    }

    /// График по одному типу за период. Список и график грузятся отдельно:
    /// график нужен только когда выбран конкретный тип, а по всем типам сразу
    /// он не значит ничего.
    func loadStats(type: String, days: Int) async {
        guard let petID = selectedPetID else { return }
        statsPeriodDays = days
        statsType = type
        do {
            let stats = try await client.get(
                "/api/stats/health?type=" + Self.query(type) + "&days=\(days)&pet_id=" + Self.query(petID),
                as: EventStatsResponse.self
            )
            statsPoints = stats.data
        } catch {
            handleHistoryError(error)
        }
    }

    private func fetchHistoryPage(petID: String, before: String?) async throws -> EventsPage {
        var path = "/api/history/timeline?page_size=50&pet_id=" + Self.query(petID)
        // «Все» — это отсутствие фильтра, а не отдельный тип.
        if let historyType {
            path += "&type=" + Self.query(historyType)
        }
        if let before {
            path += "&before=" + Self.query(before)
        }
        return try await client.get(path, as: EventsPage.self)
    }

    private func applyHistory(_ page: EventsPage, appending: Bool) {
        historyRaw = appending ? historyRaw + page.items : page.items
        historyCursor = page.nextCursor
        hasMoreHistory = page.nextCursor != nil
    }

    private func handleHistoryError(_ error: Error) {
        let apiError = error as? APIError
        if apiError?.isAuthProblem == true {
            signOut()
            return
        }
        historyErrorText = apiError?.errorDescription ?? error.localizedDescription
    }

    private static func index(_ types: [EventTypeInfo]) -> [String: EventTypeInfo] {
        Dictionary(types.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
