//
//  RAGView.swift
//  RAGSearchLLMSwift
//
//  Created by Sanskar Thapa on July 15th, 2025.
//

import SwiftUI
import Foundation
import Combine

struct RAGView: View {
    @StateObject private var llm = LLM()
    @StateObject private var sessionManager = ChatSessionManager()
    
    @State private var messageText: String = ""
    @State private var useRAG: Bool = true
    @State private var useWebSearch: Bool = false
    @State private var showKnowledgeBase: Bool = false
    @State private var newEntry: String = ""
    @State private var showSidebar: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            if showSidebar {
                ChatSidebar(sessionManager: sessionManager)
                    .frame(width: 280)
            }
            
            // Main chat area
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Chat content
                if let currentSession = sessionManager.currentSession {
                    chatContentView(for: currentSession)
                } else {
                    emptyStateView
                }
                
                // Input area
                if sessionManager.currentSession != nil {
                    inputView
                }
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            // Initialize with first session or create one if none exist
            if sessionManager.sessions.isEmpty {
                _ = sessionManager.createNewSession()
            }
            
            if let currentSession = sessionManager.currentSession {
                llm.switchToSession(currentSession)
            }
        }
        .onChange(of: sessionManager.currentSession) { oldValue, newValue in
            if let session = newValue {
                llm.switchToSession(session)
            }
        }
        .sheet(isPresented: $showKnowledgeBase) {
            if let currentSession = sessionManager.currentSession {
                KnowledgeBaseView(llm: llm, session: currentSession, newEntry: $newEntry)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                // Sidebar toggle
                Button(action: { 
                    showSidebar.toggle()
                }) {
                    Image(systemName: "sidebar.leading")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                
                Text(sessionManager.currentSession?.displayTitle ?? "RAG Chat Assistant")
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
                    .toggleStyle(.switch)
                    .tint(.green)
                    .onChange(of: useRAG) { oldValue, newValue in
                        if newValue { useWebSearch = false }
                    }
                
                Toggle("Web Search", isOn: $useWebSearch)
                    .toggleStyle(.switch)
                    .tint(.blue)
                    .onChange(of: useWebSearch) { oldValue, newValue in
                        if newValue { useRAG = false }
                    }
            }
            .font(.subheadline)
            
            Divider()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color(.systemBackground))
    }
    
    private func chatContentView(for session: ChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(llm.chatMessages) { message in
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
            .onChange(of: llm.chatMessages.count) { oldValue, newValue in
                if let lastMessage = llm.chatMessages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "message")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No chat selected")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.gray)
            
            Text("Select a chat from the sidebar or create a new one")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        guard !trimmedMessage.isEmpty, let currentSession = sessionManager.currentSession else { return }
        
        // Clear input
        messageText = ""
        
        // Send to appropriate service
        Task {
            do {
                if useWebSearch {
                    try await llm.webSearch(trimmedMessage, for: currentSession)
                } else if useRAG {
                    try await llm.queryLLM(trimmedMessage, for: currentSession)
                }
            } catch {
                print("Error processing message: \(error)")
            }
        }
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
                            .easeInOut(duration: 0.6)
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
    let session: ChatSession
    @Binding var newEntry: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Knowledge to \(session.displayTitle)")
                        .font(.headline)
                    
                    TextField("Enter new knowledge entry...", text: $newEntry, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    
                    Button("Add Entry") {
                        Task {
                            await llm.addEntry(newEntry, to: session)
                            newEntry = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                if !llm.getRagNeighbors(for: session).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knowledge Base Entries")
                            .font(.headline)
                        
                        List(llm.getRagNeighbors(for: session), id: \.0) { neighbor in
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
