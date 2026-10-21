import Foundation
@testable import Petzy
import Testing
import UIKit
import UniformTypeIdentifiers

/// Что можно приложить к документу. Сервер принимает ровно шесть типов
/// (`ALLOWED_CONTENT_TYPES` в `web/documents.py`), и на всё остальное отвечает
/// 422 уже после загрузки: проверять это на телефоне дешевле.
@Suite("Документы: что приложить")
struct DocumentUploadTests {
    /// Те же шесть, что в вебе: JPEG, PNG, WebP, HEIC, HEIF и PDF.
    @Test("Шесть типов веба принимаются")
    func webTypesAreAccepted() {
        for type in ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "application/pdf"] {
            #expect(UploadFile.isAccepted(type), "сервер принимает \(type)")
        }
    }

    /// GIF и SVG — картинки, но сервер их не берёт, и обещать загрузку нельзя.
    @Test("GIF и SVG не принимаются")
    func otherImagesAreRefused() {
        #expect(UploadFile.isAccepted("image/gif") == false)
        #expect(UploadFile.isAccepted("image/svg+xml") == false)
        #expect(UploadFile.isAccepted("application/octet-stream") == false)
    }

    /// Регистр в заголовке не наш, и `IMAGE/JPEG` не должен внезапно стать
    /// отказом.
    @Test("Регистр типа не важен")
    func typeCaseDoesNotMatter() {
        #expect(UploadFile.isAccepted("IMAGE/JPEG"))
    }

    /// Тип по расширению: без него сервер не разберётся, картинка это или pdf.
    @Test("Расширение даёт тип, который понимает сервер")
    func extensionGivesServerType() {
        let cases: [(String, String)] = [
            ("a.pdf", "application/pdf"),
            ("a.jpg", "image/jpeg"),
            ("a.png", "image/png"),
            ("a.webp", "image/webp"),
            ("a.heic", "image/heic")
        ]
        for (name, expected) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            #expect(UploadFile.contentType(of: url) == expected, "тип для \(name)")
        }
    }

    /// Фото из галереи в разрешённом типе едет как есть: перегонять JPEG в JPEG
    /// незачем.
    @Test("Разрешённое фото не трогаем")
    func acceptedPhotoIsKept() throws {
        let png = try Self.pngData()
        let result = try #require(UploadFile.normalizedImage(png, type: "image/png"))

        #expect(result.contentType == "image/png")
        #expect(result.data == png)
        #expect(result.name == "фото.png")
    }

    /// Библиотека умеет отдать GIF или TIFF, а сервер их не берёт. Отказать
    /// человеку после съёмки хуже, чем перегнать в JPEG.
    @Test("Чужой тип перегоняем в JPEG")
    func otherPhotoBecomesJpeg() throws {
        let result = try #require(UploadFile.normalizedImage(Self.gifData, type: "image/gif"))

        #expect(result.contentType == "image/jpeg")
        #expect(result.name == "фото.jpg")
        // JPEG начинается с FF D8 FF: это не пустая заглушка, а картинка.
        #expect(result.data.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
    }

    /// Битые байты вместо картинки: о такой ошибке человек должен узнать до
    /// запроса, а не после.
    @Test("Битые байты не превращаются в файл")
    func brokenBytesGiveNothing() {
        #expect(UploadFile.normalizedImage(Data("не картинка".utf8), type: "image/gif") == nil)
    }

    /// 1×1 PNG.
    static func pngData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.pngData())
    }

    /// Тот же пиксель, но GIF: тип, который сервер не принимает.
    static let gifData = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") ?? Data()
}
