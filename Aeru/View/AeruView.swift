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
import WebKit
import UIKit
import MarkdownUI
import FoundationModels


struct BrowserURL: Identifiable {
    let id = UUID()
    let url: String
}

struct AeruView: View {
    @StateObject private var llm = LLM()
    @StateObject private var sessionManager = ChatSessionManager()
    @StateObject private var networkConnectivity = NetworkConnectivity()
    
    @State private var messageText: String = ""
    // useWebSearch is now per-session, computed from currentSession
    @State private var showKnowledgeBase: Bool = false
    @State private var newEntry: String = ""
    @State private var showSidebar: Bool = false
    @State private var webBrowserURL: BrowserURL? = nil
    @State private var showConnectivityAlert: Bool = false
    @FocusState private var isMessageFieldFocused: Bool
    
    // Sidebar animation properties
    @State private var offset: CGFloat = 0
    @GestureState private var gestureOffset: CGFloat = 0
    
    private var sidebarWidth: CGFloat {
        UIScreen.main.bounds.width * 0.8
    }

    private var isModelResponding: Bool {
        llm.userLLMResponse != nil || llm.isWebSearching
    }
    
    private var shouldDisableNewChatButton: Bool {
        // Enable if no sessions exist (user needs a way to create first chat)
        guard !sessionManager.sessions.isEmpty else { return false }
        
        // Disable if current chat is empty (new chat with 0 messages) or model is responding
        return llm.chatMessages.isEmpty || isModelResponding
    }
    
    private var useWebSearch: Bool {
        sessionManager.currentSession?.useWebSearch ?? false
    }
    
    private func handleNewChatCreation() {
        let result = sessionManager.createNewSession(title: "")
        switch result {
        case .success(_):
            // Successfully created new chat
            break
        case .duplicateUntitled:
            // Redirect to existing new chat instead of showing alert
            if let existingNewChat = sessionManager.sessions.first(where: { $0.title.isEmpty }) {
                sessionManager.selectSession(existingNewChat)
            }
        case .duplicateTitle, .databaseError:
            // Handle other errors if needed
            break
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Main chat area (gets pushed by sidebar)
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
                .background(Color(.systemBackground))
                .offset(x: max(offset + gestureOffset, 0))
                .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: gestureOffset)
                .overlay(
                    // Overlay for dimming when sidebar is open
                    Color.black.opacity(getOverlayOpacity())
                        .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: showSidebar)
                        .onTapGesture {
                            withAnimation {
                                showSidebar = false
                            }
                        }
                        .allowsHitTesting(showSidebar)
                )
                
