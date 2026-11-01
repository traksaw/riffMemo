//
//  AudioRecovery.swift
//  RiffMemo
//

import Foundation
import UniformTypeIdentifiers

/// WAS-121: finds the raw audio files on disk so they can be exported even when the
/// SwiftData store can't be opened. Audio lives as plain files in Documents (see
/// `AudioRecordingManager` / `Recording.audioFileURL`), independent of the store,
/// so this deliberately does not consult `Recording` rows at all.
enum AudioRecovery {
    static var defaultAudioDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Every audio file directly inside `directory`, sorted by name.
    static func audioFiles(in directory: URL = defaultAudioDirectory) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { url in
                let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                let isAudio = UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
                return isRegularFile && isAudio
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
