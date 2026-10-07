import SwiftUI

struct ContentView: View {

    // Screen state.
    @State private var isListening = false
    @State private var recognizedText = ""
    @State private var finalRecognizedText = ""
    @State private var aiResponse = ""
    @State private var isWaitingForAI = false

    // Shows Gemini errors on the screen.
    @State private var statusMessage = ""

    // App services.
    private let audioManager = AudioManager()
    private let speechRecognizer = SpeechRecognizer()
    private let speechSynthesizer = SpeechSynthesizer()
    private let aiService = AIService()

    // Start the microphone and speech recognition.
    private func startListening(
        autoAskAI: Bool = false
    ) async {

        // Clear the previous turn.
        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        statusMessage = ""

        // Ask for microphone permission.
        let microphonePermission =
            await audioManager.requestMicrophonePermission()

        guard microphonePermission else {
            print("Microphone permission denied.")
            return
        }

        // Start Apple's SpeechAnalyzer.
        let recognitionStarted =
            await speechRecognizer.startRecognition {
                text,
                isFinal in

                Task { @MainActor in

                    // Show live speech.
                    recognizedText = text

                    // Save the finished sentence.
                    if isFinal {

                        finalRecognizedText = text

                        // AI TALK sends it automatically.
                        if autoAskAI {

                            Task {
                                await askAI()
                            }
                        }
                    }
                }
            }

        guard recognitionStarted else {
            print("Speech recognition failed to start.")
            return
        }

        // Connect microphone audio to SpeechAnalyzer.
        let audioHandler =
            speechRecognizer.makeAudioHandler()

        // Start the microphone.
        let microphoneStarted =
            audioManager.startListening(
                onAudio: audioHandler
            )

        guard microphoneStarted else {

            await speechRecognizer.stopRecognition()

            print("Microphone failed to start.")
            return
        }

        isListening = true
    }

    // Send the finished sentence to Gemini.
    private func askAI() async {

        guard !finalRecognizedText.isEmpty else {
            print("No final sentence to send.")
            return
        }

        statusMessage = ""
        isWaitingForAI = true

        do {

            // Gemini generates the text answer.
            let response =
                try await aiService.sendMessage(
                    finalRecognizedText
                )

            // Show Gemini's answer.
            aiResponse = response

            // Apple speaks Gemini's answer.
            speechSynthesizer.speak(
                response
            )

        } catch let error as AIService.AIError {

            // Convert the error into a user-friendly message.
            let message: String

            switch error {

            case .invalidAPIKey:
                message =
                    "Gemini is unavailable because the API key is missing."

            case .serverError(429, _):
                message =
                    "Gemini quota has been reached. Please try again later."

            case .serverError(503, _):
                message =
                    "Gemini is temporarily unavailable. Please try again."

            default:
                message =
                    "I couldn't reach Gemini right now. Please try again."
            }

            // Show the message on screen.
            statusMessage = message

            // Apple speaks the message.
            speechSynthesizer.speak(
                message
            )

            print(
                "AI ERROR:",
                error
            )

        } catch {

            // Handle any unexpected error.
            let message =
                "Something went wrong. Please try again."

            statusMessage = message

            // Apple speaks the message.
            speechSynthesizer.speak(
                message
            )

            print(
                "AI ERROR:",
                error
            )
        }

        isWaitingForAI = false
    }

    // Stop the microphone and finish recognition.
    private func stopListening() async {

        audioManager.stopListening()

        await speechRecognizer.stopRecognition()

        isListening = false
    }

    var body: some View {

        VStack(spacing: 25) {

            Text("CAR BUDDY")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Show whether Car Buddy is listening.
            Text(
                isListening
                ? "Listening..."
                : "Ready to talk"
            )
            .foregroundStyle(.secondary)

            // Live speech.
            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text("You said:")
                    .font(.headline)

                Text(
                    recognizedText.isEmpty
                    ? "Nothing yet..."
                    : recognizedText
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding()
                .background(
                    .gray.opacity(0.1)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }

            // Final sentence.
            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text("Final sentence:")
                    .font(.headline)

                Text(
                    finalRecognizedText.isEmpty
                    ? "Waiting for final result..."
                    : finalRecognizedText
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding()
                .background(
                    .gray.opacity(0.1)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }

            // Gemini's answer.
            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text("Car Buddy:")
                    .font(.headline)

                Text(
                    aiResponse.isEmpty
                    ? "No response yet..."
                    : aiResponse
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding()
                .background(
                    .gray.opacity(0.1)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )

                // Show an error/status message when needed.
                if !statusMessage.isEmpty {

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // First tap = listen.
            // Second tap = finish the question.
            Button(
                isListening
                ? "DONE ASKING"
                : "ASK AI"
            ) {

                if isListening {

                    Task {
                        await stopListening()
                    }

                } else {

                    Task {
                        await startListening(
                            autoAskAI: true
                        )
                    }
                }
            }
            .font(.headline)
            .buttonStyle(.bordered)

            // Stop Apple's voice.
            Button("STOP ANSWERING") {

                speechSynthesizer.stopSpeaking()
            }

            // Start a new Gemini conversation.
            Button("NEW CHAT") {

                aiService.resetConversation()

                recognizedText = ""
                finalRecognizedText = ""
                aiResponse = ""
                statusMessage = ""
            }

            // Show this while Gemini is responding.
            if isWaitingForAI {

                ProgressView(
                    "Car Buddy is thinking..."
                )
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
