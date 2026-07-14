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

    private let analysisManager: any AnalysisManagerProtocol

    // MARK: - Initialization

    init(analysisManager: any AnalysisManagerProtocol = AudioAnalysisManager.shared) {
        self.analysisManager = analysisManager
    }

    // MARK: - Actions

    func analyze(_ recording: Recording) async {
        isAnalyzing = true
        // `options` has no default in the protocol (protocol requirements can't carry default
        // parameter values), so the `.all` default the concrete manager used to supply here is
        // now explicit.
        _ = await analysisManager.analyzeRecording(recording, options: .all)
        isAnalyzing = false
    }
}
