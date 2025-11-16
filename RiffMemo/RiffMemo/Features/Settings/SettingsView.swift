//
//  SettingsView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("autoAnalyzeRecordings") private var autoAnalyze = true
    @AppStorage("analyzeBPM") private var analyzeBPM = true
    @AppStorage("analyzeKey") private var analyzeKey = true
    @AppStorage("analyzeQuality") private var analyzeQuality = true

    var body: some View {
        NavigationStack {
            Form {
                // Analysis Settings
                Section {
                    Toggle("Auto-Analyze New Recordings", isOn: $autoAnalyze)

                    if autoAnalyze {
                        Toggle("Detect BPM (Tempo)", isOn: $analyzeBPM)
                        Toggle("Detect Musical Key", isOn: $analyzeKey)
                        Toggle("Analyze Audio Quality", isOn: $analyzeQuality)
                    }
                } header: {
                    Label("Audio Analysis", systemImage: "waveform.badge.magnifyingglass")
                } footer: {
                    Text("Automatically analyzes recordings to detect tempo, musical key, and audio quality. Analysis happens in the background.")
                }

                // Analysis Info
                Section {
                    HStack {
                        Text("Analysis Queue")
                        Spacer()
                        Text("\(AudioAnalysisManager.shared.queueCount) pending")
                            .foregroundStyle(.secondary)
                    }

                    if AudioAnalysisManager.shared.isAnalyzing {
                        HStack {
                            Text("Currently Analyzing")
                            Spacer()
                            if let current = AudioAnalysisManager.shared.currentlyAnalyzing {
                                Text(current)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        ProgressView(value: AudioAnalysisManager.shared.analysisProgress)
                    }

                    Button("Clear Analysis Queue") {
                        AudioAnalysisManager.shared.clearQueue()
                        HapticManager.shared.lightTap()
                    }
                    .disabled(AudioAnalysisManager.shared.queueCount == 0)
                } header: {
                    Label("Status", systemImage: "chart.bar")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    SettingsView()
}
