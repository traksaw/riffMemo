//
//  OrphanTakeRecovery.swift
//  RiffMemo
//

import AVFoundation
import Foundation
import OSLog
import SwiftData

/// WAS-118: turns audio files that no `Recording` row names back into saved takes.
///
/// A take gets its row only when the user stops it. If iOS kills the app mid-take (memory
/// pressure, a force quit, a crash), the file is on disk with every second recorded up to
/// the kill, but nothing in the library points at it. This runs once per launch and saves
/// each such file as a take, so the musician finds it in the library instead of losing it.
///
/// Deletes move a take's file out of Documents before the row goes (see
/// `SwiftDataRecordingRepository.delete`), so a deleted take never comes back here.
enum OrphanTakeRecovery {

    static let recoveredTitle = "Recovered Recording"

    private static var hasRunThisLaunch = false

    /// The files in `audioFiles` that no row names.
    nonisolated static func orphans(in audioFiles: [URL], knownFilenames: Set<String>) -> [URL] {
        audioFiles.filter { !knownFilenames.contains($0.lastPathComponent) }
    }

    /// Recovers orphan takes once per launch, before the user can start a new take, then
    /// queues them for analysis like any other take.
    static func recoverOnLaunch(modelContainer: ModelContainer) async {
        guard !hasRunThisLaunch else { return }
        hasRunThisLaunch = true

        let repository = SwiftDataRecordingRepository(modelContext: modelContainer.mainContext)
        for take in await recover(repository: repository) {
            AudioAnalysisManager.shared.queueAnalysis(take)
        }
    }

    /// Saves each orphan in `audioDirectory` as an interrupted take and returns them.
    ///
    /// - An orphan with no audio in it (a kill right after Record) is removed.
    /// - An orphan that is not readable audio stays on disk. The WAS-121 audio export can
    ///   still reach it, and deleting it could lose a take.
    /// - If the library cannot be read, nothing happens: every file would look like an orphan.
    @discardableResult
    static func recover(
        audioDirectory: URL = AudioRecovery.defaultAudioDirectory,
        repository: any RecordingRepository
    ) async -> [Recording] {
        let files: [URL]
        let knownFilenames: Set<String>
        do {
            files = try AudioRecovery.audioFiles(in: audioDirectory)
            knownFilenames = Set(try await repository.fetchAll().map(\.audioFilename))
        } catch {
            Logger.data.error("Orphan take check skipped: [\(error.logCode, privacy: .public)] \(error)")
            return []
        }

        var recovered: [Recording] = []
        for url in orphans(in: files, knownFilenames: knownFilenames) {
            guard let audio = try? AVAudioFile(forReading: url) else {
                Logger.data.error("Orphan take is not readable audio, kept on disk: \(url.lastPathComponent)")
                continue
            }

            guard audio.length > 0 else {
                try? FileManager.default.removeItem(at: url)
                Logger.data.info("Removed an empty orphan take: \(url.lastPathComponent)")
                continue
            }

            let sampleRate = audio.fileFormat.sampleRate
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let take = Recording(
                title: recoveredTitle,
                createdDate: values?.creationDate ?? Date(),
                duration: Double(audio.length) / sampleRate,
                audioFileURL: url,
                fileSize: Int64(values?.fileSize ?? 0),
                sampleRate: sampleRate,
                wasInterrupted: true
            )

            do {
                try await repository.save(take)
                recovered.append(take)
                Logger.data.info("Recovered an orphan take: \(url.lastPathComponent), \(take.duration)s")
            } catch {
                Logger.data.error("Could not save a recovered take: [\(error.logCode, privacy: .public)] \(error)")
            }
        }
        return recovered
    }
}
