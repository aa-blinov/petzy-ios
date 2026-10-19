import Foundation

/// Офлайн-часть раздела «Лекарства»: курс, отметка приёма и правка, сделанные
/// без связи, ждут своей очереди. Отдельным файлом, а не в модели: там уже
/// не помещается.
extension MedicationsModel {
    /// Неотправленное раздела: курсы и отметки приёма, сделанные без связи.
    /// Они уйдут на сервер, когда связь появится.
    var pending: [PendingWrite] {
        offline.pendingWrites(kind: .medication, petID: petID)
            + offline.pendingWrites(kind: .intake, petID: petID)
    }

    /// Убирает неотправленное: человек передумал, и запись не должна уйти.
    func removePending(_ write: PendingWrite) {
        offline.removePending(write.localID)
    }

    /// Ставит курс в очередь под своим именем.
    func queueCourse(_ draft: MedicationDraft) {
        let localID = "local-" + UUID().uuidString
        guard let payload = MedicationsAPI.coursePayload(draft, localID: localID) else { return }
        offline.enqueue(PendingWrite(
            localID: localID,
            petID: petID,
            kind: .medication,
            title: draft.name,
            method: "POST",
            path: "/api/medications",
            payload: payload
        ))
    }

    /// Ставит правку курса в очередь. Курс на сервере уже есть, поэтому идёт
    /// запрос на его адрес, но с версией, которую человек видел.
    func queueUpdate(medicationID: String, draft: MedicationDraft) {
        let version = medications.first { $0.id == medicationID }?.updatedAt
        guard let payload = MedicationsAPI.updatePayload(draft, baseVersion: version) else { return }
        offline.enqueue(PendingWrite(
            localID: medicationID,
            petID: petID,
            kind: .medication,
            title: draft.name,
            method: "PUT",
            path: "/api/medications/\(medicationID)",
            payload: payload
        ))
    }

    /// Ставит отметку приёма в очередь под своим именем. Слот при этом остаётся
    /// открытым: сервер закроет его, когда отметка дойдёт.
    func queueIntake(_ mark: IntakeMark, medication: Medication) {
        let localID = "local-" + UUID().uuidString
        guard let payload = MedicationsAPI.intakePayload(mark, localID: localID) else { return }
        offline.enqueue(PendingWrite(
            localID: localID,
            petID: petID,
            kind: .intake,
            title: medication.name,
            method: "POST",
            path: "/api/medications/\(medication.id)/log",
            payload: payload
        ))
    }
}
