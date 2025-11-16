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

    init(viewModel: RecordingViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Duration Display
            Text(viewModel.currentDuration.formattedDuration())
                .font(.system(size: 60, weight: .thin, design: .monospaced))
                .foregroundColor(.primary)

            // Audio Level Indicator
            AudioLevelBar(level: viewModel.audioLevel)
                .frame(height: 8)
                .padding(.horizontal, 40)

            Spacer()

            // Record Button
            Button(action: {
                viewModel.toggleRecording()
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
