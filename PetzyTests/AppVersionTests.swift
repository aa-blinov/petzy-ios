@testable import Petzy
import Testing

/// Версию человек называет, когда просит помощи, и её же сверяют с тем, что
/// установлено. Строка одна на всё приложение, чтобы формат не разъезжался.
@Suite("Версия приложения")
struct AppVersionTests {
    @Test("Версия со сборкой")
    func versionAndBuild() {
        #expect(AppVersion.text(short: "1.0.0", build: "1") == "1.0.0 (1)")
    }

    /// Сборки может не быть: пустые скобки человеку не нужны.
    @Test("Версия без сборки")
    func versionOnly() {
        #expect(AppVersion.text(short: "1.0.0", build: nil) == "1.0.0")
        #expect(AppVersion.text(short: "1.0.0", build: "") == "1.0.0")
    }

    /// Пустая версия не должна превращаться в пустую строку: на её месте
    /// человек увидел бы загадочное «Версия» без значения.
    @Test("Без версии остаётся прочерк")
    func noVersion() {
        #expect(AppVersion.text(short: nil, build: "1") == "—")
        #expect(AppVersion.text(short: "", build: "1") == "—")
    }
}
