//
//  RAGView.swift
//  SVDBDemo
//
//  Created by Jordan Howlett on 8/4/23.
//

import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import SwiftUI
import FoundationModels

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

struct RAGView: View {
    let collectionName: String = "testCollection"
    @State private var collection: Collection?
    @State private var query: String = "emotions"
    @State private var newEntry: String = ""
    @State private var neighbors: [(String, Double)] = []
    @State private var userLLMQuery: String = ""
    @State private var userLLMResponse: String.PartiallyGenerated = ""

    var body: some View {
        VStack {
            TextField("Enter query", text: $query)
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

            Button("Find Neighbors") {
                self.neighbors.removeAll()
                Task {
                    await findNeighbors()
                    print("CURRENT NEIGHBORS: -----------------------------------\n", neighbors)
                }
            }

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
                Button("Query LLM") {
                    Task {
                        try await queryLLM()
                    }
                }
            }
            TextEditor(text: $userLLMResponse)
                .frame(minHeight: 100, maxHeight: 250)
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
    
    func queryLLM() async throws {
        let session: LanguageModelSession = LanguageModelSession()
        await findLLMNeighbors()
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

    func findNeighbors() async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: query) else {
            return
        }

        let results = collection.search(query: queryEmbedding, num_results: 5)
        neighbors = results.map { ($0.text, $0.score) }
    }
    
    func findLLMNeighbors() async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: userLLMQuery) else {
            return
        }

        let results = collection.search(query: queryEmbedding)
        neighbors = results.map { ($0.text, $0.score) }
    }
}

struct RAGView_Previews: PreviewProvider {
    static var previews: some View {
        RAGView()
    }
}
