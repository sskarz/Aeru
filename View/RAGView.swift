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

// Main view
struct RAGView: View {
    @StateObject private var llm = LLM()
    @StateObject private var rag = RAGModel()
    
    @State private var newEntry: String = ""
    @State private var userLLMQuery: String = ""
    @State private var userLLMResponse: String.PartiallyGenerated = ""
    @State private var isWebSearching: Bool = false
    @State private var webSearchResults: [WebSearchResult] = []

    var body: some View {
        VStack {
            HStack {
                TextField("New Entry", text: $newEntry)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add Entry") {
                    Task {
                        await rag.addEntry(newEntry)
                    }
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
                        try await llm.queryLLM(userLLMQuery)
                        if let userLLMResponse = llm.userLLMResponse {
                            self.userLLMResponse = userLLMResponse
                        }
                    }
                }.padding()
                
                Button("Web Search") {
                    Task {
                        try await llm.webSearch(userLLMQuery)
                        if let userLLMResponse = llm.userLLMResponse {
                            self.userLLMResponse = userLLMResponse
                        }
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
            

            List(rag.neighbors, id: \.0) { neighbor in
                Text("\(neighbor.0) - \(neighbor.1)")
            }
            
        }
        .padding()
        .onAppear {
            Task {
                await rag.loadCollection()
            }
        }
    }
}

struct RAGView_Previews: PreviewProvider {
    static var previews: some View {
        RAGView()
    }
}
