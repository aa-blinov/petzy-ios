import SwiftUI

/// Выгрузка записей таблицей. Файл уходит в системный лист «Поделиться»: там
/// «Сохранить в файлы», «Отправить себе» и почта врачу, и отдельно своя кнопка
/// «Скачать» не нужна.
struct ExportSheet: View {
    /// Выбор хранится в модели, а не в `@State` вида: пока файл скачивается,
    /// вкладка «Настройки» пересоздаётся целиком, и `@State` на ней
    /// возвращался к «Все» — уже выбранный тип пропадал у человека на глазах.
    @Bindable var model: AppModel

    @Environment(\.dismiss) private var dismiss

    /// Форматы те же, что и в вебе: телефон их ничем не отличает друг от
    /// друга, но получатель файла может оказаться не телефоном.
    private let formats = [
        ("csv", "CSV, открывается в таблицах"),
        ("tsv", "Разделено табуляцией"),
        ("html", "Страница для печати"),
        ("md", "Текст с разметкой")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Записи", selection: $model.exportType) {
                        Text("Все").tag("all")
                        ForEach(model.exportTypeOptions) { type in
                            Text(type.label).tag(type.key)
                        }
                    }
                }
                Section {
                    Picker("Формат", selection: $model.exportFormat) {
                        ForEach(formats, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                }
                if let error = model.exportErrorText {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    if let file = model.exportedFile {
                        ShareLink(item: file) {
                            Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await model.export(type: model.exportType, format: model.exportFormat) }
                        } label: {
                            Label(
                                model.isExporting ? "Готовим файл" : "Подготовить файл",
                                systemImage: "arrow.down.doc"
                            )
                        }
                        .disabled(model.isExporting)
                    }
                } footer: {
                    Text(
                        "Файл придёт на телефон и откроется системным меню: "
                            + "«Сохранить в файлы», «Отправить себе» или почта врачу"
                    )
                }
            }
            .task { await model.loadUsedTypes() }
            .navigationTitle("Экспорт записей")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
