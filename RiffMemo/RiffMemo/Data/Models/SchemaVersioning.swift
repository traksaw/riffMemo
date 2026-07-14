//
//  SchemaVersioning.swift
//  RiffMemo
//
//  Created by Claude Code on 7/13/26.
//

import Foundation
import SwiftData

// WAS-61: scaffolding only — there is nothing to migrate yet, but the first
// non-additive model change needs this in place *before* it ships, not after.
//
// SwiftData's lightweight migration (no version bump, no stage) is enough when a
// change is purely additive: a new optional property, or a new property with an
// inline default value (see the CloudKit comment on `Recording` for why inline
// defaults matter there). Adding or removing a whole model type is also
// lightweight, as long as no existing model's stored properties change shape.
//
// A new `VersionedSchema` (`RiffMemoSchemaV2`, `V3`, ...) plus a `MigrationStage`
// in `RiffMemoMigrationPlan.stages` is REQUIRED the moment a stored property is:
//   - renamed
//   - retyped (e.g. `Int` -> `Int64`, `String` -> an enum)
//   - removed
//   - made non-optional without an inline default
// Skipping that step for one of these changes doesn't fail at build time — it
// crashes at launch on every existing user's device when SwiftData can't
// reconcile the old store with the new model.
//
// CloudKit trap: `Recording`'s CloudKit entitlement (WAS-51) is dormant today
// (`ModelConfiguration(cloudKitDatabase: .none)` in RiffMemoApp), but the day a
// *custom* `MigrationStage` (one with `willMigrate`/`didMigrate` closures that
// transform data) is added, CloudKit sync must stay off (`.none`) until that
// migration has shipped and run on every existing user's device. Apple's own
// forums confirm `willMigrate`/`didMigrate` are unreliable — sometimes silently
// skipped — once CloudKit sync is live; turn sync on only after confirming the
// migration completed cleanly with it off. `.lightweight` stages don't carry
// this risk.

/// The app's schema as of WAS-61: just `Recording`, unchanged since it shipped.
enum RiffMemoSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self]
    }
}

/// No-op today — there's only one schema version, so there's nothing to migrate
/// from. Add a `.lightweight` or `.custom` `MigrationStage` here the first time
/// `RiffMemoSchemaV2` exists.
enum RiffMemoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RiffMemoSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
