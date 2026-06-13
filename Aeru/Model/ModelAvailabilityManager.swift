//
//  ModelAvailabilityManager.swift
//  Aeru
//
//  Tracks whether the on-device Foundation model is actually usable.
//
//  Why a probe instead of just reading availability?
//  `SystemLanguageModel.default.availability` reports `.available` even when the
//  safety model's assets (com.apple.fm.language.instruct_300m.safety) haven't
//  finished downloading. When that happens the first real prompt fails deep in
//  the framework with `promptTemplateNotFound` (surfaced as GenerationError -1).
//  The only reliable signal is to run a tiny throwaway generation and see if it
//  actually succeeds.
//

import Foundation
import FoundationModels
import Combine

@MainActor
final class ModelAvailabilityManager: ObservableObject {

    enum Status: Equatable {
        case checking
        case ready
        case preparing          // assets still downloading or safety model not ready
        case unsupported(String) // device ineligible / Apple Intelligence off
    }

    @Published private(set) var status: Status = .checking

    private var pollTask: Task<Void, Never>?

    /// Begin monitoring. Polls until the model is ready (or hits a hard-stop state).
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.monitor()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One-shot refresh, e.g. after the user returns from Settings.
    func refresh() {
        stop()
        status = .checking
        start()
    }

    private func monitor() async {
        while !Task.isCancelled {
            let newStatus = await probe()
            if newStatus != status {
                status = newStatus
            }
            switch newStatus {
            case .ready, .unsupported:
                return // settled — nothing to keep polling for
            case .checking, .preparing:
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func probe() async -> Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unsupported("On-device AI isn't supported on this device. Aeru's AI features require iPhone 15 Pro or later.")
            case .appleIntelligenceNotEnabled:
                return .unsupported("Turn on Apple Intelligence in Settings › Apple Intelligence & Siri to use Aeru's AI features.")
            case .modelNotReady:
                return .preparing
            @unknown default:
                return .preparing
            }
        @unknown default:
            break
        }

        // availability says `.available`, but it lies about the safety model.
        // Ground-truth check: attempt a 1-token generation.
        let session = LanguageModelSession {
            "You are a helpful assistant."
        }
        do {
            _ = try await session.respond(
                to: "Hi",
                options: GenerationOptions(maximumResponseTokens: 1)
            )
            return .ready
        } catch {
            // Safety template missing / -1 / not-ready — assets aren't usable yet.
            return .preparing
        }
    }
}
