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
    
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var silenceTimer: Timer?
    private var lastSpeechTime: Date?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence
    private var onAutoStop: (() -> Void)?
    private var audioPlayer: AVAudioPlayer?
    
    init() {
        checkAuthorization()
    }
    
    private func checkAuthorization() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            isAuthorized = true
        case .denied, .restricted, .notDetermined:
            requestAuthorization()
        @unknown default:
            isAuthorized = false
        }
    }
    
    private func requestAuthorization() {
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
        
        guard !audioEngine.isRunning else {
            return
        }
        
        isInContinuousMode = continuousMode
        self.onAutoStop = onAutoStop
        
        // Reset previous recognition
        stopRecording()
        recognizedText = ""
        hasError = false
        
        // Request microphone permission
        AVAudioApplication.requestRecordPermission() { [weak self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    self?.isRecording = true  // Set recording state immediately when permission granted
                    if self?.isInContinuousMode == true {
                        self?.playListeningStartSound()
                    }
                    self?.performRecording()
                } else {
                    self?.showError("Microphone permission denied")
                }
            }
        }
    }
    
    private func performRecording() {
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
