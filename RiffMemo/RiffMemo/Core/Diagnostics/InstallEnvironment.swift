//
//  InstallEnvironment.swift
//  RiffMemo
//

import StoreKit

/// Where this binary is installed. WAS-114: the forced-crash button must show on
/// TestFlight and never on the App Store.
///
/// This must be a runtime check. The TestFlight build is the same binary that is
/// later promoted to the App Store, so a compile-time flag would give the same
/// answer in both places and ship the button to every user.
enum InstallEnvironment {
    /// True on TestFlight (`.sandbox`) and on builds run from Xcode (`.xcode`).
    /// False on the App Store, and false when StoreKit gives no answer, so a
    /// failure hides developer tools instead of showing them.
    static func allowsDeveloperTools() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        switch result.unsafePayloadValue.environment {
        case .sandbox, .xcode:
            return true
        default:
            return false
        }
    }
}
