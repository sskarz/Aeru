import Foundation
import AVFoundation
import Combine

@MainActor
class ModernAudioRecorder: ObservableObject {
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let audioEngine: AVAudioEngine
    private let transcriber: SpokenWordTranscriber
    private var playerNode: AVAudioPlayerNode?
    
    @Published var isRecording = false
    @Published var isAuthorized = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    var file: AVAudioFile?
    private let url: URL
    
    init(transcriber: SpokenWordTranscriber) {
        self.audioEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension(for: .wav)
        
        checkAuthorization()
    }
    
    private func checkAuthorization() {
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
    
    func record() async throws {
        print("🎤 [ModernAudioRecorder] Starting recording...")
        
        // Check authorization first
        guard await isAuthorized() else {
            print("❌ [ModernAudioRecorder] Not authorized")
            showError("Microphone permission not granted")
            return
        }
        print("✅ [ModernAudioRecorder] Microphone authorized")
        
        guard !audioEngine.isRunning else {
            print("⚠️ [ModernAudioRecorder] Audio engine already running")
            return
        }
        
        isRecording = true
        hasError = false
        print("🔴 [ModernAudioRecorder] Recording state set to true")
        
        #if os(iOS)
        do {
            try setUpAudioSession()
            print("🔊 [ModernAudioRecorder] Audio session configured")
        } catch {
            print("❌ [ModernAudioRecorder] Audio session setup failed: \(error)")
            throw error
        }
        #endif
        
        do {
            try await transcriber.setUpTranscriber()
            print("🎤 [ModernAudioRecorder] Transcriber setup complete")
        } catch {
            print("❌ [ModernAudioRecorder] Transcriber setup failed: \(error)")
            throw error
        }
        
        print("🎵 [ModernAudioRecorder] Starting audio stream...")
        for await input in try await audioStream() {
            do {
                try await transcriber.streamAudioToTranscriber(input)
            } catch {
                print("❌ [ModernAudioRecorder] Failed to stream audio to transcriber: \(error)")
                throw error
            }
        }
        print("🛑 [ModernAudioRecorder] Audio stream ended")
    }
    
    func isAuthorized() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🔐 [ModernAudioRecorder] Current auth status: \(currentStatus.rawValue)")
        
        if currentStatus == .authorized {
            print("✅ [ModernAudioRecorder] Already authorized")
            return true
        }
        
        print("🔐 [ModernAudioRecorder] Requesting audio access...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        print("🔐 [ModernAudioRecorder] Access granted: \(granted)")
        return granted
    }
    
    func stopRecording() async throws {
        print("🛑 [ModernAudioRecorder] Stopping recording...")
        
        audioEngine.stop()
        print("⏹️ [ModernAudioRecorder] Audio engine stopped")
        
        isRecording = false
        print("🔴 [ModernAudioRecorder] Recording state set to false")
        
        do {
            try await transcriber.finishTranscribing()
            print("🎤 [ModernAudioRecorder] Transcriber finished")
        } catch {
            print("❌ [ModernAudioRecorder] Error finishing transcriber: \(error)")
            throw error
        }
        
        do {
            try deactivateAudioSession()
            print("🔊 [ModernAudioRecorder] Audio session deactivated")
        } catch {
            print("❌ [ModernAudioRecorder] Error deactivating audio session: \(error)")
            throw error
        }
        
        print("✅ [ModernAudioRecorder] Stop recording complete")
    }
    
    func pauseRecording() {
        audioEngine.pause()
    }
    
    func resumeRecording() throws {
        try audioEngine.start()
    }
    
    #if os(iOS)
    func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func deactivateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
    #else
    private func deactivateAudioSession() throws {
        // No action needed on non-iOS platforms
    }
    #endif
    
    private func audioStream() async throws -> AsyncStream<AVAudioPCMBuffer> {
        print("🎵 [ModernAudioRecorder] Setting up audio stream")
        
        try setupAudioEngine()
        print("⚙️ [ModernAudioRecorder] Audio engine setup complete")
        
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        print("🎵 [ModernAudioRecorder] Input format: \(inputFormat)")
        
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, time in
            guard let self = self else { return }
            print("🎵 [ModernAudioRecorder] Received audio buffer - frameLength: \(buffer.frameLength)")
            self.writeBufferToDisk(buffer: buffer)
            self.outputContinuation?.yield(buffer)
        }
        print("🎵 [ModernAudioRecorder] Audio tap installed")
        
        audioEngine.prepare()
        print("⚙️ [ModernAudioRecorder] Audio engine prepared")
        
        try audioEngine.start()
        print("🚀 [ModernAudioRecorder] Audio engine started")
        
        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            print("📡 [ModernAudioRecorder] Audio stream created")
            outputContinuation = continuation
        }
    }
    
    private func setupAudioEngine() throws {
        print("⚙️ [ModernAudioRecorder] Setting up audio engine")
        
        let inputSettings = audioEngine.inputNode.inputFormat(forBus: 0).settings
        print("📊 [ModernAudioRecorder] Input settings: \(inputSettings)")
        
        do {
            file = try AVAudioFile(forWriting: url, settings: inputSettings)
            print("📁 [ModernAudioRecorder] Audio file created at: \(url)")
        } catch {
            print("❌ [ModernAudioRecorder] Failed to create audio file: \(error)")
            throw error
        }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        print("🔇 [ModernAudioRecorder] Previous tap removed")
    }
    
    private func writeBufferToDisk(buffer: AVAudioPCMBuffer) {
        guard let file = file else { return }
        
        do {
            try file.write(from: buffer)
        } catch {
            Task { @MainActor in
                self.showError("Failed to write audio to disk: \(error.localizedDescription)")
            }
        }
    }
    
    func playRecording() {
        guard let file = file else {
            showError("No recording available to play")
            return
        }
        
        playerNode = AVAudioPlayerNode()
        guard let playerNode = playerNode else {
            showError("Failed to create audio player")
            return
        }
        
        audioEngine.attach(playerNode)
        audioEngine.connect(
            playerNode,
            to: audioEngine.outputNode,
            format: file.processingFormat
        )
        
        playerNode.scheduleFile(
            file,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            // Playback completed
        }
        
        do {
            try audioEngine.start()
            playerNode.play()
        } catch {
            showError("Playback failed: \(error.localizedDescription)")
        }
    }
    
    func stopPlaying() {
        audioEngine.stop()
        if let playerNode = playerNode {
            audioEngine.detach(playerNode)
            self.playerNode = nil
        }
    }
    
    func cancelRecording() async {
        audioEngine.stop()
        isRecording = false
        
        await transcriber.cancelTranscription()
        
        do {
            try deactivateAudioSession()
        } catch {
            // Silent fail for audio session deactivation
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
    
    var recordingURL: URL {
        return url
    }
}
