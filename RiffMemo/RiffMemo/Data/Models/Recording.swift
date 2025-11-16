//
//  Recording.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID
    var title: String
    var createdDate: Date
    var modifiedDate: Date
    var duration: TimeInterval

    // Audio metadata
    var audioFileURL: URL
    var fileSize: Int64
    var sampleRate: Double

    // Detected properties
    var detectedBPM: Int?
    var detectedKey: String?
    var detectedInstrument: String?

    // User metadata
    var rating: Int
    var isFavorite: Bool
    var notes: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        duration: TimeInterval,
        audioFileURL: URL,
        fileSize: Int64 = 0,
        sampleRate: Double = 44100.0,
        detectedBPM: Int? = nil,
        detectedKey: String? = nil,
        detectedInstrument: String? = nil,
        rating: Int = 0,
        isFavorite: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.fileSize = fileSize
        self.sampleRate = sampleRate
        self.detectedBPM = detectedBPM
        self.detectedKey = detectedKey
        self.detectedInstrument = detectedInstrument
        self.rating = rating
        self.isFavorite = isFavorite
        self.notes = notes
    }
}
