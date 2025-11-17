//
//  MetronomeView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

struct MetronomeView: View {
    @ObservedObject private var metronome = SharedMetronomeService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.purple.opacity(0.1), Color.pink.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 40) {
                        Spacer()
                            .frame(height: 20)

                    // Visual Beat Indicator
                    BeatIndicator(
                        currentBeat: metronome.displayBeat,
                        totalBeats: metronome.timeSignature.beatsPerMeasure,
                        isPlaying: metronome.isPlaying
                    )

                    // BPM Display
                    VStack(spacing: 12) {
                        Text("\(Int(metronome.bpm))")
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()

                        Text("BPM")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }

                    // BPM Slider
                    VStack(spacing: 16) {
                        Slider(
                            value: Binding(
                                get: { metronome.bpm },
                                set: { metronome.setBPM($0) }
                            ),
                            in: 30...300,
                            step: 1
                        )
                        .tint(.purple)
                        .padding(.horizontal, 40)

                        // Quick BPM adjustments
                        HStack(spacing: 20) {
                            BPMButton(label: "-10", action: {
                                metronome.incrementBPM(-10)
                            })

                            BPMButton(label: "-1", action: {
                                metronome.incrementBPM(-1)
                            })

                            BPMButton(label: "+1", action: {
                                metronome.incrementBPM(1)
                            })

                            BPMButton(label: "+10", action: {
                                metronome.incrementBPM(10)
                            })
                        }

                        // Tempo Presets
                        VStack(spacing: 8) {
                            Text("Quick Tempos")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(TempoPreset.common, id: \.name) { preset in
                                    Button(action: {
                                        metronome.setBPM(preset.bpm)
                                        HapticManager.shared.lightTap()
                                    }) {
                                        VStack(spacing: 2) {
                                            Text(preset.name)
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                            Text("\(Int(preset.bpm))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            abs(metronome.bpm - preset.bpm) < 1 ?
                                            Color.purple.opacity(0.3) :
                                            Color.purple.opacity(0.1)
                                        )
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    // Tap Tempo Button
                    VStack(spacing: 8) {
                        Button(action: {
                            metronome.tapTempo()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                Text("Tap Tempo")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: 300)
                            .padding(.vertical, 12)
                            .background(Color.purple.opacity(0.8))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // Tap Tempo Feedback
                        if metronome.tapCount > 0 {
                            HStack(spacing: 16) {
                                // Tap count
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.tap")
                                        .font(.caption)
                                    Text("\(metronome.tapCount) tap\(metronome.tapCount == 1 ? "" : "s")")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)

                                // Calculated BPM
                                if let calculatedBPM = metronome.calculatedBPM {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                        Text("\(Int(calculatedBPM)) BPM")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(.purple)
                                }

                                // Reset button
                                Button(action: {
                                    metronome.resetTapTempo()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 8)

                    // Volume Control
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "speaker.wave.1.fill")
                                .foregroundStyle(.secondary)

                            Slider(
                                value: Binding(
                                    get: { metronome.volume },
                                    set: { metronome.setVolume($0) }
                                ),
                                in: 0...1
                            )
                            .tint(.purple)

                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 40)

                        Text("Volume")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Time Signature Selector
                    VStack(spacing: 12) {
                        Text("Time Signature")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

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

                    Divider()
                        .padding(.vertical, 8)

                    // MARK: - Advanced Features

                    // Subdivision Selector
                    VStack(spacing: 12) {
                        Text("Subdivisions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Subdivisions", selection: Binding(
                            get: { metronome.subdivision },
                            set: { metronome.setSubdivision($0) }
                        )) {
                            ForEach(SharedMetronomeService.Subdivision.allCases, id: \.self) { subdivision in
                                Text(subdivision.displayName).tag(subdivision)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 40)
                    }

                    // Click Sound Selector
                    VStack(spacing: 12) {
                        Text("Click Sound")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Click Sound", selection: Binding(
                            get: { metronome.clickSound },
                            set: { metronome.setClickSound($0) }
                        )) {
                            ForEach(SharedMetronomeService.ClickSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 40)
                    }

                    // Visual-Only Mode Toggle
                    Toggle(isOn: Binding(
                        get: { metronome.visualOnlyMode },
                        set: { metronome.setVisualOnlyMode($0) }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: metronome.visualOnlyMode ? "eye.fill" : "speaker.wave.2.fill")
                            Text("Visual Only")
                        }
                        .font(.subheadline)
                    }
                    .tint(.purple)
                    .padding(.horizontal, 40)

                    // Tempo Ramp Section
                    VStack(spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { metronome.tempoRampEnabled },
                            set: { metronome.setTempoRampEnabled($0) }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                Text("Tempo Ramp")
                            }
                            .font(.subheadline)
                        }
                        .tint(.purple)
                        .padding(.horizontal, 40)

                        if metronome.tempoRampEnabled {
                            VStack(spacing: 16) {
                                // Start BPM
                                HStack {
                                    Text("Start:")
                                        .font(.caption)
                                        .frame(width: 50, alignment: .leading)
                                    Text("\(Int(metronome.tempoRampStartBPM))")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .frame(width: 40)
                                    Slider(
                                        value: Binding(
                                            get: { metronome.tempoRampStartBPM },
                                            set: { newValue in
                                                metronome.setTempoRampSettings(
                                                    startBPM: newValue,
                                                    targetBPM: metronome.tempoRampTargetBPM,
                                                    duration: metronome.tempoRampDuration
                                                )
                                            }
                                        ),
                                        in: 30...300,
                                        step: 5
                                    )
                                    .tint(.purple)
                                }

                                // Target BPM
                                HStack {
                                    Text("Target:")
                                        .font(.caption)
                                        .frame(width: 50, alignment: .leading)
                                    Text("\(Int(metronome.tempoRampTargetBPM))")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .frame(width: 40)
                                    Slider(
                                        value: Binding(
                                            get: { metronome.tempoRampTargetBPM },
                                            set: { newValue in
                                                metronome.setTempoRampSettings(
                                                    startBPM: metronome.tempoRampStartBPM,
                                                    targetBPM: newValue,
                                                    duration: metronome.tempoRampDuration
                                                )
                                            }
                                        ),
                                        in: 30...300,
                                        step: 5
                                    )
                                    .tint(.purple)
                                }

                                // Duration
                                HStack {
                                    Text("Duration:")
                                        .font(.caption)
                                        .frame(width: 50, alignment: .leading)
                                    Text("\(Int(metronome.tempoRampDuration))s")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .frame(width: 40)
                                    Slider(
                                        value: Binding(
                                            get: { metronome.tempoRampDuration },
                                            set: { newValue in
                                                metronome.setTempoRampSettings(
                                                    startBPM: metronome.tempoRampStartBPM,
                                                    targetBPM: metronome.tempoRampTargetBPM,
                                                    duration: newValue
                                                )
                                            }
                                        ),
                                        in: 10...300,
                                        step: 10
                                    )
                                    .tint(.purple)
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 8)
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(8)
                            .padding(.horizontal, 40)
                        }
                    }

                    Spacer()

                    // Start/Stop Button
                    Button(action: {
                        if metronome.isPlaying {
                            metronome.stop()
                        } else {
                            metronome.start()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: metronome.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)

                            Text(metronome.isPlaying ? "Stop" : "Start")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: 300)
                        .padding()
                        .background(metronome.isPlaying ? Color.red : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 8)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                        .frame(height: 40)
                    }
                }
            }
            .navigationTitle("Metronome")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            if metronome.isPlaying {
                metronome.stop()
            }
        }
        .alert("Metronome Error", isPresented: $metronome.showError) {
            Button("OK") {
                metronome.showError = false
            }
        } message: {
            if let message = metronome.errorMessage {
                Text(message)
            }
        }
    }
}

// MARK: - Beat Indicator

struct BeatIndicator: View {
    let currentBeat: Int
    let totalBeats: Int
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<totalBeats, id: \.self) { beat in
                ZStack {
                    // Outer glow ring for active beat
                    if isPlaying && beat == currentBeat {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        beatColor(for: beat).opacity(0.4),
                                        beatColor(for: beat).opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 40
                                )
                            )
                            .frame(width: 80, height: 80)
                            .scaleEffect(1.2)
                    }

                    // Main beat circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: beatGradient(for: beat),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: beatSize(for: beat), height: beatSize(for: beat))
                        .overlay(
                            Circle()
                                .stroke(beatStrokeColor(for: beat), lineWidth: 3)
                        )
                        .shadow(color: beatColor(for: beat).opacity(0.6), radius: beatShadow(for: beat))
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: currentBeat)
            }
        }
        .frame(height: 100)
    }

    private func beatColor(for beat: Int) -> Color {
        if !isPlaying {
            return .gray.opacity(0.3)
        }

        if beat == currentBeat {
            return beat == 0 ? .orange : .purple
        } else {
            return .gray.opacity(0.3)
        }
    }

    private func beatGradient(for beat: Int) -> [Color] {
        if !isPlaying {
            return [.gray.opacity(0.2), .gray.opacity(0.3)]
        }

        if beat == currentBeat {
            if beat == 0 {
                return [.orange, .orange.opacity(0.8)]
            } else {
                return [.purple, .purple.opacity(0.8)]
            }
        } else {
            return [.gray.opacity(0.2), .gray.opacity(0.3)]
        }
    }

    private func beatStrokeColor(for beat: Int) -> Color {
        if isPlaying && beat == currentBeat {
            return .white.opacity(0.8)
        } else {
            return .white.opacity(0.3)
        }
    }

    private func beatSize(for beat: Int) -> CGFloat {
        if isPlaying && beat == currentBeat {
            return beat == 0 ? 64 : 56
        } else {
            return 42
        }
    }

    private func beatShadow(for beat: Int) -> CGFloat {
        if isPlaying && beat == currentBeat {
            return 15
        } else {
            return 0
        }
    }
}

// MARK: - BPM Button

struct BPMButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.purple)
                .frame(width: 60, height: 44)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tempo Presets

struct TempoPreset {
    let name: String
    let bpm: Double

    static let common = [
        TempoPreset(name: "Largo", bpm: 50),
        TempoPreset(name: "Adagio", bpm: 70),
        TempoPreset(name: "Andante", bpm: 90),
        TempoPreset(name: "Moderato", bpm: 108),
        TempoPreset(name: "Allegro", bpm: 132),
        TempoPreset(name: "Presto", bpm: 180)
    ]
}

#Preview {
    MetronomeView()
}
