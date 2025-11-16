//
//  WaveformView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

/// High-performance interactive waveform visualization using Canvas API
/// Supports playback position indicator, tap/drag scrubbing, and haptic feedback
struct WaveformView: View {
    let samples: [Float]
    let configuration: WaveformConfiguration

    // Playback state
    var currentProgress: Double = 0 // 0.0 to 1.0
    var onSeek: ((Double) -> Void)? = nil

    // Internal state
    @State private var isDragging = false
    @GestureState private var dragProgress: Double? = nil

    init(
        samples: [Float],
        configuration: WaveformConfiguration = .default,
        currentProgress: Double = 0,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.samples = samples
        self.configuration = configuration
        self.currentProgress = currentProgress
        self.onSeek = onSeek
    }

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let width = size.width
            let height = size.height
            let midY = height / 2

            // Calculate bar width and spacing
            let totalBars = samples.count
            let barWidth = max(1, (width - CGFloat(totalBars - 1) * configuration.barSpacing) / CGFloat(totalBars))

            // Determine effective progress (drag or playback)
            let effectiveProgress = dragProgress ?? currentProgress

            // Draw each sample as a bar
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + configuration.barSpacing)

                // Calculate bar height (sample is normalized 0-1)
                let normalizedHeight = CGFloat(sample) * height * configuration.amplitudeScale

                // Create bar rectangle (centered vertically)
                let barRect = CGRect(
                    x: x,
                    y: midY - normalizedHeight / 2,
                    width: barWidth,
                    height: max(configuration.minBarHeight, normalizedHeight)
                )

                // Determine if this bar is before or after playback position
                let barProgress = Double(index) / Double(max(1, totalBars - 1))
                let isPlayed = barProgress <= effectiveProgress

                // Draw the bar with appropriate color
                var path = Path(roundedRect: barRect, cornerRadius: configuration.cornerRadius)

                let barColor = configuration.style.color(
                    for: sample,
                    at: index,
                    total: totalBars,
                    isPlayed: isPlayed
                )

                context.fill(path, with: .color(barColor))
            }

            // Draw playback position indicator
            if configuration.showPlayhead {
                let playheadX = width * effectiveProgress
                let playheadPath = Path { path in
                    path.move(to: CGPoint(x: playheadX, y: 0))
                    path.addLine(to: CGPoint(x: playheadX, y: height))
                }

                context.stroke(
                    playheadPath,
                    with: .color(configuration.playheadColor),
                    lineWidth: configuration.playheadWidth
                )
            }
        }
        .contentShape(Rectangle()) // Make entire area tappable
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragProgress) { value, state, _ in
                    // Calculate progress from drag location
                    let progress = min(max(value.location.x / value.startLocation.x * currentProgress, 0), 1)
                    state = progress
                }
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        HapticManager.shared.impact(style: .light)
                    }
                }
                .onEnded { value in
                    // Calculate final seek position
                    guard let onSeek = onSeek else { return }

                    // Get the geometry of the gesture
                    let progress = min(max(value.location.x / max(value.startLocation.x * 2, 1), 0), 1)

                    HapticManager.shared.impact(style: .medium)
                    onSeek(progress)
                    isDragging = false
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    HapticManager.shared.impact(style: .light)
                }
        )
    }
}

// MARK: - Waveform Configuration

struct WaveformConfiguration {
    var style: WaveformStyle
    var barSpacing: CGFloat
    var cornerRadius: CGFloat
    var amplitudeScale: CGFloat
    var minBarHeight: CGFloat
    var showPlayhead: Bool
    var playheadColor: Color
    var playheadWidth: CGFloat

    static let `default` = WaveformConfiguration(
        style: .solid(.blue),
        barSpacing: 2,
        cornerRadius: 1,
        amplitudeScale: 0.8,
        minBarHeight: 2,
        showPlayhead: true,
        playheadColor: .white,
        playheadWidth: 2
    )

