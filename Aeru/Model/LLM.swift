//
//  LLM.swift
//  RAGSearchLLMSwift
//
//  Created by Sanskar Thapa on 7/21/25.
//

import Foundation
import SVDB
import Combine
import FoundationModels

@MainActor
class LLM: ObservableObject {

    // MARK: - Properties

    private var ragModels: [String: RAGModel] = [:]
    private var sessions: [String: LanguageModelSession] = [:]
    private let modelProvider = ModelProvider()

    /// The user's currently selected model id (mirrors `@AppStorage("selectedModelID")`
    /// written by the picker). Falls back to the Apple default for any unknown value.
    private var currentModelID: String {
        UserDefaults.standard.string(forKey: "selectedModelID") ?? ModelCatalog.defaultModelID
    }

    @Published var userLLMQuery: String = ""
    @Published var userLLMResponse: LanguageModelSession.ResponseStream<String>.Snapshot?

    var webSearch: WebSearchService = WebSearchService()
    @Published var isWebSearching = false
    @Published var webSearchResults: [WebSearchResult] = []

    @Published var chatMessages: [ChatMessage] = []
    private var currentSessionId: String?
    private let databaseManager = DatabaseManager.shared
    @Published var isResponding: Bool = false

    // MARK: - Session Lifecycle

    private func updateIsResponding() {
        guard let currentSessionId, let session = sessions[currentSessionId] else {
            isResponding = false
            return
        }
        isResponding = session.isResponding
    }

    private func newSession(previousSession: LanguageModelSession) async -> LanguageModelSession {
        let all = previousSession.transcript
        var condensed = [Transcript.Entry]()
        if let first = all.first {
            condensed.append(first)
            if all.count > 1, let last = all.last { condensed.append(last) }
        }
        let transcript = Transcript(entries: condensed)
        // Rebuild against the selected model; fall back to the system model if
        // the selected one can't be built (availability is gated upstream).
        if let session = try? await modelProvider.makeSession(for: currentModelID, transcript: transcript) {
            return session
        }
        return LanguageModelSession(transcript: transcript)
    }

    /// Called when the user picks a different model. Drops cached sessions and
    /// loaded model instances so the next query rebuilds against the new model.
    /// No-op while a response is streaming to avoid tearing a live session.
    func modelSelectionChanged() {
        guard !isResponding else { return }
        sessions.removeAll()
        modelProvider.invalidate()
    }

    private func getRagForSession(_ sessionId: String, collectionName: String) -> RAGModel {
        if let existing = ragModels[sessionId] { return existing }
        let rag = RAGModel(collectionName: collectionName)
        ragModels[sessionId] = rag
        return rag
    }

    private static let instructions = "You are a helpful, accurate, and concise AI assistant."

    private func getSessionForChat(_ sessionId: String) async -> LanguageModelSession {
        if let existing = sessions[sessionId] { return existing }
        // Rehydrate the model's conversation memory from a saved transcript when
        // one exists, so follow-up questions keep context across app launches.
        let session: LanguageModelSession
        if let saved = loadTranscript(for: sessionId) {
            session = (try? await modelProvider.makeSession(for: currentModelID, transcript: saved))
                ?? LanguageModelSession(transcript: saved)
        } else {
            session = (try? await modelProvider.makeSession(for: currentModelID, instructions: Self.instructions))
                ?? LanguageModelSession { Self.instructions }
        }
        session.prewarm()
        sessions[sessionId] = session
        return session
    }

    /// Persists the model's transcript so its conversation memory survives launches.
    /// Tags it with the current model id so it is only rehydrated under the same model.
    private func saveTranscript(_ transcript: Transcript, sessionId: String) {
        do {
            let data = try JSONEncoder().encode(transcript)
            guard let json = String(data: data, encoding: .utf8) else { return }
            databaseManager.saveTranscriptJSON(json, modelID: currentModelID, sessionId: sessionId)
        } catch {
            print("Failed to encode transcript: \(error)")
        }
    }

