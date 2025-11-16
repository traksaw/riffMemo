//
//  LibraryView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @State private var viewModel: LibraryViewModel

    init(viewModel: LibraryViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.recordings.isEmpty {
                    // Empty State
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "mic.slash",
                        description: Text("Start recording to see your musical ideas here")
                    )
                } else {
                    // Recordings List
                    List {
                        ForEach(viewModel.recordings) { recording in
                            NavigationLink {
                                RecordingDetailView(
                                    recording: recording,
                                    viewModel: RecordingDetailViewModel(
                                        recording: recording,
                                        audioPlayer: AudioPlaybackManager()
                                    )
                                )
                            } label: {
                                RecordingRow(recording: recording)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteRecording(recording)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Analyze all button
                    if viewModel.unanalyzedCount > 0 {
                        Button(action: {
                            viewModel.analyzeAll()
                            HapticManager.shared.lightTap()
                        }) {
                            Label("Analyze All", systemImage: "waveform.badge.magnifyingglass")
                                .font(.caption)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Waveform generation indicator
                        if viewModel.isGeneratingWaveforms {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("\(Int(viewModel.waveformProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Analysis status
                        if AudioAnalysisManager.shared.isAnalyzing {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text("Analyzing")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Recording count
                        Text("\(viewModel.recordings.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await viewModel.loadRecordings()
                // Preload waveforms for first 10 recordings
                await viewModel.preloadWaveforms(count: 10)
            }
        }
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording
    @State private var isEditing = false
    @State private var editedTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title - editable
            if isEditing {
                HStack {
                    TextField("Recording Title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .onSubmit {
                            if !editedTitle.isEmpty {
                                recording.title = editedTitle
                            }
                            isEditing = false
                        }

                    Button("Cancel") {
                        isEditing = false
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text(recording.title)
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        editedTitle = recording.title
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless) // Prevent navigation when tapping edit button
                }
            }

            // Waveform Thumbnail
            WaveformThumbnail(recording: recording, height: 40)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)

            // Metadata
            HStack {
                // Duration
                Label(
                    recording.duration.formattedDuration(),
                    systemImage: "waveform"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                // Date
                Text(recording.createdDate.formattedForRecording())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // File Size (for debugging)
            if recording.fileSize > 0 {
                Text("File size: \(ByteCountFormatter.string(fromByteCount: recording.fileSize, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Detected metadata (if available)
            if recording.detectedBPM != nil || recording.detectedKey != nil {
                HStack(spacing: 12) {
                    if let bpm = recording.detectedBPM {
                        Label("\(bpm) BPM", systemImage: "metronome")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let key = recording.detectedKey {
                        Label(key, systemImage: "music.note")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = try! ModelContainer(for: Recording.self)

    // Add sample data
    let sampleRecording = Recording(
        title: "Guitar Riff",
        duration: 45.5,
        audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf"),
        fileSize: 480376,
        detectedBPM: 120,
        detectedKey: "C Major"
    )
    container.mainContext.insert(sampleRecording)

    return LibraryView(
        viewModel: LibraryViewModel(
            repository: SwiftDataRecordingRepository(
                modelContext: container.mainContext
            )
        )
    )
}
