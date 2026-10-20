import Foundation

/// Настоящий ответ сервера на `/api/pets/<id>/medical-card`, снят с живого
/// стенда и урезан по количеству записей. Фикстуры, написанные руками,
/// обманывают: в них `conditions` оказывались строками, а сервер присылает
/// объектами, и медкарта падала на живых данных при зелёных тестах.
///
/// Строка лежит на уровне файла, а не внутри типа: тело типа не должно расти
/// на четыреста строк из-за данных.
private let medicalCardJSON = #"""
{
"card": {
  "can_edit": true,
  "documents": [
  {
    "added": "2026-10-03",
    "category": "lab_result",
    "id": "6ac0b451c775325d197b871a",
    "title": "Анализ крови"
  }
  ],
  "generated_at": "2026-10-20",
  "medications": [
  {
    "comment": null,
    "dose_text": "1 таб",
    "ended_on": null,
    "given": 9,
    "id": "6ac0b451c775325d197b86d2",
    "name": "Дронтал Плюс",
    "prescribed_by": "Каримов Д.",
    "purpose": "Профилактика глистов",
    "schedule_text": "По сб в 10:00",
    "skipped": 0,
    "started_on": "2026-08-08",
    "status": "active",
    "strength": null,
    "type": "Таблетка"
  },
  {
    "comment": "Не чаще раза в сутки, с едой",
    "dose_text": "2,5 мл",
    "ended_on": null,
    "given": 8,
    "id": "6ac0b451c775325d197b872c",
    "name": "Мелоксидил",
    "prescribed_by": "Каримов Д.",
    "purpose": "Обезболивающее при хромоте",
    "schedule_text": "По необходимости",
    "skipped": 0,
    "started_on": "2026-09-20",
    "status": "active",
    "strength": "1,5 мг/мл",
    "type": "Суспензия"
  }
  ],
  "overdue_records": [
  {
    "_id": "6ac0b451c775325d197b8727",
    "batch": null,
    "clinic": null,
    "complaint": null,
    "date": "2026-07-12",
    "days_left": -13,
    "diagnosis": null,
    "documents": [],
    "kind": "parasite",
    "next_due": "2026-10-07",
    "note": null,
    "pet_id": "6ac0b44fc775325d197b84df",
    "protects": null,
    "protects_label": null,
    "recommendations": null,
    "status": "overdue",
    "superseded": false,
    "target": "fleas_ticks",
    "title": "Бравекто",
    "vet": null
  }
  ],
  "past_courses": [
  {
    "comment": null,
    "dose_text": "2 таб",
    "ended_on": "2026-08-14",
    "given": 59,
    "id": "6ac0b451c775325d197b8730",
    "name": "Глюкозамин",
    "prescribed_by": "Каримов Д.",
    "purpose": "Поддержка суставов",
    "schedule_text": "Ежедневно в 09:00",
    "skipped": 2,
    "started_on": "2026-06-15",
    "status": "ended",
    "strength": "500 мг",
    "type": "Таблетка"
  }
  ],
  "past_courses_total": 1,
  "pet": {
  "age_text": "5 лет",
  "birth_date": "2021-08-01",
  "breed": "Лабрадор",
  "gender": "Мальчик",
  "health_notes": null,
  "name": "Рекс",
  "neutered_text": null,
  "species": "Собака"
  },
  "profile": {
  "allergies": [
    {
    "reaction": "зуд, покраснение ушей",
    "substance": "Курица"
    },
    {
    "reaction": "сыпь",
    "substance": "Амоксициллин"
    }
  ],
  "allergies_none_known": false,
  "base_version": null,
  "blood_type": "DEA 1.1+",
  "chip_number": "643094100200311",
  "clinic": {
    "name": "Ортовет",
    "phone": "+7 727 555 03 04",
    "vet": "Каримов Д."
  },
  "clinics": [
    {
    "doctors": [
      {
      "name": "Каримов Д.",
      "specialty": null
      }
    ],
    "name": "Ортовет",
    "phone": "+7 727 555 03 04"
    }
  ],
  "conditions": [
    {
    "name": "Дисплазия тазобедренных суставов",
    "note": "обострения после нагрузки",
    "since_year": 2023
    },
    {
    "name": "Хронический гастрит",
    "note": null,
    "since_year": 2024
    }
  ],
  "diet": "Сухой корм для крупных пород, два раза в день",
  "living": "Квартира, гуляет два раза в день",
  "reproduction": null,
  "updated_at": "2026-10-18T17:51:10Z",
  "version": "bcf7921cf6f841fba0cef50dd6ef7d9b"
  },
  "record_counts": {
  "parasite": 2,
  "procedure": 1,
  "vaccination": 3,
  "visit": 2
  },
  "records": {
  "parasite": [
    {
    "_id": "6ac0b451c775325d197b8728",
    "batch": null,
    "clinic": null,
    "complaint": null,
    "date": "2026-09-08",
    "days_left": 48,
    "diagnosis": null,
    "documents": [],
    "kind": "parasite",
    "next_due": "2026-12-07",
    "note": null,
    "pet_id": "6ac0b44fc775325d197b84df",
    "protects": null,
    "protects_label": null,
    "recommendations": null,
    "status": "ok",
    "superseded": false,
    "target": "worms",
    "title": "Дронтал Плюс",
    "vet": null
    }
  ],
  "procedure": [
    {
    "_id": "6ac0b451c775325d197b872b",
    "batch": null,
    "clinic": "Ортовет",
    "complaint": null,
    "date": "2024-02-26",
    "days_left": null,
    "diagnosis": null,
    "documents": [],
    "kind": "procedure",
    "next_due": null,
    "note": null,
    "pet_id": "6ac0b44fc775325d197b84df",
    "protects": null,
    "protects_label": null,
    "recommendations": null,
    "status": "none",
    "superseded": false,
    "target": null,
    "title": "Чипирование",
    "vet": null
    }
  ],
  "vaccination": [
    {
    "_id": "6ac0b451c775325d197b8726",
    "batch": null,
    "clinic": "Ортовет",
    "complaint": null,
    "date": "2026-07-30",
    "days_left": 283,
    "diagnosis": null,
    "documents": [],
    "kind": "vaccination",
    "next_due": "2027-07-30",
    "note": null,
    "pet_id": "6ac0b44fc775325d197b84df",
    "protects": "kennel",
    "protects_label": "Питомниковый кашель",
    "recommendations": null,
    "status": "ok",
    "superseded": false,
    "target": null,
    "title": "Нобивак KC",
    "vet": "Каримов Д."
    }
  ],
  "visit": [
    {
    "_id": "6ac0b451c775325d197b8729",
    "batch": null,
    "clinic": "Ортовет",
    "complaint": "Чаще пьёт воду",
    "date": "2026-09-23",
    "days_left": null,
    "diagnosis": "Без патологии",
    "documents": [
      {
      "id": "6ac0b451c775325d197b871a",
      "title": "Анализ крови"
      }
    ],
    "kind": "visit",
    "next_due": null,
    "note": null,
    "pet_id": "6ac0b44fc775325d197b84df",
    "protects": null,
    "protects_label": null,
    "recommendations": "Повторить анализы через три месяца",
    "status": "none",
    "superseded": false,
    "target": null,
    "title": "Плановый осмотр",
    "vet": "Каримов Д."
    }
  ]
  },
  "vaccinations": [
  {
    "days_left": 26,
    "expires_at": "2026-11-15",
    "id": "6ad7b5f9dd50593074769727",
    "note": "Год validity до 15.11.2026",
    "status": "valid",
    "title": "Сертификат прививки от бешенства"
  }
  ],
  "visit_prep": null,
  "weight": {
  "latest": {
    "date": "2026-10-04",
    "value": 29.3
  },
  "series": [
    {
    "date": "2026-08-08",
    "value": 28.4
    },
    {
    "date": "2026-08-22",
    "value": 28.6
    },
    {
    "date": "2026-09-05",
    "value": 28.8
    },
    {
    "date": "2026-09-19",
    "value": 29.0
    },
    {
    "date": "2026-10-03",
    "value": 29.1
    },
    {
    "date": "2026-10-03",
    "value": 29.3
    },
    {
    "date": "2026-10-04",
    "value": 29.3
    }
  ]
  }
}
}
"""#

enum LiveFixtures {
    static var medicalCard: [String: Any] {
        json(medicalCardJSON)
    }
}

/// JSON-строка в объект. Разбор здесь падает так же, как на экране: ошибку
/// видно в тесте, а не у человека в медкарте.
func json(_ text: String) -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}
