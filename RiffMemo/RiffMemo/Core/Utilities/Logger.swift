//
//  Logger.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import OSLog

/// Centralized logging utility
enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.traksaw.RiffMemo"

    static let app = OSLog(subsystem: subsystem, category: "App")
    static let audio = OSLog(subsystem: subsystem, category: "Audio")
    static let data = OSLog(subsystem: subsystem, category: "Data")
    static let ui = OSLog(subsystem: subsystem, category: "UI")

    /// Log info message
    static func info(_ message: String, category: OSLog = Logger.app) {
        os_log(.info, log: category, "%{public}@", message)
    }

    /// Log error message
    static func error(_ message: String, category: OSLog = Logger.app) {
        os_log(.error, log: category, "%{public}@", message)
    }

    /// Log debug message
    static func debug(_ message: String, category: OSLog = Logger.app) {
        os_log(.debug, log: category, "%{public}@", message)
    }
}
