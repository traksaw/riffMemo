//
//  AnalysisResultsView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

/// Displays analysis results for a recording
struct AnalysisResultsView: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Recorded with metronome settings
            if recording.recordedWithBPM != nil || recording.recordedWithTimeSignature != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recorded With")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 12) {
                        if let bpm = recording.recordedWithBPM {
                            HStack(spacing: 6) {
                                Image(systemName: "metronome.fill")
                                    .foregroundStyle(.green)
                                Text("\(bpm) BPM")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }

                        if let timeSig = recording.recordedWithTimeSignature {
                            HStack(spacing: 6) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.green)
                                Text(timeSig)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }

            // BPM and Key
            if recording.detectedBPM != nil || recording.detectedKey != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 20) {
                        if let bpm = recording.detectedBPM {
                            AnalysisMetricCard(
                                icon: "metronome",
                                label: "Tempo",
                                value: "\(bpm) BPM",
                                color: .blue
                            )
                        }

                        if let key = recording.detectedKey {
                            AnalysisMetricCard(
                                icon: "music.note",
                                label: "Key",
                                value: key,
                                color: .purple
                            )
                        }
                    }
                }
            }

            // Audio Quality
            if let quality = recording.audioQuality {
                AudioQualityCard(
                    quality: quality,
                    peakLevel: recording.peakLevel,
                    rmsLevel: recording.rmsLevel,
                    dynamicRange: recording.dynamicRange
                )
            }

            // Analysis timestamp
            if let analyzedDate = recording.lastAnalyzedDate {
                Text("Analyzed \(analyzedDate.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Analysis Metric Card

struct AnalysisMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Audio Quality Card

struct AudioQualityCard: View {
    let quality: String
    let peakLevel: Double?
    let rmsLevel: Double?
    let dynamicRange: Double?

    private var qualityColor: Color {
        switch quality {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "Poor": return .red
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quality badge
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(qualityColor)

                Text("Audio Quality: \(quality)")
                    .font(.headline)

                Spacer()

                Text(quality)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(qualityColor)
                    .cornerRadius(12)
            }

            Divider()

            // Detailed metrics
            VStack(spacing: 8) {
                if let peak = peakLevel {
                    MetricRow(label: "Peak Level", value: String(format: "%.1f dB", peak))
                }

                if let rms = rmsLevel {
                    MetricRow(label: "RMS Level", value: String(format: "%.1f dB", rms))
                }

                if let range = dynamicRange {
                    MetricRow(label: "Dynamic Range", value: String(format: "%.1f dB", range))
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Metric Row

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

// MARK: - Analysis Button

struct AnalyzeButton: View {
    let recording: Recording
    @State private var isAnalyzing = false

    var body: some View {
        Button(action: {
            isAnalyzing = true
            Task {
                _ = await AudioAnalysisManager.shared.analyzeRecording(recording)
                isAnalyzing = false
                HapticManager.shared.success()
            }
        }) {
            HStack {
                if isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }

                Text(isAnalyzing ? "Analyzing..." : "Analyze Audio")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled(isAnalyzing)
    }
}

#Preview {
    VStack(spacing: 20) {
        AnalysisResultsView(
            recording: Recording(
                title: "Guitar Riff",
                duration: 45.5,
                audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf"),
                detectedBPM: 120,
                detectedKey: "C Major",
                audioQuality: "Excellent",
                peakLevel: -3.2,
                rmsLevel: -18.5,
                dynamicRange: 12.3,
                lastAnalyzedDate: Date()
            )
        )

        AnalyzeButton(
            recording: Recording(
                title: "Test",
                duration: 30,
                audioFileURL: URL(fileURLWithPath: "/tmp/test.caf")
            )
        )
    }
    .padding()
}
