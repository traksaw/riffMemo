//
//  AudioQualityAnalyzer.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import Accelerate

/// Analyzes audio quality metrics (peak level, RMS, dynamic range, etc.)
actor AudioQualityAnalyzer {

    // MARK: - Public Methods

    /// Analyzes audio quality from a file
    /// - Parameter url: URL of the audio file
    /// - Returns: Audio quality metrics
    func analyze(from url: URL) async throws -> AudioQualityMetrics {
        Logger.info("Analyzing audio quality from \(url.lastPathComponent)", category: Logger.audio)

        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw QualityAnalysisError.emptyFile
        }

        // Read audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw QualityAnalysisError.bufferAllocationFailed
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw QualityAnalysisError.noChannelData
        }

        // Extract samples
        let samples = extractSamples(from: channelData[0], frameCount: Int(buffer.frameLength))

        // Calculate metrics
        let peakLevel = calculatePeakLevel(samples: samples)
        let rmsLevel = calculateRMS(samples: samples)
        let dynamicRange = calculateDynamicRange(samples: samples)
        let crestFactor = calculateCrestFactor(peak: peakLevel, rms: rmsLevel)
        let silenceRatio = calculateSilenceRatio(samples: samples)
        let clippingDetected = detectClipping(samples: samples)

        let metrics = AudioQualityMetrics(
            peakLevel: peakLevel,
            rmsLevel: rmsLevel,
            dynamicRange: dynamicRange,
            crestFactor: crestFactor,
            silenceRatio: silenceRatio,
            clippingDetected: clippingDetected,
            quality: determineQuality(
                peakLevel: peakLevel,
                rmsLevel: rmsLevel,
                dynamicRange: dynamicRange,
                clippingDetected: clippingDetected
            )
        )

        Logger.info("Quality analysis complete: \(metrics.quality)", category: Logger.audio)

        return metrics
    }

    // MARK: - Private Methods

    private func extractSamples(from channelData: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = channelData[i]
        }
        return samples
    }

    /// Calculates peak level in dB
    private func calculatePeakLevel(samples: [Float]) -> Double {
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        guard peak > 0 else { return -Double.infinity }

        return 20 * log10(Double(peak))
    }

    /// Calculates RMS level in dB
    private func calculateRMS(samples: [Float]) -> Double {
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))

        let rms = sqrt(sum / Float(samples.count))

        guard rms > 0 else { return -Double.infinity }

        return 20 * log10(Double(rms))
    }

    /// Calculates dynamic range (difference between loudest and quietest parts)
    private func calculateDynamicRange(samples: [Float]) -> Double {
        let windowSize = 44100 // 1 second at 44.1kHz
        let numWindows = samples.count / windowSize

        guard numWindows > 0 else { return 0 }

        var windowRMS = [Double]()

        for i in 0..<numWindows {
            let start = i * windowSize
            let end = min(start + windowSize, samples.count)
            let window = Array(samples[start..<end])

            var sum: Float = 0
            vDSP_svesq(window, 1, &sum, vDSP_Length(window.count))
            let rms = sqrt(sum / Float(window.count))

            if rms > 0 {
                windowRMS.append(20 * log10(Double(rms)))
            }
        }

        guard !windowRMS.isEmpty else { return 0 }

        let maxRMS = windowRMS.max() ?? 0
        let minRMS = windowRMS.min() ?? 0

        return maxRMS - minRMS
    }

    /// Calculates crest factor (peak-to-RMS ratio)
    private func calculateCrestFactor(peak: Double, rms: Double) -> Double {
        return peak - rms // In dB, so this is a subtraction
    }

    /// Calculates ratio of silence to total duration
    private func calculateSilenceRatio(samples: [Float]) -> Double {
        let silenceThreshold: Float = 0.01 // -40 dB roughly

        let silentSamples = samples.filter { abs($0) < silenceThreshold }.count

        return Double(silentSamples) / Double(samples.count)
    }

    /// Detects if clipping occurred
    private func detectClipping(samples: [Float]) -> Bool {
        let clippingThreshold: Float = 0.99

        return samples.contains { abs($0) >= clippingThreshold }
    }

    /// Determines overall quality rating
    private func determineQuality(
        peakLevel: Double,
        rmsLevel: Double,
        dynamicRange: Double,
        clippingDetected: Bool
    ) -> AudioQuality {
        // Clipping is bad
        if clippingDetected {
            return .poor
        }

        // Very low level
        if rmsLevel < -40 {
            return .poor
        }

        // Good dynamic range and reasonable levels
        if dynamicRange > 6 && rmsLevel > -24 && rmsLevel < -6 {
            return .excellent
        }

        // Decent recording
        if dynamicRange > 3 && rmsLevel > -30 {
            return .good
        }

        return .fair
    }
}

// MARK: - Audio Quality Metrics

struct AudioQualityMetrics {
    let peakLevel: Double         // dB
    let rmsLevel: Double           // dB
    let dynamicRange: Double       // dB
    let crestFactor: Double        // dB
    let silenceRatio: Double       // 0.0 to 1.0
    let clippingDetected: Bool
    let quality: AudioQuality

    var peakLevelFormatted: String {
        String(format: "%.1f dB", peakLevel)
    }

    var rmsLevelFormatted: String {
        String(format: "%.1f dB", rmsLevel)
    }

    var dynamicRangeFormatted: String {
        String(format: "%.1f dB", dynamicRange)
    }

    var silencePercentage: String {
        String(format: "%.1f%%", silenceRatio * 100)
    }
}

enum AudioQuality: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
}

// MARK: - Quality Analysis Error

enum QualityAnalysisError: LocalizedError {
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
