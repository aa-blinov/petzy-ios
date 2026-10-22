import Foundation

/// Версия приложения словами: «1.0.0 (1)». Её называют, когда просят помощи,
/// и по ней сверяют, та ли сборка установлена. Одно место на всё приложение,
/// чтобы формат не разъезжался по экранам.
enum AppVersion {
    /// Сборка без версии не показывается, версия без сборки — показывается:
    /// пустых скобок человеку не нужно. Пустая версия даёт прочерк, а не
    /// подпись без значения.
    static func text(short: String?, build: String?) -> String {
        guard let short, !short.isEmpty else { return "—" }
        guard let build, !build.isEmpty else { return short }
        return "\(short) (\(build))"
    }

    /// То, что записано в бандле приложения.
    static var current: String {
        text(
            short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
