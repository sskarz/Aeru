import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var isAuthorized = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
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
        print("🎙️ SpeechRecognitionManager: startRecording called")
        print("🎙️ SpeechRecognitionManager: isAuthorized: \(isAuthorized), audioEngine.isRunning: \(audioEngine.isRunning)")
        
        guard isAuthorized else {
            print("🎙️ SpeechRecognitionManager: Speech recognition not authorized")
            showError("Speech recognition not authorized")
            return
        }
        
        guard !audioEngine.isRunning else { 
            print("🎙️ SpeechRecognitionManager: Audio engine already running, returning")
            return 
        }
        
        print("🎙️ SpeechRecognitionManager: Resetting previous recognition state")
        // Reset previous recognition
        stopRecording()
        recognizedText = ""
        hasError = false
        
        print("🎙️ SpeechRecognitionManager: Requesting microphone permission")
        // Request microphone permission
        AVAudioApplication.requestRecordPermission() { [weak self] allowed in
            DispatchQueue.main.async {
                print("🎙️ SpeechRecognitionManager: Microphone permission result: \(allowed)")
                if allowed {
                    self?.isRecording = true  // Set recording state immediately when permission granted
                    print("🎙️ SpeechRecognitionManager: Set isRecording to true, starting performRecording")
                    self?.performRecording()
                } else {
                    print("🎙️ SpeechRecognitionManager: Microphone permission denied")
                    self?.showError("Microphone permission denied")
                }
            }
        }
    }
    
    private func performRecording() {
        print("🎙️ SpeechRecognitionManager: performRecording started")
        do {
            print("🎙️ SpeechRecognitionManager: Configuring audio session")
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            print("🎙️ SpeechRecognitionManager: Creating recognition request")
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                print("🎙️ SpeechRecognitionManager: Failed to create recognition request")
                showError("Unable to create speech recognition request")
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            print("🎙️ SpeechRecognitionManager: Recognition request configured")
            
            print("🎙️ SpeechRecognitionManager: Configuring audio engine")
            // Configure audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            
            print("🎙️ SpeechRecognitionManager: Starting audio engine")
            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()
            print("🎙️ SpeechRecognitionManager: Audio engine started successfully")
            
            print("🎙️ SpeechRecognitionManager: Starting speech recognition task")
            // Start recognition
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        let newText = result.bestTranscription.formattedString
                        print("🎙️ SpeechRecognitionManager: Recognition result: '\(newText)'")
                        self?.recognizedText = newText
                    }
                    
                    if error != nil || result?.isFinal == true {
                        let wasRecording = self?.isRecording ?? false
                        print("🎙️ SpeechRecognitionManager: Recognition ended - error: \(error?.localizedDescription ?? "none"), isFinal: \(result?.isFinal ?? false), wasRecording: \(wasRecording)")
                        
                        // Always stop recording to clean up audio session
                        if wasRecording {
                            self?.stopRecording()
                        }
                        
                        if let error = error, wasRecording {
                            // Only show error if we were still recording (not manually cancelled)
                            let nsError = error as NSError
                            if nsError.code != 216 { // 216 is the cancellation error code
                                print("🎙️ SpeechRecognitionManager: Speech recognition error (code \(nsError.code)): \(error.localizedDescription)")
                                self?.showError("Speech recognition error: \(error.localizedDescription)")
                            } else {
                                print("🎙️ SpeechRecognitionManager: Recognition cancelled (code 216)")
                            }
                        }
                    }
                }
            }
            print("🎙️ SpeechRecognitionManager: Speech recognition task started")
            
        } catch {
            print("🎙️ SpeechRecognitionManager: Error in performRecording: \(error.localizedDescription)")
            isRecording = false  // Reset recording state on error
            showError("Audio recording setup failed: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        print("🎙️ SpeechRecognitionManager: stopRecording called, current isRecording: \(isRecording)")
        isRecording = false
        
        if audioEngine.isRunning {
            print("🎙️ SpeechRecognitionManager: Stopping audio engine")
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        } else {
            print("🎙️ SpeechRecognitionManager: Audio engine was not running")
        }
        
        print("🎙️ SpeechRecognitionManager: Cleaning up recognition request and task")
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            print("🎙️ SpeechRecognitionManager: Deactivating audio session")
            // Properly deactivate and allow other audio sessions to resume
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("🎙️ SpeechRecognitionManager: Audio session deactivated successfully")
        } catch {
            print("🎙️ SpeechRecognitionManager: Failed to deactivate audio session: \(error)")
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
}
