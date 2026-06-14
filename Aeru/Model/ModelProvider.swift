//
//  ModelProvider.swift
//  Aeru
//
//  Resolves a model id from `ModelCatalog` into a `LanguageModelSession` and
//  reports per-model availability. This is the seam that lets the rest of the
//  app stay model-agnostic: `LLM` asks the provider to build sessions and never
//  references a concrete model type.
//
//  Apple's system model is always available via FoundationModels. Third-party
//  Core AI models (e.g. Gemma) are loaded from a sideloaded `.aimodel` bundle on
//  disk. Loading a Core AI model is expensive, so loaded instances are cached
//  and dropped via `invalidate()` when the user switches models.
//

import Foundation
import FoundationModels

// NOTE (Core AI integration point): The concrete `CoreAILanguageModel` type
// ships in Apple's "Core AI Language Models" Swift package, which is added to the
// project alongside the model bundle in a later step. Until that package and a
// sideloaded bundle are present, the Google/Gemma branch reports `.notDownloaded`
// and the build stays clean against the stock iOS 27 SDK. The exact loading call
// to enable is shown inline below.
// import CoreAILanguageModels

@MainActor
final class ModelProvider {

    /// Whether a given model can currently serve requests, with a user-facing
    /// explanation when it can't.
    enum Availability: Equatable {
        case available
        case unavailable(Reason)

        enum Reason: Equatable {
            case appleDeviceNotEligible
            case appleIntelligenceNotEnabled
            case appleModelNotReady
            case notDownloaded
        }
    }

    /// Cache of loaded Core AI model instances keyed by model id. The Apple
    /// system model needs no caching (it's a cheap system singleton).
    ///
    /// Typed `Any` for now so the file compiles without the Core AI package;
    /// becomes `[String: CoreAILanguageModel]` once the package is added.
    private var loadedCoreAIModels: [String: Any] = [:]

    // MARK: - Availability

    func availability(for id: String) -> Availability {
        let definition = ModelCatalog.definition(for: id)
        if definition.isSystemModel {
            return appleAvailability()
        }
        return coreAIAvailability(for: definition)
    }

    private func appleAvailability() -> Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.appleDeviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.appleModelNotReady)
            @unknown default:
                return .unavailable(.appleModelNotReady)
            }
        @unknown default:
            return .unavailable(.appleModelNotReady)
        }
    }

    /// A Core AI model is available once its sideloaded bundle is present on
    /// disk. (A real downloader and specialization check land in a later phase.)
    private func coreAIAvailability(for definition: AIModelDefinition) -> Availability {
        guard let dir = ModelCatalog.sideloadDirectory(for: definition),
              bundleIsPresent(at: dir) else {
            return .unavailable(.notDownloaded)
        }
        return .available
    }

    /// A bundle counts as present if the directory exists and is non-empty (the
    /// Core AI `.aimodel` bundle is a multi-file directory: frontend/decoder/head).
    private func bundleIsPresent(at dir: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    // MARK: - Session construction

    /// Build a fresh session (blank slate) for the given model with system
    /// instructions.
    func makeSession(for id: String, instructions: String) async throws -> LanguageModelSession {
        let definition = ModelCatalog.definition(for: id)
        if definition.isSystemModel {
            return LanguageModelSession(model: SystemLanguageModel.default) { instructions }
        }
        let model = try await coreAIModel(for: definition)
        return LanguageModelSession(model: model) { instructions }
    }

    /// Build a session rehydrated from a saved transcript for the given model.
    func makeSession(for id: String, transcript: Transcript) async throws -> LanguageModelSession {
        let definition = ModelCatalog.definition(for: id)
        if definition.isSystemModel {
            return LanguageModelSession(model: SystemLanguageModel.default, transcript: transcript)
        }
        let model = try await coreAIModel(for: definition)
        return LanguageModelSession(model: model, transcript: transcript)
    }

    /// Load (or reuse a cached) Core AI model instance for a third-party model.
    ///
    /// INTEGRATION POINT — enable once the Core AI Language Models package and a
    /// sideloaded bundle are present:
    ///
    ///     if let cached = loadedCoreAIModels[definition.id] as? CoreAILanguageModel {
    ///         return cached
    ///     }
    ///     guard let dir = ModelCatalog.sideloadDirectory(for: definition),
    ///           bundleIsPresent(at: dir) else {
    ///         throw ModelProviderError.notDownloaded(definition.id)
    ///     }
    ///     let model = try await CoreAILanguageModel(resourcesAt: dir)
    ///     loadedCoreAIModels[definition.id] = model
    ///     return model
    ///
    /// `coreAIModel` is declared to return the concrete model type once the
    /// package is added; for now it throws so callers degrade gracefully.
    private func coreAIModel(for definition: AIModelDefinition) async throws -> SystemLanguageModel {
        // Until the Core AI package is wired in, third-party models can't be
        // loaded — callers (LLM.executeQuery) gate on `availability` first, so
        // this only fires as a safety net.
        throw ModelProviderError.notDownloaded(definition.id)
    }

    // MARK: - Cache invalidation

    /// Drop cached Core AI instance(s) so the next session rebuilds. Pass a model
    /// id to invalidate one, or `nil` to clear all (e.g. on model switch).
    func invalidate(_ id: String? = nil) {
        if let id {
            loadedCoreAIModels[id] = nil
        } else {
            loadedCoreAIModels.removeAll()
        }
    }
}

enum ModelProviderError: Error {
    case notDownloaded(String)
}
