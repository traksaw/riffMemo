//
//  PitchDetector.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

/// Real-time pitch detection for tuner functionality
@MainActor
class PitchDetector: ObservableObject {

    // MARK: - Published Properties

    @Published var frequency: Double = 0.0
    @Published var note: String = ""
    @Published var cents: Double = 0.0
    @Published var isDetecting = false

    // MARK: - Configuration

    private let bufferSize: AVAudioFrameCount = 4096
    private let a4Frequency: Double = 440.0
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Audio Components

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // MARK: - Public Methods

    func startDetection() async throws {
        guard !isDetecting else { return }

        // Setup audio session
        try setupAudioSession()

        // Setup audio engine
        try setupAudioEngine()

        isDetecting = true
        Logger.info("Pitch detection started", category: Logger.audio)
    }

    func stopDetection() async {
        guard isDetecting else { return }

        // Remove tap
        inputNode?.removeTap(onBus: 0)

        // Stop engine
        audioEngine?.stop()

        isDetecting = false
        frequency = 0.0
        note = ""
        cents = 0.0

        Logger.info("Pitch detection stopped", category: Logger.audio)
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Install tap for real-time processing
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processBuffer(buffer, sampleRate: format.sampleRate)
        }

        try engine.start()

        self.audioEngine = engine
        self.inputNode = inputNode
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let samples = extractSamples(from: channelData[0], count: frameLength)

        // Detect pitch using autocorrelation
        if let detectedFreq = detectPitch(samples: samples, sampleRate: sampleRate) {
            Task { @MainActor in
                self.frequency = detectedFreq
                self.updateNoteAndCents(from: detectedFreq)
            }
        }
    }

    private func extractSamples(from channelData: UnsafeMutablePointer<Float>, count: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = channelData[i]
        }
        return samples
    }

    /// Detects pitch using autocorrelation
    private func detectPitch(samples: [Float], sampleRate: Double) -> Double? {
        let minFreq: Double = 80.0  // ~E2
        let maxFreq: Double = 1200.0 // ~D6

        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = Int(sampleRate / minFreq)

        guard maxPeriod < samples.count else { return nil }

        // Calculate autocorrelation
        var maxCorr: Float = 0
        var bestPeriod = minPeriod

        for period in minPeriod...maxPeriod {
            var corr: Float = 0
            for i in 0..<(samples.count - period) {
                corr += samples[i] * samples[i + period]
            }

            if corr > maxCorr {
                maxCorr = corr
                bestPeriod = period
            }
        }

        // Check if correlation is strong enough
        guard maxCorr > 0.1 else { return nil }

        // Refine using parabolic interpolation
        let refinedPeriod = refineWithParabolicInterpolation(
            period: bestPeriod,
            samples: samples,
            minPeriod: minPeriod,
            maxPeriod: maxPeriod
        )

        let frequency = sampleRate / Double(refinedPeriod)

        // Filter out unrealistic frequencies
        guard frequency >= minFreq && frequency <= maxFreq else { return nil }

        return frequency
    }

    /// Parabolic interpolation for sub-sample accuracy
    private func refineWithParabolicInterpolation(
        period: Int,
        samples: [Float],
        minPeriod: Int,
        maxPeriod: Int
    ) -> Double {
        guard period > minPeriod && period < maxPeriod else {
            return Double(period)
        }

        // Calculate autocorrelation for neighboring periods
        let periods = [period - 1, period, period + 1]
        var correlations: [Float] = []

        for p in periods {
            var corr: Float = 0
            for i in 0..<(samples.count - p) {
                corr += samples[i] * samples[i + p]
            }
            correlations.append(corr)
        }

        // Parabolic interpolation
        let alpha = correlations[0]
        let beta = correlations[1]
        let gamma = correlations[2]

        let offset = 0.5 * (alpha - gamma) / (alpha - 2 * beta + gamma)

        return Double(period) + Double(offset)
    }

    /// Updates note name and cents deviation from detected frequency
    private func updateNoteAndCents(from frequency: Double) {
        // Calculate number of semitones from A4 (440 Hz)
        let semitones = 12 * log2(frequency / a4Frequency)

        // Find nearest note
        let nearestNote = round(semitones)
        let noteIndex = (Int(nearestNote) + 9 + 120) % 12  // +9 because A is index 9

        // Calculate cents deviation (-50 to +50)
        let centsDeviation = (semitones - nearestNote) * 100

        self.note = noteNames[noteIndex]
        self.cents = centsDeviation
    }
}
