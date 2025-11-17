//
//  RecordingTimerView.swift
//  RiffMemo
//
//  Timer display with milliseconds for recording
//

import SwiftUI

struct RecordingTimerView: View {
    let duration: TimeInterval
    let showMilliseconds: Bool
    let isRecording: Bool

    init(duration: TimeInterval, showMilliseconds: Bool = true, isRecording: Bool = false) {
        self.duration = duration
        self.showMilliseconds = showMilliseconds
        self.isRecording = isRecording
    }

    var body: some View {
        Text(formattedTime)
            .font(.system(size: 42, weight: .light, design: .default))
            .monospacedDigit()
            .foregroundColor(isRecording ? .red : .primary)
    }

    private var formattedTime: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)

        if showMilliseconds {
            return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
