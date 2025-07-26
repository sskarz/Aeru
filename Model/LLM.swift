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
    
    private var session: LanguageModelSession = LanguageModelSession()
    
    // Get or create RAG model for current session
    private func getRagForSession(_ sessionId: String, collectionName: String) -> RAGModel {
        if let existingRAG = ragModels[sessionId] {
            return existingRAG
        }
        
        let newRAG = RAGModel(collectionName: collectionName)
        ragModels[sessionId] = newRAG
        return newRAG
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
    
    func webSearch(_ UIQuery: String, for chatSession: ChatSession) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = ""
        userLLMQuery = UIQuery
        isWebSearching = true
        webSearchResults = []
        
        // Save user message
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
        // Perform web search and scraping
        let results = await webSearch.searchAndScrape(query: userLLMQuery)
        webSearchResults = results
        
        // Create context from web search results
        let webContext = results.map { result in
                """
                Title: \(result.title)
                Content: \(result.content)
                """
        }.joined(separator: "\n\n---\n\n")
        
        // Create enhanced prompt with web context
        let prompt = """
                    You are a helpful assistant that answers questions based on web search results.
                    
                    Web Search Results:
                    \(webContext)
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer concisely based primarily on the web search results above
                    2. Be accurate and cite the sources when possible
                    3. If the web results don't contain enough information, say so
                    4. Provide a comprehensive and informative response
                    
                    Answer:
                    """
        
        // Generate response using LLM
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
        
        // Clear streaming response to prevent duplicate display
        userLLMResponse = nil
        isWebSearching = false
    }
    
    func queryLLM(_ UIQuery: String, for chatSession: ChatSession) async throws {
        guard let sessionId = currentSessionId else { return }
        
        userLLMResponse = ""
        userLLMQuery = UIQuery
        webSearchResults = [] // Clear web search results when using RAG
        
        // Save user message
        let userMessage = ChatMessage(text: UIQuery, isUser: true)
        chatMessages.append(userMessage)
        databaseManager.saveMessage(userMessage, sessionId: sessionId)
        
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
        
        // Clear streaming response to prevent duplicate display
        userLLMResponse = nil
    }
    
    
}
