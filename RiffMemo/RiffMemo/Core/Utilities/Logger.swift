//
//  Logger.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import OSLog

/// App log categories, as `os.Logger` instances.
///
/// Write interpolated values straight into the message so the system applies privacy per value:
///
///     Logger.audio.info("Saved \(recording.title) after \(duration)s")
///     // Console: "Saved <private> after 12.4s"
///
/// Defaults: strings and objects (titles, paths, URLs, errors) are private; numbers and Bools
/// are public. Add `privacy: .public` only to values that identify no person, song, or file,
/// such as counts, durations, states, and error codes.
///
/// `nonisolated`: `os.Logger` is thread-safe, so these work off the main actor too.
extension Logger {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "com.traksaw.riffmemo"

    nonisolated static let app = Logger(subsystem: subsystem, category: "App")
    nonisolated static let audio = Logger(subsystem: subsystem, category: "Audio")
    nonisolated static let data = Logger(subsystem: subsystem, category: "Data")
    nonisolated static let ui = Logger(subsystem: subsystem, category: "UI")
}
