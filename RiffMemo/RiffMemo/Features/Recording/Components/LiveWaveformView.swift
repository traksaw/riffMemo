//
//  LiveWaveformView.swift
//  RiffMemo
//
//  Apple Voice Memos-style live waveform visualization
//

import SwiftUI
import Combine

/// Custom Shape for rendering waveform with smooth animations
struct WaveformShape: Shape {
    /// Array of amplitude samples (0.0 to 1.0)
    var samples: [Float]

    /// Whether currently recording (affects opacity fade)
    var isRecording: Bool

    /// Maximum number of bars to display
    let maxBars: Int = 150

    /// Bar spacing in points
    let barSpacing: CGFloat = 3

    /// Bar width in points
    let barWidth: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let displaySamples = Array(samples.suffix(maxBars))
        let barCount = displaySamples.count

        guard barCount > 0 else { return path }

        // Calculate how many bars actually fit in the view width
        let barTotalWidth = barWidth + barSpacing
        let maxVisibleBars = Int(rect.width / barTotalWidth)

        // Only show the most recent bars that fit
        let visibleSamples = displaySamples.suffix(min(maxVisibleBars, barCount))
        let visibleCount = visibleSamples.count

        let centerY = rect.height / 2
        let totalWidth = CGFloat(visibleCount) * barTotalWidth

        // Right-align the waveform (like Voice Memos)
        let startX = rect.width - totalWidth

        for (index, sample) in visibleSamples.enumerated() {
            let x = startX + CGFloat(index) * barTotalWidth

            // Calculate bar height (minimum 2pt, maximum 80% of view height)
            let normalizedSample = CGFloat(sample)
            let maxHeight = rect.height * 0.8
            let barHeight = max(2, normalizedSample * maxHeight)

            // Draw bar as rounded rectangle
            let barRect = CGRect(
                x: x,
                y: centerY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )

            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: 1, height: 1))
        }

        return path
    }
}

/// Live waveform view matching Apple Voice Memos style
/// Displays thin, evenly-spaced vertical bars that update in real-time
struct LiveWaveformView: View {

    /// Array of amplitude samples (0.0 to 1.0)
    let samples: [Float]

    /// Whether currently recording (affects color)
    let isRecording: Bool

    var body: some View {
        WaveformShape(samples: samples, isRecording: isRecording)
            .fill(waveformColor)
            .animation(.linear(duration: 0.05), value: samples.count)
            .clipped() // Ensure waveform stays within bounds
            .background(Color(.systemBackground))
    }

    private var waveformColor: Color {
        Color(red: 0.3 as Double, green: 0.7 as Double, blue: 1.0 as Double) // Light blue like Voice Memos
    }
}

/// Rolling buffer to store waveform samples for live recording
@MainActor
class WaveformSampleBuffer: ObservableObject {
    @Published var samples: [Float] = []

    private let maxSamples: Int
    private var sampleAccumulator: [Float] = []
    private let samplesPerBar: Int = 5 // Average multiple samples per bar for smoothness

    init(maxSamples: Int = 150) {
        self.maxSamples = maxSamples
    }

    /// Add a new amplitude sample
    func addSample(_ amplitude: Float) {
        sampleAccumulator.append(amplitude)

        // When we have enough samples, average them and add to buffer
        if sampleAccumulator.count >= samplesPerBar {
            let average = sampleAccumulator.reduce(0, +) / Float(sampleAccumulator.count)
            samples.append(average)
            sampleAccumulator.removeAll()

            // Keep only the most recent samples
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
        }
    }

    /// Clear all samples
    func clear() {
        samples.removeAll()
        sampleAccumulator.removeAll()
    }

    /// Get current samples array
    func getSamples() -> [Float] {
        return samples
    }
}

// MARK: - Preview

#Preview("Live Recording") {
    VStack(spacing: 20) {
        Text("Recording...")
            .font(.headline)

        LiveWaveformView(
            samples: generatePreviewSamples(),
            isRecording: true
        )
        .frame(height: 100)
        .padding()

        Text("0:05")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

#Preview("Idle") {
    VStack(spacing: 20) {
        Text("Tap to Record")
            .font(.headline)

        LiveWaveformView(
            samples: [],
            isRecording: false
        )
        .frame(height: 100)
        .padding()

        Text("0:00")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

private func generatePreviewSamples() -> [Float] {
    (0..<150).map { index in
        let position = Float(index) / 150.0
        let wave1 = sin(position * .pi * 8) * 0.4
        let wave2 = sin(position * .pi * 16) * 0.2
        let noise = Float.random(in: 0...0.1)
        return abs(wave1 + wave2) + noise
    }
}
