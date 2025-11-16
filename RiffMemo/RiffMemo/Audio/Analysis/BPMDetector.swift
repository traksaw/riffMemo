//
//  BPMDetector.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import Accelerate

/// Detects tempo (BPM) using autocorrelation and onset detection
actor BPMDetector {

    // MARK: - Configuration

    private let minBPM: Double = 60
    private let maxBPM: Double = 180
    private let hopSize: Int = 512
    private let frameSize: Int = 2048

    // MARK: - Public Methods

    /// Detects BPM from an audio file
    /// - Parameter url: URL of the audio file
    /// - Returns: Detected BPM value, or nil if detection failed
    func detectBPM(from url: URL) async throws -> Int? {
        Logger.info("Detecting BPM from \(url.lastPathComponent)", category: Logger.audio)

        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw BPMError.emptyFile
        }

        // Read audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw BPMError.bufferAllocationFailed
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw BPMError.noChannelData
        }

        // Extract samples from first channel
        let samples = extractSamples(from: channelData[0], frameCount: Int(buffer.frameLength))

        // Calculate onset strength envelope
        let onsetEnvelope = calculateOnsetEnvelope(samples: samples, sampleRate: format.sampleRate)

        // Detect tempo using autocorrelation
        let bpm = detectTempoFromOnsets(
            onsetEnvelope: onsetEnvelope,
            sampleRate: format.sampleRate
        )

        Logger.info("Detected BPM: \(bpm ?? 0)", category: Logger.audio)

        return bpm
    }

    // MARK: - Private Methods

    private func extractSamples(from channelData: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = channelData[i]
        }
        return samples
    }

    /// Calculates onset strength envelope using spectral flux
    private func calculateOnsetEnvelope(samples: [Float], sampleRate: Double) -> [Float] {
        let numFrames = (samples.count - frameSize) / hopSize

        var onsetStrength = [Float](repeating: 0, count: numFrames)
        var previousMagnitudes = [Float](repeating: 0, count: frameSize / 2)

        // Setup FFT
        guard let fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(frameSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            return onsetStrength
        }

        defer { vDSP_DFT_DestroySetup(fftSetup) }

        for frameIndex in 0..<numFrames {
            let startIndex = frameIndex * hopSize
            let endIndex = min(startIndex + frameSize, samples.count)

            // Extract frame
            var frame = Array(samples[startIndex..<endIndex])
            if frame.count < frameSize {
                frame.append(contentsOf: [Float](repeating: 0, count: frameSize - frame.count))
            }

            // Apply Hanning window
            applyHanningWindow(&frame)

            // Perform FFT
            let magnitudes = performFFT(frame, setup: fftSetup)

            // Calculate spectral flux (difference from previous frame)
            var flux: Float = 0
            for i in 0..<magnitudes.count {
                let diff = max(0, magnitudes[i] - previousMagnitudes[i])
                flux += diff * diff
            }

            onsetStrength[frameIndex] = sqrt(flux)
            previousMagnitudes = magnitudes
        }

        // Normalize onset strength
        normalizeArray(&onsetStrength)

        return onsetStrength
    }

    /// Applies Hanning window to reduce spectral leakage
    private func applyHanningWindow(_ samples: inout [Float]) {
        let count = samples.count
        var window = [Float](repeating: 0, count: count)

        // Generate Hanning window
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))

        // Apply window
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(count))
    }

    /// Performs FFT and returns magnitude spectrum
    private func performFFT(_ samples: [Float], setup: OpaquePointer) -> [Float] {
        let count = samples.count
        let halfCount = count / 2

        // Prepare input/output buffers
        var realIn = [Float](repeating: 0, count: count)
        var imagIn = [Float](repeating: 0, count: count)
        var realOut = [Float](repeating: 0, count: count)
        var imagOut = [Float](repeating: 0, count: count)

        // Copy samples to real input
        realIn = samples

        // Perform DFT
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: halfCount)
        for i in 0..<halfCount {
            magnitudes[i] = sqrt(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        return magnitudes
    }

    /// Detects tempo from onset envelope using autocorrelation
    private func detectTempoFromOnsets(onsetEnvelope: [Float], sampleRate: Double) -> Int? {
        let hopDuration = Double(hopSize) / sampleRate

        // Convert BPM range to lag range (in frames)
        let minLag = Int(60.0 / (maxBPM * hopDuration))
        let maxLag = Int(60.0 / (minBPM * hopDuration))

        guard maxLag < onsetEnvelope.count else {
            return nil
        }

        // Calculate autocorrelation
        var autocorr = [Float](repeating: 0, count: maxLag - minLag)

        for lag in minLag..<maxLag {
            var sum: Float = 0
            for i in 0..<(onsetEnvelope.count - lag) {
                sum += onsetEnvelope[i] * onsetEnvelope[i + lag]
            }
            autocorr[lag - minLag] = sum
        }

        // Find peak in autocorrelation
        guard let maxIndex = autocorr.indices.max(by: { autocorr[$0] < autocorr[$1] }) else {
            return nil
        }

        let peakLag = maxIndex + minLag
        let bpm = 60.0 / (Double(peakLag) * hopDuration)

        // Round to nearest integer
        return Int(round(bpm))
    }

    /// Normalizes array to 0-1 range
    private func normalizeArray(_ array: inout [Float]) {
        var max: Float = 0
        vDSP_maxv(array, 1, &max, vDSP_Length(array.count))

        guard max > 0 else { return }

        var divisor = max
        vDSP_vsdiv(array, 1, &divisor, &array, 1, vDSP_Length(array.count))
    }
}

// MARK: - BPM Error

enum BPMError: LocalizedError {
    case emptyFile
    case bufferAllocationFailed
    case noChannelData

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "Audio file is empty"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .noChannelData:
            return "No channel data available"
        }
    }
}
