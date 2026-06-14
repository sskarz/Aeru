//
//  ModelCatalog.swift
//  Aeru
//
//  Declarative registry of the AI models the user can pick from, grouped by
//  family. This is the single source of truth for the model picker — adding a
//  new model (or family) means appending one entry here.
//
//  The on-device model assets are NOT bundled in the app binary. Apple's model
//  is provided by the system (FoundationModels); third-party Core AI models are
//  expected on disk at a per-model sideload directory (a real downloader lands
//  in a later phase). See `ModelProvider` for resolution and availability.
//

import Foundation

/// A vendor/family grouping shown as a section header in the picker.
enum ModelFamily: String, CaseIterable, Identifiable {
    case apple
    case google

    var id: String { rawValue }

    /// Section title shown in the picker.
    var displayName: String {
        switch self {
        case .apple:  return "Apple"
        case .google: return "Google"
        }
    }
}

/// One selectable model. `id` is the stable key persisted in `@AppStorage`.
struct AIModelDefinition: Identifiable, Equatable {
    let id: String
    let family: ModelFamily
    let displayName: String
    /// Approximate on-disk footprint once downloaded; `nil` for the Apple
    /// system model (managed by the OS, not stored in the app container).
    let approxOnDiskBytes: Int64?

    /// `true` for Apple's system model, which is always provided by the OS and
    /// never sideloaded/downloaded by the app.
    var isSystemModel: Bool { family == .apple }
}

/// A family and its models, used to drive the picker's sectioned layout.
struct ModelFamilyGroup: Identifiable {
    let family: ModelFamily
    let models: [AIModelDefinition]
    var id: String { family.id }
}

/// The static catalog. Order here is the order shown in the picker.
enum ModelCatalog {

    /// Stable id of the default selection (Apple's on-device system model).
    static let defaultModelID = "apple.default"

    static let all: [AIModelDefinition] = [
        AIModelDefinition(
            id: defaultModelID,
            family: .apple,
            displayName: "On-device (Apple)",
            approxOnDiskBytes: nil
        ),
        AIModelDefinition(
            id: "google.gemma-4-e2b",
            family: .google,
            displayName: "Gemma 4 E2B",
            approxOnDiskBytes: 4_100_000_000 // iOS GPU bundle ≈ 4.1 GB
        )
    ]

    /// Look up a definition by id, falling back to the Apple default for any
    /// unknown/stale persisted id so the app always has a valid selection.
    static func definition(for id: String) -> AIModelDefinition {
        all.first { $0.id == id } ?? all.first { $0.id == defaultModelID }!
    }

    /// Models grouped by family, preserving catalog order — drives the picker's
    /// sectioned layout.
    static var byFamily: [ModelFamilyGroup] {
        ModelFamily.allCases.compactMap { family in
            let models = all.filter { $0.family == family }
            return models.isEmpty ? nil : ModelFamilyGroup(family: family, models: models)
        }
    }

    // MARK: - Sideload location

    /// Directory under Application Support that holds a sideloaded Core AI model
    /// bundle for the given definition, e.g. `…/Models/google.gemma-4-e2b/`.
    ///
    /// During this phase you copy the converted `.aimodel` bundle here manually
    /// (Xcode → Devices & Simulators → app container, or the Files app). A real
    /// in-app downloader replaces this step later.
    static func sideloadDirectory(for definition: AIModelDefinition) -> URL? {
        guard !definition.isSystemModel else { return nil }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        return base?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(definition.id, isDirectory: true)
    }
}
