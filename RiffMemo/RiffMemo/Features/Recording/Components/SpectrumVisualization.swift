//
//  SpectrumVisualization.swift
//  RiffMemo
//
//  Frequency spectrum visualization with colored bars
//

import SwiftUI

struct SpectrumVisualization: View {
    let frequencyMagnitudes: [Float]
    let colorForBand: (Int) -> BandColor

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: barSpacing(for: geometry.size.width)) {
                ForEach(Array(frequencyMagnitudes.enumerated()), id: \.offset) { index, magnitude in
                    SpectrumBar(
                        magnitude: CGFloat(magnitude),
                        maxHeight: geometry.size.height,
                        color: colorForFrequency(colorForBand(index))
                    )
                }
            }
        }
    }

    private func barSpacing(for width: CGFloat) -> CGFloat {
        let barCount = CGFloat(frequencyMagnitudes.count)
        let totalSpacing = width * 0.15
        return totalSpacing / max(1, barCount - 1)
    }

    private func colorForFrequency(_ band: BandColor) -> Color {
        switch band {
        case .bass: return .red
        case .lowMid: return .orange
        case .mid: return .yellow
        case .highMid: return .green
        case .high: return .blue
        }
    }
}

struct SpectrumBar: View {
    let magnitude: CGFloat
    let maxHeight: CGFloat
    let color: Color
    private let minHeight: CGFloat = 2

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.8),
                        color,
                        color.opacity(0.6)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(height: max(minHeight, magnitude * maxHeight))
            .shadow(color: color.opacity(0.5), radius: 3)
            .animation(.easeOut(duration: 0.08), value: magnitude)
    }
}
