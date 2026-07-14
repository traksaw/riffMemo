//
//  AnalysisManagerProtocol.swift
//  RiffMemo
//

import Foundation

/// Narrow protocol over `AudioAnalysisManager`'s public surface, scoped to exactly what
/// `AnalysisViewModel` calls. `@MainActor` because the concrete manager is `@MainActor`, and
/// `AnalysisViewModel` itself only ever calls this from the main actor.
@MainActor
protocol AnalysisManagerProtocol: AnyObject {
    func analyzeRecording(_ recording: Recording, options: AnalysisOptions) async -> AnalysisResults
}

extension AudioAnalysisManager: AnalysisManagerProtocol {}
