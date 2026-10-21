import Foundation
@testable import Petzy
import Testing

/// Что на «+» у питомца и в каком порядке. Правила взяты с веба
/// (`utils/tilesConfig.ts`): умолчание — восемь изначальных типов и свои типы
/// семьи, а всё, что добавили в каталог позже, само не появляется.
@Suite("Типы на «+»")
struct TileSettingsTests {
    @Test("Восемь изначальных типов видны по умолчанию")
    func originalTypesAreShown() {
        let settings = TileSettings()
        let originals = ["feeding", "weight", "defecation", "litter", "asthma", "eye_drops", "ear_cleaning",
                         "tooth_brushing"]

        for id in originals {
            #expect(settings.isShown(id), "\(id) виден по умолчанию")
        }
    }

    @Test("Свой тип семьи виден по умолчанию")
    func customTypeIsShown() {
        #expect(TileSettings().isShown("custom_9fae537102"))
    }

    /// Иначе «+» у каждого питомца заполнился бы десятками кнопок, которых
    /// никто не просил.
    @Test("Добавленное позже само не появляется")
    func newTypesStayHidden() {
        #expect(TileSettings().isShown("walk") == false)
        #expect(TileSettings().isShown("training") == false)
    }

    @Test("Сказанное человеком важнее умолчания в обе стороны")
    func explicitChoiceWins() {
        var settings = TileSettings()
        settings.visible["walk"] = true
        settings.visible["feeding"] = false

        #expect(settings.isShown("walk"))
        #expect(settings.isShown("feeding") == false)
    }

    @Test("Порядок: поставленные вперёд, остальные как есть")
    func orderPutsChosenFirst() {
        var settings = TileSettings()
        settings.order = ["weight", "feeding"]

        #expect(settings.ordered(["feeding", "weight", "walk", "litter"]) == [
            "weight", "feeding", "walk", "litter"
        ])
    }

    /// Пустой порядок — не ошибка: питомец, которому ничего не выбирали,
    /// показывает всё в порядке каталога.
    @Test("Без порядка список не меняется")
    func emptyOrderKeepsList() {
        #expect(TileSettings().ordered(["feeding", "walk"]) == ["feeding", "walk"])
    }

    /// Питомец приходит с сервера вместе с настройкой; ключа может не быть, и
    /// тогда это умолчание.
    @Test("Питомец приносит свой набор типов с сервера")
    func petCarriesTileSettings() throws {
        let json = """
        {"_id": "p1", "name": "Рекс",
         "tiles_settings": {"order": ["weight", "feeding"], "visible": {"walk": true}}}
        """
        let pet = try JSONDecoder().decode(Pet.self, from: Data(json.utf8))

        #expect(pet.tiles.order == ["weight", "feeding"])
        #expect(pet.tiles.isShown("walk"))
    }

    @Test("Без настройки у питомца умолчание")
    func missingTilesGiveDefaults() throws {
        let pet = try JSONDecoder().decode(Pet.self, from: Data(#"{"_id": "p1", "name": "Рекс"}"#.utf8))

        #expect(pet.tiles.isShown("feeding"))
        #expect(pet.tiles.isShown("walk") == false)
    }
}
