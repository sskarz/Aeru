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
        guard let collection = collection else { return }
        guard let embedding = generateEmbedding(for: entry) else {
            return
        }
        print("COLLECTION: ", collection)
        print("ENTRY STRING: ", entry)
        print("EMBEDDING: ", embedding)
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
    
    func findLLMNeighbors(for query: String) async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: query) else {
            return
        }
        let results = collection.search(query: queryEmbedding, num_results: 5)
        neighbors = results.map { ($0.text, $0.score) }
        print("NEIGHBORS: ", neighbors)
    }
    
    
}

