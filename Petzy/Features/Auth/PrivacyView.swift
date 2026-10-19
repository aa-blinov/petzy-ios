import SwiftUI

/// Политика обработки данных и согласие с ней. Текст условий приходит с
/// сервера вместе с редакцией: правила могут поменяться, и приложение не должно
/// показывать свой собственный устаревший текст.
struct PrivacyView: View {
    let model: AuthFlowModel
    /// `false` на экране согласия: без кнопки человек ничего не согласит.
    let showsAgree: Bool
    let onAgreed: () -> Void

    var body: some View {
        Form {
            if let text = model.errorText {
                Section {
                    Label(text, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text(
                    """
                    Petzy хранит записи о питомцах, их лекарства и файлы. \
                    Данные нужны, чтобы вести дневник и показать врачу.
                    """
                )
                .font(.subheadline)
                ForEach(model.policy?.facts ?? [], id: \.self) { fact in
                    Text(fact).font(.subheadline)
                }
                if let version = model.policy?.version {
                    Text("Редакция от \(MomentText.russianDay(MomentText.day(of: version)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Обработка персональных данных")
            }
            if showsAgree {
                Section {
                    Button("Согласен и продолжить") {
                        Task {
                            if await model.acceptPolicy() {
                                onAgreed()
                            }
                        }
                    }
                    .disabled(model.policy == nil)
                }
            }
        }
        .navigationTitle("Политика")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.policy == nil {
                await model.loadPolicy()
            }
        }
    }
}

/// Справка: короткие ответы на вопросы, которые правда возникают. Текст написан
/// под этот интерфейс, а не перенесён из веба: там кнопки и жесты другие.
struct HelpView: View {
    var body: some View {
        List {
            Section {
                ForEach(Self.entries) { entry in
                    DisclosureGroup(entry.title) {
                        Text(entry.body).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Как это работает")
            }
        }
        .navigationTitle("Справка")
        .navigationBarTitleDisplayMode(.inline)
    }

    struct Entry: Identifiable {
        let id: String
        let title: String
        let body: String
    }

    static let entries: [Entry] = [
        Entry(
            id: "add",
            title: "Как добавить запись",
            body: """
            Нажмите «+» на вкладке «Лента» и выберите, что записать. \
            Дата и время подставятся текущие, их можно поменять.
            """
        ),
        Entry(
            id: "edit",
            title: "Как исправить или удалить запись",
            body: """
            Свайп по записи открывает «Изменить» и «Удалить». \
            Тап по записи открывает её форму.
            """
        ),
        Entry(
            id: "dose",
            title: "Как отметить приём лекарства",
            body: """
            На вкладке «Лекарства» нажмите «Дали сейчас». \
            Отдельная кнопка «Пропустить приём» записывает в ленту, что приёма \
            не было, и не тратит остаток.
            """
        ),
        Entry(
            id: "medical",
            title: "Что такое медкарта",
            body: """
            Это то, что ветеринар видит первым: прививки, обработки, анализы \
            и лекарства по срокам. Оттуда же готовится PDF для врача.
            """
        ),
        Entry(
            id: "documents",
            title: "Где хранятся документы",
            body: """
            На вкладке «Документы»: прививки, анализы, заключения, снимки \
            и страховка файлами. Истёкший срок видно сразу, он же горит \
            на значке вкладки.
            """
        ),
        Entry(
            id: "pet",
            title: "Как поменять данные питомца",
            body: """
            «Настройки», «О питомце». Там же снимается или ставится фото \
            и удаляется питомец вместе со всеми его записями.
            """
        ),
        Entry(
            id: "account",
            title: "Как сменить почту или пароль",
            body: """
            «Настройки», «Аккаунт». Почта нужна для восстановления пароля: \
            если её нет, восстановить пароль будет нечем.
            """
        ),
        Entry(
            id: "password",
            title: "Я забыл пароль",
            body: """
            На экране входа есть «Забыли пароль». Сервер отвечает одинаково, \
            есть такой аккаунт или нет, и письмо придёт только на \
            подтверждённую почту.
            """
        ),
        Entry(
            id: "share",
            title: "Как показать врачу",
            body: """
            «Медкарта», «Для врача»: готовая ссылка на одну минуту либо PDF. \
            Ссылка действует час, её можно отозвать.
            """
        ),
        Entry(
            id: "devices",
            title: "Выйти с этого телефона",
            body: """
            «Настройки», «Выйти». Другие устройства останутся в системе: \
            выход сюда не выкидывает человека с планшета.
            """
        )
    ]
}
