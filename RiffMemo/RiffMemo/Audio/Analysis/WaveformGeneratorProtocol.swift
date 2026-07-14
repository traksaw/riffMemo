//
//  WaveformGeneratorProtocol.swift
//  RiffMemo
//

import Foundation

/// Narrow protocol over `WaveformGenerator`'s public surface, scoped to exactly what
/// `WaveformViewModel` calls. Protocol requirements can't carry default parameter values, so
/// `targetSamples` has none here — every call site already passes it explicitly.
protocol WaveformGeneratorProtocol: AnyObject {
    func generateWaveform(from url: URL, targetSamples: Int) async throws -> [Float]
    func generateWaveformData(from url: URL, targetSamples: Int) async throws -> Data
    func decodeWaveform(from data: Data) async -> [Float]
}

extension WaveformGenerator: WaveformGeneratorProtocol {}
