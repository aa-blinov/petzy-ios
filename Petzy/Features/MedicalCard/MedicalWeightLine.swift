import Charts
import SwiftUI

/// Линия веса: как менялся вес питомца. Это подсказка «растёт или худеет»,
/// а не график для чтения, поэтому осей нет, линия растянута на ширину, а
/// точка последнего замера — своя.
struct MedicalWeightLine: View {
    /// Ряд замеров, от старого к новому.
    let series: [WeightPoint]

    var body: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { index, point in
                LineMark(
                    x: .value("Замер", index),
                    y: .value("Вес", point.value)
                )
                .foregroundStyle(.tint)
                .lineStyle(.init(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            if let last = series.last {
                PointMark(
                    x: .value("Замер", series.count - 1),
                    y: .value("Вес", last.value)
                )
                .foregroundStyle(.tint)
                .symbolSize(60)
            }
        }
        // Шкала по самим значениям, а не от нуля: иначе колебание веса в
        // треть килограмма рисуется прямой у самого верха.
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(.clear)
                .border(.clear)
        }
        .frame(height: 64)
        .accessibilityLabel("Линия веса: \(series.count) замеров")
    }

    /// Область значений с запасом сверху и снизу, иначе линия липнет к краям.
    private var yDomain: ClosedRange<Double> {
        let values = series.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0 ... 1 }
        let margin = max((high - low) * 0.2, 0.1)
        return (low - margin) ... (high + margin)
    }
}
