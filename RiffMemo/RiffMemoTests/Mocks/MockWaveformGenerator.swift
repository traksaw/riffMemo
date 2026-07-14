//
//  MockWaveformGenerator.swift
//  RiffMemoTests
//

import Foundation
@testable import RiffMemo

/// Test double for `WaveformGeneratorProtocol`. Lets `WaveformViewModel` tests drive all three
/// caching tiers deterministically without decoding a real audio file.
final class MockWaveformGenerator: WaveformGeneratorProtocol, @unchecked Sendable {
    private(set) var generateWaveformCallCount = 0
    private(set) var generateWaveformDataCallCount = 0
    private(set) var decodeWaveformCallCount = 0

    var generateWaveformError: Error?
    var generateWaveformDataError: Error?
    var waveformToReturn: [Float] = [0.1, 0.2, 0.3]
    var waveformDataToReturn: Data = Data([0x01, 0x02])
    var decodedWaveformToReturn: [Float] = [0.4, 0.5]

    func generateWaveform(from url: URL, targetSamples: Int) async throws -> [Float] {
        generateWaveformCallCount += 1
        if let generateWaveformError {
            throw generateWaveformError
        }
        return waveformToReturn
    }

    func generateWaveformData(from url: URL, targetSamples: Int) async throws -> Data {
        generateWaveformDataCallCount += 1
        if let generateWaveformDataError {
            throw generateWaveformDataError
        }
        return waveformDataToReturn
    }

    func decodeWaveform(from data: Data) async -> [Float] {
        decodeWaveformCallCount += 1
        return decodedWaveformToReturn
    }
}
