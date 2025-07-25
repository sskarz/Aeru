//
//  RAGView.swift
//  RAGSearchLLMSwift
//
//  Created by Sanskar Thapa on July 15th, 2025.
//

import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import SwiftUI
import FoundationModels
import SwiftSoup
import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let sources: [WebSearchResult]?
    let timestamp: Date
    
    init(text: String, isUser: Bool, sources: [WebSearchResult]? = nil) {
        self.text = text
        self.isUser = isUser
        self.sources = sources
        self.timestamp = Date()
    }
}

struct RAGView: View {
    @StateObject private var llm = LLM()
    
    @State private var messageText: String = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var useRAG: Bool = true
    @State private var useWebSearch: Bool = false
    @State private var showKnowledgeBase: Bool = false
    @State private var newEntry: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(chatMessages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                        
                        // Loading indicator
                        if llm.isWebSearching || llm.userLLMResponse != nil {
                            TypingIndicatorView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: chatMessages.count) { _ in
                    if let lastMessage = chatMessages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: llm.userLLMResponse) { response in
                    if let response = response, !response.description.isEmpty {
                        updateLastAssistantMessage(with: response.description)
                    }
                }
            }
            
            // Input area
            inputView
        }
        .background(Color(.systemBackground))
        .onAppear {
            Task {
                await llm.rag.loadCollection()
            }
        }
        .sheet(isPresented: $showKnowledgeBase) {
            KnowledgeBaseView(llm: llm, newEntry: $newEntry)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("RAG Chat Assistant")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { showKnowledgeBase.toggle() }) {
                    Image(systemName: "books.vertical")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            
            // Mode toggles
            HStack(spacing: 20) {
                Toggle("RAG Mode", isOn: $useRAG)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                
                Toggle("Web Search", isOn: $useWebSearch)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            .font(.subheadline)
            
            Divider()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color(.systemBackground))
    }
    
    private var inputView: some View {
        VStack(spacing: 8) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...4)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                      Color.gray : Color.blue)
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(text: trimmedMessage, isUser: true)
        chatMessages.append(userMessage)
        
        // Clear input
        messageText = ""
        
        // Add placeholder assistant message
        let assistantMessage = ChatMessage(text: "", isUser: false)
        chatMessages.append(assistantMessage)
        
        // Send to appropriate service
        Task {
            do {
                if useWebSearch {
                    try await llm.webSearch(trimmedMessage)
                } else if useRAG {
                    try await llm.queryLLM(trimmedMessage)
                }
            } catch {
                updateLastAssistantMessage(with: "Sorry, there was an error processing your request.")
            }
        }
    }
    
    private func updateLastAssistantMessage(with text: String) {
        guard let lastIndex = chatMessages.lastIndex(where: { !$0.isUser }) else { return }
        
        let sources = useWebSearch ? llm.webSearchResults : nil
        chatMessages[lastIndex] = ChatMessage(
            text: text,
            isUser: false,
            sources: sources
        )
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(message.isUser ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                
                // Web sources
                if let sources = message.sources, !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sources:")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)  
                        
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            Text("• \(source.title)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            
            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
    }
}

struct TypingIndicatorView: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 6, height: 6)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray5))
            )
            
            Spacer(minLength: 50)
        }
        .onAppear {
            animating = true
        }
    }
}

struct KnowledgeBaseView: View {
    let llm: LLM
    @Binding var newEntry: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Knowledge")
                        .font(.headline)
                    
                    TextField("Enter new knowledge entry...", text: $newEntry, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    
                    Button("Add Entry") {
                        Task {
                            await llm.rag.addEntry(newEntry)
                            newEntry = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                if !llm.rag.neighbors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knowledge Base Entries")
                            .font(.headline)
                        
                        List(llm.rag.neighbors, id: \.0) { neighbor in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(neighbor.0)
                                    .font(.body)
                                Text("Similarity: \(String(format: "%.3f", neighbor.1))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Knowledge Base")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RAGView_Previews: PreviewProvider {
    static var previews: some View {
        RAGView()
    }
}
