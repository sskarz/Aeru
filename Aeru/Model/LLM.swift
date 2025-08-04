//
//  LLM.swift
//  RAGSearchLLMSwift
//
//  Created by Sanskar Thapa on 7/21/25.
//

import Foundation
import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import Combine
import FoundationModels

@MainActor
class LLM: ObservableObject {
    
    // Contains all the generation and invokes RAGModel.swift and WebSearchService.swift
    
    // RAG - now managed per chat session
    private var ragModels: [String: RAGModel] = [:]
    
    // LLM Generation
    @Published var userLLMQuery: String = ""
    @Published var userLLMResponse: String.PartiallyGenerated?
    
    // Web Search Services
    var webSearch: WebSearchService = WebSearchService()
    @Published var isWebSearching = false
    @Published var webSearchResults: [WebSearchResult] = []
    
    // Chat session management
    @Published var chatMessages: [ChatMessage] = []
    private var currentSessionId: String?
    private let databaseManager = DatabaseManager.shared
    
    private lazy var session: LanguageModelSession = LanguageModelSession()
    
    private func newSession(previousSession: LanguageModelSession) -> LanguageModelSession {
        let allEntries = previousSession.transcript
        var condensedEntries = [Transcript.Entry]()
        print("\nCONDENSED ENTRIES: ", condensedEntries)
        if let firstEntry = allEntries.first {
            condensedEntries.append(firstEntry)
            if allEntries.count > 1, let lastEntry = allEntries.last {
                condensedEntries.append(lastEntry)
            }
        }
        let condensedTranscript = Transcript(entries: condensedEntries)
        return LanguageModelSession(transcript: condensedTranscript)
    }
    
    // Get or create RAG model for current session
    private func getRagForSession(_ sessionId: String, collectionName: String) -> RAGModel {
        if let existingRAG = ragModels[sessionId] {
            return existingRAG
        }
        
        let newRAG = RAGModel(collectionName: collectionName)
        ragModels[sessionId] = newRAG
        return newRAG
    }
    
    func sessionHasDocuments(_ session: ChatSession) -> Bool {
        let documents = databaseManager.getDocuments(for: session.id)
        return !documents.isEmpty
    }
    
    func queryIntelligently(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager, useWebSearch: Bool) async throws {
        // Intelligent routing logic:
        // 1. If web search is toggled, use web search
        // 2. If session has 1 or more documents, use RAG
        // 3. Else use general query
        
        if useWebSearch {
            try await webSearch(UIQuery, for: chatSession, sessionManager: sessionManager)
        } else if sessionHasDocuments(chatSession) {
            try await queryLLM(UIQuery, for: chatSession, sessionManager: sessionManager)
        } else {
            try await queryLLMGeneral(UIQuery, for: chatSession, sessionManager: sessionManager)
        }
    }
    
    func switchToSession(_ session: ChatSession) {
        currentSessionId = session.id
        loadMessagesForCurrentSession()
    }
    
    func loadMessagesForCurrentSession() {
        guard let sessionId = currentSessionId else {
            chatMessages = []
            return
        }
        
        chatMessages = databaseManager.getMessages(for: sessionId)
    }
    
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
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let extractedText = DocumentProcessor.extractTextFromPDF(at: url) else {
            print("Failed to extract text from PDF")
            return false
        }
        
        let originalFileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        let baseName = originalFileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        let uniqueFileName = "\(baseName)_\(UUID().uuidString).\(fileExtension)"
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsDirectory.appendingPathComponent("Documents").appendingPathComponent(uniqueFileName)
        
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
        print("SUCCESS: Extracted \(extractedText.count) characters from PDF")
        print("SUCCESS: Created \(chunks.count) chunks from text")
        
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        await rag.loadCollection()
        
        for (index, chunk) in chunks.enumerated() {
            print("Processing chunk \(index + 1)/\(chunks.count): \(String(chunk.prefix(100)))...")
            
            if let chunkId = databaseManager.saveDocumentChunk(
                documentId: documentId,
                text: chunk,
                index: index
            ) {
                print("SUCCESS: Saved chunk \(index + 1) to database")
                await rag.addEntry(chunk)
                databaseManager.markChunkAsEmbedded(chunkId)
                print("SUCCESS: Added chunk \(index + 1) to RAG and marked as embedded")
            } else {
                print("ERROR: Failed to save chunk \(index + 1) to database")
            }
        }
        
