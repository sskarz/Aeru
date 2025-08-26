import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpokenWordTranscriber: ObservableObject {
    @Published var transcribedText = ""
    @Published var isTranscribing = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var audioFormat: AVAudioFormat?
    
    private let locale: Locale
    
    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }
    
    func setUpTranscriber() async throws {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.unsupportedLocale
        }
        
        transcriber = SpeechTranscriber(locale: Locale.current,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])
        
        guard let transcriber = transcriber else {
            throw TranscriptionError.transcriber
        }
        
        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
        }
        
        audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        
        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = inputBuilder
        
        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        await startTranscriptionTask(transcriber: transcriber)
        
        try await analyzer?.start(inputSequence: inputSequence)
        
        isTranscribing = true
    }
    
    private func startTranscriptionTask(transcriber: SpeechTranscriber) async {
        transcriptionTask = Task {
            do {
                for try await result in transcriber.results {
                    let bestTranscription = result.text
                    let plainTextTranscription = String(bestTranscription.characters)
                    
                    await MainActor.run {
                        self.transcribedText = plainTextTranscription
                    }
                }
            } catch {
                await MainActor.run {
                    self.showError("Transcription error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let audioFormat = audioFormat,
              let inputBuilder = inputBuilder else {
            throw TranscriptionError.notSetUp
        }
        
        let convertedBuffer: AVAudioPCMBuffer
        
        if buffer.format == audioFormat {
            convertedBuffer = buffer
        } else {
            guard let converter = AVAudioConverter(from: buffer.format, to: audioFormat),
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: buffer.frameLength) else {
                throw TranscriptionError.audioConversion
            }
            
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, _ in
                return buffer
            }
            
            if let error = error {
                throw TranscriptionError.audioConversion
            }
            
            convertedBuffer = outputBuffer
        }
        
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputBuilder.yield(input)
    }
    
    func finishTranscribing() async throws {
        inputBuilder?.finish()
        inputBuilder = nil
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        if let analyzer = analyzer {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        
        isTranscribing = false
        analyzer = nil
        transcriber = nil
    }
    
    func cancelTranscription() async {
        inputBuilder?.finish()
        inputBuilder = nil
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        if let analyzer = analyzer {
            await analyzer.cancelAndFinishNow()
        }
        
        isTranscribing = false
        analyzer = nil
        transcriber = nil
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        hasError = true
        isTranscribing = false
    }
    
    func clearError() {
        hasError = false
        errorMessage = ""
    }
    
    func clearTranscribedText() {
        transcribedText = ""
    }
}

enum TranscriptionError: LocalizedError {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound
    case unsupportedLocale
    case transcriber
    case notSetUp
    case audioConversion
    
    var errorDescription: String? {
        switch self {
        case .couldNotDownloadModel:
            return "Could not download the model."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format."
        case .localeNotSupported:
            return "This locale is not yet supported by SpeechAnalyzer."
        case .noInternetForModelDownload:
            return "The model could not be downloaded because the user is not connected to internet."
        case .audioFilePathNotFound:
            return "Couldn't write audio to file."
        case .unsupportedLocale:
            return "Unsupported locale for transcription"
        case .transcriber:
            return "Failed to create transcriber"
        case .notSetUp:
            return "Transcriber not set up properly"
        case .audioConversion:
            return "Audio format conversion failed"
        }
    }
}
