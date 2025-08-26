import Foundation
import Speech
import AVFoundation
import Combine
import AudioToolbox

@MainActor
class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var isAuthorized = false
    @Published var hasError = false
    @Published var errorMessage = ""
    @Published var isInContinuousMode = false
    
    // Legacy Speech Framework (iOS < 26)
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    // Modern Speech Framework (iOS 26+)
    private var modernTranscriber: SpokenWordTranscriber?
    private var modernRecorder: ModernAudioRecorder?
    
    // Common properties
    private var silenceTimer: Timer?
    private var lastSpeechTime: Date?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence
    private var onAutoStop: (() -> Void)?
    private var audioPlayer: AVAudioPlayer?
    
    private var useModernFramework: Bool {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }
    
    init() {
        checkAuthorization()
        setupModernFramework()
    }
    
    private func setupModernFramework() {
        if useModernFramework {
            modernTranscriber = SpokenWordTranscriber(locale: Locale(identifier: "en-US"))
            if let transcriber = modernTranscriber {
                modernRecorder = ModernAudioRecorder(transcriber: transcriber)
            }
        }
    }
    
    private func checkAuthorization() {
        if useModernFramework {
            checkModernAuthorization()
        } else {
            checkLegacyAuthorization()
        }
    }
    
    private func checkLegacyAuthorization() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            isAuthorized = true
        case .denied, .restricted, .notDetermined:
            requestLegacyAuthorization()
        @unknown default:
            isAuthorized = false
        }
    }
    
    private func checkModernAuthorization() {
        // For iOS 26+, check microphone permissions using AVCaptureDevice
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            isAuthorized = true
        case .denied, .restricted, .notDetermined:
            requestModernAuthorization()
        @unknown default:
            isAuthorized = false
        }
    }
    
    private func requestLegacyAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAuthorized = true
                case .denied:
                    self?.isAuthorized = false
                    self?.showError("Speech recognition permission denied")
                case .restricted:
                    self?.isAuthorized = false
                    self?.showError("Speech recognition is restricted on this device")
                case .notDetermined:
                    self?.isAuthorized = false
                    self?.showError("Speech recognition permission not determined")
                @unknown default:
                    self?.isAuthorized = false
                    self?.showError("Unknown speech recognition authorization status")
                }
            }
        }
    }
    
    private func requestModernAuthorization() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                self.isAuthorized = granted
                if !granted {
                    self.showError("Microphone permission denied")
                }
            }
        }
    }
    
    func startRecording() {
        startRecording(continuousMode: false, onAutoStop: nil)
    }
    
    func startContinuousRecording(onAutoStop: @escaping () -> Void) {
        startRecording(continuousMode: true, onAutoStop: onAutoStop)
    }
    
    private func startRecording(continuousMode: Bool, onAutoStop: (() -> Void)?) {
        guard isAuthorized else {
            showError("Speech recognition not authorized")
            return
        }
        
        isInContinuousMode = continuousMode
        self.onAutoStop = onAutoStop
        
        // Reset previous recognition
        stopRecording()
        recognizedText = ""
        hasError = false
        
        if useModernFramework {
            startModernRecording()
        } else {
            startLegacyRecording()
        }
    }
    
    private func startLegacyRecording() {
        guard !audioEngine.isRunning else { 
            return 
        }
        
        // Request microphone permission
        AVAudioApplication.requestRecordPermission() { [weak self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    self?.isRecording = true  // Set recording state immediately when permission granted
                    if self?.isInContinuousMode == true {
                        self?.playListeningStartSound()
                    }
                    self?.performLegacyRecording()
                } else {
                    self?.showError("Microphone permission denied")
                }
            }
        }
    }
    
    private func startModernRecording() {
        guard let transcriber = modernTranscriber,
              let recorder = modernRecorder else {
            showError("Modern speech framework not available")
            return
        }
        
        isRecording = true
        if isInContinuousMode {
            playListeningStartSound()
        }
        
        Task {
            do {
                try await recorder.record()
            } catch {
                await MainActor.run {
                    self.showError("Modern recording failed: \(error.localizedDescription)")
                }
            }
        }
        
        // Monitor transcriber for text updates
        Task {
            while isRecording {
                await MainActor.run {
                    let newText = transcriber.transcribedText
                    if newText != self.recognizedText {
                        self.recognizedText = newText
                        
                        // Update last speech time if we have text and are in continuous mode
                        if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && self.isInContinuousMode {
                            self.lastSpeechTime = Date()
                            self.resetSilenceTimer()
                        }
                    }
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
    }
    
    private func performLegacyRecording() {
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                showError("Unable to create speech recognition request")
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            // Configure audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            
            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()
            
            // Start recognition
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        let newText = result.bestTranscription.formattedString
                        self?.recognizedText = newText
                        
                        // Update last speech time if we have text and are in continuous mode
                        if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && self?.isInContinuousMode == true {
                            self?.lastSpeechTime = Date()
                            self?.resetSilenceTimer()
                        }
                    }
                    
                    if error != nil || result?.isFinal == true {
                        let wasRecording = self?.isRecording ?? false
                        
                        // Always stop recording to clean up audio session
                        if wasRecording {
                            self?.stopRecording()
                        }
                        
                        if let error = error, wasRecording {
                            // Only show error if we were still recording (not manually cancelled)
                            let nsError = error as NSError
                            if nsError.code != 216 { // 216 is the cancellation error code
                                self?.showError("Speech recognition error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            
        } catch {
            isRecording = false  // Reset recording state on error
            showError("Audio recording setup failed: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        isRecording = false
        
        // Clear silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        lastSpeechTime = nil
        
        if useModernFramework {
            stopModernRecording()
        } else {
            stopLegacyRecording()
        }
    }
    
    private func stopLegacyRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Properly deactivate and allow other audio sessions to resume
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Silent fail for audio session deactivation
        }
    }
    
    private func stopModernRecording() {
        guard let recorder = modernRecorder else { return }
        
        Task {
            do {
                try await recorder.stopRecording()
            } catch {
                await MainActor.run {
                    // Silent fail for stop recording
                }
            }
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        
        if isInContinuousMode && isRecording {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    if self?.isRecording == true && self?.isInContinuousMode == true {
                        self?.playListeningStopSound()
                        self?.stopRecording()
                        self?.onAutoStop?()
                    }
                }
            }
        }
    }
    
    func exitContinuousMode() {
        isInContinuousMode = false
        onAutoStop = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        lastSpeechTime = nil
        if isRecording {
            stopRecording()
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        hasError = true
        isRecording = false
    }
    
    func clearError() {
        hasError = false
        errorMessage = ""
    }
    
    func clearRecognizedText() {
        recognizedText = ""
    }
    
    private func playListeningStartSound() {
        // Use system sound for listening start
        AudioServicesPlaySystemSound(1113) // Tock sound
    }
    
    private func playListeningStopSound() {
        // Use system sound for listening stop
        AudioServicesPlaySystemSound(1114) // Tick sound
    }
}
