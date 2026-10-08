import SwiftUI

struct ContentView: View {

    // Screen state.
    @State private var isListening = false
    @State private var conversationActive = false
    @State private var recognizedText = ""
    @State private var finalRecognizedText = ""
    @State private var aiResponse = ""
    @State private var isWaitingForAI = false
    @State private var statusMessage = ""

    // App services.
    private let audioManager = AudioManager()
    private let speechRecognizer = SpeechRecognizer()
    private let speechSynthesizer = SpeechSynthesizer()
    private let aiService = AIService()

    // Start a hands-free conversation.
    private func startConversation() async {

        // Check Gemini before starting.
        guard aiService.hasAPIKey else {

            let message =
                "Hmm, I can't connect to my AI right now. My Gemini key is missing."

            statusMessage = message
            speechSynthesizer.speak(message)

            return
        }

        conversationActive = true

        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        statusMessage = ""

        // Start listening right away.
        await startListening()
    }

    // Start one microphone turn.
    private func startListening() async {

        guard conversationActive else {
            return
        }

        // Clear the new turn.
        recognizedText = ""
        finalRecognizedText = ""
        statusMessage = ""

        let microphonePermission =
            await audioManager
                .requestMicrophonePermission()

        guard microphonePermission else {

            conversationActive = false

            let message =
                "I need microphone permission before we can talk."

            statusMessage = message
            speechSynthesizer.speak(message)

            return
        }

        // Start SpeechAnalyzer.
        let recognitionStarted =
            await speechRecognizer.startRecognition {
                text,
                isFinal in

                Task { @MainActor in

                    // Show live speech.
                    recognizedText = text

                    // Save the final result.
                    if isFinal {
                        finalRecognizedText = text
                    }
                }
            }

        guard recognitionStarted else {

            conversationActive = false

            let message =
                "Hmm, I'm having trouble starting speech recognition."

            statusMessage = message
            speechSynthesizer.speak(message)

            return
        }

        // Connect the microphone to SpeechAnalyzer.
        let audioHandler =
            speechRecognizer.makeAudioHandler()

        // Start listening and watch for silence.
        let microphoneStarted =
            audioManager.startListening(
                onAudio: audioHandler,
                onSilence: {

                    Task { @MainActor in
                        await finishUserTurn()
                    }
                }
            )

        guard microphoneStarted else {

            _ = await speechRecognizer.stopRecognition()

            conversationActive = false

            let message =
                "Hmm, I couldn't get the microphone started."

            statusMessage = message
            speechSynthesizer.speak(message)

            return
        }

        isListening = true
    }

    // Finish the user's turn.
    private func finishUserTurn() async {

        guard conversationActive,
              isListening
        else {
            return
        }

        // Stop listening and get the final sentence.
        let finalText =
            await stopListening()

        guard !finalText.isEmpty else {

            // Nothing was recognized.
            // Listen again.
            await startListening()

            return
        }

        // Check whether the user wants to exit.
        if shouldEndConversation(finalText) {

            await endConversation()

            return
        }

        // Ask Gemini.
        //
        // true  = keep the conversation going
        // false = stop the conversation
        let shouldContinue =
            await askAI()

        guard shouldContinue,
              conversationActive
        else {
            return
        }

        // Start the next turn automatically.
        await startListening()
    }

    // Send the user's sentence to Gemini.
    //
    // Returns true when the conversation should continue.
    private func askAI() async -> Bool {

        guard !finalRecognizedText.isEmpty else {
            return false
        }

        isWaitingForAI = true

        do {

            // Gemini creates the answer.
            let response =
                try await aiService.sendMessage(
                    finalRecognizedText
                )

            // Show the answer.
            aiResponse = response

            isWaitingForAI = false

            // Apple speaks Gemini's answer.
            speechSynthesizer.speak(response)

            // Wait until Car Buddy finishes speaking.
            await speechSynthesizer
                .waitUntilFinished()

            return true

        } catch let error as AIService.AIError {

            isWaitingForAI = false

            let message: String

            switch error {

            case .invalidAPIKey:

                message =
                    "Hmm, I can't connect to my AI right now. My Gemini key is missing."

            case .serverError(429, _):

                message =
                    "Looks like I've hit my Gemini limit for now. We can try again later."

            case .serverError(503, _):

                message =
                    "Hmm, Gemini is having a busy moment. We can try again later."

            default:

                message =
                    "Hmm, I'm having trouble connecting right now. We can try again later."
            }

            // Show the problem.
            statusMessage = message

            // End the hands-free session.
            //
            // This is important: otherwise the microphone
            // could hear this message and start the loop again.
            conversationActive = false

            // Speak the problem using Apple's voice.
            speechSynthesizer.speak(message)

            await speechSynthesizer
                .waitUntilFinished()

            print(
                "AI ERROR:",
                error
            )

            return false

        } catch {

            isWaitingForAI = false

            let message =
                "Oops, something went wrong on my end. We can try again later."

            statusMessage = message

            // Stop the automatic conversation.
            conversationActive = false

            // Speak the problem.
            speechSynthesizer.speak(message)

            await speechSynthesizer
                .waitUntilFinished()

            print(
                "AI ERROR:",
                error
            )

            return false
        }
    }

    // Stop the current microphone turn.
    private func stopListening() async -> String {

        audioManager.stopListening()

        let finalText =
            await speechRecognizer.stopRecognition()

        isListening = false

        finalRecognizedText = finalText

        return finalText
    }

    // Check for a spoken exit phrase.
    private func shouldEndConversation(
        _ text: String
    ) -> Bool {

        let text =
            text
                .lowercased()
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let exitPhrases = [
            "bye",
            "goodbye",
            "i'm done",
            "im done",
            "i am done",
            "stop conversation",
            "end conversation"
        ]

        // Require the exit phrase to be a complete word/phrase.
        return exitPhrases.contains { phrase in

            text == phrase ||
            text.hasPrefix(phrase + " ") ||
            text.hasSuffix(" " + phrase)
        }
    }

    // End the hands-free conversation.
    private func endConversation() async {

        conversationActive = false

        if isListening {
            _ = await stopListening()
        }

        speechSynthesizer.stopSpeaking()

        let goodbye =
            "Okay, talk to you later!"

        aiResponse = goodbye

        speechSynthesizer.speak(goodbye)
    }

    // Reset everything and start a fresh Gemini chat.
    private func newChat() async {

        conversationActive = false

        if isListening {
            _ = await stopListening()
        }

        speechSynthesizer.stopSpeaking()

        aiService.resetConversation()

        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        statusMessage = ""
        isWaitingForAI = false
    }

    var body: some View {

        VStack(spacing: 25) {

            Text("CAR BUDDY")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Show what Car Buddy is doing.
            Text(
                conversationActive
                ? (
                    isWaitingForAI
                    ? "Thinking..."
                    : isListening
                        ? "Listening..."
                        : "Speaking..."
                )
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

                // Show errors or status messages.
                if !statusMessage.isEmpty {

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // One tap starts the conversation.
            // The conversation then runs hands-free.
            Button(
                conversationActive
                ? "END CONVERSATION"
                : "ASK AI"
            ) {

                if conversationActive {

                    Task {
                        await endConversation()
                    }

                } else {

                    Task {
                        await startConversation()
                    }
                }
            }
            .font(.headline)
            .buttonStyle(.bordered)

            // Stop Apple's voice.
            Button("STOP ANSWERING") {

                speechSynthesizer.stopSpeaking()
            }

            // Start a fresh Gemini conversation.
            Button("NEW CHAT") {

                Task {
                    await newChat()
                }
            }

            // Show this while Gemini is working.
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
