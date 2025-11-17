//
//  ExportOptionsView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

/// View for configuring export settings
struct ExportOptionsView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: AudioFormat = .m4a
    @State private var selectedQuality: ExportQuality = .high
    @State private var includeMetadata = true
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            Form {
                // Format Selection
                Section {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Format info
                    FormatInfoRow(format: selectedFormat)

                } header: {
                    Label("Audio Format", systemImage: "waveform")
                } footer: {
                    Text(formatDescription(for: selectedFormat))
                }

                // Quality Selection
                Section {
                    Picker("Quality", selection: $selectedQuality) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .pickerStyle(.menu)

                    QualityInfoRow(quality: selectedQuality)

                } header: {
                    Label("Export Quality", systemImage: "gauge.high")
                } footer: {
                    Text("Higher quality results in larger file sizes")
                }

                // Metadata Options
                Section {
                    Toggle("Include Metadata", isOn: $includeMetadata)

                    if includeMetadata {
                        VStack(alignment: .leading, spacing: 8) {
                            MetadataRow(label: "Title", value: recording.title)

                            if let bpm = recording.detectedBPM {
                                MetadataRow(label: "BPM", value: "\(bpm)")
                            }

                            if let key = recording.detectedKey {
                                MetadataRow(label: "Key", value: key)
                            }

                            MetadataRow(
                                label: "Date",
                                value: recording.createdDate.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                } header: {
                    Label("Metadata", systemImage: "tag")
                } footer: {
                    Text("Embed recording information in the exported file")
                }

                // File Size Estimate
                Section {
                    EstimatedSizeRow(
                        duration: recording.duration,
                        format: selectedFormat,
                        quality: selectedQuality
                    )
                } header: {
                    Label("Estimated Size", systemImage: "doc")
                }
            }
            .navigationTitle("Export Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        exportAndShare()
                    }) {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Share")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isExporting)
                }
            }
        }
    }

    private func exportAndShare() {
        isExporting = true
        HapticManager.shared.mediumTap()

        Task {
            let settings = ExportSettings(
                format: selectedFormat,
                quality: selectedQuality,
                includeMetadata: includeMetadata,
                metadata: includeMetadata ? ExportMetadata.from(recording) : nil
            )

            await ShareManager.shared.shareRecording(recording, settings: settings)

            isExporting = false
            dismiss()
        }
    }

    private func formatDescription(for format: AudioFormat) -> String {
        switch format {
        case .caf:
            return "Native iOS format, best compatibility with Apple devices"
        case .m4a:
            return "Compressed format with good quality, widely supported"
        case .wav:
            return "Uncompressed format, large file size, universal compatibility"
        case .aiff:
            return "Apple's uncompressed format, excellent quality"
        }
    }
}

// MARK: - Supporting Views

struct FormatInfoRow: View {
    let format: AudioFormat

    var body: some View {
        HStack {
            Text("File Extension")
                .foregroundStyle(.secondary)
            Spacer()
            Text(".\(format.fileExtension)")
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

struct QualityInfoRow: View {
    let quality: ExportQuality

    var body: some View {
        HStack {
            Text("Bitrate")
                .foregroundStyle(.secondary)
            Spacer()
            if quality == .lossless {
                Text("Lossless")
                    .fontWeight(.medium)
            } else {
                Text("\(quality.bitrate / 1000) kbps")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .font(.subheadline)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }
}

struct EstimatedSizeRow: View {
    let duration: TimeInterval
    let format: AudioFormat
    let quality: ExportQuality

    private var estimatedSize: String {
        let bitrate = quality.bitrate > 0 ? quality.bitrate : 1411000 // CD quality for lossless
        let bytes = Int64((Double(bitrate) / 8.0) * duration)

        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        HStack {
            Text("Approximate file size")
                .foregroundStyle(.secondary)
            Spacer()
            Text(estimatedSize)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

// MARK: - Quick Share Button

struct QuickShareButton: View {
    let recording: Recording
    @State private var showingExportOptions = false

    var body: some View {
        Button(action: {
            showingExportOptions = true
            HapticManager.shared.lightTap()
        }) {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .buttonStyle(.borderedProminent)
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(recording: recording)
        }
    }
}

#Preview {
    ExportOptionsView(
        recording: Recording(
            title: "Guitar Riff",
            duration: 45.5,
            audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf"),
            detectedBPM: 120,
            detectedKey: "C Major"
        )
    )
}
