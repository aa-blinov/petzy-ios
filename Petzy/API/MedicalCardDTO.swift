import Foundation

// MARK: - Разобранный ответ

/// Ответ `/api/pets/<id>/medical-card`. Ключи ответа живут в этом файле, а
/// наружу выходят доменные типы: экран про JSON не знает.
struct CardResponse: Decodable {
    let card: CardDTO
}

struct RecordsResponse: Decodable {
    let records: [RecordDTO]
}

struct CardDTO: Decodable {
    let pet: CardPetDTO
    let records: [String: [RecordDTO]]
    let recordCounts: [String: Int]
    let overdueRecords: [RecordDTO]
    let weight: WeightDTO?
    let medications: [CardMedicationDTO]
    let documents: [CardDocumentDTO]
    let pastCourses: [CardCourseDTO]
    let profile: ProfileDTO?
    let visitPrep: VisitPrepDTO?
    let generatedAt: String
    let canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case pet, records, medications, documents, profile
        case recordCounts = "record_counts"
        case overdueRecords = "overdue_records"
        case weight
        case pastCourses = "past_courses"
        case visitPrep = "visit_prep"
        case generatedAt = "generated_at"
        case canEdit = "can_edit"
    }
}

struct CardPetDTO: Decodable {
    let name: String
    let breed: String?
    let species: String?
    let ageText: String?
    let neuteredText: String?

    enum CodingKeys: String, CodingKey {
        case name, breed, species
        case ageText = "age_text"
        case neuteredText = "neutered_text"
    }
}

struct RecordDTO: Decodable {
    let id: String
    let kind: String?
    let title: String
    let date: String
    let nextDue: String?
    let status: String?
    let daysLeft: Int?
    let clinic: String?
    let vet: String?
    let note: String?
    let target: String?
    let protects: String?
    let batch: String?
    let complaint: String?
    let diagnosis: String?
    let recommendations: String?
    let documents: [CardDocumentDTO]
    /// Версия записи: когда её меняли в последний раз. Её приложение
    /// отправляет при правке, и сервер отвечает отказом, если запись поменяли
    /// с тех пор.
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind, title, date
        case nextDue = "next_due"
        case status
        case daysLeft = "days_left"
        case clinic, vet, note, target, protects, batch
        case complaint, diagnosis, recommendations, documents
        case updatedAt = "updated_at"
    }
}

struct WeightDTO: Decodable {
    let latest: PointDTO?
}

struct PointDTO: Decodable {
    let date: String
    let value: Double
}

struct CardMedicationDTO: Decodable {
    let id: String
    let name: String
    let doseText: String?
    let purpose: String?

    enum CodingKeys: String, CodingKey {
        case id, name, purpose
        case doseText = "dose_text"
    }
}

struct CardDocumentDTO: Decodable {
    let id: String
    let title: String
}

struct CardCourseDTO: Decodable {
    let id: String
    let name: String
}

struct ProfileDTO: Decodable {
    /// Версия профиля: её приложение возвращает как `base_version` при правке.
    let version: String?
    let allergies: [AllergyDTO]?
    let allergiesNoneKnown: Bool?
    let bloodType: String?
    let chipNumber: String?
    let clinic: ClinicDTO?
    let clinics: [ClinicEntryDTO]?
    let conditions: [ConditionDTO]?
    let diet: String?
    let living: String?
    let reproduction: String?

    enum CodingKeys: String, CodingKey {
        case allergies, clinic, clinics, conditions, diet, living, reproduction, version
        case allergiesNoneKnown = "allergies_none_known"
        case bloodType = "blood_type"
        case chipNumber = "chip_number"
    }
}

struct ClinicEntryDTO: Decodable {
    let name: String?
    let phone: String?
    let doctors: [DoctorDTO]?
}

struct DoctorDTO: Decodable {
    let name: String?
    let specialty: String?
}

struct ConditionDTO: Decodable {
    let name: String
    let note: String?
    let sinceYear: Int?

    enum CodingKeys: String, CodingKey {
        case name, note
        case sinceYear = "since_year"
    }
}

struct AllergyDTO: Decodable {
    let substance: String?
    let reaction: String?
}

struct ClinicDTO: Decodable {
    let name: String?
    let phone: String?
    let vet: String?
}

struct VisitPrepDTO: Decodable {
    let version: String?
    let complaint: String?
    let checks: [String: String]?
}

// MARK: - Разбор в домен

