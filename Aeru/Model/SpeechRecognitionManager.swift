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
        guard isAuthorized else {
            showError("Speech recognition not authorized")
            return
        }
        
        guard !audioEngine.isRunning else { return }
        
        // Reset previous recognition
        stopRecording()
        recognizedText = ""
        hasError = false
        
        // Request microphone permission
        AVAudioApplication.requestRecordPermission() { [weak self] allowed in
            DispatchQueue.main.async {
                if allowed {
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
                        self?.recognizedText = result.bestTranscription.formattedString
                    }
                    
                    if error != nil || result?.isFinal == true {
                        let wasRecording = self?.isRecording ?? false
                        self?.stopRecording()
                        
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
            
            isRecording = true
            
        } catch {
            showError("Audio recording setup failed: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        isRecording = false
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
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
