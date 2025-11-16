//
//  AppCoordinator.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI
import Observation

/// Main app coordinator that manages navigation flow
@MainActor
@Observable
class AppCoordinator {

    // MARK: - Published Properties

    var currentTab: AppTab = .recording

    // MARK: - Child Coordinators

    private var recordingCoordinator: RecordingCoordinator?
    private var libraryCoordinator: LibraryCoordinator?

    // MARK: - Initialization

    init() {
        setupCoordinators()
    }

    // MARK: - Setup

    private func setupCoordinators() {
        // Child coordinators will be initialized here
    }

    // MARK: - Navigation

    func navigateToTab(_ tab: AppTab) {
        currentTab = tab
    }
}

// MARK: - AppTab

enum AppTab {
    case recording
    case library
    case settings
}
