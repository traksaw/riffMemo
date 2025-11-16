//
//  WaveformGenerator.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import Accelerate

/// Actor responsible for generating waveform data from audio files
/// Uses downsampling to create manageable data for visualization
actor WaveformGenerator {

    // MARK: - Public Methods

    /// Generates waveform amplitude data from an audio file
    /// - Parameters:
    ///   - url: The URL of the audio file to analyze
    ///   - targetSamples: Number of samples to generate (default: 300 for typical screen widths)
    /// - Returns: Array of normalized amplitude values (0.0 to 1.0)
    func generateWaveform(from url: URL, targetSamples: Int = 300) async throws -> [Float] {
        Logger.info("Generating waveform for \(url.lastPathComponent) with \(targetSamples) samples", category: Logger.audio)

        // Open the audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw WaveformError.emptyFile
        }

        // Create buffer to read audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WaveformError.bufferAllocationFailed
        }

        // Read the entire file into the buffer
        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw WaveformError.noChannelData
        }

        // Extract samples from the first channel
        let samples = extractSamples(from: channelData[0], frameCount: Int(buffer.frameLength))

        // Downsample to target number of samples
        let downsampled = downsample(samples: samples, to: targetSamples)

        // Normalize to 0.0 - 1.0 range
        let normalized = normalize(samples: downsampled)

        Logger.info("Waveform generated: \(normalized.count) samples", category: Logger.audio)

        return normalized
    }

    /// Generates waveform data and encodes it to Data for storage
    /// - Parameters:
    ///   - url: The URL of the audio file to analyze
    ///   - targetSamples: Number of samples to generate
    /// - Returns: Encoded waveform data
    func generateWaveformData(from url: URL, targetSamples: Int = 300) async throws -> Data {
        let waveform = try await generateWaveform(from: url, targetSamples: targetSamples)

        // Convert [Float] to Data
        let data = waveform.withUnsafeBytes { buffer in
            Data(buffer)
        }

        return data
    }

    /// Decodes waveform data back to Float array
    /// - Parameter data: The encoded waveform data
    /// - Returns: Array of amplitude values
    func decodeWaveform(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        var waveform = [Float](repeating: 0, count: count)

        _ = waveform.withUnsafeMutableBytes { buffer in
            data.copyBytes(to: buffer)
        }

        return waveform
    }

    // MARK: - Private Methods

    /// Extracts samples from raw channel data
    private func extractSamples(from channelData: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            samples[i] = channelData[i]
        }

        return samples
    }

    /// Downsamples audio data using RMS (Root Mean Square) for each bucket
    /// This preserves the perceived loudness better than simple averaging
    private func downsample(samples: [Float], to targetCount: Int) -> [Float] {
        let sampleCount = samples.count

        // If we already have fewer samples than target, return as-is
        guard sampleCount > targetCount else {
            return samples
        }

        let bucketSize = sampleCount / targetCount
        var downsampled = [Float](repeating: 0, count: targetCount)

        for i in 0..<targetCount {
            let startIndex = i * bucketSize
            let endIndex = min(startIndex + bucketSize, sampleCount)

            // Calculate RMS for this bucket
            var sum: Float = 0
            for j in startIndex..<endIndex {
                let sample = samples[j]
                sum += sample * sample
            }

            let rms = sqrt(sum / Float(endIndex - startIndex))
            downsampled[i] = rms
        }

        return downsampled
    }

    /// Normalizes samples to 0.0 - 1.0 range
    private func normalize(samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }

        // Find the maximum absolute value
        var maxValue: Float = 0
        vDSP_maxmgv(samples, 1, &maxValue, vDSP_Length(samples.count))

        // Avoid division by zero
        guard maxValue > 0 else {
            return samples.map { _ in 0.0 }
        }

        // Normalize all values
        var normalized = [Float](repeating: 0, count: samples.count)
        var divisor = maxValue
        vDSP_vsdiv(samples, 1, &divisor, &normalized, 1, vDSP_Length(samples.count))

        return normalized
    }
}

// MARK: - Waveform Error

enum WaveformError: LocalizedError {
    case emptyFile
    case bufferAllocationFailed
    case noChannelData
    case invalidData

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "Audio file is empty"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .noChannelData:
            return "No channel data available in audio file"
        case .invalidData:
            return "Invalid waveform data"
        }
    }
}
