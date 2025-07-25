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
    
    // RAG
    var rag: RAGModel = RAGModel(collectionName: "dog")
    
    // LLM Generation
    @Published var userLLMQuery: String = ""
    @Published var userLLMResponse: String.PartiallyGenerated?
    
    // Web Search Services
    var webSearch: WebSearchService = WebSearchService()
    @Published var isWebSearching = false
    @Published var webSearchResults: [WebSearchResult] = []
    
    private var session: LanguageModelSession = LanguageModelSession()
    
    func webSearch(_ UIQuery: String) async throws {
        userLLMResponse = ""
        userLLMQuery = UIQuery
        isWebSearching = true
        webSearchResults = []
        
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
        for try await partialStream in responseStream {
            userLLMResponse = partialStream
        }
        isWebSearching = false
    }
    
    func queryLLM(_ UIQuery: String) async throws {
        userLLMResponse = ""
        userLLMQuery = UIQuery
        await rag.findLLMNeighbors(for: userLLMQuery)
        webSearchResults = [] // Clear web search results when using RAG
        
        let prompt = """
                    You are a helpful assistant that answers questions based on the provided context.
                    
                    Context:
                    \(rag.neighbors.map { $0.0 }.joined(separator: "\n"))
                    
                    Question: \(userLLMQuery)
                    
                    Instructions:
                    1. Answer based solely on the information provided in the context
                    2. If the context doesn't contain enough information, say so
                    3. Be concise and accurate
                    
                    Answer:
                    """
        let responseStream = session.streamResponse(to: prompt)
        for try await partialStream in responseStream {
            userLLMResponse = partialStream
        }
    }
    
    
}
