//
//  RAGModel.swift
//  Aeru
//
//  Created by Sanskar
//

import Foundation
import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import Combine
import FoundationModels

class RAGModel {
    
    let collectionName: String
    var collection: Collection?
    var neighbors: [(String, Double)] = []
    
    init(collectionName: String) {
        self.collectionName = collectionName
    }
    
    func loadCollection() async {
        if let existing = SVDB.shared.getCollection(collectionName) {
            self.collection = existing
            return
        }
        do {
            self.collection = try SVDB.shared.collection(collectionName)
        } catch {
            print("Failed to load collection:", error)
        }
    }
    
    func addEntry(_ entry: String) async {
        guard let collection = collection else { 
            print("ERROR: Collection is nil")
            return 
        }
        
        // Move embedding generation to background thread
        let embedding = await Task.detached(priority: .userInitiated) {
            return self.generateEmbedding(for: entry)
        }.value
        
        guard let embedding = embedding else {
            print("ERROR: Failed to generate embedding for entry: \(String(entry.prefix(100)))...")
            return
        }
        
        print("SUCCESS: Adding entry to collection")
        print("COLLECTION: ", collection)
        print("ENTRY STRING: ", String(entry.prefix(200)))
        print("EMBEDDING COUNT: ", embedding.count)
        collection.addDocument(text: entry, embedding: embedding)
        print("SUCCESS: Document added to collection")
    }
    
    func generateEmbedding(for sentence: String) -> [Double]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            print("ERROR: Failed to get NLEmbedding for English")
            return nil
        }
        
        let words = sentence.lowercased().split(separator: " ").map { String($0) }
        guard !words.isEmpty else {
            print("ERROR: No words found in sentence")
            return nil
        }
        
        var validVectors: [[Double]] = []
        
        for word in words {
            if let vector = embedding.vector(for: word) {
                validVectors.append([Double](vector))
            }
        }
        
        guard !validVectors.isEmpty else {
            print("ERROR: No valid word embeddings found for any words in: \(String(sentence.prefix(50)))...")
            return nil
        }
        
        let vectorLength = validVectors[0].count
        var vectorSum = [Double](repeating: 0, count: vectorLength)
        
        for vector in validVectors {
            vDSP_vaddD(vectorSum, 1, vector, 1, &vectorSum, 1, vDSP_Length(vectorSum.count))
        }
        
        var vectorAverage = [Double](repeating: 0, count: vectorSum.count)
        var divisor = Double(validVectors.count)
        vDSP_vsdivD(vectorSum, 1, &divisor, &vectorAverage, 1, vDSP_Length(vectorAverage.count))
        
        print("SUCCESS: Generated embedding with \(validVectors.count) valid word vectors out of \(words.count) total words")
        return vectorAverage
    }
    
    func findLLMNeighbors(for query: String) async {
        guard let collection = collection else { 
            print("ERROR: Collection is nil in findLLMNeighbors")
            return 
        }
        
        // Move query embedding generation to background thread
        let queryEmbedding = await Task.detached(priority: .userInitiated) {
            return self.generateEmbedding(for: query)
        }.value
        
        guard let queryEmbedding = queryEmbedding else {
            print("ERROR: Failed to generate query embedding")
            return
        }
        
        print("SUCCESS: Searching collection for query: \(query)")
        let results = collection.search(query: queryEmbedding, num_results: 3)
        neighbors = results.map { ($0.text, $0.score) }
        print("SEARCH RESULTS: Found \(results.count) neighbors")
        for (index, neighbor) in neighbors.enumerated() {
            print("Neighbor \(index + 1): Score \(neighbor.1), Text: \(String(neighbor.0.prefix(100)))...")
        }
    }
    
    
}

