import Foundation
import Speech
import AVFoundation

// Turns microphone audio into text using Apple's
// SpeechAnalyzer + SpeechTranscriber system.

final class SpeechRecognizer {

    // Apple's speech-to-text module.
    private var transcriber: SpeechTranscriber?

    // Manages the speech-analysis session.
    private var analyzer: SpeechAnalyzer?

    // Sends audio into SpeechAnalyzer.
    private var inputBuilder:
        AsyncStream<AnalyzerInput>.Continuation?

    // Audio format required by SpeechAnalyzer.
    private var analyzerFormat: AVAudioFormat?

    // Converts microphone audio into the format
    // required by SpeechAnalyzer.
    private let converter = BufferConverter()

    // Keeps reading speech results while listening.
    private var resultTask:
        Task<String, Never>?

    // Sends recognized text back to ContentView.
    private var onResult:
        (@Sendable (String, Bool) -> Void)?

    // Starts a new speech-recognition session.
    func startRecognition(
        onResult: @escaping @Sendable (String, Bool) -> Void
    ) async -> Bool {

        self.onResult = onResult

        // Check that this device supports
        // Apple's SpeechTranscriber.
        guard SpeechTranscriber.isAvailable else {
            print("SpeechTranscriber is not available.")
            return false
        }

        // Find the supported US English locale.
        guard let locale =
                await SpeechTranscriber.supportedLocale(
                    equivalentTo: Locale(identifier: "en-US")
                ) else {

            print("English speech recognition is not supported.")
            return false
        }

        // Create Apple's speech-to-text module.
        let transcriber =
            SpeechTranscriber(
                locale: locale,
                preset: .progressiveTranscription
            )

        // Install the speech model if needed.
        do {

            if let request =
                try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                ) {

                try await request.downloadAndInstall()
            }

        } catch {

            print("Could not install speech model:", error)
            return false
        }

        // Find the audio format required by the model.
        guard let analyzerFormat =
                await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber]
                ) else {

            print("No compatible speech audio format.")
            return false
        }

        // Create the stream that will carry microphone audio.
        let (inputSequence, inputBuilder) =
            AsyncStream.makeStream(
                of: AnalyzerInput.self
            )

        // Create the analyzer.
        let analyzer =
            SpeechAnalyzer(
                modules: [transcriber]
            )

        // Save the current session.
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder
        self.analyzerFormat = analyzerFormat

        // Start listening for transcription results.
        //
        // This function keeps the transcript state
        // inside its own task instead of modifying
        // SpeechRecognizer properties from that task.
        resultTask = Task {

            await Self.readResults(
                from: transcriber,
                onResult: onResult
            )
        }

        // Start the analyzer.
        do {

            try await analyzer.start(
                inputSequence: inputSequence
            )

        } catch {

            print("Speech analyzer failed:", error)
            resultTask?.cancel()
            resultTask = nil
            return false
        }

        print("Speech recognition started")
        return true
    }

    // Reads transcription results from Apple.
    //
    // This function owns the temporary transcript state,
    // which keeps the concurrency simple.
    private static func readResults(
        from transcriber: SpeechTranscriber,
        onResult: @escaping @Sendable (String, Bool) -> Void
    ) async -> String {

        var finalizedText = ""
        var volatileText = ""

        do {

            for try await result in transcriber.results {

                // Convert Apple's AttributedString
                // into a normal Swift String.
                let text =
                    String(result.text.characters)

                guard !text.isEmpty else {
                    continue
                }

                if result.isFinal {

                    // This part is no longer changing.
                    finalizedText += text
                    volatileText = ""

                } else {

                    // This part may still change.
                    volatileText = text
                }

                // Combine the finished text with
                // the current live text.
                let currentText =
                    (finalizedText + volatileText)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                // Send live text back to ContentView.
                onResult(currentText, false)
            }

        } catch {

            print("Speech recognition error:", error)
        }

        // After the stream finishes, include both
        // finalized text and any last volatile text.
        return (finalizedText + volatileText)
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    // Creates the function that AudioManager calls
    // whenever it receives microphone audio.
    func makeAudioHandler()
        -> (AVAudioPCMBuffer) -> Void {

        guard let inputBuilder,
              let analyzerFormat else {

            // SpeechAnalyzer has not been started yet.
            return { _ in }
        }

        return { [converter] buffer in

            do {

                // Convert the microphone audio into
                // the format SpeechAnalyzer expects.
                let converted =
                    try converter.convertBuffer(
                        buffer,
                        to: analyzerFormat
                    )

                // Wrap the converted audio for SpeechAnalyzer.
                let input =
                    AnalyzerInput(
                        buffer: converted
                    )

                // Send the audio into the analyzer.
                inputBuilder.yield(input)

            } catch {

                print("Audio conversion error:", error)
            }
        }
    }

    // Stops speech recognition and returns
    // the complete transcript.
    func stopRecognition() async {

        guard let inputBuilder,
              let analyzer else {

            return
        }

        // Tell the audio stream that no more
        // microphone audio is coming.
        inputBuilder.finish()

        do {

            // Finish processing the remaining audio.
            try await analyzer
                .finalizeAndFinishThroughEndOfInput()

        } catch {

            print("Could not finalize speech:", error)
        }

        // Wait for Apple's result stream to finish.
        let finalText =
            await resultTask?.value ?? ""

        // Tell ContentView this is the final sentence.
        onResult?(finalText, true)

        print("Final speech:", finalText)
        print("Speech recognition stopped")

        // Clean up the current session.
        resultTask = nil
        self.inputBuilder = nil
        self.analyzer = nil
        self.transcriber = nil
        self.analyzerFormat = nil
        self.onResult = nil
    }
}


// Converts microphone audio into the format
// required by SpeechAnalyzer.

private final class BufferConverter {

    private var converter: AVAudioConverter?

    func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {

        // If the formats already match,
        // no conversion is needed.
        if buffer.format == format {
            return buffer
        }

        // Create a converter when the format changes.
        if converter == nil ||
            converter?.outputFormat != format {

            converter =
                AVAudioConverter(
                    from: buffer.format,
                    to: format
                )

            // Prevent timestamp drift.
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw ConversionError.failed
        }

        // Calculate the required output size.
        let sampleRateRatio =
            converter.outputFormat.sampleRate /
            converter.inputFormat.sampleRate

        let frameCapacity =
            AVAudioFrameCount(
                (Double(buffer.frameLength) * sampleRateRatio)
                    .rounded(.up)
            )

        guard let outputBuffer =
                AVAudioPCMBuffer(
                    pcmFormat: converter.outputFormat,
                    frameCapacity: frameCapacity
                ) else {

            throw ConversionError.failed
        }

        var conversionError: NSError?
        var bufferProcessed = false

        // Convert this microphone buffer.
        let status =
            converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, inputStatus in

                // Give the converter this buffer once.
                if bufferProcessed {

                    // More audio may arrive later.
                    inputStatus.pointee = .noDataNow
                    return nil
                }

                bufferProcessed = true
                inputStatus.pointee = .haveData

                return buffer
            }

        guard status != .error else {

            throw conversionError
                ?? ConversionError.failed
        }

        return outputBuffer
    }

    private enum ConversionError: Error {
        case failed
    }
}
