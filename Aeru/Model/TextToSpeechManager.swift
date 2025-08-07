import Foundation
import AVFoundation
import Combine

@MainActor
class TextToSpeechManager: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentText = ""
    @Published var speechRate: Float = 0.5
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoice: AVSpeechSynthesisVoice?
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    
    override init() {
        super.init()
        setupSpeechSynthesizer()
        loadAvailableVoices()
        setupAudioSession()
    }
    
    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
    }
    
    private func loadAvailableVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
        
        // Set default voice to system default English voice
        selectedVoice = AVSpeechSynthesisVoice(language: "en-US") ?? availableVoices.first
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        } catch {
            print("Failed to setup audio session for TTS: \(error)")
        }
    }
    
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Stop any current speech
        stopSpeaking()
        
        currentText = text
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            speechSynthesizer.speak(utterance)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
    
    func pauseSpeaking() {
        guard isSpeaking && !isPaused else { return }
        speechSynthesizer.pauseSpeaking(at: .word)
    }
    
    func continueSpeaking() {
        guard isSpeaking && isPaused else { return }
        speechSynthesizer.continueSpeaking()
    }
    
    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        currentText = ""
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.1, min(1.0, rate))
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
    }
    
    // Convenience methods for common use cases
    func speakWithOptions(_ text: String, rate: Float? = nil, voice: AVSpeechSynthesisVoice? = nil) {
        if let rate = rate {
            setSpeechRate(rate)
        }
        if let voice = voice {
            setVoice(voice)
        }
        speak(text)
    }
    
    func toggle() {
        if isSpeaking {
            if isPaused {
                continueSpeaking()
            } else {
                pauseSpeaking()
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TextToSpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
            isPaused = false
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPaused = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPaused = false
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            currentText = ""
            currentUtterance = nil
            
            // Deactivate audio session
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            currentText = ""
            currentUtterance = nil
            
            // Deactivate audio session
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        // This can be used for highlighting text being spoken in future features
    }
}