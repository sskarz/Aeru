//
//  RAGView.swift
//  SVDBDemo
//
//  Created by Sanskar Thapa on July 15th, 2025.
//
// Resetting
import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import SwiftUI
import FoundationModels
import SwiftSoup
import Foundation
// Assuming WebSearchService is now in a separate file/module, import it here if needed
// import WebSearchService 

struct EmbeddingEntry: Codable {
    let id: UUID
    let text: String
    let embedding: [Double]
    let magnitude: Double
}

func generateRandomSentence() -> String {
    var sentence = ""
    for _ in 1...5 {
        if let randomWord = words.randomElement() {
            sentence += randomWord + " "
        }
    }
    return sentence.trimmingCharacters(in: .whitespaces)
}

// Main view
struct RAGView: View {
    let collectionName: String = "testCollection"
    @State private var collection: Collection?
    @State private var query: String = ""
    @State private var newEntry: String = ""
    @State private var neighbors: [(String, Double)] = []
    @State private var userLLMQuery: String = ""
    @State private var userLLMResponse: String.PartiallyGenerated = ""
    @State private var session: LanguageModelSession = LanguageModelSession()
    @State private var isWebSearching: Bool = false
    @State private var webSearchResults: [WebSearchResult] = []
    private let webSearchService = WebSearchService()

    var body: some View {
        VStack {
            TextField("Enter RAG Vector query", text: $query)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())

            HStack {
                TextField("New Entry", text: $newEntry)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add Entry") {
                    Task {
                        await addEntry(newEntry)
                    }
                }
            }
            .padding()

            Button("Generate Random Embeddings") {
                Task {
                    await generateRandomEmbeddings()
                }
            }
            .padding()
            
            HStack {
                TextField("User LLM Query", text: $userLLMQuery)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            HStack {
                Button("RAG LLM") {
                    Task {
                        try await queryLLM()
                    }
                }.padding()
                
                Button("Web Search") {
                    Task {
                        try await webSearch()
                    }
                }
                .padding()
                .disabled(isWebSearching)
                .overlay(
                    isWebSearching ?
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(.caption)
                    } : nil
                )
            }
            
            // Web search results indicato
            if !webSearchResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Web Sources Used:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    ForEach(Array(webSearchResults.enumerated()), id: \.offset) { index, result in
                        Text("• \(result.title)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            TextEditor(text: $userLLMResponse)
                .frame(minHeight: 100)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
                .background(Color(.systemGray6))
                .cornerRadius(8)
            

            List(neighbors, id: \.0) { neighbor in
                Text("\(neighbor.0) - \(neighbor.1)")
            }
            
        }
        .padding()
        .onAppear {
            Task {
                await loadCollection()
            }
        }
    }
    
    func webSearch() async throws {
        userLLMResponse = ""
        isWebSearching = true
        webSearchResults = []
        
        // Perform web search and scraping
        let results = await webSearchService.searchAndScrape(query: userLLMQuery)
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
        print("WEB SEARCH PROMPT: \n", prompt)
        
        // Generate response using LLM
        let responseStream = session.streamResponse(to: prompt)
        for try await partialStream in responseStream {
            userLLMResponse = partialStream
        }
        
        isWebSearching = false
    }
    
    func queryLLM() async throws {
        userLLMResponse = ""
        await findLLMNeighbors()
        webSearchResults = [] // Clear web search results when using RAG
        
        let prompt = """
                You are a helpful assistant that answers questions based on the provided context.
                
                Context:
                \(neighbors.map { $0.0 }.joined(separator: "\n"))
                
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

    func loadCollection() async {
        do {
            collection = try SVDB.shared.collection(collectionName)
        } catch {
            print("Failed to load collection:", error)
        }
    }

    func generateRandomEmbeddings() async {
        var randomSentences: [String] = []
        for _ in 1...100 {
            let sentence = generateRandomSentence()
            randomSentences.append(sentence)
        }

        for sentence in randomSentences {
            await addEntry(sentence)
        }

        print("Done creating")
    }

    // addentry reset the state reset the state
    func addEntry(_ entry: String) async {
        guard let collection = collection else { return }
        guard let embedding = generateEmbedding(for: entry) else {
            return
        }

        collection.addDocument(text: entry, embedding: embedding)
    }

    func generateEmbedding(for sentence: String) -> [Double]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return nil
        }

        let words = sentence.lowercased().split(separator: " ")
        guard let firstVector = embedding.vector(for: String(words.first!)) else {
            return nil
        }

        var vectorSum = [Double](firstVector)

        for word in words.dropFirst() {
            if let vector = embedding.vector(for: String(word)) {
                vDSP_vaddD(vectorSum, 1, vector, 1, &vectorSum, 1, vDSP_Length(vectorSum.count))
            }
        }

        var vectorAverage = [Double](repeating: 0, count: vectorSum.count)
        var divisor = Double(words.count)
        vDSP_vsdivD(vectorSum, 1, &divisor, &vectorAverage, 1, vDSP_Length(vectorAverage.count))

        return vectorAverage
    }
    
    func findLLMNeighbors() async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: userLLMQuery) else {
            return
        }
        
        let results = collection.search(query: queryEmbedding, num_results: 5)
        neighbors = results.map { ($0.text, $0.score) }
        print("NEIGHBORS: ", neighbors)
    }
}

struct RAGView_Previews: PreviewProvider {
    static var previews: some View {
        RAGView()
    }
}
