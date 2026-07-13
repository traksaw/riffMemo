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

    /// Minimum average per-sample energy (mean of squared samples, ~-60dBFS RMS) required
    /// before attempting pitch detection at all — see the noise-floor comment in detectPitch(_:sampleRate:).
    private static let minimumAverageEnergy: Float = 1e-6

    // MARK: - Audio Components

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // Reused across tap callbacks so the render thread doesn't allocate a new array every buffer.
    // `nonisolated(unsafe)`: written from processBuffer(_:sampleRate:), which — like the rest of
    // this class's tap-driven path — runs synchronously on Core Audio's real-time thread, not
    // hopped onto the MainActor. Matches the same documented pattern used for the render-thread
    // callback properties in AudioRecordingManager. Safe because Core Audio serializes tap
    // callbacks (never concurrent), so there is exactly one writer at a time.
    private nonisolated(unsafe) var sampleBuffer: [Float] = []

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
        fillSampleBuffer(from: channelData[0], count: frameLength)

        // Detect pitch using autocorrelation
        if let detectedFreq = Self.detectPitch(samples: sampleBuffer, sampleRate: sampleRate) {
            Task { @MainActor in
                self.frequency = detectedFreq
                self.updateNoteAndCents(from: detectedFreq)
            }
        }
    }

    /// Copies `count` samples into the reusable `sampleBuffer`, resizing only when the
    /// incoming frame count changes (normally constant across callbacks for a given tap).
    private func fillSampleBuffer(from channelData: UnsafeMutablePointer<Float>, count: Int) {
        if sampleBuffer.count != count {
            sampleBuffer = [Float](repeating: 0, count: count)
        }
        sampleBuffer.withUnsafeMutableBufferPointer { destination in
            destination.baseAddress?.update(from: channelData, count: count)
        }
    }

    /// Detects pitch using autocorrelation. A pure function of its arguments (touches no
    /// instance state) — kept `static` so it's testable without allocating/deallocating a
    /// full `@MainActor` `PitchDetector` instance.
    static func detectPitch(samples: [Float], sampleRate: Double) -> Double? {
        let minFreq: Double = 80.0  // ~E2
        let maxFreq: Double = 1200.0 // ~D6

        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = Int(sampleRate / minFreq)

        guard maxPeriod < samples.count else { return nil }

        // Absolute noise floor. The correlation check below is normalized by the signal's own
        // energy specifically so its sensitivity is amplitude-independent (WAS-55) — but that
        // means it can no longer tell quiet real playing apart from silence/ambient mic noise
        // on its own, since normalizing divides out the very amplitude information a raw
        // threshold used to gate on. Require a minimum average per-sample energy first; digital
        // silence is exactly 0 and typical mic self-/room-noise sits well below this, chosen
        // conservatively so real playing (even quiet) still passes.
        var averageEnergy: Float = 0
        vDSP_svesq(samples, 1, &averageEnergy, vDSP_Length(samples.count))
        averageEnergy /= Float(samples.count)
        guard averageEnergy > PitchDetector.minimumAverageEnergy else { return nil }

        // Calculate autocorrelation. Vectorized (vDSP_dotpr) rather than a scalar Swift loop —
        // this runs on the real-time render thread for every buffer, same reasoning
        // AudioQualityAnalyzer already uses vDSP for its sum-of-squares work.
        var maxCorr: Float = 0
        var bestPeriod = minPeriod

        samples.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            for period in minPeriod...maxPeriod {
                var corr: Float = 0
                vDSP_dotpr(base, 1, base + period, 1, &corr, vDSP_Length(samples.count - period))

                if corr > maxCorr {
                    maxCorr = corr
                    bestPeriod = period
                }
            }
        }

        // Normalize by the combined energy of the two windows being correlated at bestPeriod
        // (NSDF-style: 2*corr / (energyA + energyB)), so the threshold is amplitude-independent
        // — otherwise a fixed 0.1 cutoff on the raw correlation sum makes sensitivity swing
        // with input loudness (quiet playing never crosses it, loud playing crosses it trivially).
        var energy: Float = 0
        samples.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            let windowCount = vDSP_Length(samples.count - bestPeriod)
            var energyA: Float = 0
            var energyB: Float = 0
            vDSP_svesq(base, 1, &energyA, windowCount)
            vDSP_svesq(base + bestPeriod, 1, &energyB, windowCount)
            energy = energyA + energyB
        }
        let normalizedCorr = energy > 0 ? (2 * maxCorr / energy) : 0

        // Check if correlation is strong enough
        guard normalizedCorr > 0.1 else { return nil }

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

    /// Parabolic interpolation for sub-sample accuracy. Also a pure function — see detectPitch(_:sampleRate:).
    static func refineWithParabolicInterpolation(
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

        samples.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            for p in periods {
                var corr: Float = 0
                vDSP_dotpr(base, 1, base + p, 1, &corr, vDSP_Length(samples.count - p))
                correlations.append(corr)
            }
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
