//
//  Recording.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import SwiftData

// CloudKit's schema mirroring reads each property's schema-level (inline) default,
// not the custom initializer's parameter defaults. Every non-optional stored
// property below needs its own `= value` or CloudKit sync fails schema validation
// the moment it's enabled, even though local SwiftData works fine without it.
@Model
final class Recording {
    var id: UUID = UUID()
    var title: String = ""
    var createdDate: Date = Date()
    var modifiedDate: Date = Date()
    var duration: TimeInterval = 0

    // Audio metadata
    var audioFilename: String = ""  // Store filename only, not full path
    var fileSize: Int64 = 0
    var sampleRate: Double = 44100.0

    // Computed property to get the full URL
    var audioFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(audioFilename)
    }

    // Recording settings (metronome used during recording)
    var recordedWithBPM: Int?
    var recordedWithTimeSignature: String?

    // Detected properties
    var detectedBPM: Int?
    var detectedKey: String?
    var detectedInstrument: String?
    var waveformData: Data?

    // Audio quality metrics
    var audioQuality: String?       // "Excellent", "Good", "Fair", "Poor"
    var peakLevel: Double?           // dB
    var rmsLevel: Double?            // dB
    var dynamicRange: Double?        // dB

    // Analysis metadata
    var lastAnalyzedDate: Date?
    var analysisVersion: String?     // Track which version of analysis was used

    // User metadata
    var rating: Int = 0
    var isFavorite: Bool = false
    var notes: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        duration: TimeInterval,
        audioFileURL: URL,  // Accept URL but store only filename
        fileSize: Int64 = 0,
        sampleRate: Double = 44100.0,
        recordedWithBPM: Int? = nil,
        recordedWithTimeSignature: String? = nil,
        detectedBPM: Int? = nil,
        detectedKey: String? = nil,
        detectedInstrument: String? = nil,
        waveformData: Data? = nil,
        audioQuality: String? = nil,
        peakLevel: Double? = nil,
        rmsLevel: Double? = nil,
        dynamicRange: Double? = nil,
        lastAnalyzedDate: Date? = nil,
        analysisVersion: String? = nil,
        rating: Int = 0,
        isFavorite: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.duration = duration
        self.audioFilename = audioFileURL.lastPathComponent  // Store only filename
        self.fileSize = fileSize
        self.sampleRate = sampleRate
        self.recordedWithBPM = recordedWithBPM
        self.recordedWithTimeSignature = recordedWithTimeSignature
        self.detectedBPM = detectedBPM
        self.detectedKey = detectedKey
        self.detectedInstrument = detectedInstrument
        self.waveformData = waveformData
        self.audioQuality = audioQuality
        self.peakLevel = peakLevel
        self.rmsLevel = rmsLevel
        self.dynamicRange = dynamicRange
        self.lastAnalyzedDate = lastAnalyzedDate
        self.analysisVersion = analysisVersion
        self.rating = rating
        self.isFavorite = isFavorite
        self.notes = notes
    }
}
