//
//  MetronomeView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

struct MetronomeView: View {
    @StateObject private var metronome = MetronomeManager()

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

                VStack(spacing: 40) {
                    Spacer()

                    // Visual Beat Indicator
                    BeatIndicator(
                        currentBeat: metronome.currentBeat,
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
                    }

                    // Time Signature Selector
                    VStack(spacing: 12) {
                        Text("Time Signature")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Time Signature", selection: $metronome.timeSignature) {
                            ForEach(MetronomeManager.TimeSignature.allCases, id: \.self) { signature in
                                Text(signature.rawValue).tag(signature)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 40)
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
            .navigationTitle("Metronome")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            if metronome.isPlaying {
                metronome.stop()
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
                Circle()
                    .fill(beatColor(for: beat))
                    .frame(width: beatSize(for: beat), height: beatSize(for: beat))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
                    .shadow(color: beatColor(for: beat).opacity(0.5), radius: beatShadow(for: beat))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentBeat)
            }
        }
        .frame(height: 80)
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

    private func beatSize(for beat: Int) -> CGFloat {
        if isPlaying && beat == currentBeat {
            return beat == 0 ? 60 : 50
        } else {
            return 40
        }
    }

    private func beatShadow(for beat: Int) -> CGFloat {
        if isPlaying && beat == currentBeat {
            return 10
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
