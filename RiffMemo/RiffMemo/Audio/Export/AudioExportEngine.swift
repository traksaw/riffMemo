//
//  AudioExportEngine.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation

/// Handles audio export with format conversion and quality settings
actor AudioExportEngine {

    // MARK: - Public Methods

    /// Exports an audio file to a different format
    /// - Parameters:
    ///   - sourceURL: URL of the source audio file
    ///   - settings: Export settings (format, quality, metadata)
    /// - Returns: URL of the exported file
    func export(
        from sourceURL: URL,
        settings: ExportSettings
    ) async throws -> URL {
        Logger.info("Exporting audio: \(sourceURL.lastPathComponent) to \(settings.format.rawValue)", category: Logger.audio)

        // Create destination URL
        let destinationURL = try createDestinationURL(for: settings.format, basedOn: sourceURL)

        // Check if format conversion is needed
        if settings.format == .caf {
            // No conversion needed, just copy
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            Logger.info("Copied original file (no conversion needed)", category: Logger.audio)
            return destinationURL
        }

        // Use AVAudioFile for audio format conversion (more reliable than AVAssetExportSession)
        return try await convertAudioFile(
            from: sourceURL,
            to: destinationURL,
            format: settings.format,
            settings: settings
        )
    }

    /// Converts audio file using AVAssetReader/AVAssetWriter for maximum compatibility
    private func convertAudioFile(
        from sourceURL: URL,
        to destinationURL: URL,
        format: AudioFormat,
        settings: ExportSettings
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    // Load source asset
                    let asset = AVURLAsset(url: sourceURL)

                    // Verify asset has audio tracks
                    guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                        throw ExportError.exportSessionFailed
                    }

                    // Create asset reader
                    let reader = try AVAssetReader(asset: asset)

                    // Configure audio output settings for reader (decompress to PCM)
                    let readerOutputSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMIsFloatKey: true,
                        AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]

                    let readerOutput = AVAssetReaderTrackOutput(
                        track: audioTrack,
                        outputSettings: readerOutputSettings
                    )
                    reader.add(readerOutput)

                    // Create asset writer
                    let writer = try AVAssetWriter(outputURL: destinationURL, fileType: format.avFileType)

                    // Configure writer input settings based on target format
                    let writerSettings = createOutputSettings(for: format)

                    let writerInput = AVAssetWriterInput(
                        mediaType: .audio,
                        outputSettings: writerSettings
                    )
                    writerInput.expectsMediaDataInRealTime = false
                    writer.add(writerInput)

                    // Start reading and writing
                    reader.startReading()
                    writer.startWriting()
                    writer.startSession(atSourceTime: .zero)

                    // Create dispatch queue for async processing
                    let processingQueue = DispatchQueue(label: "audio.export.processing")

                    await withCheckedContinuation { innerContinuation in
                        writerInput.requestMediaDataWhenReady(on: processingQueue) {
                            while writerInput.isReadyForMoreMediaData {
                                if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                                    writerInput.append(sampleBuffer)
                                } else {
                                    // Finished reading
                                    writerInput.markAsFinished()
                                    innerContinuation.resume()
                                    break
                                }
                            }
                        }
                    }

                    // Finish writing
                    await writer.finishWriting()

                    if writer.status == .completed {
                        Logger.info("Export complete: \(destinationURL.lastPathComponent)", category: Logger.audio)
                        continuation.resume(returning: destinationURL)
                    } else if let error = writer.error {
                        Logger.error("Writer failed: \(error)", category: Logger.audio)
                        continuation.resume(throwing: ExportError.exportFailed(error))
                    } else {
                        continuation.resume(throwing: ExportError.exportIncomplete)
                    }

                } catch {
                    Logger.error("Audio conversion failed: \(error)", category: Logger.audio)
                    continuation.resume(throwing: ExportError.exportFailed(error))
                }
            }
        }
    }

    /// Creates output settings dictionary for the specified format
    private func createOutputSettings(for format: AudioFormat) -> [String: Any] {
        var settings: [String: Any] = [:]

        switch format {
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVSampleRateKey] = 44100.0
            settings[AVNumberOfChannelsKey] = 2
            settings[AVEncoderBitRateKey] = 256000 // 256 kbps

        case .wav:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVSampleRateKey] = 44100.0
            settings[AVNumberOfChannelsKey] = 2
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false

        case .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVSampleRateKey] = 44100.0
            settings[AVNumberOfChannelsKey] = 2
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = true

        case .caf:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVSampleRateKey] = 44100.0
            settings[AVNumberOfChannelsKey] = 2
        }

        return settings
    }

    /// Exports multiple recordings in batch
    /// - Parameters:
    ///   - recordings: Array of recordings to export
    ///   - settings: Export settings
    ///   - onProgress: Progress callback
    /// - Returns: Array of exported file URLs
    func batchExport(
        recordings: [Recording],
        settings: ExportSettings,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> [URL] {
        var exportedURLs: [URL] = []

        for (index, recording) in recordings.enumerated() {
            do {
                let url = try await export(from: recording.audioFileURL, settings: settings)
                exportedURLs.append(url)

                // Update progress
                let progress = Double(index + 1) / Double(recordings.count)
                onProgress?(progress)

            } catch {
                Logger.error("Failed to export \(recording.title): \(error)", category: Logger.audio)
                throw error
            }
        }

        return exportedURLs
    }

    // MARK: - Private Methods

    private func createDestinationURL(for format: AudioFormat, basedOn sourceURL: URL) throws -> URL {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)

        // Create exports directory if needed
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        // Generate unique filename
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Date().timeIntervalSince1970
        let filename = "\(baseName)_\(Int(timestamp)).\(format.fileExtension)"

        return exportDirectory.appendingPathComponent(filename)
    }

    private func createAVMetadata(from metadata: ExportMetadata) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        // Title
        if let title = metadata.title {
            let item = createMetadataItem(
                identifier: .commonIdentifierTitle,
                value: title as NSString
            )
            items.append(item)
        }

        // Artist
        if let artist = metadata.artist {
            let item = createMetadataItem(
                identifier: .commonIdentifierArtist,
                value: artist as NSString
            )
            items.append(item)
        }

        // Album
        if let album = metadata.album {
            let item = createMetadataItem(
                identifier: .commonIdentifierAlbumName,
                value: album as NSString
            )
            items.append(item)
        }

        // Date
        if let date = metadata.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = formatter.string(from: date)
            let item = createMetadataItem(
                identifier: .commonIdentifierCreationDate,
                value: dateString as NSString
            )
            items.append(item)
        }

        // BPM
        if let bpm = metadata.bpm {
            let item = createMetadataItem(
                identifier: .iTunesMetadataBeatsPerMin,
                value: bpm as NSNumber
            )
            items.append(item)
        }

        // Key (stored in comment field as initial key is not standard)
        if let key = metadata.key {
            let item = createMetadataItem(
                identifier: .commonIdentifierDescription,
                value: "Key: \(key)" as NSString
            )
            items.append(item)
        }

        return items
    }

    private func createMetadataItem(
        identifier: AVMetadataIdentifier,
        value: NSCopying & NSObjectProtocol
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        return item
    }
}

