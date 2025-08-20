import SwiftUI
import Foundation
import FoundationModels
import MarkdownUI

struct VoiceConversationView: View {
    let llm: LLM
    @ObservedObject var speechRecognitionManager: SpeechRecognitionManager
    @ObservedObject var textToSpeechManager: TextToSpeechManager
    let currentSession: ChatSession
    let sessionManager: ChatSessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var userText: String = ""
    @State private var aiResponse: String = ""
    @State private var isWaitingForResponse: Bool = false
    @State private var isInLiveMode: Bool = false
    @State private var conversationHistory: [(user: String, ai: String)] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: getHeaderIcon())
                        .font(.system(size: 48))
                        .foregroundColor(getHeaderColor())
                        .scaleEffect(speechRecognitionManager.isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: speechRecognitionManager.isRecording)
                    
                    Text("Live Conversation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(getStatusText())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Conversation Content
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Conversation history
                            ForEach(Array(conversationHistory.enumerated()), id: \.offset) { index, exchange in
                                VStack(spacing: 12) {
                                    // User message
                                    HStack {
                                        HStack {
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.blue)
                                            Text(exchange.user)
                                                .font(.body)
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                        Spacer()
                                    }
                                    
                                    // AI response
                                    HStack {
                                        Spacer()
                                        HStack {
                                            Image(systemName: "brain.head.profile")
                                                .foregroundColor(.purple)
                                            Markdown(exchange.ai)
                                                .textSelection(.enabled)
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.purple.opacity(0.1))
                                        )
                                    }
                                }
                            }
                            
                            // Current exchange
                            VStack(spacing: 12) {
                                // Current user input
                                if !userText.isEmpty || speechRecognitionManager.isRecording {
                                    HStack {
                                        HStack {
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.blue)
                                            Text(userText.isEmpty ? "Listening..." : userText)
                                                .font(.body)
                                                .foregroundColor(userText.isEmpty ? .secondary : .primary)
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                        Spacer()
                                    }
                                    .id("current")
                                }
                                
                                // Current AI response
                                if isWaitingForResponse || !aiResponse.isEmpty || textToSpeechManager.isSpeaking {
                                    HStack {
                                        Spacer()
                                        HStack {
                                            Image(systemName: "brain.head.profile")
                                                .foregroundColor(.purple)
                                            if isWaitingForResponse && aiResponse.isEmpty {
                                                HStack(spacing: 8) {
                                                    ProgressView()
                                                        .scaleEffect(0.7)
                                                    Text("Thinking...")
                                                        .font(.body)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else {
                                                Markdown(aiResponse)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.purple.opacity(0.1))
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: conversationHistory.count) { _, _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("current", anchor: .bottom)
                        }
                    }
                    .onChange(of: userText) { _, _ in
                        // Scroll when user text changes
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("current", anchor: .bottom)
                        }
                    }
                    .onChange(of: aiResponse) { _, _ in
                        // Scroll when AI response updates
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("current", anchor: .bottom)
                        }
                    }
                    .onChange(of: speechRecognitionManager.isRecording) { _, newValue in
                        // Scroll when recording state changes
                        if newValue {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isWaitingForResponse) { _, newValue in
                        // Scroll when waiting state changes
                        if newValue {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: textToSpeechManager.isSpeaking) { _, newValue in
                        // Scroll when TTS state changes
                        if newValue {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Control Buttons
                VStack(spacing: 16) {
                    if !isInLiveMode {
                        Button(action: startLiveMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 20, weight: .medium))
                                
                                Text("Start Live Conversation")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green)
                            )
                        }
                        .padding(.horizontal, 20)
                    } else {
                        Button(action: exitLiveMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 20, weight: .medium))
                                
                                Text("Stop Conversation")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red)
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Voice Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        exitLiveMode()
                        textToSpeechManager.stopSpeaking()
                        speechRecognitionManager.stopRecording()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Auto-start live mode when view appears
            if !isInLiveMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startLiveMode()
                }
            }
        }
        .onDisappear {
            exitLiveMode()
            textToSpeechManager.stopSpeaking()
            speechRecognitionManager.stopRecording()
        }
        .onReceive(llm.$userLLMResponse) { streamingResponse in
            if let response = streamingResponse {
                // Update AI response with streaming content
                aiResponse = response.content
            }
        }
    }
    
    // MARK: - Helper Methods for UI
    private func getHeaderIcon() -> String {
        if isInLiveMode {
            if speechRecognitionManager.isRecording {
                return "waveform.circle.fill"
            } else if textToSpeechManager.isSpeaking {
                return "speaker.wave.3.fill"
            } else if isWaitingForResponse {
                return "brain.head.profile.fill"
            } else {
                return "waveform.circle"
            }
        } else {
            return "waveform"
        }
    }
    
    private func getHeaderColor() -> Color {
        if isInLiveMode {
            if speechRecognitionManager.isRecording {
                return .red
            } else if textToSpeechManager.isSpeaking {
                return .green
            } else if isWaitingForResponse {
                return .purple
            } else {
                return .blue
            }
        } else {
            return .blue
        }
    }
    
    private func getStatusText() -> String {
        if isInLiveMode {
            if speechRecognitionManager.isRecording {
                return "Listening for your voice..."
            } else if isWaitingForResponse {
                return "Processing your request..."
            } else if textToSpeechManager.isSpeaking {
                return "AI is responding..."
            } else {
                return "Ready to listen"
            }
        } else {
            return "Tap Start to begin your live conversation"
        }
    }
    
    // MARK: - Live Mode Functions
    private func startLiveMode() {
        isInLiveMode = true
        conversationHistory.removeAll()
        resetCurrentExchange()
        
        // Start the first listening session
        startListening()
    }
    
    private func exitLiveMode() {
        isInLiveMode = false
        speechRecognitionManager.exitContinuousMode()
        textToSpeechManager.stopSpeaking()
        resetCurrentExchange()
    }
    
    private func startListening() {
        userText = ""
        aiResponse = ""
        
        speechRecognitionManager.startContinuousRecording {
            Task { @MainActor in
                self.onVoiceInputComplete()
            }
        }
    }
    
    private func onVoiceInputComplete() {
        guard isInLiveMode, !speechRecognitionManager.recognizedText.isEmpty else { return }
        
        userText = speechRecognitionManager.recognizedText
        speechRecognitionManager.clearRecognizedText()
        
        Task {
            await queryLLMInLiveMode()
        }
    }
    
    @MainActor
    private func queryLLMInLiveMode() async {
        guard !userText.isEmpty else { return }
        
        isWaitingForResponse = true
        aiResponse = ""
        
        do {
            try await llm.queryLLMGeneral(userText, for: currentSession, sessionManager: sessionManager)
            
            // Wait for streaming to complete
            while llm.isResponding {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            
            // Update response and start TTS
            isWaitingForResponse = false
            
            if !aiResponse.isEmpty {
                // Start TTS with completion handler
                textToSpeechManager.speak(aiResponse) {
                    Task { @MainActor in
                        self.onTTSComplete()
                    }
                }
            }
        } catch {
            isWaitingForResponse = false
            aiResponse = "Sorry, I encountered an error. Please try again."
            
            // Start TTS even for error message
            textToSpeechManager.speak(aiResponse) {
                Task { @MainActor in
                    self.onTTSComplete()
                }
            }
        }
    }
    
    private func onTTSComplete() {
        guard isInLiveMode else { return }
        
        // Add the exchange to history
        if !userText.isEmpty && !aiResponse.isEmpty {
            conversationHistory.append((user: userText, ai: aiResponse))
        }
        
        // Reset for next exchange and start listening again
        resetCurrentExchange()
        
        // Add a small delay before starting next listening session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            if self.isInLiveMode {
                self.startListening()
            }
        }
    }
    
    private func resetCurrentExchange() {
        userText = ""
        aiResponse = ""
        isWaitingForResponse = false
    }
    
}
