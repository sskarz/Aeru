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
    
    var collection: Collection? // documents, name
    // Document contains:
    // id: UUID (random ID)
    // text: String
    // embedding: [Double]
    
    // User Query
    let query: String = ""
    
    // user's query text, embedding score
    var neighbors: [(String, Double)] = []
    
    // Takes in document string and generates embedding, then adds to collection
    func addEntry(_ entry: String) async {
        guard let collection = collection else { return }
        guard let embedding = generateEmbedding(for: entry) else {
            return
        }

        collection.addDocument(text: entry, embedding: embedding)
    }

    // Takes in document string, creates an embedding and returns vector average
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

    // Takes in user query and generates embedding
    func findNeighbors() async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: query) else {
            return
        }

        let results = collection.search(query: queryEmbedding)
        neighbors = results.map { ($0.text, $0.score) }
    }
}
