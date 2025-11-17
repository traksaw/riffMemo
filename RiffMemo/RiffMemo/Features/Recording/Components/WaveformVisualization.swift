//
//  WaveformVisualization.swift
//  RiffMemo
//
//  Waveform bars visualization
//

import SwiftUI

struct WaveformVisualization: View {
    let amplitudes: [Float]
    let isRecording: Bool

    init(amplitudes: [Float] = [], isRecording: Bool = false) {
        self.amplitudes = amplitudes.isEmpty ? Self.generateIdleWaveform() : amplitudes
        self.isRecording = isRecording
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: barSpacing(for: geometry.size.width)) {
                ForEach(Array(amplitudes.enumerated()), id: \.offset) { index, amplitude in
                    WaveBar(
                        amplitude: CGFloat(amplitude),
                        maxHeight: geometry.size.height,
                        color: isRecording ? .red : .blue
                    )
                    .animation(.easeInOut(duration: 0.15), value: amplitude)
                }
            }
        }
    }

    private func barSpacing(for width: CGFloat) -> CGFloat {
        let barCount = CGFloat(amplitudes.count)
        let totalSpacing = width * 0.1
        return totalSpacing / max(1, barCount - 1)
    }

    static func generateIdleWaveform(sampleCount: Int = 100) -> [Float] {
        (0..<sampleCount).map { index in
            let position = Float(index) / Float(sampleCount)
            let wave1 = sin(position * .pi * 4) * 0.3
            let wave2 = sin(position * .pi * 8) * 0.15
            return abs(wave1 + wave2)
        }
    }
}

struct WaveBar: View {
    let amplitude: CGFloat
    let maxHeight: CGFloat
    let color: Color
    private let minHeight: CGFloat = 2

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.6)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(height: max(minHeight, amplitude * maxHeight * 0.8))
            .shadow(color: color.opacity(0.3), radius: 2)
    }
}