extension CardDTO {
    var domain: MedicalCard {
        var records: [MedicalKind: [MedicalRecord]] = [:]
        for kind in MedicalKind.allCases {
            // Вид может прийти ключом словаря или полем в самой записи: у
            // просроченных вид задан явно, у лежащих в разделе — ключом.
            records[kind] = (self.records[kind.rawValue] ?? []).map { $0.domain(fallback: kind) }
        }
        // Счётчики приходят ключами-строками, а плитки ходят по видам: без
        // переноса плитка всегда показывала бы ноль.
        var counts: [MedicalKind: Int] = [:]
        for kind in MedicalKind.allCases {
            counts[kind] = recordCounts[kind.rawValue] ?? 0
        }
        return MedicalCard(
            pet: CardPet(
                name: pet.name,
                breed: pet.breed ?? "",
                species: pet.species ?? "",
                ageText: pet.ageText ?? "",
                neuteredText: pet.neuteredText ?? ""
            ),
            records: records,
            counts: counts,
            overdueCount: overdueRecords.count,
            weight: weight?.latest.map { WeightPoint(date: $0.date, value: $0.value) },
            medications: medications.map { CardMedication(
                id: $0.id,
                name: $0.name,
                doseText: $0.doseText,
                purpose: $0.purpose
            ) },
            documents: documents.map { CardDocument(id: $0.id, title: $0.title) },
            pastCourses: pastCourses.map { CardCourse(id: $0.id, name: $0.name) },
            profile: profile?.domain,
            visitPrep: visitPrep.map {
                VisitPrep(
                    baseVersion: $0.version,
                    complaint: $0.complaint,
                    checks: ($0.checks ?? [:]).sorted { $0.key < $1.key }.map { VisitCheck(
                        id: $0.key,
                        title: $0.key,
                        value: $0.value
                    ) }
                )
            },
            generatedAt: generatedAt,
            canEdit: canEdit
        )
    }
}

extension RecordDTO {
    /// Запись без ключа раздела: в просроченных вид задан полем `kind`.
    func domain(fallback: MedicalKind) -> MedicalRecord {
        MedicalRecord(
            id: id,
            kind: kind.flatMap(MedicalKind.init(rawValue:)) ?? fallback,
            title: title,
            date: date,
            nextDue: nextDue,
            status: status.flatMap(MedicalStatus.init(rawValue:)) ?? .none,
            daysLeft: daysLeft,
            clinic: clinic,
            vet: vet,
            note: note,
            batch: batch,
            target: target,
            protects: protects,
            complaint: complaint,
            diagnosis: diagnosis,
            recommendations: recommendations,
            documentIDs: documents.map(\.id),
            updatedAt: updatedAt
        )
    }
}

extension ProfileDTO {
    /// Клиники в том виде, в котором их держит сервер. У старых записей, где
    /// есть только зеркало `clinic`, берётся она: список строится из неё сам,
    /// иначе профиль выглядел бы пустым.
    private static func domainClinics(_ clinics: [ClinicEntryDTO], mirror: ClinicDTO?) -> [ProfileClinic] {
        guard clinics.isEmpty else {
            return clinics.map { entry in
                ProfileClinic(
                    name: entry.name,
                    phone: entry.phone,
                    doctors: (entry.doctors ?? []).map { ProfileDoctor(name: $0.name, specialty: $0.specialty) }
                )
            }
        }
        guard let mirror, let name = mirror.name, !name.isEmpty else { return [] }
        return [ProfileClinic(
            name: name,
            phone: mirror.phone,
            doctors: mirror.vet.map { [ProfileDoctor(name: $0, specialty: nil)] } ?? []
        )]
    }

    var domain: MedicalProfile {
        MedicalProfile(
            baseVersion: version,
            allergies: (allergies ?? []).compactMap {
                guard let substance = $0.substance, !substance.isEmpty else { return nil }
                return Allergy(substance: substance, reaction: $0.reaction ?? "")
            },
            allergiesNoneKnown: allergiesNoneKnown ?? false,
            bloodType: bloodType,
            chipNumber: chipNumber,
            clinicName: clinic?.name,
            clinicPhone: clinic?.phone,
            vetName: clinic?.vet,
            clinics: Self.domainClinics(clinics ?? [], mirror: clinic),
            conditions: (conditions ?? [])
                .map { MedicalCondition(name: $0.name, note: $0.note, sinceYear: $0.sinceYear) },
            diet: diet,
            living: living,
            reproduction: reproduction
        )
    }
}
