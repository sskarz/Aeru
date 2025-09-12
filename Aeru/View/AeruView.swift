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
import Speech


struct BrowserURL: Identifiable {
    let id = UUID()
    let url: String
}

struct AeruView: View {
    @StateObject private var llm = LLM()
    @StateObject private var sessionManager = ChatSessionManager()
    @StateObject private var networkConnectivity = NetworkConnectivity()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @StateObject private var textToSpeechManager = TextToSpeechManager()
    @AppStorage("colorScheme") private var selectedColorScheme = AppColorScheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var messageText: String = ""
    // useWebSearch is now per-session, computed from currentSession
    @State private var showKnowledgeBase: Bool = false
    @State private var newEntry: String = ""
    @State private var showSidebar: Bool = false
    @State private var webBrowserURL: BrowserURL? = nil
    @State private var showConnectivityAlert: Bool = false
    @State private var showSources: Bool = false
    @State private var sourcesToShow: [WebSearchResult] = []
    @State private var sourcesLoading: Bool = false
    @State private var showVoiceConversation: Bool = false
    @FocusState private var isMessageFieldFocused: Bool
    
    
    // Sidebar animation properties
    @State private var offset: CGFloat = 0
    @GestureState private var gestureOffset: CGFloat = 0
    
    private var sidebarWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad: Use fixed width that scales better
            return min(320, screenWidth * 0.35)
        } else {
            // iPhone: Use 80% of screen width
            return screenWidth * 0.8
        }
    }

    private var isModelResponding: Bool {
        llm.isResponding || llm.isWebSearching
    }
    
    private var shouldHideNewChatButton: Bool {
        // Hide if current chat is empty (new chat with 0 messages) or model is responding
        return llm.chatMessages.isEmpty || isModelResponding
    }
    
    private var useWebSearch: Bool {
        sessionManager.currentSession?.useWebSearch ?? false
    }
    
    private func handleNewChatCreation() {
        // Stop any ongoing TTS when starting a new chat
        textToSpeechManager.stopSpeaking()
        _ = sessionManager.getOrCreateNewChat()
    }
    
    private var inputBar: some View {
        HStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12) {
            // Document upload button
            Button(action: { 
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                showKnowledgeBase.toggle() 
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 44 : 36, height: UIDevice.current.userInterfaceIdiom == .pad ? 44 : 36)
                    .glassEffect(.regular.interactive())
            }
            
            // Text input area
            HStack(spacing: 8) {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .glassEffect(.regular.interactive())
                
                // Send/Voice button
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        speechRecognitionManager.stopRecording()
                        startInstantVoiceConversation()
                    } else {
                        sendMessage()
                    }
                }) {
                    Image(systemName: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "waveform" : "arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 32, height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 32)
                        .glassEffect(.regular.interactive())
                        .background(
                            Circle()
                                .fill(isModelResponding ? Color.gray.opacity(0.6) : Color.blue)
                        )
                }
                .disabled(isModelResponding)
            }
        }
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 16)
    }
    
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Main chat area (gets pushed by sidebar)
                NavigationStack {
                    VStack(spacing: 0) {
                        // Chat content
                        if let currentSession = sessionManager.currentSession {
                            chatContentView(for: currentSession)
                        } else {
                            emptyStateView
                        }
                    }
                    .navigationTitle(sessionManager.currentSession?.displayTitle ?? "Aeru")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { 
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                isMessageFieldFocused = false
                                showSidebar.toggle()
                            }) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.title3)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if !shouldHideNewChatButton {
                                Button(action: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    handleNewChatCreation()
                                }) {
                                    Image(systemName: "plus.message")
                                        .font(.title3)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        
                    }
                    .safeAreaInset(edge: .bottom) {
                        if sessionManager.currentSession != nil {
                            inputBar
                                .padding(.bottom, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .offset(x: max(offset + gestureOffset, 0))
                .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: gestureOffset)
                
                // Sidebar
                ChatSidebar(sessionManager: sessionManager)
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
                            // Clamp to prevent over-swiping beyond the open position
                            out = max(min(translation, 0), -sidebarWidth)
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
                
                // Always ensure there's a current session (empty chat)
                if sessionManager.currentSession == nil {
                    _ = sessionManager.getOrCreateNewChat()
                }
                
                if let currentSession = sessionManager.currentSession {
                    llm.switchToSession(currentSession)
                }
            }
        }
        .onChange(of: sessionManager.currentSession) { oldValue, newValue in
            // Stop TTS when switching to a different chat session
            if oldValue?.id != newValue?.id {
                textToSpeechManager.stopSpeaking()
            }
            
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
        .sheet(isPresented: $showSources) {
            SourcesView(sources: sourcesToShow, onLinkTap: { url in
                webBrowserURL = BrowserURL(url: url)
            }, isLoading: sourcesLoading)
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $webBrowserURL) { browserURL in
            WebBrowserView(url: browserURL.url)
        }
        .sheet(isPresented: $showVoiceConversation) {
            if let currentSession = sessionManager.currentSession {
                VoiceConversationView(
                    llm: llm,
                    speechRecognitionManager: speechRecognitionManager,
                    textToSpeechManager: textToSpeechManager,
                    currentSession: currentSession,
                    sessionManager: sessionManager
                )
            }
        }
        .alert("No Internet Connection", isPresented: $showConnectivityAlert) {
            Button("OK") { }
        } message: {
            Text("Please turn on cellular or WiFi to use web search functionality.")
        }
        .alert("Speech Recognition Error", isPresented: $speechRecognitionManager.hasError) {
            Button("OK") { 
                speechRecognitionManager.clearError()
            }
        } message: {
            Text(speechRecognitionManager.errorMessage)
        }
        .onChange(of: speechRecognitionManager.recognizedText) { oldValue, newValue in
            // Only handle STT in main view when voice conversation is not active
            if !showVoiceConversation && !newValue.isEmpty {
                messageText = newValue
            }
        }
        .onChange(of: speechRecognitionManager.isRecording) { oldValue, newValue in
            // Only handle STT cleanup in main view when voice conversation is not active
            if !showVoiceConversation && !newValue && !speechRecognitionManager.recognizedText.isEmpty {
                speechRecognitionManager.clearRecognizedText()
            }
        }
        .onDisappear {
            textToSpeechManager.stopSpeaking()
        }
        .preferredColorScheme(AppColorScheme(rawValue: selectedColorScheme)?.colorScheme)
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
                        ChatBubbleView(message: message, onLinkTap: { url in
                            webBrowserURL = BrowserURL(url: url)
                        }, onSourcesTap: { sources in
                            // Set loading state first
                            sourcesLoading = true
                            sourcesToShow = []
                            showSources = true
                            
                            // Show loading briefly then display sources
                            Task {
                                // Small delay to show loading indicator
                                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second
                                await MainActor.run {
                                    sourcesToShow = sources
                                    sourcesLoading = false
                                }
                            }
                        }, textToSpeechManager: textToSpeechManager, selectedColorScheme: selectedColorScheme, colorScheme: colorScheme)
                        .id(message.id)
                    }
                    
                    // Streaming response display
                    if let streamingResponse = llm.userLLMResponse {
                        ChatBubbleView(message: ChatMessage(text: streamingResponse.content, isUser: false), onLinkTap: { url in
                            webBrowserURL = BrowserURL(url: url)
                        }, onSourcesTap: { sources in
                            // Set loading state first
                            sourcesLoading = true
                            sourcesToShow = []
                            showSources = true
                            
                            // Show loading briefly then display sources
                            Task {
                                // Small delay to show loading indicator
                                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second
                                await MainActor.run {
                                    sourcesToShow = sources
                                    sourcesLoading = false
                                }
                            }
                        }, textToSpeechManager: textToSpeechManager, selectedColorScheme: selectedColorScheme, colorScheme: colorScheme)
                        .id("streaming")
                    }
                    
                    // Loading indicator
                    if llm.isWebSearching && !llm.isResponding {
                        TypingIndicatorView()
                            .id("typing")
                    }
                    
                    // Bottom spacer for better scroll behavior
                    Spacer()
                        .frame(height: 8)
                }
                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 32 : 20)
                .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 16)
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
                if newValue && !llm.isResponding {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            .onChange(of: isMessageFieldFocused) { _, newValue in
                if newValue && !llm.chatMessages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if let lastMessage = llm.chatMessages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
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
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    private func handleVoiceButtonTap() {
        if speechRecognitionManager.isRecording {
            speechRecognitionManager.stopRecording()
        } else {
            isMessageFieldFocused = false
            speechRecognitionManager.startRecording()
        }
    }
    
    private func startInstantVoiceConversation() {
        // Dismiss keyboard
        isMessageFieldFocused = false
        
        // Show voice conversation modal and start live mode immediately
        showVoiceConversation = true
        
        // Small delay to ensure modal is presented before starting live mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // The VoiceConversationView will auto-start live mode on appear
        }
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, let currentSession = sessionManager.currentSession else { return }
        
        // Check connectivity for web search
        if useWebSearch && !NetworkConnectivity.hasActiveConnection() {
            showConnectivityAlert = true
            return
        }
        
        // Stop any ongoing TTS when sending a new message
        textToSpeechManager.stopSpeaking()
        
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
        
        let willToggleSidebar: Bool
        if showSidebar {
            // Sidebar is open - check if should close
            willToggleSidebar = translation < -threshold || velocity < -500
            showSidebar = !willToggleSidebar
        } else {
            // Sidebar is closed - check if should open
            willToggleSidebar = translation > threshold || velocity > 500
            showSidebar = willToggleSidebar
        }
        
        // Add haptic feedback for successful swipe gestures
        if willToggleSidebar {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }
    
}

struct ChatBubbleView: View {
    let message: ChatMessage
    let onLinkTap: ((String) -> Void)?
    let onSourcesTap: (([WebSearchResult]) -> Void)?
    let textToSpeechManager: TextToSpeechManager?
    let selectedColorScheme: String
    let colorScheme: ColorScheme
    
    init(message: ChatMessage, onLinkTap: ((String) -> Void)? = nil, onSourcesTap: (([WebSearchResult]) -> Void)? = nil, textToSpeechManager: TextToSpeechManager? = nil, selectedColorScheme: String, colorScheme: ColorScheme) {
        self.message = message
        self.onLinkTap = onLinkTap
        self.onSourcesTap = onSourcesTap
        self.textToSpeechManager = textToSpeechManager
        self.selectedColorScheme = selectedColorScheme
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.isUser {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20.0))
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue)
                        )
                        .foregroundColor(getUserTextColor())
                } else {
                    Markdown(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20.0))
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemGray5))
                        )
                        .foregroundColor(.primary)
                }
                
                // Action buttons for AI responses
                if !message.isUser {
                    HStack(spacing: 8) {
                        // Text-to-Speech button
                        if let ttsManager = textToSpeechManager {
                            Button(action: {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                handleTTSButtonTap(ttsManager: ttsManager)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: getTTSButtonIcon(ttsManager: ttsManager))
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text(getTTSButtonText(ttsManager: ttsManager))
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16.0))
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.blue.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Sources button
                        if let sources = message.sources, !sources.isEmpty {
                            Button(action: {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                onSourcesTap?(sources)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("Sources (\(sources.count))")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16.0))
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.blue.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if !message.isUser {
                Spacer(minLength: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 50)
            }
        }
    }
    
    private func handleTTSButtonTap(ttsManager: TextToSpeechManager) {
        if ttsManager.isSpeaking && ttsManager.currentText == message.text {
            // If currently speaking this message, stop it
            ttsManager.stopSpeaking()
        } else {
            // Start speaking this message
            ttsManager.speak(message.text)
        }
    }
    
    private func getTTSButtonIcon(ttsManager: TextToSpeechManager) -> String {
        if ttsManager.currentText == message.text && ttsManager.isSpeaking {
            return "stop.fill"
        }
        return "speaker.wave.2.fill"
    }
    
    private func getTTSButtonText(ttsManager: TextToSpeechManager) -> String {
        if ttsManager.currentText == message.text && ttsManager.isSpeaking {
            return "Stop"
        }
        return "Listen"
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
    
    private func getUserTextColor() -> Color {
        if selectedColorScheme == AppColorScheme.dark.rawValue {
            return .white
        } else if selectedColorScheme == AppColorScheme.system.rawValue {
            return colorScheme == .dark ? .white : .secondary
        } else {
            return .secondary
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
            
            Spacer(minLength: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 50)
        }
        .onAppear {
            animating = true
        }
    }
}

struct SourcesView: View {
    let sources: [WebSearchResult]
    let onLinkTap: ((String) -> Void)?
    let isLoading: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isLoading && sources.isEmpty {
                        // Loading state
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading sources...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            Text(source.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(source.url)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if !source.content.isEmpty {
                                Text(source.content)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16.0))
                        .onTapGesture {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            onLinkTap?(source.url)
                            dismiss()
                        }
                        .contextMenu {
                            Button(action: {
                                copyToClipboard(source.url)
                            }) {
                                Label("Copy Link", systemImage: "doc.on.clipboard")
                            }
                            
                            Button(action: {
                                onLinkTap?(source.url)
                                dismiss()
                            }) {
                                Label("Open Link", systemImage: "safari")
                            }
                        }
                    }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
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
        NavigationStack {
            VStack(spacing: 16) {
                
                Button(action: { 
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    showDocumentPicker = true 
                }) {
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
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
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
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8.0))
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
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8.0))
                        }
                    }
                }
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
        NavigationStack {
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
        
        // Initialize the coordinator with the current URL
        context.coordinator.lastLoadedURL = url
        
        if let validURL = URL(string: url) {
            let request = URLRequest(url: validURL)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Only load if this is a different URL than what we last loaded
        // This prevents infinite reload loops
        if url != context.coordinator.lastLoadedURL {
            context.coordinator.lastLoadedURL = url
            if let validURL = URL(string: url) {
                let request = URLRequest(url: validURL)
                uiView.load(request)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        var lastLoadedURL: String = ""
        
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
