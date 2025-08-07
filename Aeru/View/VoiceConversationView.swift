import SwiftUI
import Foundation
import FoundationModels

struct VoiceConversationView: View {
    let llm: LLM
    let speechRecognitionManager: SpeechRecognitionManager
    let textToSpeechManager: TextToSpeechManager
    let currentSession: ChatSession
    let sessionManager: ChatSessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var userText: String = ""
    @State private var aiResponse: String = ""
    @State private var isWaitingForResponse: Bool = false
    @State private var hasStartedConversation: Bool = false
    @State private var conversationComplete: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "mic.and.signal.meter.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("Voice Conversation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Speak your question, then listen to the AI response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Conversation Content
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
                
                Spacer()
                
                // Control Buttons
                VStack(spacing: 16) {
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
                .padding(.bottom, 20)
            }
            .navigationTitle("Voice Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        textToSpeechManager.stopSpeaking()
                        speechRecognitionManager.stopRecording()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            textToSpeechManager.stopSpeaking()
            speechRecognitionManager.stopRecording()
        }
        .onChange(of: speechRecognitionManager.recognizedText) { oldValue, newValue in
            if !newValue.isEmpty {
                userText = newValue
            }
        }
        .onChange(of: speechRecognitionManager.isRecording) { oldValue, newValue in
            if !newValue && !userText.isEmpty && !hasStartedConversation {
                // STT finished, start LLM query
                hasStartedConversation = true
                speechRecognitionManager.clearRecognizedText()
                Task {
                    await queryLLMAndSpeak()
                }
            }
        }
        .onReceive(llm.$userLLMResponse) { streamingResponse in
            if let response = streamingResponse {
                // Update AI response with streaming content
                aiResponse = response.content
            }
        }
    }
    
    private func handleVoiceButtonTap() {
        if speechRecognitionManager.isRecording {
            speechRecognitionManager.stopRecording()
        } else {
            speechRecognitionManager.startRecording()
        }
    }
    
    private func handleTTSButtonTap() {
        if textToSpeechManager.isSpeaking {
            textToSpeechManager.toggle()
        } else {
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
        if textToSpeechManager.isSpeaking && !textToSpeechManager.isPaused {
            return "pause.fill"
        } else if textToSpeechManager.isPaused {
            return "play.fill"
        }
        return "speaker.wave.2.fill"
    }
    
    private func getTTSButtonText() -> String {
        if textToSpeechManager.isSpeaking && !textToSpeechManager.isPaused {
            return "Pause"
        } else if textToSpeechManager.isPaused {
            return "Resume"
        }
        return "Listen to Response"
    }
    
    private func resetConversation() {
        textToSpeechManager.stopSpeaking()
        speechRecognitionManager.stopRecording()
        userText = ""
        aiResponse = ""
        isWaitingForResponse = false
        hasStartedConversation = false
        conversationComplete = false
    }
    
    @MainActor
    private func queryLLMAndSpeak() async {
        guard !userText.isEmpty else { return }
        
        isWaitingForResponse = true
        aiResponse = ""
        
        // Monitor when LLM streaming completes
        let streamingTask = Task {
            while llm.userLLMResponse != nil {
                try await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1 seconds
            }
            
            // LLM streaming has completed
            await MainActor.run {
                isWaitingForResponse = false
                conversationComplete = true
                
                // Auto-start TTS when response is complete
                if !aiResponse.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        textToSpeechManager.speak(aiResponse)
                    }
                }
            }
        }
        
        do {
            // Use queryLLMGeneral with required parameters
            try await llm.queryLLMGeneral(userText, for: currentSession, sessionManager: sessionManager)
        } catch {
            streamingTask.cancel()
            aiResponse = "Sorry, I encountered an error processing your request. Please try again."
            isWaitingForResponse = false
            conversationComplete = true
            print("Error in voice conversation: \(error)")
        }
    }
}