    static let compact = WaveformConfiguration(
        style: .solid(.blue.opacity(0.6)),
        barSpacing: 1,
        cornerRadius: 0.5,
        amplitudeScale: 0.9,
        minBarHeight: 1,
        showPlayhead: false,
        playheadColor: .white,
        playheadWidth: 1
    )

    static let gradient = WaveformConfiguration(
        style: .gradient(
            low: .blue,
            high: .purple
        ),
        barSpacing: 2,
        cornerRadius: 2,
        amplitudeScale: 0.8,
        minBarHeight: 2,
        showPlayhead: true,
        playheadColor: .white,
        playheadWidth: 2
    )

    static let thumbnail = WaveformConfiguration(
        style: .solid(.blue.opacity(0.7)),
        barSpacing: 0.5,
        cornerRadius: 0.5,
        amplitudeScale: 0.95,
        minBarHeight: 1,
        showPlayhead: false,
        playheadColor: .clear,
        playheadWidth: 0
    )
}

// MARK: - Waveform Style

enum WaveformStyle {
    case solid(Color)
    case gradient(low: Color, high: Color)
    case progressive(Color)

    func color(for sample: Float, at index: Int, total: Int, isPlayed: Bool = false) -> Color {
        let baseColor: Color

        switch self {
        case .solid(let color):
            baseColor = color

        case .gradient(let low, let high):
            // Interpolate between colors based on amplitude
            baseColor = Color(
                red: Double(low.cgColor?.components?[0] ?? 0) * Double(1 - sample) + Double(high.cgColor?.components?[0] ?? 0) * Double(sample),
                green: Double(low.cgColor?.components?[1] ?? 0) * Double(1 - sample) + Double(high.cgColor?.components?[1] ?? 0) * Double(sample),
                blue: Double(low.cgColor?.components?[2] ?? 0) * Double(1 - sample) + Double(high.cgColor?.components?[2] ?? 0) * Double(sample)
            )

        case .progressive(let color):
            // Fade based on position
            let progress = Double(index) / Double(max(1, total - 1))
            baseColor = color.opacity(0.4 + 0.6 * (1 - progress))
        }

        // Dim unplayed portions
        return isPlayed ? baseColor : baseColor.opacity(0.3)
    }
}

// MARK: - Convenience Extensions

extension Color {
    var cgColor: CGColor? {
        #if canImport(UIKit)
        return UIColor(self).cgColor
        #elseif canImport(AppKit)
        return NSColor(self).cgColor
        #endif
    }
}

// MARK: - Preview

#Preview("Default Style") {
    VStack(spacing: 20) {
        Text("Default Waveform")
            .font(.headline)

        WaveformView(
            samples: generateSampleWaveform(sampleCount: 100),
            configuration: .default
        )
        .frame(height: 80)
        .padding()
    }
}

#Preview("Compact Style") {
    VStack(spacing: 20) {
        Text("Compact Waveform")
            .font(.headline)

        WaveformView(
            samples: generateSampleWaveform(sampleCount: 200),
            configuration: .compact
        )
        .frame(height: 60)
        .padding()
    }
}

#Preview("Gradient Style") {
    VStack(spacing: 20) {
        Text("Gradient Waveform")
            .font(.headline)

        WaveformView(
            samples: generateSampleWaveform(sampleCount: 150),
            configuration: .gradient
        )
        .frame(height: 100)
        .padding()
    }
}

// MARK: - Preview Helpers

private func generateSampleWaveform(sampleCount: Int) -> [Float] {
    var samples = [Float]()

    for i in 0..<sampleCount {
        // Create a natural-looking waveform with varying amplitude
        let progress = Float(i) / Float(sampleCount)
        let envelope = sin(progress * .pi) // Rise and fall
        let detail = Float.random(in: 0.3...1.0) // Random variation
        let amplitude = envelope * detail

        samples.append(amplitude)
    }

    return samples
}
