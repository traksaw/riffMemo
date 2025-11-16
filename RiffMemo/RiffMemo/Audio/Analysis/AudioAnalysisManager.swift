//
//  AudioAnalysisManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation

/// Coordinates all audio analysis operations with background queue processing
@MainActor
@Observable
class AudioAnalysisManager {

    // MARK: - Published State

    var isAnalyzing: Bool = false
    var analysisProgress: Double = 0
    var currentlyAnalyzing: String?

    // MARK: - Dependencies

    private let bpmDetector = BPMDetector()
    private let keyDetector = KeyDetector()
    private let qualityAnalyzer = AudioQualityAnalyzer()

    // Analysis queue
    private var analysisQueue: [Recording] = []
    private var isProcessingQueue = false

    // MARK: - Singleton

    static let shared = AudioAnalysisManager()

    private init() {}

    // MARK: - Public Methods

    /// Performs full analysis on a recording
    /// - Parameters:
    ///   - recording: The recording to analyze
    ///   - options: Analysis options (which analyses to perform)
    /// - Returns: Complete analysis results
    func analyzeRecording(
        _ recording: Recording,
        options: AnalysisOptions = .all
    ) async -> AnalysisResults {
        Logger.info("Starting analysis for: \(recording.title)", category: Logger.audio)

        isAnalyzing = true
        currentlyAnalyzing = recording.title
        analysisProgress = 0

        var results = AnalysisResults()

        // BPM Detection
        if options.contains(.bpm) {
            analysisProgress = 0.1
            do {
                results.bpm = try await bpmDetector.detectBPM(from: recording.audioFileURL)
                Logger.info("BPM detected: \(results.bpm ?? 0)", category: Logger.audio)
            } catch {
                Logger.error("BPM detection failed: \(error)", category: Logger.audio)
            }
        }

        // Key Detection
        if options.contains(.key) {
            analysisProgress = 0.4
            do {
                results.key = try await keyDetector.detectKey(from: recording.audioFileURL)
                Logger.info("Key detected: \(results.key ?? "Unknown")", category: Logger.audio)
            } catch {
                Logger.error("Key detection failed: \(error)", category: Logger.audio)
            }
        }

        // Quality Analysis
        if options.contains(.quality) {
            analysisProgress = 0.7
            do {
                results.quality = try await qualityAnalyzer.analyze(from: recording.audioFileURL)
                Logger.info("Quality: \(results.quality?.quality.rawValue ?? "Unknown")", category: Logger.audio)
            } catch {
                Logger.error("Quality analysis failed: \(error)", category: Logger.audio)
            }
        }

        analysisProgress = 1.0

        // Update recording with results
        if let bpm = results.bpm {
            recording.detectedBPM = bpm
        }

        if let key = results.key {
            recording.detectedKey = key
        }

        if let quality = results.quality {
            recording.audioQuality = quality.quality.rawValue
            recording.peakLevel = quality.peakLevel
            recording.rmsLevel = quality.rmsLevel
            recording.dynamicRange = quality.dynamicRange
        }

        recording.lastAnalyzedDate = Date()

        isAnalyzing = false
        currentlyAnalyzing = nil
        analysisProgress = 0

        Logger.info("Analysis complete for: \(recording.title)", category: Logger.audio)

        return results
    }

    // MARK: - Queue Management

    /// Adds a recording to the analysis queue
    func queueAnalysis(_ recording: Recording, options: AnalysisOptions = .all) {
        analysisQueue.append(recording)
        Logger.info("Queued analysis for: \(recording.title)", category: Logger.audio)

        if !isProcessingQueue {
            Task {
                await processQueue(options: options)
            }
        }
    }

    /// Adds multiple recordings to the analysis queue
    func queueBatchAnalysis(_ recordings: [Recording], options: AnalysisOptions = .all) {
        analysisQueue.append(contentsOf: recordings)
        Logger.info("Queued \(recordings.count) recordings for analysis", category: Logger.audio)

        if !isProcessingQueue {
            Task {
                await processQueue(options: options)
            }
        }
    }

    /// Processes the analysis queue in the background
    private func processQueue(options: AnalysisOptions) async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true

        while !analysisQueue.isEmpty {
            let recording = analysisQueue.removeFirst()

            // Check if already analyzed
            if recording.lastAnalyzedDate != nil {
                Logger.info("Skipping already analyzed: \(recording.title)", category: Logger.audio)
                continue
            }

            _ = await analyzeRecording(recording, options: options)

            // Small delay to keep UI responsive
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        isProcessingQueue = false
        Logger.info("Analysis queue complete", category: Logger.audio)
    }

    /// Clears the analysis queue
    func clearQueue() {
        analysisQueue.removeAll()
        Logger.info("Analysis queue cleared", category: Logger.audio)
    }

    /// Returns the number of recordings waiting in the queue
    var queueCount: Int {
        analysisQueue.count
    }
}

// MARK: - Analysis Options

struct AnalysisOptions: OptionSet {
    let rawValue: Int

    static let bpm = AnalysisOptions(rawValue: 1 << 0)
    static let key = AnalysisOptions(rawValue: 1 << 1)
    static let quality = AnalysisOptions(rawValue: 1 << 2)

    static let all: AnalysisOptions = [.bpm, .key, .quality]
}

// MARK: - Analysis Results

struct AnalysisResults {
    var bpm: Int?
    var key: String?
    var quality: AudioQualityMetrics?

    var hasResults: Bool {
        bpm != nil || key != nil || quality != nil
    }
}
