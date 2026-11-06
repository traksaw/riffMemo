//
//  RecordingView.swift
//  RiffMemo
//
//

import SwiftUI
import SwiftData
import OSLog

struct RecordingView: View {
    @State private var viewModel: RecordingViewModel
    @ObservedObject private var metronome = SharedMetronomeService.shared
    @State private var metronomeEnabled = false
    @State private var playingInterruptedTake: Recording?

    init(viewModel: RecordingViewModel) {
        self.viewModel = viewModel
    }

    /// While a recording is in progress, the click track's on/off state is owned by
    /// `SharedMetronomeService.isPlaying` — another screen (e.g. the Metronome tab) can
    /// stop it out from under us, so this reflects that reality instead of the stale
    /// local intent flag. Before/after recording, `metronomeEnabled` is just the user's
    /// intent for the next recording.
    private var clickTrackToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isRecording ? metronome.isPlaying : metronomeEnabled },
            set: { metronomeEnabled = $0 }
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()

                // WAS-118: a call cut the last take. It is saved; offer to keep going.
                if let take = viewModel.interruptedTake, !viewModel.isRecording {
                    InterruptedTakeCard(
                        take: take,
                        onContinue: { toggleRecording() },
                        onPlay: { playingInterruptedTake = take }
                    )
                    .padding(.horizontal, 16)
                }

                // Timer with milliseconds
                RecordingTimerView(
                    duration: viewModel.currentDuration,
                    showMilliseconds: true,
                    isRecording: viewModel.isRecording
                )
                .opacity(metronome.preCountRemaining > 0 ? 0 : 1)

                // Live Waveform (Apple Voice Memos style)
                LiveWaveformView(
                    samples: viewModel.waveformSamples,
                    isRecording: viewModel.isRecording
                )
                .frame(height: 120)
                .padding(.horizontal, 32)

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

            // Metronome Controls (collapsed when not in use)
            VStack(spacing: 12) {
                // Enable/Disable Toggle
                Toggle(isOn: clickTrackToggleBinding) {
                    HStack(spacing: 6) {
                        Image(systemName: "metronome")
                            .font(.callout)
                        Text("Click Track")
                            .font(.subheadline)
                    }
                }
                .tint(.blue)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("clickTrackToggle")
                .onChange(of: metronomeEnabled) { oldValue, newValue in
                    if !newValue && metronome.isPlaying {
                        metronome.stop()
                    }
                }

                if metronomeEnabled {
                    VStack(spacing: 10) {
                        // BPM Control
                        HStack(spacing: 12) {
                            Text("\(Int(metronome.bpm))")
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 60)

                            Slider(
                                value: Binding(
                                    get: { metronome.bpm },
                                    set: { metronome.setBPM($0) }
                                ),
                                in: 30...300,
                                step: 1
                            )
                            .tint(.blue)

                            Text("BPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40)
                        }
                        .padding(.horizontal, 32)

                        // Compact controls row
                        HStack(spacing: 20) {
                            // Volume
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { metronome.volume },
                                        set: { metronome.setVolume($0) }
                                    ),
                                    in: 0...1
                                )
                                .tint(.blue)
                            }

                            // Time Signature
                            Picker("", selection: Binding(
                                get: { metronome.timeSignature },
                                set: { metronome.setTimeSignature($0) }
                            )) {
                                ForEach(SharedMetronomeService.TimeSignature.allCases, id: \.self) { signature in
                                    Text(signature.rawValue).tag(signature)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 180)
                        }
                        .padding(.horizontal, 32)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 12)
            .background(metronomeEnabled ? Color(.systemGray6).opacity(0.3) : Color.clear)
            .cornerRadius(8)
            .padding(.horizontal, 20)

            Spacer()

            // Record Button
            VStack(spacing: 16) {
                Button(action: {
                    toggleRecording()
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.blue)
                            .frame(width: 100, height: 100)
                            .shadow(color: viewModel.isRecording ? .red.opacity(0.3) : .blue.opacity(0.3), radius: 12)

                        if viewModel.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .frame(width: 32, height: 32)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recordButton")

                // Status Text
                Text(viewModel.isRecording ? "Recording..." : "Tap to Record")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
            }
            .padding()
            .background(Color(.systemBackground))

            // Pre-count Countdown Overlay
            if metronome.state == .preCount {
                // Calculate which beat we're on (1, 2, 3, 4)
                // preCountDisplayNumber counts down, we map to beat numbers
                let beatsInMeasure = metronome.timeSignature.beatsPerMeasure
                let currentBeat = beatsInMeasure - metronome.preCountDisplayNumber + 1
                let isFinalBeat = currentBeat == beatsInMeasure

                VStack {
                    Spacer()

                    // Show actual beat number (1, 2, 3, 4)
                    Text("\(currentBeat)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(isFinalBeat ? .red : .blue)
                        .transition(.scale.combined(with: .opacity))
                        .id("countdown-\(metronome.preCountDisplayNumber)")

                    Text(isFinalBeat ? "Recording starts next!" : "Count In")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isFinalBeat ? .red : .blue.opacity(0.6))
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
        .onChange(of: viewModel.interruptedTake?.id) { _, takeID in
            // The call stopped the take, so the click under it stops too.
            if takeID != nil, metronome.isPlaying {
                metronome.stop()
            }
        }
        .sheet(item: $playingInterruptedTake) { take in
            NavigationStack {
                RecordingDetailView(
                    recording: take,
                    viewModel: RecordingDetailViewModel(
                        recording: take,
                        audioPlayer: AudioPlaybackManager()
                    )
                )
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
                if metronome.visualOnlyMode {
                    Logger.audio.info("Auto-disabling visual-only mode for recording click track")
                    metronome.setVisualOnlyMode(false)
                }

                viewModel.recordingBPM = Int(metronome.bpm)
                viewModel.recordingTimeSignature = metronome.timeSignature.rawValue

                metronome.startWithPreCount {
                    self.viewModel.startRecording()
                }
            } else {
                viewModel.toggleRecording()
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
