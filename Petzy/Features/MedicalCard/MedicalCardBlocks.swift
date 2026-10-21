import SwiftUI

/// Куда ведут кнопки медкарты. Отдельная структура, а не замыкания по месту:
/// документ сам ничего не знает ни про формы, ни про разделы.
struct MedicalCardActions {
    /// Новая запись своего вида.
    var newRecord: (MedicalKind) -> Void
    /// Профиль для врача.
    var openProfile: () -> Void
    /// «К приёму».
    var openVisitPrep: () -> Void
    /// Пункт готовности: что человек должен заполнить.
    var readinessStep: (MedicalReadiness) -> Void
    /// Правка записи: тап по строке в документе открывает её, как на вебе.
    var editRecord: (MedicalRecord) -> Void
    /// Записать вес: это запись в дневнике, а не в медкарте, и форма у неё
    /// общая с лентой.
    var recordWeight: () -> Void
}

/// Блоки медкарты о самом питомце: данные для врача, приём, лекарства и вес.
/// Записи по видам — в следующем файле.
struct MedicalCardBlocks: View {
    let card: MedicalCard
    let actions: MedicalCardActions

    var body: some View {
        vetData
        visitPrep
        medications
        weight
    }

    // MARK: - Данные для врача

    /// Всё, что врач спрашивает о питомце, в одном месте: аллергии, хронические
    /// состояния, группа крови, чип, клиники и условия жизни. На вебе это три
    /// отдельных блока, но на телефоне один список читается быстрее, и правка
    /// одна, а не три.
    private var vetData: some View {
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
            if let blood = card.profile?.bloodType, !blood.isEmpty {
                LabeledContent("Группа крови", value: blood)
            }
            if let chip = card.profile?.chipNumber, !chip.isEmpty {
                // Номер чипа копируется по нажатию: его диктуют по телефону.
                Button {
                    UIPasteboard.general.string = chip
                } label: {
                    HStack {
                        Label("Чип", systemImage: "doc.on.doc")
                        Spacer()
                        Text(chip)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Скопировать номер чипа")
            }
            ForEach(card.clinics, id: \.name) { clinic in
                VStack(alignment: .leading, spacing: 2) {
                    if let name = clinic.name, !name.isEmpty {
                        Text(name).font(.subheadline.weight(.medium))
                    }
                    if let phone = clinic.phone, !phone.isEmpty {
                        phoneLink(phone)
                    }
                    ForEach(Array(clinic.doctors.enumerated()), id: \.offset) { _, doctor in
                        Text(doctorLine(doctor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(card.life, id: \.title) { row in
                LabeledContent(row.title, value: row.value)
            }
            Button("Изменить", action: actions.openProfile)
                .font(.subheadline)
                .foregroundStyle(.tint)
        } header: {
            Text("Данные для врача")
        }
    }

    /// Телефон открывается как звонок: его диктуют по телефону, и искать его
    /// вручную незачем.
    private func phoneLink(_ phone: String) -> some View {
        let number = phone.filter(\.isNumber)
        return Link(destination: URL(string: "tel://\(number)") ?? URL(string: "tel:")!) {
            Label(phone, systemImage: "phone")
                .font(.subheadline)
        }
    }

    /// «Каримов Д.» или «Каримов Д., кардиолог».
    private func doctorLine(_ doctor: ProfileDoctor) -> String {
        let name = doctor.name ?? ""
        let specialty = doctor.specialty ?? ""
        return specialty.isEmpty ? name : "\(name), \(specialty)"
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
            Button("Изменить", action: actions.openVisitPrep)
                .font(.subheadline)
                .foregroundStyle(.tint)
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
            Button("Записать вес", action: actions.recordWeight)
                .font(.subheadline)
                .foregroundStyle(.tint)
        } header: {
            Text("Вес")
        }
    }
}