// MARK: - Export Settings

struct ExportSettings {
    var format: AudioFormat
    var quality: ExportQuality
    var includeMetadata: Bool
    var metadata: ExportMetadata?

    static let `default` = ExportSettings(
        format: .m4a,
        quality: .high,
        includeMetadata: true,
        metadata: nil
    )
}

// MARK: - Audio Format

enum AudioFormat: String, CaseIterable {
    case caf = "CAF"
    case m4a = "M4A"
    case wav = "WAV"
    case aiff = "AIFF"

    var fileExtension: String {
        switch self {
        case .caf: return "caf"
        case .m4a: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .caf: return .caf
        case .m4a: return .m4a
        case .wav: return .wav
        case .aiff: return .aiff
        }
    }

    var displayName: String {
        rawValue
    }
}

// MARK: - Export Quality

enum ExportQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case lossless = "Lossless"

    func avPreset(for format: AudioFormat) -> String {
        // For M4A, use Apple M4A preset for better compatibility
        if format == .m4a {
            switch self {
            case .low, .medium: return AVAssetExportPresetAppleM4A
            case .high, .lossless: return AVAssetExportPresetAppleM4A
            }
        }

        // For WAV, AIFF, and CAF (lossless formats), always use passthrough
        if format == .wav || format == .aiff || format == .caf {
            return AVAssetExportPresetPassthrough
        }

        // Fallback to passthrough
        return AVAssetExportPresetPassthrough
    }

    var avPreset: String {
        // Legacy compatibility - defaults to passthrough
        return AVAssetExportPresetPassthrough
    }

    var bitrate: Int {
        switch self {
        case .low: return 64000      // 64 kbps
        case .medium: return 128000   // 128 kbps
        case .high: return 256000     // 256 kbps
        case .lossless: return 0      // No compression
        }
    }
}

// MARK: - Export Metadata

struct ExportMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var date: Date?
    var bpm: Int?
    var key: String?

    static func from(_ recording: Recording) -> ExportMetadata {
        ExportMetadata(
            title: recording.title,
            artist: "RiffMemo",
            album: nil,
            date: recording.createdDate,
            bpm: recording.detectedBPM,
            key: recording.detectedKey
        )
    }
}

// MARK: - Export Error

enum ExportError: LocalizedError {
    case exportSessionFailed
    case exportFailed(Error)
    case exportIncomplete
    case invalidSourceFile

    var errorDescription: String? {
        switch self {
        case .exportSessionFailed:
            return "Failed to create export session"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        case .exportIncomplete:
            return "Export did not complete successfully"
        case .invalidSourceFile:
            return "Source audio file is invalid"
        }
    }
}
