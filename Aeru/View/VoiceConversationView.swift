import SwiftUI
import Foundation
import FoundationModels
import MarkdownUI
import AudioToolbox

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
    
    // Modern STT components
    @StateObject private var modernTranscriber = SpokenWordTranscriber(locale: Locale(identifier: "en-US"))
    @StateObject private var modernRecorder: ModernAudioRecorder
    @State private var silenceTimer: Timer?
    @State private var lastSpeechTime: Date?
    @State private var hasReceivedFirstTranscription = false
    private let silenceThreshold: TimeInterval = 1.5
    
    private var isCurrentlyRecording: Bool {
        return modernRecorder.isRecording
    }
    
    init(llm: LLM, speechRecognitionManager: SpeechRecognitionManager, textToSpeechManager: TextToSpeechManager, currentSession: ChatSession, sessionManager: ChatSessionManager) {
        self.llm = llm
        self.speechRecognitionManager = speechRecognitionManager
        self.textToSpeechManager = textToSpeechManager
        self.currentSession = currentSession
        self.sessionManager = sessionManager
        
        let transcriber = SpokenWordTranscriber(locale: Locale(identifier: "en-US"))
        self._modernRecorder = StateObject(wrappedValue: ModernAudioRecorder(transcriber: transcriber))
        self._modernTranscriber = StateObject(wrappedValue: transcriber)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Conversation Content
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Conversation history
                            ForEach(Array(conversationHistory.enumerated()), id: \.offset) { index, exchange in
                                VStack(spacing: 12) {
                                    // User message
                                    HStack {
                                        Spacer(minLength: 50)
                                        
                                        Text(exchange.user)
                                            .textSelection(.enabled)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20.0))
                                            .background(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(Color.blue)
                                            )
                                            .foregroundColor(.white)
                                    }
                                    
                                    // AI response
                                    HStack {
                                        Markdown(exchange.ai)
                                            .textSelection(.enabled)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20.0))
                                            .background(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(Color(.systemGray5))
                                            )
                                            .foregroundColor(.primary)
                                        
                                        Spacer(minLength: 50)
                                    }
                                }
                            }
                            
                            // Current exchange
                            VStack(spacing: 12) {
                                // Current user input
                                if !userText.isEmpty || isCurrentlyRecording {
                                    HStack {
                                        Spacer(minLength: 50)
                                        
                                        Text(userText.isEmpty ? "Listening..." : userText)
                                            .textSelection(.enabled)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20.0))
                                            .background(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(Color.blue)
                                            )
                                            .foregroundColor(.white)
                                    }
                                    .id("current")
                                }
                                
                                // Current AI response
                                if isWaitingForResponse || !aiResponse.isEmpty || textToSpeechManager.isSpeaking {
                                    HStack {
                                        VStack {
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
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20.0))
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color(.systemGray5))
                                        )
                                        .foregroundColor(.primary)
                                        
                                        Spacer(minLength: 50)
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
                    .onChange(of: isCurrentlyRecording) { _, newValue in
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
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: getHeaderIcon())
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(getHeaderColor())
                            .scaleEffect(isCurrentlyRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: isCurrentlyRecording)
                        
                        Text("Live Conversation")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        exitLiveMode()
                        textToSpeechManager.stopSpeaking()
                        
                        Task {
                            try? await modernRecorder.stopRecording()
                        }
                        
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
            
            Task {
                try? await modernRecorder.stopRecording()
            }
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
            if isCurrentlyRecording {
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
            if isCurrentlyRecording {
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
            if isCurrentlyRecording {
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
        print("🚀 [VoiceConversationView] Starting live mode")
        
        isInLiveMode = true
        conversationHistory.removeAll()
        resetCurrentExchange()
        
        // Start the first listening session
        startListening()
        print("✅ [VoiceConversationView] Live mode started")
    }
    
    private func exitLiveMode() {
        isInLiveMode = false
        stopModernListening()
        textToSpeechManager.stopSpeaking()
        resetCurrentExchange()
    }
    
    private func startListening() {
        print("🎧 [VoiceConversationView] Starting listening session")
        
        userText = ""
        aiResponse = ""
        
        print("🔊 [VoiceConversationView] Using modern STT framework")
        startModernListening()
    }
    
    private func startModernListening() {
        print("🎤 [VoiceConversationView] Starting modern listening")
        
        // Reset transcription state
        modernTranscriber.clearTranscribedText()
        hasReceivedFirstTranscription = false
        print("🧠 [VoiceConversationView] Cleared transcriber text and reset transcription state")
        
        // Play listening sound
        AudioServicesPlaySystemSound(1113) // Tock sound
        print("🔔 [VoiceConversationView] Played start sound")
        
        Task {
            do {
                print("🎤 [VoiceConversationView] Starting recorder...")
                try await modernRecorder.record()
                print("🛑 [VoiceConversationView] Recorder finished")
            } catch {
                print("❌ [VoiceConversationView] Modern recording failed: \(error)")
            }
        }
        
        // Monitor for transcribed text and silence - IMPROVED LOGIC
        Task {
            print("👀 [VoiceConversationView] Starting text monitoring loop")
            var loopCount = 0
            
            while modernRecorder.isRecording {
                loopCount += 1
                let currentText = modernTranscriber.transcribedText
                
                if loopCount % 10 == 0 { // Log every 1 second
                    print("👀 [VoiceConversationView] Loop \(loopCount): isRecording=\(modernRecorder.isRecording), currentText='\(currentText)', hasReceived1st=\(hasReceivedFirstTranscription)")
                }
                
                if currentText != userText {
                    print("📝 [VoiceConversationView] Text changed from '\(userText)' to '\(currentText)'")
                    userText = currentText
                    
                    // If we have ANY text (not just meaningful text), we've received first transcription
                    if !hasReceivedFirstTranscription && !currentText.isEmpty {
                        hasReceivedFirstTranscription = true
                        print("🎉 [VoiceConversationView] First transcription received! Starting silence monitoring")
                        resetModernSilenceTimer()
                    }
                    // Reset timer on meaningful text changes after first transcription
                    else if hasReceivedFirstTranscription && !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("⏰ [VoiceConversationView] Meaningful text detected, resetting silence timer")
                        lastSpeechTime = Date()
                        resetModernSilenceTimer()
                    }
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            print("🛑 [VoiceConversationView] Text monitoring loop ended after \(loopCount) iterations")
        }
    }
    
    private func resetModernSilenceTimer() {
        print("⏰ [VoiceConversationView] Resetting silence timer (\(silenceThreshold)s)")
        
        silenceTimer?.invalidate()
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            print("⏰ [VoiceConversationView] Silence timer fired")
            Task { @MainActor in
                if self.modernRecorder.isRecording {
                    print("🔇 [VoiceConversationView] Silence detected, stopping listening")
                    self.stopModernListening()
                    self.onVoiceInputComplete()
                } else {
                    print("⚠️ [VoiceConversationView] Silence timer fired but not recording")
                }
            }
        }
    }
    
    private func stopModernListening() {
        print("🛑 [VoiceConversationView] Stopping modern listening")
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        print("⏰ [VoiceConversationView] Silence timer invalidated")
        
        // Play listening stop sound
        AudioServicesPlaySystemSound(1114) // Tick sound
        print("🔔 [VoiceConversationView] Played stop sound")
        
        Task {
            do {
                try await modernRecorder.stopRecording()
                print("✅ [VoiceConversationView] Modern recorder stopped successfully")
            } catch {
                print("❌ [VoiceConversationView] Error stopping modern recorder: \(error)")
            }
        }
    }
    
    private func onVoiceInputComplete() {
        print("✅ [VoiceConversationView] Voice input complete")
        
        let transcribedText = modernTranscriber.transcribedText
        print("🎤 [VoiceConversationView] Transcribed: '\(transcribedText)'")
        
        guard isInLiveMode, !transcribedText.isEmpty else { 
            print("⚠️ [VoiceConversationView] Skipping - not in live mode or empty text. LiveMode: \(isInLiveMode), Text: '\(transcribedText)'")
            return 
        }
        
        userText = transcribedText
        modernTranscriber.clearTranscribedText()
        print("🧠 [VoiceConversationView] Cleared transcriber text")
        print("💬 [VoiceConversationView] Set userText to: '\(userText)'")
        
        Task {
            print("🤖 [VoiceConversationView] Querying LLM...")
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
