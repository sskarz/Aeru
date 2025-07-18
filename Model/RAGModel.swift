//
//  RAGModel.swift
//  RAGSearchLLM
//
//  Created by Sanskar Thapa on 7/15/25.
//
import Accelerate
import CoreML
import Foundation
import FoundationModels
import NaturalLanguage
import SVDB

class RAGModel {
    
    let collectionName: String = "rag_collection"
    var collection: Collection? // documents, name
    // Document contains:
    // id: UUID (random ID)
    // text: String
    // embedding: [Double]
    
    // User Query
    var query: String = ""
    
    // user's query text, embedding score
    var neighbors: [(String, Double)] = []
    
    public func setQuery(query: String) {
        self.query = query
    }
    
    func loadCollection() {
        do {
            print("Loading collection...")
            collection = try SVDB.shared.collection(collectionName)
        } catch {
            print("Failed to load collection:", error)
        }
    }
    
    // Takes in document string and generates embedding, then adds to collection
    public func addEntry(_ entry: String) async {
        guard let collection = collection else { return }
        guard let embedding = generateEmbedding(for: entry) else {
            return
        }

        collection.addDocument(text: entry, embedding: embedding)
    }

    // Takes in document string, creates an embedding and returns vector average
    private func generateEmbedding(for sentence: String) -> [Double]? {
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

    // Takes in user query and generates embedding
    private func findNeighbors() async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: query) else {
            return
        }

        let results = collection.search(query: queryEmbedding, num_results: 3)
        neighbors = results.map { ($0.text, $0.score) }
    }
    
    /**
     Ideally we have a function like this
     We also assume the user has uploaded 1 or more documents in collection
     
     func generateQuery() {
     we make sure the collection exists
     then we take the user's text query and embed it using generateEmbedding if it wasn't done so already
     then we compare the user's text query using findNeighbors and find the closest 3 text references
     then we include those as Context in a prompt
     then we create a session using LanguageModelSession
     then we generate the response with the prompt with Context
     }
     */
    
    public func generateAnswer(query: String) async throws -> String {
        setQuery(query: query)
        await findNeighbors()
        print("Current Context Neighbors: ", neighbors)
        
        let contextStrings = neighbors.map { $0.0 }
        let formattedContext = contextStrings.joined(separator: "\n")
        
        let session: LanguageModelSession = LanguageModelSession()
        let prompt = """
                You are a helpful assistant that answers questions based on the provided context.
                
                Context:
                \(formattedContext)
                
                Question: \(query)
                
                Instructions:
                1. Answer based solely on the information provided in the context
                2. If the context doesn't contain enough information, say so
                3. Be concise and accurate
                
                Answer:
                """
        print("THE PROMPT: \n", prompt)
        
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
