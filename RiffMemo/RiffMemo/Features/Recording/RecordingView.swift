//
//  RecordingView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @State private var viewModel: RecordingViewModel
    @ObservedObject private var metronome = SharedMetronomeService.shared
    @State private var metronomeEnabled = false

    init(viewModel: RecordingViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                Spacer()

                // Duration Display
                Text(viewModel.currentDuration.formattedDuration())
                    .font(.system(size: 60, weight: .thin, design: .monospaced))
                    .foregroundColor(.primary)
                    .opacity(metronome.preCountRemaining > 0 ? 0 : 1)

            // Audio Level Indicator
            AudioLevelBar(level: viewModel.audioLevel)
                .frame(height: 8)
                .padding(.horizontal, 40)

            // Visual Beat Indicator (during recording with metronome)
            if viewModel.isRecording && metronomeEnabled && metronome.isPlaying {
                BeatFlashIndicator(
                    currentBeat: metronome.displayBeat,
                    totalBeats: metronome.timeSignature.beatsPerMeasure,
                    isPlaying: metronome.isPlaying
                )
                .frame(height: 50)
                .padding(.horizontal, 40)
            }

            // Metronome Controls
            VStack(spacing: 16) {
                // Enable/Disable Toggle
                Toggle(isOn: $metronomeEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "metronome")
                        Text("Click Track")
                    }
                    .font(.headline)
                }
                .tint(.blue)
                .padding(.horizontal, 40)
                .onChange(of: metronomeEnabled) { oldValue, newValue in
                    // Stop metronome if toggled off while playing
                    if !newValue && metronome.isPlaying {
                        metronome.stop()
                    }
                }

                if metronomeEnabled {
                    // BPM Control
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(Int(metronome.bpm))")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("BPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "tortoise.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)

                            Slider(
                                value: Binding(
                                    get: { metronome.bpm },
                                    set: { metronome.setBPM($0) }
                                ),
                                in: 30...300,
                                step: 1
                            )
                            .tint(.blue)

                            Image(systemName: "hare.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 40)
                    }

                    // Volume Control
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.1.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)

                        Slider(
                            value: Binding(
                                get: { metronome.volume },
                                set: { metronome.setVolume($0) }
                            ),
                            in: 0...1
                        )
                        .tint(.blue)

                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 40)

                    // Time Signature
                    Picker("Time Signature", selection: Binding(
                        get: { metronome.timeSignature },
                        set: { metronome.setTimeSignature($0) }
                    )) {
                        ForEach(SharedMetronomeService.TimeSignature.allCases, id: \.self) { signature in
                            Text(signature.rawValue).tag(signature)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                }
            }
            .padding(.vertical, 16)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
            .padding(.horizontal, 20)

            Spacer()

            // Record Button
            Button(action: {
                toggleRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.blue)
                        .frame(width: 120, height: 120)
                        .shadow(color: viewModel.isRecording ? .red.opacity(0.4) : .blue.opacity(0.4), radius: 20)

                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            .buttonStyle(.plain)

            // Status Text
            Text(viewModel.isRecording ? "Recording..." : "Tap to Record")
                .font(.headline)
                .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))

            // Pre-count Countdown Overlay
            if metronome.state == .preCount {
                VStack {
                    Spacer()

                    Text("\(metronome.preCountDisplayNumber)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(metronome.preCountDisplayNumber == metronome.timeSignature.beatsPerMeasure ? .green : .blue)
                        .transition(.scale.combined(with: .opacity))
                        .id("countdown-\(metronome.preCountDisplayNumber)")

                    // Show which beat is accented (downbeat = first beat of measure)
                    Text(metronome.preCountDisplayNumber == metronome.timeSignature.beatsPerMeasure ? "DOWNBEAT" : "beat \(metronome.timeSignature.beatsPerMeasure - metronome.preCountDisplayNumber + 1)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(metronome.preCountDisplayNumber == metronome.timeSignature.beatsPerMeasure ? .green : .blue.opacity(0.6))
                        .padding(.top, 8)

                    Text("Get Ready")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).opacity(0.95))
                .transition(.opacity)
            }
        }
        .alert("Recording Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }

    // MARK: - Private Methods

    private func toggleRecording() {
        if viewModel.isRecording {
            // Stop recording
            if metronomeEnabled {
                metronome.stop()
            }
            viewModel.toggleRecording()
        } else {
            // Start recording
            if metronomeEnabled {
                // IMPORTANT: Disable visual-only mode for recording
                // You need to HEAR the click track during recording!
                if metronome.visualOnlyMode {
                    Logger.info("Auto-disabling visual-only mode for recording click track", category: Logger.audio)
                    metronome.setVisualOnlyMode(false)
                }

                // Set metronome settings in viewModel
                viewModel.recordingBPM = Int(metronome.bpm)
                viewModel.recordingTimeSignature = metronome.timeSignature.rawValue

                // Start metronome with pre-count, then start recording when pre-count completes
                metronome.startWithPreCount {
                    // Start actual recording after pre-count
                    self.viewModel.startRecording()
                }
            } else {
                // No metronome, start recording immediately
                viewModel.toggleRecording()
            }
        }
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Level
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
    }
}

// MARK: - Beat Flash Indicator

struct BeatFlashIndicator: View {
    let currentBeat: Int
    let totalBeats: Int
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalBeats, id: \.self) { beat in
                Circle()
                    .fill(beatColor(for: beat))
                    .frame(width: beatSize(for: beat), height: beatSize(for: beat))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 2)
                            .opacity(beat == currentBeat && isPlaying ? 1 : 0)
                    )
                    .shadow(
                        color: beatColor(for: beat).opacity(0.8),
                        radius: beat == currentBeat && isPlaying ? 8 : 0
                    )
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: currentBeat)
            }
        }
    }

    private func beatColor(for beat: Int) -> Color {
        if !isPlaying {
            return .gray.opacity(0.3)
        }

        if beat == currentBeat {
            return beat == 0 ? .orange.opacity(0.8) : .blue.opacity(0.8)
        } else {
            return .gray.opacity(0.2)
        }
    }

    private func beatSize(for beat: Int) -> CGFloat {
        if isPlaying && beat == currentBeat {
            return beat == 0 ? 40 : 36
        } else {
            return 28
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Recording.self)

    return RecordingView(
        viewModel: RecordingViewModel(
            audioRecorder: AudioRecordingManager(),
            repository: SwiftDataRecordingRepository(
                modelContext: container.mainContext
            )
        )
    )
}
