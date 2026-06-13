//
//  ModelAvailabilityManager.swift
//  Aeru
//
//  Tracks whether the on-device Foundation model is usable, driven by
//  SystemLanguageModel.default.availability. Polls while the model is still
//  downloading so the UI can reflect readiness without the user reopening the app.
//

import Foundation
import FoundationModels
import Combine

@MainActor
final class ModelAvailabilityManager: ObservableObject {

    enum Status: Equatable {
        case checking
        case ready
        case preparing          // assets still downloading
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
            let newStatus = currentStatus()
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

    private func currentStatus() -> Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
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
            return .preparing
        }
    }
}
