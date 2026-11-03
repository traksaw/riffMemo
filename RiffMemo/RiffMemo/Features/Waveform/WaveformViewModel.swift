//
//  WaveformViewModel.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation
import OSLog

/// ViewModel for managing waveform data loading and caching
@MainActor
@Observable
class WaveformViewModel {

    // MARK: - Published State

    var samples: [Float] = []
    var isLoading: Bool = false
    var loadError: String?

    // MARK: - Dependencies

    private let waveformGenerator: any WaveformGeneratorProtocol
    private let recording: Recording

    // MARK: - Configuration

    private let targetSamples: Int

    // MARK: - Initialization

    init(
        recording: Recording,
        waveformGenerator: any WaveformGeneratorProtocol = WaveformGenerator(),
        targetSamples: Int = 300
    ) {
        self.recording = recording
        self.waveformGenerator = waveformGenerator
        self.targetSamples = targetSamples
    }

    // MARK: - Public Methods

    /// Loads waveform data for the recording
    /// Uses three-tier caching: memory -> SwiftData -> regenerate
    func loadWaveform() async {
        // Tier 1: Check if already loaded in memory
        if !samples.isEmpty {
            Logger.audio.info("Waveform already loaded in memory")
            return
        }

        isLoading = true
        loadError = nil

        do {
            // Tier 2: Check if waveform is cached in SwiftData
            if let cachedData = recording.waveformData {
                Logger.audio.info("Loading cached waveform from database")
                samples = await waveformGenerator.decodeWaveform(from: cachedData)
                isLoading = false
                return
            }

            // Tier 3: Generate new waveform
            Logger.audio.info("Generating new waveform for recording")
            let generatedSamples = try await waveformGenerator.generateWaveform(
                from: recording.audioFileURL,
                targetSamples: targetSamples
            )

            // Cache the waveform data
            let waveformData = try await waveformGenerator.generateWaveformData(
                from: recording.audioFileURL,
                targetSamples: targetSamples
            )
            recording.waveformData = waveformData

            samples = generatedSamples
            isLoading = false

            Logger.audio.info("Waveform generated and cached")

        } catch {
            loadError = "Failed to load waveform: \(error.localizedDescription)"
            isLoading = false
            Logger.audio.error("Failed to load waveform: [\(error.logCode, privacy: .public)] \(error)")
        }
    }

    /// Clears the cached waveform data
    func clearCache() {
        samples = []
        recording.waveformData = nil
        Logger.audio.info("Waveform cache cleared")
    }

    /// Regenerates the waveform from scratch
    func regenerate() async {
        clearCache()
        await loadWaveform()
    }
}