        return true
    }
    
    func getDocuments(for session: ChatSession) -> [(id: String, name: String, type: String, uploadedAt: Date)] {
        return databaseManager.getDocuments(for: session.id)
    }
    
    func getRagNeighbors(for session: ChatSession) -> [(String, Double)] {
        let rag = getRagForSession(session.id, collectionName: session.collectionName)
        return rag.neighbors
    }
    
    func webSearch(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = ""
        userLLMQuery = UIQuery
        isWebSearching = true
        webSearchResults = []
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Generate title first if this is the first message
        if isFirstMessage && chatSession.title.isEmpty {
            print("🔍 WebSearch: Generating title for first message. Session ID: \(chatSession.id)")
            let generatedTitle = await generateChatTitle(from: UIQuery)
            print("🔍 WebSearch: Generated title: '\(generatedTitle)'")
            sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
            print("🔍 WebSearch: Title update completed")
        }
        
        // Perform web search and scraping
        let results = await webSearch.searchAndScrape(query: userLLMQuery)
        webSearchResults = results
        
        // Get or create RAG model for this session
        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.loadCollection()
        
        // Embed all scraped content into RAG
        for result in results {
            let chunks = webSearch.chunkText(result.content)
            for chunk in chunks {
                await rag.addEntry(chunk)
            }
        }
        
        // Use semantic similarity to find top 3 most relevant chunks
        await rag.findLLMNeighbors(for: userLLMQuery)
        
        // Get top 3 neighbors for context
        let topNeighbors = Array(rag.neighbors.prefix(3))
        let semanticContext = topNeighbors.map { neighbor in
            "Relevance Score: \(String(format: "%.3f", neighbor.1))\n\(neighbor.0)"
        }.joined(separator: "\n\n---\n\n")
        
        // Create enhanced prompt with semantic search results
        let prompt = """
                    You are a helpful assistant that answers questions based on semantically relevant web search results.
                    
                    Most Relevant Web Content (ranked by semantic similarity):
                    \(semanticContext)
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer based primarily on the most relevant content above (higher relevance scores are more important)
                    2. Be accurate and cite the sources when possible
                    3. If the content doesn't fully answer the question, acknowledge the limitations
                    4. Provide a comprehensive and informative response based on the available information
                    
                    Answer:
                    """
        
        // Generate response using LLM
        do {
            let responseStream = session.streamResponse(to: prompt)
            var fullResponse = ""
            for try await partialStream in responseStream {
                userLLMResponse = partialStream
                fullResponse = partialStream.description
            }
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false, sources: results)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // New session, with some history from the previous session
            session = newSession(previousSession: session)
            // Retry with new session
            do {
                let responseStream = session.streamResponse(to: prompt)
                var fullResponse = ""
                for try await partialStream in responseStream {
                    userLLMResponse = partialStream
                    fullResponse = partialStream.description
                }
                
                // Save assistant message
                let assistantMessage = ChatMessage(text: fullResponse, isUser: false, sources: results)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
            } catch {
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false, sources: results)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false, sources: results)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            // Handle errors including guardrail violations
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false, sources: results)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
        
        // Clear streaming response to prevent duplicate display
        userLLMResponse = nil
        isWebSearching = false
    }
    
    func generateChatTitle(from prompt: String) async -> String {
        let titlePrompt = """
        Generate a short, descriptive title (3-4 words) for a chat conversation that starts with this message. The title should capture the main topic or question being asked.
        
        Message: "\(prompt)"
        
        Instructions:
        1. Keep it concise (3-6 words maximum)
        2. Focus on the main topic or intent
        3. Don't include quotation marks
        4. Make it suitable as a chat title
        5. If it's a general greeting, use "General Chat"
        
        Title:
        """
        
        do {
            let responseStream = session.streamResponse(to: titlePrompt)
            var fullResponse = ""
            for try await partialStream in responseStream {
                fullResponse = partialStream.description
            }
            
            let cleanTitle = fullResponse
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: """
                , with: "")
                .replacingOccurrences(of:
 """, with: "")
            
            return cleanTitle.isEmpty ? "New Chat" : cleanTitle
        } catch {
            print("Error generating title: \(error)")
            return "New Chat"
        }
    }
    
    func queryLLM(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = ""
        userLLMQuery = UIQuery
        webSearchResults = [] // Clear web search results when using RAG
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Generate title first if this is the first message
        if isFirstMessage && chatSession.title.isEmpty {
            print("📚 RAG: Generating title for first message. Session ID: \(chatSession.id)")
            let generatedTitle = await generateChatTitle(from: UIQuery)
            print("📚 RAG: Generated title: '\(generatedTitle)'")
            sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
            print("📚 RAG: Title update completed")
        }
        
        let rag = getRagForSession(chatSession.id, collectionName: chatSession.collectionName)
        await rag.loadCollection()
        await rag.findLLMNeighbors(for: userLLMQuery)
        
        let contextItems = rag.neighbors.map { "- \($0.0)" }.joined(separator: "\n")
        let prompt = """
                    You are a helpful assistant that answers questions based on the provided context from uploaded documents and knowledge base.
                    
                    Context:
                    \(contextItems)
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer based primarily on the information provided in the context above
                    2. If the context contains relevant information from uploaded documents, prioritize that
                    3. If the context doesn't contain enough information, say so clearly
                    4. Be concise and accurate
                    
                    Answer:
                    """
        do {
            let responseStream = session.streamResponse(to: prompt)
            var fullResponse = ""
            for try await partialStream in responseStream {
                userLLMResponse = partialStream
                fullResponse = partialStream.description
            }
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // New session, with some history from the previous session
            session = newSession(previousSession: session)
            // Retry with new session
            do {
                let responseStream = session.streamResponse(to: prompt)
                var fullResponse = ""
                for try await partialStream in responseStream {
                    userLLMResponse = partialStream
                    fullResponse = partialStream.description
                }
                
                // Save assistant message
                let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
            } catch {
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            // Handle errors including guardrail violations
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to safety guidelines. Please try rephrasing your question."
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
        
        // Clear streaming response to prevent duplicate display
        userLLMResponse = nil
    }
    
    func queryLLMGeneral(_ UIQuery: String, for chatSession: ChatSession, sessionManager: ChatSessionManager) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = ""
        userLLMQuery = UIQuery
        webSearchResults = [] // Clear web search results when using general mode
        
        // Check if this is the first message in the session
        let isFirstMessage = chatMessages.isEmpty
        
        // Save user message immediately so it displays right away
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Generate title first if this is the first message
        if isFirstMessage && chatSession.title.isEmpty {
            print("💬 General: Generating title for first message. Session ID: \(chatSession.id)")
            let generatedTitle = await generateChatTitle(from: UIQuery)
            print("💬 General: Generated title: '\(generatedTitle)'")
            sessionManager.updateSessionTitleIfEmpty(chatSession, with: generatedTitle)
            print("💬 General: Title update completed")
        }
        
        // Create a simple prompt without RAG context or web search results
        let prompt = """
                    You are a helpful assistant. Answer the following question based on your general knowledge and training.
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Provide a helpful and accurate response based on your general knowledge
                    2. Be concise and informative
                    3. If you're not certain about something, mention that
                    4. Use a conversational tone
                    
                    Answer:
                    """
        print("--------------------\nMODEL TRANSCRIPT:\n ", session.transcript)
        
        do {
            let responseStream = session.streamResponse(to: prompt)
            var fullResponse = ""
            for try await partialStream in responseStream {
                userLLMResponse = partialStream
                fullResponse = partialStream.description
            }
            
            // Save assistant message
            let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // New session, with some history from the previous session
            session = newSession(previousSession: session)
            // Retry with new session
            do {
                let responseStream = session.streamResponse(to: prompt)
                var fullResponse = ""
                for try await partialStream in responseStream {
                    userLLMResponse = partialStream
                    fullResponse = partialStream.description
                }
                
                // Save assistant message
                let assistantMessage = ChatMessage(text: fullResponse, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
                
            } catch {
                let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                    "Sorry, I cannot provide a response to that query due to Apple's safety guidelines. Please try rephrasing your question."
                } else {
                    "An error occurred while processing your request: \(error.localizedDescription)"
                }
                
                let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
                chatMessages.append(assistantMessage)
                databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
            }
        } catch LanguageModelSession.GenerationError.rateLimited {
            let errorMessage = "The on-device model is currently rate limited. Please wait a moment and try again."
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        } catch {
            // Handle errors including guardrail violations
            let errorMessage = if error.localizedDescription.contains("GenerationError error 2") {
                "Sorry, I cannot provide a response to that query due to Apple's safety guidelines. Please try rephrasing your question."
            } else {
                "An error occurred while processing your request: \(error.localizedDescription)"
            }
            
            let assistantMessage = ChatMessage(text: errorMessage, isUser: false)
            chatMessages.append(assistantMessage)
            databaseManager.saveMessage(assistantMessage, sessionId: sessionId)
        }
        
        // Clear streaming response to prevent duplicate display
        userLLMResponse = nil
    }
    
    
}
