//
//  Date+Extensions.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation

extension Date {
    /// Format date for recording list display
    func formattedForRecording() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Format date for detail view
    func formattedDetailed() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
