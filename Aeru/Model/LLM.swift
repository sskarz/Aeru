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

    private func newSession(previousSession: LanguageModelSession) -> LanguageModelSession {
        let all = previousSession.transcript
        var condensed = [Transcript.Entry]()
        if let first = all.first {
            condensed.append(first)
            if all.count > 1, let last = all.last { condensed.append(last) }
        }
        return LanguageModelSession(transcript: Transcript(entries: condensed))
    }

    private func getRagForSession(_ sessionId: String, collectionName: String) -> RAGModel {
        if let existing = ragModels[sessionId] { return existing }
        let rag = RAGModel(collectionName: collectionName)
        ragModels[sessionId] = rag
        return rag
    }

    private static let instructions = "You are a helpful, accurate, and concise AI assistant."

    private func getSessionForChat(_ sessionId: String) -> LanguageModelSession {
        if let existing = sessions[sessionId] { return existing }
        // Rehydrate the model's conversation memory from a saved transcript when
        // one exists, so follow-up questions keep context across app launches.
        let session: LanguageModelSession
        if let saved = loadTranscript(for: sessionId) {
            session = LanguageModelSession(transcript: saved)
        } else {
            session = LanguageModelSession { Self.instructions }
        }
        session.prewarm()
        sessions[sessionId] = session
        return session
    }

    /// Persists the model's transcript so its conversation memory survives launches.
    private func saveTranscript(_ transcript: Transcript, sessionId: String) {
        do {
            let data = try JSONEncoder().encode(transcript)
            guard let json = String(data: data, encoding: .utf8) else { return }
            databaseManager.saveTranscriptJSON(json, sessionId: sessionId)
        } catch {
            print("Failed to encode transcript: \(error)")
        }
    }

    private func loadTranscript(for sessionId: String) -> Transcript? {
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
        _ = getSessionForChat(session.id)
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
        for try await partial in responseStream {
            userLLMResponse = partial
            fullResponse = partial.content
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

    private func handleError(_ error: Error, sessionId: String, sources: [WebSearchResult]? = nil) {
        updateIsResponding()
        let message = ChatMessage(text: userFacingMessage(for: error), isUser: false, sources: sources)
        chatMessages.append(message)
        databaseManager.saveMessage(message, sessionId: sessionId)
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

    private func executeQuery(
        prompt: String,
        sessionId: String,
        for chatSession: ChatSession,
        sessionManager: ChatSessionManager,
        sources: [WebSearchResult]? = nil,
        isFirstMessage: Bool
    ) async {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            let text: String
            switch reason {
            case .deviceNotEligible:
                text = "Apple Intelligence requires iPhone 15 Pro or later."
            case .appleIntelligenceNotEnabled:
                text = "Please enable Apple Intelligence in Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                text = "The on-device model is still preparing. Please wait a moment and try again."
            }
            let message = ChatMessage(text: text, isUser: false, sources: sources)
            chatMessages.append(message)
            databaseManager.saveMessage(message, sessionId: sessionId)
            return
        }

        let session = getSessionForChat(chatSession.id)
        do {
            let response = try await stream(prompt, using: session)
            await commitResponse(response, sessionId: sessionId,
                                 chatSession: chatSession, sessionManager: sessionManager,
                                 sources: sources, isFirstMessage: isFirstMessage)
            saveTranscript(session.transcript, sessionId: sessionId)
        } catch LanguageModelError.contextSizeExceeded {
            // Context window full — condense to a fresh session and retry once.
            let refreshed = newSession(previousSession: session)
            sessions[chatSession.id] = refreshed
            do {
                let response = try await stream(prompt, using: refreshed)
                await commitResponse(response, sessionId: sessionId,
                                     chatSession: chatSession, sessionManager: sessionManager,
                                     sources: sources, isFirstMessage: isFirstMessage)
                saveTranscript(refreshed.transcript, sessionId: sessionId)
            } catch {
                handleError(error, sessionId: sessionId, sources: sources)
            }
        } catch {
            handleError(error, sessionId: sessionId, sources: sources)
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

        // Use a throwaway session so the title prompt never pollutes the
        // chat's persisted conversation memory.
        let session = LanguageModelSession { Self.instructions }

        do {
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
