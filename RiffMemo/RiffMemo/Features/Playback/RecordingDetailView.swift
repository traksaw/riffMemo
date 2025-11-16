//
//  RecordingDetailView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

struct RecordingDetailView: View {
    @State private var viewModel: RecordingDetailViewModel
    let recording: Recording

    init(recording: Recording, viewModel: RecordingDetailViewModel) {
        self.recording = recording
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Recording Title
            VStack(spacing: 8) {
                Text(recording.title)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(recording.createdDate.formattedForRecording())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Waveform Placeholder (simple visualization for now)
            WaveformPlaceholder()
                .frame(height: 120)
                .padding(.horizontal)

            // Time Display
            HStack {
                Text(viewModel.currentTime.formattedDuration())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(viewModel.duration.formattedDuration())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)

            // Playback Slider
            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.duration, 1)
            )
            .padding(.horizontal, 40)
            .disabled(!viewModel.isPlaying && viewModel.currentTime == 0)

            Spacer()

            // Play/Pause Button
            Button(action: {
                viewModel.togglePlayback()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.4), radius: 15)

                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .offset(x: viewModel.isPlaying ? 0 : 3) // Slight offset for play icon to look centered
                }
            }
            .buttonStyle(.plain)

            // Metadata
            if recording.detectedBPM != nil || recording.detectedKey != nil {
                HStack(spacing: 20) {
                    if let bpm = recording.detectedBPM {
                        Label("\(bpm) BPM", systemImage: "metronome")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    if let key = recording.detectedKey {
                        Label(key, systemImage: "music.note")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            viewModel.stop()
        }
        .alert("Playback Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }
}

// MARK: - Waveform Placeholder

struct WaveformPlaceholder: View {
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<60, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.7))
                        .frame(
                            width: 3,
                            height: CGFloat.random(in: 20...geometry.size.height)
                        )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(
            recording: Recording(
                title: "Guitar Riff",
                duration: 45.5,
                audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf"),
                fileSize: 480376,
                detectedBPM: 120,
                detectedKey: "C Major"
            ),
            viewModel: RecordingDetailViewModel(
                recording: Recording(
                    title: "Guitar Riff",
                    duration: 45.5,
                    audioFileURL: URL(fileURLWithPath: "/tmp/sample.caf")
                ),
                audioPlayer: AudioPlaybackManager()
            )
        )
    }
}
