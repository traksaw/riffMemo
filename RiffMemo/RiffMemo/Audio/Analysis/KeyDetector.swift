//
//  KeyDetector.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import Accelerate

/// Detects musical key using pitch class profile and Krumhansl-Schmuckler algorithm
actor KeyDetector {

    // MARK: - Configuration

    private let frameSize: Int = 4096
    private let hopSize: Int = 2048
    private let a4Frequency: Double = 440.0

    // Krumhansl-Schmuckler key profiles
    private let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Public Methods

    /// Detects musical key from an audio file
    /// - Parameter url: URL of the audio file
    /// - Returns: Detected key (e.g., "C Major", "A Minor"), or nil if detection failed
    func detectKey(from url: URL) async throws -> String? {
        Logger.info("Detecting key from \(url.lastPathComponent)", category: Logger.audio)

        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw KeyDetectionError.emptyFile
        }

        // Read audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw KeyDetectionError.bufferAllocationFailed
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw KeyDetectionError.noChannelData
        }

        // Extract samples
        let samples = extractSamples(from: channelData[0], frameCount: Int(buffer.frameLength))

        // Calculate pitch class profile
        let pitchClassProfile = calculatePitchClassProfile(
            samples: samples,
            sampleRate: format.sampleRate
        )

        // Detect key using Krumhansl-Schmuckler algorithm
        let key = detectKeyFromProfile(pitchClassProfile)

        Logger.info("Detected key: \(key ?? "Unknown")", category: Logger.audio)

        return key
    }

    // MARK: - Private Methods

    private func extractSamples(from channelData: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = channelData[i]
        }
        return samples
    }

    /// Calculates pitch class profile (chromagram)
    private func calculatePitchClassProfile(samples: [Float], sampleRate: Double) -> [Double] {
        var pitchClasses = [Double](repeating: 0, count: 12)

        let numFrames = (samples.count - frameSize) / hopSize

        // Setup FFT
        guard let fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(frameSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            return pitchClasses
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

            // Map frequencies to pitch classes
            for (binIndex, magnitude) in magnitudes.enumerated() {
                let frequency = Double(binIndex) * sampleRate / Double(frameSize)

                // Skip DC and very low frequencies
                guard frequency > 60 else { continue }

                // Convert frequency to MIDI note
                let midiNote = 12 * log2(frequency / a4Frequency) + 69

                // Get pitch class (0-11, where 0 = C)
                let pitchClass = Int(round(midiNote)) % 12

                if pitchClass >= 0 && pitchClass < 12 {
                    pitchClasses[pitchClass] += Double(magnitude)
                }
            }
        }

        // Normalize pitch class profile
        let sum = pitchClasses.reduce(0, +)
        if sum > 0 {
            pitchClasses = pitchClasses.map { $0 / sum }
        }

        return pitchClasses
    }

    /// Applies Hanning window
    private func applyHanningWindow(_ samples: inout [Float]) {
        let count = samples.count
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(count))
    }

    /// Performs FFT and returns magnitude spectrum
    private func performFFT(_ samples: [Float], setup: OpaquePointer) -> [Float] {
        let count = samples.count
        let halfCount = count / 2

        var realIn = samples
        var imagIn = [Float](repeating: 0, count: count)
        var realOut = [Float](repeating: 0, count: count)
        var imagOut = [Float](repeating: 0, count: count)

        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        var magnitudes = [Float](repeating: 0, count: halfCount)
        for i in 0..<halfCount {
            magnitudes[i] = sqrt(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        return magnitudes
    }

    /// Detects key from pitch class profile using Krumhansl-Schmuckler algorithm
    private func detectKeyFromProfile(_ profile: [Double]) -> String? {
        var bestCorrelation = -Double.infinity
        var bestKey: String?

        // Test all 24 keys (12 major + 12 minor)
        for tonic in 0..<12 {
            // Test major key
            let majorCorr = calculateCorrelation(
                profile: rotateArray(profile, by: tonic),
                template: majorProfile
            )

            if majorCorr > bestCorrelation {
                bestCorrelation = majorCorr
                bestKey = "\(noteNames[tonic]) Major"
            }

            // Test minor key
            let minorCorr = calculateCorrelation(
                profile: rotateArray(profile, by: tonic),
                template: minorProfile
            )

            if minorCorr > bestCorrelation {
                bestCorrelation = minorCorr
                bestKey = "\(noteNames[tonic]) Minor"
            }
        }

        return bestKey
    }

    /// Calculates Pearson correlation coefficient
    private func calculateCorrelation(profile: [Double], template: [Double]) -> Double {
        guard profile.count == template.count else { return 0 }

        let n = Double(profile.count)

        let profileMean = profile.reduce(0, +) / n
        let templateMean = template.reduce(0, +) / n

        var numerator: Double = 0
        var profileSumSq: Double = 0
        var templateSumSq: Double = 0

        for i in 0..<profile.count {
            let profileDiff = profile[i] - profileMean
            let templateDiff = template[i] - templateMean

            numerator += profileDiff * templateDiff
            profileSumSq += profileDiff * profileDiff
            templateSumSq += templateDiff * templateDiff
        }

        let denominator = sqrt(profileSumSq * templateSumSq)

        guard denominator > 0 else { return 0 }

        return numerator / denominator
    }

    /// Rotates array circularly
    private func rotateArray(_ array: [Double], by offset: Int) -> [Double] {
        let count = array.count
        let normalizedOffset = ((offset % count) + count) % count

        return Array(array[normalizedOffset..<count] + array[0..<normalizedOffset])
    }
}

// MARK: - Key Detection Error

enum KeyDetectionError: LocalizedError {
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