    private func loadTranscript(for sessionId: String) -> Transcript? {
        // Transcripts are tokenizer-specific: only rehydrate when the saved
        // transcript was produced under the currently selected model. Sessions
        // predating model tagging have an empty id and are treated as the default.
        let storedID = databaseManager.loadTranscriptModelID(for: sessionId) ?? ""
        let effectiveStoredID = storedID.isEmpty ? ModelCatalog.defaultModelID : storedID
        guard effectiveStoredID == currentModelID else { return nil }

        guard let json = databaseManager.loadTranscriptJSON(for: sessionId),
              !json.isEmpty,
              let data = json.data(using: .utf8) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Transcript.self, from: data)
        } catch {
            print("Failed to decode transcript: \(error)")
            return nil
        }
    }

    func sessionHasDocuments(_ session: ChatSession) -> Bool {
        !databaseManager.getDocuments(for: session.id).isEmpty
    }

    func switchToSession(_ session: ChatSession) {
        currentSessionId = session.id
        loadMessagesForCurrentSession()
        // Warm the session in the background; building it may be async (loading a
        // Core AI model). Callers don't need to wait — executeQuery awaits it too.
        Task { _ = await getSessionForChat(session.id) }
    }

    func loadMessagesForCurrentSession() {
        guard let sessionId = currentSessionId else { chatMessages = []; return }
        chatMessages = databaseManager.getMessages(for: sessionId)
    }

    // MARK: - Document / Entry Management

    func addEntry(_ entry: String, to session: ChatSession) async {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.loadCollection()
        await rag.addEntry(entry)
    }

    func processDocument(url: URL, for session: ChatSession) async -> Bool {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource")
            return false
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let extractedText = DocumentProcessor.extractTextFromPDF(at: url) else {
            print("Failed to extract text from PDF")
            return false
        }

        let originalFileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        let baseName = originalFileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        let uniqueFileName = "\(baseName)_\(UUID().uuidString).\(fileExtension)"

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsDir.appendingPathComponent("Documents").appendingPathComponent(uniqueFileName)

        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            print("Failed to copy document: \(error)")
            return false
        }

        guard let documentId = databaseManager.saveDocument(
            sessionId: session.id,
            name: originalFileName,
            path: destinationURL.path,
            type: "pdf"
        ) else {
            print("Failed to save document to database")
            return false
        }

        let chunks = DocumentProcessor.chunkText(extractedText)
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.loadCollection()

        for (index, chunk) in chunks.enumerated() {
            if let chunkId = databaseManager.saveDocumentChunk(documentId: documentId, text: chunk, index: index) {
                await rag.addEntry(chunk)
                databaseManager.markChunkAsEmbedded(chunkId)
            } else {
                print("Failed to save chunk \(index + 1) to database")
            }
        }

        return true
    }

    func getDocuments(for session: ChatSession) -> [(id: String, name: String, type: String, uploadedAt: Date)] {
        databaseManager.getDocuments(for: session.id)
    }

    func getRagNeighbors(for session: ChatSession) -> [(String, Double)] {
        getRagForSession(session.id, collectionName: session.collectionName).neighbors
    }

    // MARK: - Query Routing

    func queryIntelligently(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager, useWebSearch: Bool) async throws {
        if useWebSearch {
            try await webSearch(UIQuery, for: chatSession, sessionManager: sessionManager)
        } else if sessionHasDocuments(chatSession) {
            try await queryLLM(UIQuery, for: chatSession, sessionManager: sessionManager)
        } else {
            try await queryLLMGeneral(UIQuery, for: chatSession, sessionManager: sessionManager)
        }
    }

    // MARK: - Core Streaming Engine

    private func stream(_ prompt: String, using session: LanguageModelSession) async throws -> String {
        let responseStream = session.streamResponse(to: prompt)
        updateIsResponding()
        var fullResponse = ""
        // Coalesce snapshot publishes to ~12 fps. The raw stream emits a snapshot
        // per token; forwarding each one re-renders the whole transcript and was
        // the main source of stutter while a response generates.
        let minInterval: TimeInterval = 0.08
        var lastPublish = Date.distantPast
        var latestPartial: LanguageModelSession.ResponseStream<String>.Snapshot?
        for try await partial in responseStream {
            fullResponse = partial.content
            latestPartial = partial
            let now = Date()
            if now.timeIntervalSince(lastPublish) >= minInterval {
                userLLMResponse = partial
                lastPublish = now
            }
        }
        // Flush the final snapshot so the streaming bubble shows the complete
        // text for the brief moment before it is committed to the transcript.
        if let latestPartial {
            userLLMResponse = latestPartial
        }
        return fullResponse
    }

    private func commitResponse(
        _ text: String,
        sessionId: String,
        chatSession: ChatSession,
        sessionManager: ChatSessionManager,
        sources: [WebSearchResult]? = nil,
        isFirstMessage: Bool
    ) async {
        userLLMResponse = nil
        updateIsResponding()
        let message = ChatMessage(text: text, isUser: false, sources: sources)
        chatMessages.append(message)
        databaseManager.saveMessage(message, sessionId: sessionId)
        if isFirstMessage && chatSession.title.isEmpty {
            let title = await generateChatTitle(from: text, for: chatSession)
            sessionManager.updateSessionTitleIfEmpty(chatSession, with: title)
        }
    }

    private func handleError(
        _ error: Error,
        sessionId: String,
        for chatSession: ChatSession,
        sessionManager: ChatSessionManager,
        isFirstMessage: Bool,
        sources: [WebSearchResult]? = nil
    ) {
        updateIsResponding()
        let message = ChatMessage(text: userFacingMessage(for: error), isUser: false, sources: sources)
        chatMessages.append(message)
        databaseManager.saveMessage(message, sessionId: sessionId)
        titleSessionOnFailure(for: chatSession, sessionManager: sessionManager, isFirstMessage: isFirstMessage)
    }

    /// When the first message of a chat fails, the model never produced a
    /// response to title from — so derive a title locally from the user's query.
    /// This keeps the session from retaining an empty title, which otherwise
    /// collides with the untitled-session dedup and makes "New Chat" a no-op.
    private func titleSessionOnFailure(
        for chatSession: ChatSession,
        sessionManager: ChatSessionManager,
        isFirstMessage: Bool
    ) {
        guard isFirstMessage, chatSession.title.isEmpty else { return }
        sessionManager.updateSessionTitleIfEmpty(chatSession, with: titleFromQuery(userLLMQuery))
    }

    /// Builds a concise title from the user's query without invoking the model
    /// (the model just failed/was unavailable, so a local heuristic is used).
    private func titleFromQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        let title = trimmed.split(whereSeparator: { $0.isWhitespace }).prefix(6).joined(separator: " ")
        guard title.count > 40 else { return title }
        return String(title.prefix(40)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Maps the iOS 27 Foundation Models error types to user-friendly text.
    private func userFacingMessage(for error: Error) -> String {
        switch error {
        case let modelError as LanguageModelError:
            switch modelError {
            case .guardrailViolation:
                return "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
            case .refusal:
                return "Sorry, I'm unable to provide a response to that request. Please try rephrasing your question."
            case .rateLimited:
                return "The on-device model is currently rate limited. Please wait a moment and try again."
            case .unsupportedLanguageOrLocale:
                return "Your current language isn't supported by Apple Intelligence. Make sure your Siri and device languages match in Settings."
            case .timeout:
                return "The request timed out. Please try again."
            case .contextSizeExceeded:
                return "This conversation got too long. I've reset the context — please resend your last message."
            default:
                return "The on-device model encountered an error. Please try again. If this persists, restart the app or check Apple Intelligence settings."
            }
        case let assetError as SystemLanguageModel.Error:
            switch assetError {
            case .assetsUnavailable:
                return "The on-device model is unavailable. Please ensure Apple Intelligence is enabled and its models have finished downloading in Settings."
            @unknown default:
                return "The on-device model is unavailable. Please ensure Apple Intelligence is enabled in Settings."
            }
        case let sessionError as LanguageModelSession.Error:
            switch sessionError {
            case .concurrentRequests:
                return "Please wait for the current response to finish before sending another message."
            case .transcriptMutationWhileResponding:
                return "The response was interrupted. Please try again."
            @unknown default:
                return "The on-device model encountered an error. Please try again."
            }
        default:
            return "An error occurred while processing your request: \(error.localizedDescription)"
        }
    }

    /// Maps a model's unavailability to user-facing text. Apple reasons keep
    /// their original wording; Core AI models surface a "not installed" message.
    private func availabilityMessage(for reason: ModelProvider.Availability.Reason) -> String {
        switch reason {
        case .appleDeviceNotEligible:
            return "Apple Intelligence requires iPhone 15 Pro or later."
        case .appleIntelligenceNotEnabled:
            return "Please enable Apple Intelligence in Settings > Apple Intelligence & Siri."
        case .appleModelNotReady:
            return "The on-device model is still preparing. Please wait a moment and try again."
        case .notDownloaded:
            return "This model isn't installed yet. Choose a downloaded model in Settings."
        }
    }

    private func executeQuery(
        prompt: String,
        sessionId: String,
        for chatSession: ChatSession,
        sessionManager: ChatSessionManager,
        sources: [WebSearchResult]? = nil,
        isFirstMessage: Bool
    ) async {
        if case .unavailable(let reason) = modelProvider.availability(for: currentModelID) {
            let message = ChatMessage(text: availabilityMessage(for: reason), isUser: false, sources: sources)
            chatMessages.append(message)
            databaseManager.saveMessage(message, sessionId: sessionId)
            titleSessionOnFailure(for: chatSession, sessionManager: sessionManager, isFirstMessage: isFirstMessage)
            return
        }

        let session = await getSessionForChat(chatSession.id)
        do {
            let response = try await stream(prompt, using: session)
            await commitResponse(response, sessionId: sessionId,
                                 chatSession: chatSession, sessionManager: sessionManager,
                                 sources: sources, isFirstMessage: isFirstMessage)
            saveTranscript(session.transcript, sessionId: sessionId)
        } catch LanguageModelError.contextSizeExceeded {
            // Context window full — condense to a fresh session and retry once.
            let refreshed = await newSession(previousSession: session)
            sessions[chatSession.id] = refreshed
            do {
                let response = try await stream(prompt, using: refreshed)
                await commitResponse(response, sessionId: sessionId,
                                     chatSession: chatSession, sessionManager: sessionManager,
                                     sources: sources, isFirstMessage: isFirstMessage)
                saveTranscript(refreshed.transcript, sessionId: sessionId)
            } catch {
                handleError(error, sessionId: sessionId, for: chatSession,
                            sessionManager: sessionManager, isFirstMessage: isFirstMessage, sources: sources)
            }
        } catch {
            handleError(error, sessionId: sessionId, for: chatSession,
                        sessionManager: sessionManager, isFirstMessage: isFirstMessage, sources: sources)
        }
    }

    // MARK: - Query Methods

    func webSearch(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }

        userLLMResponse = nil
        userLLMQuery = UIQuery
        isWebSearching = true
        webSearchResults = []

        let isFirstMessage = chatMessages.isEmpty

        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        sessionManager.markSessionHasMessages(sessionId)

        let results = await webSearch.searchAndScrape(query: userLLMQuery)
        webSearchResults = results

        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.loadCollection()

        await withTaskGroup(of: Void.self) { group in
            for result in results {
                for chunk in webSearch.chunkText(result.content) {
                    group.addTask { await rag.addEntry(chunk) }
                }
            }
        }

        await rag.findLLMNeighbors(for: userLLMQuery)

        let semanticContext = rag.neighbors.prefix(3).map {
            "Relevance Score: \(String(format: "%.3f", $0.1))\n\($0.0)"
        }.joined(separator: "\n\n---\n\n")

        let prompt = """
                    Using the following web search results (ranked by relevance), please answer the question.

                    Web Content:
                    \(semanticContext)

                    Question: \(userLLMQuery)

                    Be accurate, cite sources when possible, and acknowledge if the content doesn't fully answer the question.
                    """

        await executeQuery(prompt: prompt, sessionId: sessionId, for: chatSession,
                           sessionManager: sessionManager, sources: results, isFirstMessage: isFirstMessage)
        isWebSearching = false
    }

    func queryLLM(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }

        userLLMResponse = nil
        userLLMQuery = UIQuery
        webSearchResults = []

        let isFirstMessage = chatMessages.isEmpty

        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        sessionManager.markSessionHasMessages(sessionId)

        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.loadCollection()
        // Restore the BM25 corpus from persisted chunks if this session was reopened
        // after a relaunch (no-op when chunks were already added this session).
        rag.seedCorpus(databaseManager.getAllChunks(for: chatSession.id))
        await rag.findLLMNeighbors(for: userLLMQuery)

        let contextItems = rag.neighbors.map { "- \($0.0)" }.joined(separator: "\n")
        let prompt = """
                    Using the following context from uploaded documents, please answer the question.

                    Context:
                    \(contextItems)

                    Question: \(userLLMQuery)

                    Answer based on the context above. If it doesn't contain enough information, say so clearly.
                    """

        await executeQuery(prompt: prompt, sessionId: sessionId, for: chatSession,
                           sessionManager: sessionManager, isFirstMessage: isFirstMessage)
    }

    func queryLLMGeneral(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }

        userLLMResponse = nil
        userLLMQuery = UIQuery
        webSearchResults = []

        let isFirstMessage = chatMessages.isEmpty

        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        sessionManager.markSessionHasMessages(sessionId)

        await executeQuery(prompt: userLLMQuery, sessionId: sessionId, for: chatSession,
                           sessionManager: sessionManager, isFirstMessage: isFirstMessage)
    }

    // MARK: - Title Generation

    func generateChatTitle(from aiResponse: String, for chatSession: ChatSession) async -> String {
        let prompt = """
        Generate a short, descriptive title (2-4 words) for a chat conversation based on this AI response. The title should capture the main topic or subject matter.

        AI Response: "\(aiResponse)"

        Instructions:
        1. Keep it concise (2-4 words maximum)
        2. Focus on the main topic or subject matter
        3. Don't include quotation marks
        4. Make it suitable as a chat title
        5. Use simple, clear language

        Title:
        """

        do {
            // Use a throwaway session (on the selected model) so the title prompt
            // never pollutes the chat's persisted conversation memory.
            let session = (try? await modelProvider.makeSession(for: currentModelID, instructions: Self.instructions))
                ?? LanguageModelSession { Self.instructions }
            let responseStream = session.streamResponse(to: prompt)
            var fullResponse = ""
            for try await partial in responseStream {
                fullResponse = partial.content
            }

            let cleanTitle = fullResponse
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\u{201C}", with: "")
                .replacingOccurrences(of: "\u{201D}", with: "")

            return cleanTitle.isEmpty ? "New Chat" : cleanTitle
        } catch {
            print("Error generating title: \(error)")
            return "New Chat"
        }
    }
}
