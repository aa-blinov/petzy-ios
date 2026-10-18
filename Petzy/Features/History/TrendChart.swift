import Charts
import SwiftUI

/// График тренда по одному типу записи. Типов с величиной много — вес,
/// температура, длина, — и их рисуют линией со средним, а счётные типы без
/// величины, вроде прививок, столбиками: усреднять количество нельзя.
struct TrendChart: View {
    let buckets: [EventStatsBucket]
    /// `true` — линия по величине, `false` — столбики по счёту.
    let byValue: Bool
    /// Единицы измерения из описания типа: «Вес (кг)». Без них на оси были бы
    /// голые числа, и 29,3 не сказало бы, килограммы это или градусы.
    let unitLabel: String

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                if byValue {
                    AreaMark(
                        x: .value("Период", bucket.label),
                        y: .value(unitLabel, bucket.value)
                    )
                    .foregroundStyle(.tint.opacity(0.18))
                    LineMark(
                        x: .value("Период", bucket.label),
                        y: .value(unitLabel, bucket.value)
                    )
                    .foregroundStyle(.tint)
                    .lineStyle(.init(lineWidth: 2))
                } else {
                    BarMark(
                        x: .value("Период", bucket.label),
                        y: .value(unitLabel, bucket.value)
                    )
                    .foregroundStyle(.tint)
                }
            }
        }
        // Шкала по самим значениям, а не от нуля: иначе колебание веса в
        // треть килограмма рисуется прямой линией у самого верха. У счётного
        // типа, наоборот, ноль нужен: столбики считают от нуля по определению.
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(centered: true, anchor: .top)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel(centered: true, anchor: .bottom) {
                    if let number = value.as(Double.self) {
                        Text(number.roundedToTenths)
                    }
                }
            }
        }
        // Подписи осей по умолчанию выходят за границы графика, а график
        // обрезан по своей рамке: без центрирования верхняя подпись резалась.
        .frame(height: 210)
        .clipShape(Rectangle())
        .accessibilityLabel("График: \(unitLabel)")
    }

    private var yDomain: ClosedRange<Double> {
        let values = buckets.map(\.value)
        if byValue, let scale = EventStats.valueScale(values) {
            return scale.lower ... scale.upper
        }
        return 0 ... max(values.max() ?? 1, 1)
    }
}

private extension Double {
    /// На оси числа не должны выглядеть как 29.300000000000001. Цифры
    /// округляются, потому что ось читают глазами, а не калькулятором.
    var roundedToTenths: String {
        let rounded = (self * 10).rounded() / 10
        return String(rounded).replacingOccurrences(of: ".", with: ",")
    }
}
