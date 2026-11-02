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

    @AppStorage("defaultExportFormat") private var defaultFormat: AudioFormat = .m4a
    @AppStorage("defaultExportQuality") private var defaultQuality: ExportQuality = .high
    @AppStorage("includeMetadataByDefault") private var includeMetadata = true

    // WAS-114: crash and hang reports
    @State private var diagnosticsCount = 0
    @State private var diagnosticsExportURL: URL?
    @State private var showsDeveloperTools = false
    @State private var isConfirmingTestCrash = false

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

                // Export Settings
                Section {
                    Picker("Default Format", selection: $defaultFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Picker("Default Quality", selection: $defaultQuality) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }

                    Toggle("Include Metadata", isOn: $includeMetadata)
                } header: {
                    Label("Export Defaults", systemImage: "square.and.arrow.up")
                } footer: {
                    Text("Default settings for exporting and sharing recordings")
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

                    if let diagnosticsExportURL {
                        ShareLink(item: diagnosticsExportURL) {
                            HStack {
                                Text("Send Diagnostics")
                                Spacer()
                                Text("\(diagnosticsCount) \(diagnosticsCount == 1 ? "report" : "reports")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Text("Diagnostics")
                            Spacer()
                            Text("No reports")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                } footer: {
                    Text("Crash and hang reports stay on this iPhone. They leave it only if you send them.")
                }

                // WAS-114: TestFlight and Xcode builds only, decided at runtime.
                // See InstallEnvironment for why this is not a compile-time flag.
                if showsDeveloperTools {
                    Section {
                        Button("Force Test Crash", role: .destructive) {
                            isConfirmingTestCrash = true
                        }
                    } header: {
                        Label("Developer", systemImage: "hammer")
                    } footer: {
                        Text("Closes the app with a crash. The report shows under Diagnostics after the next launch.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                "Crash RiffMemo now?",
                isPresented: $isConfirmingTestCrash,
                titleVisibility: .visible
            ) {
                Button("Crash Now", role: .destructive) {
                    fatalError("WAS-114 forced test crash")
                }
            } message: {
                Text("This tests crash reporting. Your recordings are not affected.")
            }
            .task {
                refreshDiagnostics()
                showsDeveloperTools = await InstallEnvironment.allowsDeveloperTools()
            }
        }
    }

    private func refreshDiagnostics() {
        let store = DiagnosticsStore.makeDefault()
        do {
            diagnosticsCount = try store.reportURLs().count
            diagnosticsExportURL = try store.makeExportFile()
        } catch {
            Logger.error("Failed to read diagnostic reports: \(error)", category: Logger.app)
            diagnosticsCount = 0
            diagnosticsExportURL = nil
        }
    }
}

#Preview {
    SettingsView()
}
