//
//  RAGView.swift
//  RAGSearchLLMSwift
//
//  Created by Sanskar Thapa on July 15th, 2025.
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

struct RAGView: View {
    @StateObject private var llm = LLM()
    @StateObject private var sessionManager = ChatSessionManager()
    
    @State private var messageText: String = ""
    @State private var useRAG: Bool = true
    @State private var useWebSearch: Bool = false
    @State private var showKnowledgeBase: Bool = false
    @State private var newEntry: String = ""
    @State private var showSidebar: Bool = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar
                if showSidebar {
                    ChatSidebar(sessionManager: sessionManager)
                        .frame(width: min(300, geometry.size.width * 0.35))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    // Divider between sidebar and main content
                    Divider()
                }
                
                // Main chat area.
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Sidebar toggle
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSidebar.toggle()
                    }
                }) {
                    Image(systemName: showSidebar ? "sidebar.left" : "sidebar.leading")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionManager.currentSession?.displayTitle ?? "RAG Chat Assistant")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: { showKnowledgeBase.toggle() }) {
                    Image(systemName: "books.vertical")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }
    
    private func chatContentView(for session: ChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Add some top padding if no messages
                    if llm.chatMessages.isEmpty {
                        Spacer()
                            .frame(height: 50)
                    }
                    
                    ForEach(llm.chatMessages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                    
                    // Streaming response display
                    if let streamingResponse = llm.userLLMResponse {
                        ChatBubbleView(message: ChatMessage(text: streamingResponse.description, isUser: false))
                            .id("streaming")
                    }
                    
                    // Loading indicator
                    if llm.isWebSearching && llm.userLLMResponse == nil {
                        TypingIndicatorView()
                            .id("typing")
                    }
                    
                    // Bottom spacer for better scroll behavior
                    Spacer()
                        .frame(height: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: llm.chatMessages.count) { oldValue, newValue in
                if let lastMessage = llm.chatMessages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: llm.userLLMResponse) { oldValue, newValue in
                if newValue != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: llm.isWebSearching) { oldValue, newValue in
                if newValue && llm.userLLMResponse == nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "message.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No chat selected")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Click the sidebar button to view your chats or create a new one to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var inputView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .lineLimit(1...4)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                      Color.gray.opacity(0.6) : Color.blue)
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
    
    @State private var showDocumentPicker = false
    @State private var isProcessingDocument = false
    @State private var documents: [(id: String, name: String, type: String, uploadedAt: Date)] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Text Entry Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Text Knowledge to \(session.displayTitle)")
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
                
                // Document Upload Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upload Documents")
                        .font(.headline)
                    
                    Button(action: { showDocumentPicker = true }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("Upload PDF Document")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isProcessingDocument)
                    
                    if isProcessingDocument {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing document...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Uploaded Documents List
                if !documents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Uploaded Documents")
                            .font(.headline)
                        
                        List(documents, id: \.id) { document in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("Uploaded: \(document.uploadedAt, style: .date)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
                
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
            .onAppear {
                loadDocuments()
            }
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleDocumentSelection(result)
            }
        }
    }
    
    private func loadDocuments() {
        documents = llm.getDocuments(for: session)
    }
    
    private func handleDocumentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            isProcessingDocument = true
            
            Task {
                let success = await llm.processDocument(url: url, for: session)
                
                await MainActor.run {
                    isProcessingDocument = false
                    if success {
                        loadDocuments()
                    }
                }
            }
            
        case .failure(let error):
            print("Document selection failed: \(error)")
        }
    }
}

struct RAGView_Previews: PreviewProvider {
    static var previews: some View {
        RAGView()
    }
}
