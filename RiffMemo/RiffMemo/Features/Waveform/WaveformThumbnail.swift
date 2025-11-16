//
//  WaveformThumbnail.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

/// Compact waveform thumbnail optimized for list views
/// Automatically loads and caches waveform data
struct WaveformThumbnail: View {
    let recording: Recording
    let height: CGFloat

    @State private var samples: [Float] = []
    @State private var isLoading = false

    init(recording: Recording, height: CGFloat = 40) {
        self.recording = recording
        self.height = height
    }

    var body: some View {
        Group {
            if isLoading {
                // Loading skeleton
                WaveformSkeleton()
                    .frame(height: height)
            } else if !samples.isEmpty {
                // Actual waveform
                WaveformView(
                    samples: samples,
                    configuration: .thumbnail
                )
                .frame(height: height)
            } else {
                // Placeholder
                WaveformPlaceholder(compact: true)
                    .frame(height: height)
            }
        }
        .task {
            await loadWaveform()
        }
    }

    private func loadWaveform() async {
        // Check cache first
        if let cachedData = recording.waveformData {
            let generator = WaveformGenerator()
            samples = await generator.decodeWaveform(from: cachedData)
            return
        }

        // Generate if not cached
        isLoading = true
        let generator = WaveformGenerator()

        do {
            // Use fewer samples for thumbnails (100 instead of 300)
            samples = try await generator.generateWaveform(
                from: recording.audioFileURL,
                targetSamples: 100
            )

            // Cache for future use
            let data = try await generator.generateWaveformData(
                from: recording.audioFileURL,
                targetSamples: 100
            )
            recording.waveformData = data

        } catch {
            Logger.error("Failed to load thumbnail waveform: \(error)", category: Logger.audio)
        }

        isLoading = false
    }
}

// MARK: - Waveform Skeleton

/// Loading skeleton for waveform thumbnails
struct WaveformSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<30, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.gray.opacity(0.3))
                        .frame(
                            width: 2,
                            height: CGFloat.random(in: 10...geometry.size.height * 0.8)
                        )
                        .opacity(isAnimating ? 0.3 : 0.6)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Waveform Placeholder Enhancement

extension WaveformPlaceholder {
    init(compact: Bool = false) {
        // Use the existing WaveformPlaceholder but with compact mode
        self.init()
    }
}

#Preview("Thumbnail") {
    VStack(spacing: 16) {
        Text("Waveform Thumbnails")
            .font(.headline)

        // Sample recording
        WaveformThumbnail(
            recording: Recording(
                title: "Sample",
                duration: 45,
                audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf")
            ),
            height: 40
        )
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)

        WaveformThumbnail(
            recording: Recording(
                title: "Sample",
                duration: 45,
                audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf")
            ),
            height: 50
        )
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    .padding()
}
