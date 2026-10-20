import SwiftUI

/// Куда ведут кнопки медкарты. Отдельная структура, а не замыкания по месту:
/// документ сам ничего не знает ни про формы, ни про разделы.
struct MedicalCardActions {
    /// Новая запись своего вида.
    var newRecord: (MedicalKind) -> Void
    /// Раздел со всеми записями вида.
    var openSection: (MedicalKind) -> Void
    /// Профиль для врача.
    var openProfile: () -> Void
    /// «К приёму».
    var openVisitPrep: () -> Void
    /// Пункт готовности: что человек должен заполнить.
    var readinessStep: (MedicalReadiness) -> Void
    /// Экран лекарств.
    var showMedications: () -> Void
    /// Экран документов.
    var showDocuments: () -> Void
    /// Правка записи: тап по строке в документе открывает её, как на вебе.
    var editRecord: (MedicalRecord) -> Void
}

/// Блоки медкарты в порядке, в каком спрашивает врач: здоровье, приём,
/// лекарства, вес, прививки, визиты, документы, клиника, условия.
struct MedicalCardBlocks: View {
    let card: MedicalCard
    let actions: MedicalCardActions

    /// Сколько записей блок показывает, прежде чем предложить пойти в раздел.
    static let shown = 4

    var body: some View {
        health
        visitPrep
        medications
        weight
    }

    // MARK: - Здоровье и аллергии

    private var health: some View {
        Section {
            if card.profile?.allergies.isEmpty == false {
                ForEach(card.profile?.allergies ?? [], id: \.substance) { allergy in
                    LabeledContent(allergy.substance, value: allergy.reaction ?? "")
                        .foregroundStyle(.secondary, .primary)
                }
            } else if card.profile?.allergiesNoneKnown == true {
                Text("Аллергий нет").foregroundStyle(.secondary)
            } else {
                Text("Аллергии не указаны").foregroundStyle(.secondary)
            }
            ForEach(card.profile?.conditions ?? []) { condition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(condition.name).font(.subheadline)
                    if !condition.subtitle.isEmpty {
                        Text(condition.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            door("Изменить", action: actions.openProfile)
        } header: {
            Text("Здоровье и аллергии")
        }
    }

    // MARK: - К приёму

    private var visitPrep: some View {
        Section {
            if let prep = card.visitPrep {
                if let complaint = prep.complaint, !complaint.isEmpty {
                    Text(complaint).font(.subheadline)
                }
                // Сначала что изменилось, потом «как обычно»: в этом порядке
                // врач это читает.
                let values = Dictionary(uniqueKeysWithValues: prep.checks.map { ($0.id, $0.value) })
                let changed = VisitChecks.changed(values)
                if !changed.isEmpty {
                    Label("Изменилось: \(changed.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                let normal = VisitChecks.normal(values)
                if !normal.isEmpty {
                    Label("Как обычно: \(normal.joined(separator: ", "))", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Что беспокоит и что изменилось: врач увидит это первой строкой")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            door("Изменить", action: actions.openVisitPrep)
        } header: {
            Text("К приёму")
        }
    }

    // MARK: - Лекарства

    private var medications: some View {
        Section {
            if card.medications.isEmpty {
                Text("Курсов нет").foregroundStyle(.secondary)
            } else {
                ForEach(card.medications) { course in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.weight(.medium))
                        let parts = [course.doseText, course.scheduleText].compactMap(\.self).filter { !$0.isEmpty }
                        if !parts.isEmpty {
                            Text(parts.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let purpose = course.purpose, !purpose.isEmpty {
                            Text(purpose).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !card.pastCourses.isEmpty {
                ForEach(card.pastCourses) { course in
                    LabeledContent(course.name, value: "закончен")
                        .font(.caption)
                        .foregroundStyle(.secondary, .primary)
                }
                if card.pastCoursesTotal > card.pastCourses.count {
                    Text("и ещё \(card.pastCoursesTotal - card.pastCourses.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            door("Все лекарства", action: actions.showMedications)
        } header: {
            Text("Лекарства")
        }
    }

    // MARK: - Вес

    private var weight: some View {
        Section {
            if card.weightSeries.isEmpty {
                Text("Вес не записан").foregroundStyle(.secondary)
            } else {
                if let last = card.weightSeries.last {
                    Text("\(Amount.text(last.value)) кг (\(MedicalCardDates.russian(last.date)))")
                        .font(.title3.weight(.semibold))
                }
                if let delta = MedicalCardWeight.delta(card.weightSeries) {
                    Text(delta).font(.subheadline).foregroundStyle(.secondary)
                }
                if card.weightSeries.count > 1 {
                    MedicalWeightLine(series: card.weightSeries)
                        .padding(.vertical, 4)
                }
                if let summary = MedicalCardWeight.summary(card.weightSeries) {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                if let byYear = MedicalCardWeight.byYear(card.weightSeries) {
                    Text("По годам: \(byYear)").font(.caption).foregroundStyle(.secondary)
                }
            }
            door("Записать вес", action: { actions.newRecord(.vaccination) })
        } header: {
            Text("Вес")
        }
    }

    /// Тихая дверь внизу блока: «Изменить», «Все лекарства». Она не спорит с
    /// содержимым блока, а просто ведёт дальше.
    private func door(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
    }
}
