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

    static var defaultStagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecoveryExport", isDirectory: true)
    }

    /// Prepares `files` for export under human-readable names. On disk takes are
    /// `recording_<UUID>.caf` and their titles live in the store that just failed to
    /// open, so the recording date is the best label left to tell takes apart.
    ///
    /// Each entry is a hard link where possible: it shares the original's bytes, so
    /// staging costs no extra space (a full disk is one reason the store fails to
    /// open). Falls back to a real copy if linking isn't possible. Originals are
    /// never moved or modified.
    static func stageForExport(
        _ files: [URL],
        in stagingDirectory: URL = defaultStagingDirectory,
        timeZone: TimeZone = .current
    ) throws -> [URL] {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        // Dots, not colons: colons aren't allowed in Files/Finder filenames.
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

        var usedNames = Set<String>()
        return try files.map { source in
            let values = try? source.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let baseName: String
            if let date = values?.creationDate ?? values?.contentModificationDate {
                baseName = "RiffMemo \(formatter.string(from: date))"
            } else {
                baseName = source.deletingPathExtension().lastPathComponent
            }

            let fileName = uniqueFileName(baseName, extension: source.pathExtension, avoiding: &usedNames)
            let destination = stagingDirectory.appendingPathComponent(fileName)
            do {
                try fileManager.linkItem(at: source, to: destination)
            } catch {
                try fileManager.copyItem(at: source, to: destination)
            }
            return destination
        }
    }

    /// Two takes recorded in the same second would otherwise collide; suffix with " (2)", " (3)"…
    private static func uniqueFileName(_ baseName: String, extension ext: String, avoiding usedNames: inout Set<String>) -> String {
        var candidate = "\(baseName).\(ext)"
        var counter = 2
        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(baseName) (\(counter)).\(ext)"
            counter += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }
}
