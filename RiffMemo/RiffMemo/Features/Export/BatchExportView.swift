//
//  BatchExportView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

/// View for batch exporting multiple recordings
struct BatchExportView: View {
    let recordings: [Recording]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: AudioFormat = .m4a
    @State private var selectedQuality: ExportQuality = .high
    @State private var includeMetadata = true
    @State private var isExporting = false
    @State private var exportProgress: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Export Progress
                if isExporting {
                    VStack(spacing: 12) {
                        ProgressView(value: exportProgress) {
                            HStack {
                                Text("Exporting...")
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(exportProgress * 100))%")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        Text("Exporting \(recordings.count) recordings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                }

                // Settings Form
                Form {
                    // Selected Recordings
                    Section {
                        ForEach(recordings.prefix(5)) { recording in
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.blue)
                                Text(recording.title)
                                    .lineLimit(1)
                            }
                        }

                        if recordings.count > 5 {
                            Text("+ \(recordings.count - 5) more recordings")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } header: {
                        Label("\(recordings.count) Recordings Selected", systemImage: "checkmark.circle.fill")
                    }

                    // Format Selection
                    Section {
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(AudioFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Label("Audio Format", systemImage: "waveform")
                    }

                    // Quality Selection
                    Section {
                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(ExportQuality.allCases, id: \.self) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Label("Export Quality", systemImage: "gauge.high")
                    }

                    // Metadata Toggle
                    Section {
                        Toggle("Include Metadata", isOn: $includeMetadata)
                    } header: {
                        Label("Options", systemImage: "slider.horizontal.3")
                    } footer: {
                        Text("Embeds title, BPM, key, and date in each file")
                    }

                    // Total Size Estimate
                    Section {
                        HStack {
                            Text("Total Estimated Size")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(estimatedTotalSize)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Batch Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isExporting)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        exportAll()
                    }) {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Export All")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isExporting)
                }
            }
        }
    }

    private var estimatedTotalSize: String {
        let totalDuration = recordings.reduce(0.0) { $0 + $1.duration }
        let bitrate = selectedQuality.bitrate > 0 ? selectedQuality.bitrate : 1411000
        let bytes = Int64((Double(bitrate) / 8.0) * totalDuration)

        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func exportAll() {
        isExporting = true
        exportProgress = 0
        HapticManager.shared.mediumTap()

        Task {
            let settings = ExportSettings(
                format: selectedFormat,
                quality: selectedQuality,
                includeMetadata: includeMetadata,
                metadata: nil
            )

            await ShareManager.shared.shareMultipleRecordings(
                recordings,
                settings: settings
            )

            HapticManager.shared.success()
            isExporting = false
            dismiss()
        }
    }
}

#Preview {
    BatchExportView(
        recordings: [
            Recording(title: "Song 1", duration: 120, audioFileURL: URL(fileURLWithPath: "/tmp/1.caf")),
            Recording(title: "Song 2", duration: 90, audioFileURL: URL(fileURLWithPath: "/tmp/2.caf")),
            Recording(title: "Song 3", duration: 150, audioFileURL: URL(fileURLWithPath: "/tmp/3.caf"))
        ]
    )
}
