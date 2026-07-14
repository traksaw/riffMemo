//
//  ShareManagerProtocol.swift
//  RiffMemo
//

import UIKit

/// Narrow protocol over `ShareManager`'s public surface, scoped to exactly what
/// `ExportViewModel` calls. Protocol requirements can't carry default parameter values, so
/// `settings`/`from` have none here — `ExportViewModel` already passes both explicitly.
@MainActor
protocol ShareManagerProtocol: AnyObject {
    func shareRecording(_ recording: Recording, settings: ExportSettings?, from sourceView: UIView?) async
    func shareMultipleRecordings(_ recordings: [Recording], settings: ExportSettings?, from sourceView: UIView?) async
}

extension ShareManager: ShareManagerProtocol {}
