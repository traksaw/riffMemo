//
//  AnalysisViewModel.swift
//  RiffMemo
//

import Foundation
import Observation

/// ViewModel for triggering audio analysis from the UI
@MainActor
@Observable
class AnalysisViewModel {

    // MARK: - Published State

    var isAnalyzing: Bool = false

    // MARK: - Dependencies

    private let analysisManager: AudioAnalysisManager

    // MARK: - Initialization

    init(analysisManager: AudioAnalysisManager = .shared) {
        self.analysisManager = analysisManager
    }

    // MARK: - Actions

    func analyze(_ recording: Recording) async {
        isAnalyzing = true
        _ = await analysisManager.analyzeRecording(recording)
        isAnalyzing = false
    }
}
