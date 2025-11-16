//
//  TimeInterval+Extensions.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation

extension TimeInterval {
    /// Format duration as MM:SS for display
    func formattedDuration() -> String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Format duration as HH:MM:SS for longer recordings
    func formattedLongDuration() -> String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
