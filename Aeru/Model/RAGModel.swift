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

    /// In-memory text corpus backing the BM25 lexical ranker. Populated by
    /// `addEntry` (web-search + freshly-uploaded chunks) and rebuilt from the
    /// database via `seedCorpus` for persisted document sessions after relaunch.
    private var corpus: [String] = []

    // Retrieval tuning knobs.
    private let candidatePoolSize = 8   // top-N pulled from each retriever before fusion
    private let fusedResultCount = 4    // final chunks fed to the prompt (4096-token budget)
    private let rrfK = 60.0             // Reciprocal Rank Fusion dampening constant

    init(collectionName: String) {
        self.collectionName = collectionName
    }

    /// Replaces the BM25 corpus only when empty, e.g. to restore document chunks
    /// from the database when a persisted session is reopened after a relaunch.
    func seedCorpus(_ texts: [String]) {
        guard corpus.isEmpty else { return }
        corpus = texts
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
        let embedding = generateEmbedding(for: entry)
        
        guard let embedding = embedding else {
            print("ERROR: Failed to generate embedding for entry: \(String(entry.prefix(100)))...")
            return
        }
        
        print("SUCCESS: Adding entry to collection")
        print("COLLECTION: ", collection)
        print("ENTRY STRING: ", String(entry.prefix(200)))
        print("EMBEDDING COUNT: ", embedding.count)
        collection.addDocument(text: entry, embedding: embedding)
        corpus.append(entry)
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
    
    /// Hybrid retrieval: rank chunks with both semantic vector search and the BM25
    /// lexical ranker, then combine the two ranked lists with Reciprocal Rank Fusion.
    /// Vector search captures meaning; BM25 rewards literal query-term presence —
    /// which is exactly what averaged word embeddings miss (e.g. a "SpaceX" query
    /// drowning in unrelated scraped text).
    func findLLMNeighbors(for query: String) async {
        guard let collection = collection else {
            print("ERROR: Collection is nil in findLLMNeighbors")
            return
        }

        // Vector candidates (gracefully empty if the query has no embedding).
        var vectorRanking: [String] = []
        if let queryEmbedding = generateEmbedding(for: query) {
            vectorRanking = collection
                .search(query: queryEmbedding, num_results: candidatePoolSize)
                .map { $0.text }
        } else {
            print("ERROR: Failed to generate query embedding — using BM25 only")
        }

        // Lexical candidates.
        let bm25Ranking = BM25Index(documents: corpus)
            .scores(for: query)
            .prefix(candidatePoolSize)
            .map { $0.text }

        // Reciprocal Rank Fusion: score = Σ 1 / (k + rank) across both lists.
        var fused: [String: Double] = [:]
        for (rank, text) in vectorRanking.enumerated() {
            fused[text, default: 0] += 1.0 / (rrfK + Double(rank))
        }
        for (rank, text) in bm25Ranking.enumerated() {
            fused[text, default: 0] += 1.0 / (rrfK + Double(rank))
        }

        neighbors = fused
            .sorted { $0.value > $1.value }
            .prefix(fusedResultCount)
            .map { ($0.key, $0.value) }

        print("SEARCH RESULTS: \(vectorRanking.count) vector + \(bm25Ranking.count) BM25 → \(neighbors.count) fused")
        for (index, neighbor) in neighbors.enumerated() {
            print("Neighbor \(index + 1): RRF \(String(format: "%.4f", neighbor.1)), Text: \(String(neighbor.0.prefix(100)))...")
        }
    }
}

/// A lightweight in-memory BM25 (Okapi) ranker over a fixed document corpus.
/// No model inference — just tokenization and term-frequency math — so it's cheap
/// enough to rebuild per query.
struct BM25Index {
    private let documents: [String]
    private let docTokens: [[String]]
    private let docLengths: [Int]
    private let averageLength: Double
    private let idf: [String: Double]

    private let k1 = 1.5
    private let b = 0.75

    init(documents: [String]) {
        self.documents = documents
        self.docTokens = documents.map { BM25Index.tokenize($0) }
        self.docLengths = docTokens.map { $0.count }
        self.averageLength = docLengths.isEmpty
            ? 0
            : Double(docLengths.reduce(0, +)) / Double(docLengths.count)

        // Document frequency → inverse document frequency.
        var docFrequency: [String: Int] = [:]
        for tokens in docTokens {
            for term in Set(tokens) {
                docFrequency[term, default: 0] += 1
            }
        }
        let n = Double(documents.count)
        var idf: [String: Double] = [:]
        for (term, df) in docFrequency {
            // Standard BM25 idf with +1 to stay non-negative.
            idf[term] = log(1 + (n - Double(df) + 0.5) / (Double(df) + 0.5))
        }
        self.idf = idf
    }

    /// Returns every document scored against the query, ranked highest first.
    func scores(for query: String) -> [(text: String, score: Double)] {
        guard !documents.isEmpty, averageLength > 0 else { return [] }
        let queryTerms = Set(BM25Index.tokenize(query))
        guard !queryTerms.isEmpty else { return [] }

        var results: [(text: String, score: Double)] = []
        for (i, tokens) in docTokens.enumerated() {
            var termFrequency: [String: Int] = [:]
            for token in tokens { termFrequency[token, default: 0] += 1 }

            var score = 0.0
            let lengthNorm = Double(docLengths[i]) / averageLength
            for term in queryTerms {
                guard let tf = termFrequency[term], let termIDF = idf[term] else { continue }
                let numerator = Double(tf) * (k1 + 1)
                let denominator = Double(tf) + k1 * (1 - b + b * lengthNorm)
                score += termIDF * (numerator / denominator)
            }
            if score > 0 { results.append((documents[i], score)) }
        }
        return results.sorted { $0.score > $1.score }
    }

    private static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        let lowercased = text.lowercased()
        tokenizer.string = lowercased
        return tokenizer.tokens(for: lowercased.startIndex..<lowercased.endIndex)
            .map { String(lowercased[$0]) }
    }
}
