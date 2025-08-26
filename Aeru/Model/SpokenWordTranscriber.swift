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
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    
    var analyzerFormat: AVAudioFormat?
    var converter = BufferConverter()
    
    private let locale: Locale
    
    init(locale: Locale = Locale.current) {
        self.locale = locale
    }
    
    func setUpTranscriber() async throws {
        print("🎤 [SpokenWordTranscriber] Starting setup for locale: \(locale)")
        
        transcriber = SpeechTranscriber(locale: locale,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])
        
        guard let transcriber = transcriber else {
            print("❌ [SpokenWordTranscriber] Failed to create transcriber")
            throw TranscriptionError.transcriber
        }
        print("✅ [SpokenWordTranscriber] Transcriber created successfully")
        
        analyzer = SpeechAnalyzer(modules: [transcriber])
        print("🧠 [SpokenWordTranscriber] Analyzer created")
        
        do {
            try await ensureModel(transcriber: transcriber, locale: locale)
            print("✅ [SpokenWordTranscriber] Model ensured")
        } catch let error as TranscriptionError {
            print("❌ [SpokenWordTranscriber] Model error: \(error)")
            throw error
        }
        
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        print("🎵 [SpokenWordTranscriber] Audio format: \(analyzerFormat?.description ?? "nil")")
        
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = inputSequence
        self.inputBuilder = inputBuilder
        print("📡 [SpokenWordTranscriber] Input stream created")
        
        // Start the recognition task - this is the key part Apple does differently!
        recognizerTask = Task {
            print("📝 [SpokenWordTranscriber] Starting recognition task")
            do {
                for try await result in transcriber.results {
                    let text = result.text
                    let plainText = String(text.characters)
                    print("🗣️ [SpokenWordTranscriber] New transcription result: '\(plainText)' (isFinal: \(result.isFinal))")
                    
                    await MainActor.run {
                        if result.isFinal {
                            print("✅ [SpokenWordTranscriber] Final result: '\(plainText)'")
                            self.transcribedText = plainText
                        } else {
                            print("🔄 [SpokenWordTranscriber] Partial result: '\(plainText)'")
                            self.transcribedText = plainText
                        }
                    }
                }
                print("⚠️ [SpokenWordTranscriber] Recognition results stream ended")
            } catch {
                print("❌ [SpokenWordTranscriber] Recognition task error: \(error)")
                await MainActor.run {
                    self.showError("Recognition failed: \(error.localizedDescription)")
                }
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
        print("🚀 [SpokenWordTranscriber] Analyzer started")
        
        isTranscribing = true
        print("✅ [SpokenWordTranscriber] Setup complete - isTranscribing: \(isTranscribing)")
    }
    
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder = inputBuilder,
              let analyzerFormat = analyzerFormat else {
            print("❌ [SpokenWordTranscriber] Not set up - inputBuilder: \(inputBuilder != nil), analyzerFormat: \(analyzerFormat != nil)")
            throw TranscriptionError.notSetUp
        }
        
        print("🎵 [SpokenWordTranscriber] Received audio buffer - frameLength: \(buffer.frameLength)")
        
        do {
            let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
            print("🔄 [SpokenWordTranscriber] Buffer converted successfully")
            
            let input = AnalyzerInput(buffer: converted)
            inputBuilder.yield(input)
            print("📡 [SpokenWordTranscriber] Audio buffer sent to analyzer")
        } catch let converterError as BufferConverter.Error {
            print("❌ [SpokenWordTranscriber] Buffer conversion failed: \(converterError)")
            throw TranscriptionError.audioConversion
        } catch {
            print("❌ [SpokenWordTranscriber] Unexpected conversion error: \(error)")
            throw TranscriptionError.audioConversion
        }
    }
    
    func finishTranscribing() async throws {
        print("🛑 [SpokenWordTranscriber] Finishing transcription")
        
        inputBuilder?.finish()
        inputBuilder = nil
        print("📡 [SpokenWordTranscriber] Input stream finished")
        
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        print("🧠 [SpokenWordTranscriber] Analyzer finalized")
        
        recognizerTask?.cancel()
        recognizerTask = nil
        print("📝 [SpokenWordTranscriber] Recognition task cancelled")
        
        isTranscribing = false
        analyzer = nil
        transcriber = nil
        print("✅ [SpokenWordTranscriber] Cleanup complete - isTranscribing: \(isTranscribing)")
    }
    
    func cancelTranscription() async {
        print("🛑 [SpokenWordTranscriber] Cancelling transcription")
        
        inputBuilder?.finish()
        inputBuilder = nil
        
        recognizerTask?.cancel()
        recognizerTask = nil
        
        if let analyzer = analyzer {
            await analyzer.cancelAndFinishNow()
        }
        
        isTranscribing = false
        analyzer = nil
        transcriber = nil
        print("✅ [SpokenWordTranscriber] Cancellation complete")
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

// MARK: - Model Management (Apple's pattern)
extension SpokenWordTranscriber {
    func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        print("📥 [SpokenWordTranscriber] Ensuring model for locale: \(locale)")
        
        guard await supported(locale: locale) else {
            print("❌ [SpokenWordTranscriber] Locale not supported: \(locale)")
            throw TranscriptionError.localeNotSupported
        }
        print("✅ [SpokenWordTranscriber] Locale supported: \(locale)")
        
        if await installed(locale: locale) {
            print("✅ [SpokenWordTranscriber] Model already installed")
            return
        } else {
            print("📥 [SpokenWordTranscriber] Model not installed, downloading...")
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        let isSupported = supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
        print("🌍 [SpokenWordTranscriber] Locale \(locale) supported: \(isSupported)")
        return isSupported
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let isInstalled = installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
        print("💾 [SpokenWordTranscriber] Locale \(locale) installed: \(isInstalled)")
        return isInstalled
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            print("📥 [SpokenWordTranscriber] Starting asset download...")
            try await downloader.downloadAndInstall()
            print("✅ [SpokenWordTranscriber] Asset download complete")
        } else {
            print("✅ [SpokenWordTranscriber] No download needed")
        }
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
