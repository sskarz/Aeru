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
    
    // Modern Speech Framework (iOS 26+)
    private var modernTranscriber: SpokenWordTranscriber?
    private var modernRecorder: ModernAudioRecorder?
    
    // Common properties
    private var silenceTimer: Timer?
    private var lastSpeechTime: Date?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence
    private var onAutoStop: (() -> Void)?
    private var audioPlayer: AVAudioPlayer?
    
    init() {
        checkAuthorization()
        setupModernFramework()
    }
    
    private func setupModernFramework() {
        modernTranscriber = SpokenWordTranscriber(locale: Locale(identifier: "en-US"))
        if let transcriber = modernTranscriber {
            modernRecorder = ModernAudioRecorder(transcriber: transcriber)
        }
    }
    
    private func checkAuthorization() {
        // Check microphone permissions using AVCaptureDevice
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            isAuthorized = true
        case .denied, .restricted, .notDetermined:
            requestAuthorization()
        @unknown default:
            isAuthorized = false
        }
    }
    
    private func requestAuthorization() {
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
        
        guard let transcriber = modernTranscriber,
              let recorder = modernRecorder else {
            showError("Speech framework not available")
            return
        }
        
        isInContinuousMode = continuousMode
        self.onAutoStop = onAutoStop
        
        // Reset previous recognition
        stopRecording()
        recognizedText = ""
        hasError = false
        
        isRecording = true
        if isInContinuousMode {
            playListeningStartSound()
        }
        
        Task {
            do {
                try await recorder.record()
            } catch {
                await MainActor.run {
                    self.showError("Recording failed: \(error.localizedDescription)")
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
    
    
    func stopRecording() {
        isRecording = false
        
        // Clear silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        lastSpeechTime = nil
        
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
