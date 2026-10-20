@testable import Petzy
import SwiftUI
import Testing

/// Плитки медкарты: на крупном шрифте две в ряд не помещаются, и подпись
/// переносится по буквам. Тогда колонка одна, и названию достаётся вся
/// ширина.
@Suite("Медкарта: плитки разделов")
struct MedicalCardTilesTests {
    @Test("На обычном шрифте плитки в две колонки")
    func twoColumnsAtNormalSize() {
        #expect(MedicalCardView.columns(for: .large).count == 2)
    }

    @Test("На крупном шрифте плитки в одну колонку")
    func oneColumnAtAccessibilitySize() {
        #expect(MedicalCardView.columns(for: .accessibility1).count == 1)
        #expect(MedicalCardView.columns(for: .accessibility5).count == 1)
    }
}
