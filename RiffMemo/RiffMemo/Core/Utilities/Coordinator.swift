//
//  Coordinator.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation

/// Base protocol for all coordinators
@MainActor
protocol Coordinator: AnyObject {
    /// Start the coordinator's flow
    func start()

    /// Child coordinators managed by this coordinator
    var childCoordinators: [Coordinator] { get set }

    /// Add a child coordinator
    func addChild(_ coordinator: Coordinator)

    /// Remove a child coordinator
    func removeChild(_ coordinator: Coordinator)
}

extension Coordinator {
    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }

    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}
