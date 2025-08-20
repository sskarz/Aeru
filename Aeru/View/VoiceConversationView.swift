import SwiftUI
import Foundation
import FoundationModels

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
    @State private var hasStartedConversation: Bool = false
    @State private var conversationComplete: Bool = false
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
                    
                    Text(isInLiveMode ? "Live Conversation" : "Voice Conversation")
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
                if isInLiveMode {
                    // Live mode - show conversation history and current exchange
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
                                                Text(exchange.ai)
                                                    .font(.body)
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
                                                    Text(aiResponse)
                                                        .font(.body)
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
                            withAnimation {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                } else {
                    // Standard mode - show current exchange only
                    VStack(spacing: 20) {
                        // User Input Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.blue)
                                Text("Your Question")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            
                            if userText.isEmpty && !hasStartedConversation {
                                Text("Tap the microphone button below to start speaking...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                Text(userText.isEmpty ? "Listening..." : userText)
                                    .font(.body)
                                    .foregroundColor(userText.isEmpty ? .secondary : .primary)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                            }
                        }
                        
                        // AI Response Section
                        if !userText.isEmpty || isWaitingForResponse {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                        .foregroundColor(.purple)
                                    Text("AI Response")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                }
                                
                                if isWaitingForResponse && aiResponse.isEmpty {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Thinking...")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                                } else if !aiResponse.isEmpty {
                                    ScrollView {
                                        Text(aiResponse)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color(.systemGray6))
                                            )
                                    }
                                    .frame(maxHeight: 200)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Control Buttons
                VStack(spacing: 16) {
                    // Live Mode Toggle Button
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
                        .disabled(isWaitingForResponse || speechRecognitionManager.isRecording)
                        .padding(.horizontal, 20)
                    } else {
                        // Live Mode - Exit Button
                        Button(action: exitLiveMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 20, weight: .medium))
                                
                                Text("Exit Live Mode")
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
                    
                    // Standard Mode Controls (when not in live mode)
                    if !isInLiveMode {
                        // Voice Input Button
                        if !conversationComplete {
                            Button(action: handleVoiceButtonTap) {
                                HStack(spacing: 12) {
                                    Image(systemName: speechRecognitionManager.isRecording ? "mic.fill" : "mic")
                                        .font(.system(size: 20, weight: .medium))
                                    
                                    Text(getVoiceButtonText())
                                        .font(.headline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(speechRecognitionManager.isRecording ? Color.red : Color.blue)
                                )
                            }
                            .disabled(isWaitingForResponse)
                            .padding(.horizontal, 20)
                        }
                        
                        // TTS Controls (when AI response is available)
                        if !aiResponse.isEmpty && conversationComplete {
                            Button(action: handleTTSButtonTap) {
                                HStack(spacing: 12) {
                                    Image(systemName: getTTSButtonIcon())
                                        .font(.system(size: 20, weight: .medium))
                                    
                                    Text(getTTSButtonText())
                                        .font(.headline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(textToSpeechManager.isSpeaking ? Color.orange : Color.green)
                                )
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Reset Button
                        if conversationComplete {
                            Button(action: resetConversation) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Start New Conversation")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue, lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, 20)
                        }
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
        .onDisappear {
            exitLiveMode()
            textToSpeechManager.stopSpeaking()
            speechRecognitionManager.stopRecording()
        }
        .onChange(of: speechRecognitionManager.recognizedText) { oldValue, newValue in
            print("🎤 VoiceConversationView: Recognized text changed from '\(oldValue)' to '\(newValue)'")
            if !newValue.isEmpty && !isInLiveMode {
                userText = newValue
                print("🎤 VoiceConversationView: Updated userText to: '\(userText)'")
            }
        }
        .onChange(of: speechRecognitionManager.isRecording) { oldValue, newValue in
            print("🎤 VoiceConversationView: Recording state changed from \(oldValue) to \(newValue)")
            
            // Only handle standard mode here - live mode is handled by the auto-stop callback
            if !isInLiveMode {
                print("🎤 VoiceConversationView: Current userText: '\(userText)', hasStartedConversation: \(hasStartedConversation)")
                print("🎤 VoiceConversationView: Current recognizedText: '\(speechRecognitionManager.recognizedText)'")
                
                // Check if recording stopped and we have text (either in userText or recognizedText)
                if !newValue && !hasStartedConversation {
                    let finalText = userText.isEmpty ? speechRecognitionManager.recognizedText : userText
                    if !finalText.isEmpty {
                        print("🎤 VoiceConversationView: STT finished with text '\(finalText)', starting LLM query...")
                        userText = finalText  // Ensure userText is set
                        hasStartedConversation = true
                        speechRecognitionManager.clearRecognizedText()
                        Task {
                            await queryLLMAndSpeak()
                        }
                    } else {
                        print("🎤 VoiceConversationView: STT finished but no text captured")
                    }
                }
            }
        }
        .onReceive(llm.$userLLMResponse) { streamingResponse in
            if let response = streamingResponse {
                print("🤖 VoiceConversationView: Received streaming response: '\(response.content.prefix(50))...'")
                // Update AI response with streaming content
                aiResponse = response.content
            } else {
                print("🤖 VoiceConversationView: Streaming response ended (nil)")
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
            return "mic.and.signal.meter.fill"
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
            return "Speak your question, then listen to the AI response"
        }
    }
    
    // MARK: - Live Mode Functions
    private func startLiveMode() {
        print("🎤 VoiceConversationView: Starting live mode")
        isInLiveMode = true
        conversationHistory.removeAll()
        resetCurrentExchange()
        
        // Start the first listening session
        startListening()
    }
    
    private func exitLiveMode() {
        print("🎤 VoiceConversationView: Exiting live mode")
        isInLiveMode = false
        speechRecognitionManager.exitContinuousMode()
        textToSpeechManager.stopSpeaking()
        resetCurrentExchange()
    }
    
    private func startListening() {
        print("🎤 VoiceConversationView: Starting listening in live mode")
        userText = ""
        aiResponse = ""
        
        speechRecognitionManager.startContinuousRecording {
            Task { @MainActor in
                self.onVoiceInputComplete()
            }
        }
    }
    
    private func onVoiceInputComplete() {
        print("🎤 VoiceConversationView: Voice input complete in live mode")
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
        
        print("🤖 VoiceConversationView: Starting LLM query in live mode with text: '\(userText)'")
        isWaitingForResponse = true
        aiResponse = ""
        
        do {
            try await llm.queryLLMGeneral(userText, for: currentSession, sessionManager: sessionManager)
            
            // Wait for streaming to complete
            while llm.userLLMResponse != nil {
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
            print("🤖 VoiceConversationView: Error in live mode LLM query: \(error)")
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
        print("🔊 VoiceConversationView: TTS complete in live mode")
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
        hasStartedConversation = false
        conversationComplete = false
    }
    
    // MARK: - Standard Mode Functions
    private func handleVoiceButtonTap() {
        print("🎤 VoiceConversationView: Voice button tapped, isRecording: \(speechRecognitionManager.isRecording)")
        if speechRecognitionManager.isRecording {
            print("🎤 VoiceConversationView: Stopping recording...")
            speechRecognitionManager.stopRecording()
        } else {
            print("🎤 VoiceConversationView: Starting recording...")
            speechRecognitionManager.startRecording()
        }
    }
    
    private func handleTTSButtonTap() {
        print("🔊 VoiceConversationView: TTS button tapped, isSpeaking: \(textToSpeechManager.isSpeaking)")
        if textToSpeechManager.isSpeaking {
            print("🔊 VoiceConversationView: Stopping TTS")
            textToSpeechManager.stopSpeaking()
        } else {
            print("🔊 VoiceConversationView: Starting TTS with text: '\(aiResponse.prefix(50))...'")
            textToSpeechManager.speak(aiResponse)
        }
    }
    
    private func getVoiceButtonText() -> String {
        if speechRecognitionManager.isRecording {
            return "Stop Recording"
        } else if userText.isEmpty {
            return "Start Speaking"
        } else {
            return "Record Again"
        }
    }
    
    private func getTTSButtonIcon() -> String {
        if textToSpeechManager.isSpeaking {
            return "stop.fill"
        }
        return "speaker.wave.2.fill"
    }
    
    private func getTTSButtonText() -> String {
        if textToSpeechManager.isSpeaking {
            return "Stop"
        }
        return "Listen to Response"
    }
    
    private func resetConversation() {
        print("🔄 VoiceConversationView: Resetting conversation")
        if isInLiveMode {
            exitLiveMode()
        } else {
            textToSpeechManager.stopSpeaking()
            speechRecognitionManager.stopRecording()
            resetCurrentExchange()
        }
        print("🔄 VoiceConversationView: Conversation reset complete")
    }
    
    @MainActor
    private func queryLLMAndSpeak() async {
        guard !userText.isEmpty else { 
            print("🤖 VoiceConversationView: queryLLMAndSpeak called but userText is empty")
            return 
        }
        
        print("🤖 VoiceConversationView: Starting LLM query with text: '\(userText)'")
        isWaitingForResponse = true
        aiResponse = ""
        
        // Monitor when LLM streaming completes
        let streamingTask = Task {
            print("🤖 VoiceConversationView: Started streaming monitoring task")
            while llm.userLLMResponse != nil {
                try await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1 seconds
            }
            
            print("🤖 VoiceConversationView: LLM streaming completed")
            // LLM streaming has completed
            await MainActor.run {
                isWaitingForResponse = false
                conversationComplete = true
                
                // Auto-start TTS when response is complete
                if !aiResponse.isEmpty {
                    print("🔊 VoiceConversationView: Auto-starting TTS with response: '\(aiResponse.prefix(50))...'")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        textToSpeechManager.speak(aiResponse)
                    }
                } else {
                    print("🔊 VoiceConversationView: No AI response to speak")
                }
            }
        }
        
        do {
            print("🤖 VoiceConversationView: Calling llm.queryLLMGeneral...")
            // Use queryLLMGeneral with required parameters
            try await llm.queryLLMGeneral(userText, for: currentSession, sessionManager: sessionManager)
            print("🤖 VoiceConversationView: llm.queryLLMGeneral completed successfully")
        } catch {
            print("🤖 VoiceConversationView: Error in LLM query: \(error)")
            streamingTask.cancel()
            aiResponse = "Sorry, I encountered an error processing your request. Please try again."
            isWaitingForResponse = false
            conversationComplete = true
            print("Error in voice conversation: \(error)")
        }
    }
}
