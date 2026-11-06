//
//  MainTabView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    let modelContainer: ModelContainer

    var body: some View {
        TabView {
            // Recording Tab
            RecordingView(
                viewModel: RecordingViewModel(
                    audioRecorder: AudioRecordingManager(),
                    repository: SwiftDataRecordingRepository(
                        modelContext: modelContainer.mainContext
                    )
                )
            )
            .tabItem {
                Label("Record", systemImage: "mic.fill")
            }

            // Library Tab
            LibraryView(
                viewModel: LibraryViewModel(
                    repository: SwiftDataRecordingRepository(
                        modelContext: modelContainer.mainContext
                    )
                )
            )
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }

            // Tuner Tab
            TunerView()
                .tabItem {
                    Label("Tuner", systemImage: "tuningfork")
                }

            // Metronome Tab
            MetronomeView()
                .tabItem {
                    Label("Metronome", systemImage: "metronome")
                }

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            // WAS-118: a take cut off by an app kill becomes a saved take again.
            await OrphanTakeRecovery.recoverOnLaunch(modelContainer: modelContainer)
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Recording.self)
    return MainTabView(modelContainer: container)
}
