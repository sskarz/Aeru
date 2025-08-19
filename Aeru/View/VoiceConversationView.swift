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
            print("🎤 VoiceConversationView: Recognized text changed from '\(oldValue)' to '\(newValue)'")
            if !newValue.isEmpty {
                userText = newValue
                print("🎤 VoiceConversationView: Updated userText to: '\(userText)'")
            }
        }
        .onChange(of: speechRecognitionManager.isRecording) { oldValue, newValue in
            print("🎤 VoiceConversationView: Recording state changed from \(oldValue) to \(newValue)")
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
        textToSpeechManager.stopSpeaking()
        speechRecognitionManager.stopRecording()
        userText = ""
        aiResponse = ""
        isWaitingForResponse = false
        hasStartedConversation = false
        conversationComplete = false
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