                // Sidebar
                ChatSidebar(sessionManager: sessionManager, shouldDisableNewChatButton: shouldDisableNewChatButton)
                    .frame(width: sidebarWidth)
                    .offset(x: -sidebarWidth)
                    .offset(x: max(offset + gestureOffset, 0))
                    .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: gestureOffset)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .updating($gestureOffset) { value, out, _ in
                        let translation = value.translation.width
                        let translationHeight = value.translation.height
                        
                        // Only activate for predominantly horizontal gestures
                        guard abs(translation) > abs(translationHeight) * 1.5 else { return }
                        
                        if showSidebar {
                            // When sidebar is open, allow closing gesture (drag right to left)
                            out = max(translation, -sidebarWidth)
                        } else {
                            // When sidebar is closed, allow opening gesture (drag left to right)
                            // Apply the translation directly but clamp it to sidebarWidth
                            out = max(0, min(translation, sidebarWidth))
                        }
                    }
                    .onEnded(onDragEnd)
            )
            .onChange(of: showSidebar) { _, newValue in
                withAnimation {
                    offset = newValue ? sidebarWidth : 0
                }
            }
        }
        .onAppear {
            // Defer heavy initialization to avoid blocking UI
            Task {
                // Wait for sessions to load from database first
                await MainActor.run {
                    sessionManager.loadSessions()
                }
                
                // Only create a new session if none exist after loading
                if sessionManager.sessions.isEmpty {
                    _ = sessionManager.createNewSession()
                }
                
                if let currentSession = sessionManager.currentSession {
                    llm.switchToSession(currentSession)
                }
            }
        }
        .onChange(of: sessionManager.currentSession) { oldValue, newValue in
            if let session = newValue {
                llm.switchToSession(session)
            }
        }
        .sheet(isPresented: $showKnowledgeBase) {
            if let currentSession = sessionManager.currentSession {
                KnowledgeBaseView(llm: llm, session: currentSession, newEntry: $newEntry, sessionManager: sessionManager)
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $webBrowserURL) { browserURL in
            WebBrowserView(url: browserURL.url)
        }
        .alert("No Internet Connection", isPresented: $showConnectivityAlert) {
            Button("OK") { }
        } message: {
            Text("Please turn on cellular or WiFi to use web search functionality.")
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Sidebar toggle
                Button(action: { 
                    isMessageFieldFocused = false
                    showSidebar.toggle()
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                }
                
                VStack(alignment: .center, spacing: 2) {
                    Text(sessionManager.currentSession?.displayTitle ?? "Aeru")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                
                // New chat button
                Button(action: handleNewChatCreation) {
                    Image(systemName: "plus.message")
                        .font(.title3)
                        .foregroundColor(shouldDisableNewChatButton ? .gray : .blue)
                        .frame(width: 24, height: 24)
                }
                .disabled(shouldDisableNewChatButton)
                
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            
            Divider()
        }
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
                        ChatBubbleView(message: message) { url in
                            webBrowserURL = BrowserURL(url: url)
                        }
                        .id(message.id)
                    }
                    
                    // Streaming response display
                    if let streamingResponse = llm.userLLMResponse {
                        ChatBubbleView(message: ChatMessage(text: streamingResponse.content, isUser: false)) { url in
                            webBrowserURL = BrowserURL(url: url)
                        }
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
            .scrollDismissesKeyboard(.immediately)
            
            .onChange(of: llm.chatMessages.count) { oldValue, newValue in
                if let lastMessage = llm.chatMessages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onReceive(llm.$userLLMResponse) { newValue in
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
        VStack(spacing: 12) {
            // Upload button, text input and send button
            HStack(spacing: 12) {
                // Document upload button
                Button(action: { showKnowledgeBase.toggle() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6))
                        )
                }
                .glassEffect(.regular.interactive())
                
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isMessageFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .lineLimit(1...2)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .glassEffect(.regular.interactive())
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isModelResponding ? 
                                      Color.gray.opacity(0.6) : Color.blue)
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isModelResponding)
                .glassEffect(.regular.interactive())
            }
            
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, let currentSession = sessionManager.currentSession else { return }
        
        // Check connectivity for web search
        if useWebSearch && !NetworkConnectivity.hasActiveConnection() {
            showConnectivityAlert = true
            return
        }
        
        // Clear input
        messageText = ""
        
        // Send to appropriate service using intelligent routing
        Task {
            do {
                try await llm.queryIntelligently(trimmedMessage, for: currentSession, sessionManager: sessionManager, useWebSearch: useWebSearch)
            } catch {
                print("Error processing message: \(error)")
            }
        }
    }
    
    private func onDragEnd(value: DragGesture.Value) {
        let translation = value.translation.width
        let translationHeight = value.translation.height
        let velocity = value.velocity.width
        
        // Only process predominantly horizontal gestures
        guard abs(translation) > abs(translationHeight) * 1.5 else { return }
        
        // Use a lower threshold for iOS 26 compatibility
        let threshold = sidebarWidth * 0.3
        
        if showSidebar {
            // Sidebar is open - check if should close
            if translation < -threshold || velocity < -500 {
                showSidebar = false
            } else {
                showSidebar = true // Keep open
            }
        } else {
            // Sidebar is closed - check if should open
            if translation > threshold || velocity > 500 {
                showSidebar = true
            } else {
                showSidebar = false // Keep closed
            }
        }
    }
    
    private func getOverlayOpacity() -> CGFloat {
        let progress = (offset + gestureOffset) / sidebarWidth
        return min(progress * 0.4, 0.4) // Max opacity of 0.4
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    let onLinkTap: ((String) -> Void)?
    
    init(message: ChatMessage, onLinkTap: ((String) -> Void)? = nil) {
        self.message = message
        self.onLinkTap = onLinkTap
    }
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.isUser {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue)
                        )
                        .foregroundColor(.white)
                } else {
                    Markdown(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemGray5))
                        )
                        .foregroundColor(.primary)
                }
                
                // Web sources
                if let sources = message.sources, !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sources:")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)  
                        
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            Button(action: {
                                onLinkTap?(source.url)
                            }) {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text(source.title)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contextMenu {
                                Button(action: {
                                    copyToClipboard(source.url)
                                }) {
                                    Label("Copy Link", systemImage: "doc.on.clipboard")
                                }
                                
                                Button(action: {
                                    onLinkTap?(source.url)
                                }) {
                                    Label("Open Link", systemImage: "safari")
                                }
                            }
                        }
                    }
                    .textSelection(.enabled)
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
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
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
    let sessionManager: ChatSessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDocumentPicker = false
    @State private var isProcessingDocument = false
    @State private var documents: [(id: String, name: String, type: String, uploadedAt: Date)] = []
    
    private var useWebSearch: Bool {
        session.useWebSearch
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                
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
                
                Button(action: {
                    sessionManager.updateSessionWebSearch(session, useWebSearch: !useWebSearch)
                }) {
                    HStack {
                        Image(systemName: "globe.americas.fill")
                        Text(useWebSearch ? "Web Search Enabled" : "Enable Web Search")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(useWebSearch ? Color.blue : Color.blue.opacity(0.1))
                    .foregroundColor(useWebSearch ? .white : .blue)
                    .cornerRadius(8)
                }
                
                // Uploaded Documents
                if !documents.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                        ForEach(documents, id: \.id) { document in
                            VStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                Text(document.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 120, height: 80)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
                // Knowledge based entries
//                if !llm.getRagNeighbors(for: session).isEmpty {
//                    VStack(alignment: .leading, spacing: 8) {
//                        Text("Knowledge Base Entries")
//                            .font(.headline)
//                        
//                        List(llm.getRagNeighbors(for: session), id: \.0) { neighbor in
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(neighbor.0)
//                                    .font(.body)
//                                Text("Similarity: \(String(format: "%.3f", neighbor.1))")
//                                    .font(.caption)
//                            }
//                        }
//                    }
//                }
//                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
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


struct WebBrowserView: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var currentURL = ""
    @State private var isLoading = false
    @State private var webView: WKWebView?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // URL Bar
                HStack(spacing: 8) {
                    Text(currentURL.isEmpty ? url : currentURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .glassEffect(.regular.interactive())
                
                Divider()
                
                // WebView
                WebView(
                    url: url,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    currentURL: $currentURL,
                    isLoading: $isLoading,
                    webView: $webView
                )
                .id(url) // Force recreation when URL changes
            }
            .navigationTitle("Web Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: {
                        webView?.goBack()
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)
                    
                    Button(action: {
                        webView?.goForward()
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                    
                    Button(action: {
                        webView?.reload()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentURL: String
    @Binding var isLoading: Bool
    @Binding var webView: WKWebView?
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        self.webView = webView
        
        if let validURL = URL(string: url) {
            let request = URLRequest(url: validURL)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let currentURL = uiView.url?.absoluteString, currentURL != url else { return }
        
        if let validURL = URL(string: url) {
            let request = URLRequest(url: validURL)
            uiView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.currentURL = webView.url?.absoluteString ?? ""
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}

struct Aeru_Previews: PreviewProvider {
    static var previews: some View {
        AeruView()
    }
}
