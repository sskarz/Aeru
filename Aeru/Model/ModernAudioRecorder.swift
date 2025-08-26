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
        // Check authorization first
        guard await isAuthorized() else {
            showError("Microphone permission not granted")
            return
        }
        
        guard !audioEngine.isRunning else {
            return
        }
        
        isRecording = true
        hasError = false
        
        #if os(iOS)
        try setUpAudioSession()
        #endif
        
        try await transcriber.setUpTranscriber()
        
        for await input in try await audioStream() {
            try await transcriber.streamAudioToTranscriber(input)
        }
    }
    
    func isAuthorized() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    func stopRecording() async throws {
        audioEngine.stop()
        isRecording = false
        
        try await transcriber.finishTranscribing()
        
        try deactivateAudioSession()
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
        try setupAudioEngine()
        
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: audioEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak self] buffer, time in
            guard let self = self else { return }
            self.writeBufferToDisk(buffer: buffer)
            self.outputContinuation?.yield(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            outputContinuation = continuation
        }
    }
    
    private func setupAudioEngine() throws {
        let inputSettings = audioEngine.inputNode.inputFormat(forBus: 0).settings
        file = try AVAudioFile(forWriting: url, settings: inputSettings)
        
        audioEngine.inputNode.removeTap(onBus: 0)
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
