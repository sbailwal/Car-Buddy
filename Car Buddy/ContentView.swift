import SwiftUI

struct ContentView: View {

    // Screen state.
    @State private var isListening = false
    @State private var conversationActive = false
    @State private var isFinishingTurn = false
    @State private var isWaitingForAI = false

    @State private var recognizedText = ""
    @State private var finalRecognizedText = ""
    @State private var aiResponse = ""
    @State private var statusMessage = ""

    // Keep the same service objects throughout the conversation.
    @State private var audioManager = AudioManager()
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var speechSynthesizer = SpeechSynthesizer()
    @State private var aiService = AIService()

    // Start a fresh hands-free conversation.
    private func startConversation() async {

        guard !conversationActive else { return }

        guard aiService.hasAPIKey else {
            statusMessage = "My Gemini key is missing."
            speechSynthesizer.speak(
                "I can't connect to my AI right now. My Gemini key is missing."
            )
            return
        }

        aiService.resetConversation()

        conversationActive = true
        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        statusMessage = ""

        await startListening()
    }

    // Start one microphone turn.
    private func startListening() async {

        guard conversationActive,
              !isListening,
              !isFinishingTurn else {
            return
        }

        recognizedText = ""
        finalRecognizedText = ""
        statusMessage = ""

        guard await audioManager.requestMicrophonePermission() else {
            await stopWithMessage(
                "I need microphone permission before we can talk."
            )
            return
        }

        // Start Apple's speech recognition first.
        let recognitionStarted = await speechRecognizer.startRecognition {
            text, isFinal in

            Task { @MainActor in
                recognizedText = text

                if isFinal {
                    finalRecognizedText = text
                }
            }
        }

        guard recognitionStarted else {
            await stopWithMessage(
                "I'm having trouble starting speech recognition."
            )
            return
        }

        let audioHandler = speechRecognizer.makeAudioHandler()

        // Start the microphone and wait for the end of speech.
        let microphoneStarted = audioManager.startListening(
            onAudio: audioHandler,
            onSilence: {
                Task { @MainActor in
                    await finishUserTurn()
                }
            }
        )

        guard microphoneStarted else {
            _ = await speechRecognizer.stopRecognition()

            await stopWithMessage(
                "I couldn't start the microphone."
            )
            return
        }

        isListening = true
    }

    // Finalize the transcript, check for exit, then ask Gemini.
    private func finishUserTurn() async {

        guard conversationActive,
              isListening,
              !isFinishingTurn else {
            return
        }

        isFinishingTurn = true

        let finalText = await stopListening()

        // The user may have ended the conversation during finalization.
        guard conversationActive else {
            isFinishingTurn = false
            return
        }

        guard !finalText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            isFinishingTurn = false
            await startListening()
            return
        }

        finalRecognizedText = finalText

        // Exit locally. Don't send this phrase to Gemini.
        if shouldEndConversation(finalText) {
            isFinishingTurn = false
            await endConversation()
            return
        }

        let shouldContinue = await askAI()

        isFinishingTurn = false

        // Listen again only if the conversation is still active.
        if shouldContinue && conversationActive {
            await startListening()
        }
    }

    // Send the finished sentence to Gemini and speak its answer.
    private func askAI() async -> Bool {

        guard conversationActive,
              !finalRecognizedText.isEmpty else {
            return false
        }

        isWaitingForAI = true

        do {
            let response = try await aiService.sendMessage(
                finalRecognizedText
            )

            // Don't speak an answer that arrives after the user exits.
            guard conversationActive else {
                isWaitingForAI = false
                return false
            }

            aiResponse = response
            isWaitingForAI = false

            speechSynthesizer.speak(response)
            await speechSynthesizer.waitUntilFinished()

            // STOP ANSWERING interrupts speech; the conversation
            // can then continue by opening the microphone again.
            return conversationActive

        } catch let error as AIService.AIError {

            let message: String

            switch error {
            case .invalidAPIKey:
                message = "My Gemini key is missing."
            case .serverError(429, _):
                message = "I've hit my Gemini limit for now."
            case .serverError(503, _):
                message = "Gemini is busy right now."
            default:
                message = "I'm having trouble connecting to my AI."
            }

            await stopWithMessage(message)
            print("AI ERROR:", error)
            return false

        } catch {
            await stopWithMessage(
                "Something went wrong. We can try again later."
            )
            print("AI ERROR:", error)
            return false
        }
    }

    // Stop the microphone and get Apple's finalized transcript.
    private func stopListening() async -> String {

        // Change the state immediately to prevent duplicate turn handling.
        isListening = false
        audioManager.stopListening()

        let finalText = await speechRecognizer.stopRecognition()
        finalRecognizedText = finalText

        return finalText
    }

    // Normalize punctuation so "Bye." and "I'm done!" work.
    private func shouldEndConversation(_ text: String) -> Bool {

        let cleaned = text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(
                of: "[^a-z0-9' ]",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let exitPhrases = [
            "bye",
            "goodbye",
            "i'm done",
            "im done",
            "i am done",
            "i'm finished",
            "im finished",
            "i am finished",
            "stop conversation",
            "end conversation"
        ]

        return exitPhrases.contains {
            cleaned == $0 || cleaned.hasSuffix(" " + $0)
        }
    }

    // Stop the session, say goodbye, and return to the starting screen.
    private func endConversation() async {

        conversationActive = false

        if isListening {
            _ = await stopListening()
        }

        isWaitingForAI = false
        isFinishingTurn = false

        speechSynthesizer.stopSpeaking()

        aiResponse = "Okay, talk to you later!"
        speechSynthesizer.speak(aiResponse)

        // Wait before deactivating audio, so goodbye can finish.
        await speechSynthesizer.waitUntilFinished()

        audioManager.deactivateAudioSession()
        aiService.resetConversation()

        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        statusMessage = ""
    }

    // Handle errors without accidentally restarting the microphone.
    private func stopWithMessage(_ message: String) async {

        conversationActive = false
        isWaitingForAI = false
        isFinishingTurn = false

        if isListening {
            _ = await stopListening()
        }

        statusMessage = message

        speechSynthesizer.stopSpeaking()
        speechSynthesizer.speak(message)
        await speechSynthesizer.waitUntilFinished()

        audioManager.deactivateAudioSession()
    }

    // Start a completely new chat.
    private func newChat() async {

        conversationActive = false

        if isListening {
            _ = await stopListening()
        }

        speechSynthesizer.stopSpeaking()
        audioManager.deactivateAudioSession()
        aiService.resetConversation()

        isFinishingTurn = false
        isWaitingForAI = false

        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        statusMessage = ""
    }

    // Reuse the same layout for each text panel.
    private func textPanel(
        _ title: String,
        value: String,
        emptyText: String
    ) -> some View {

        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(value.isEmpty ? emptyText : value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    var body: some View {

        VStack(spacing: 25) {

            Text("CAR BUDDY")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                !conversationActive
                    ? "Ready to talk"
                    : isWaitingForAI
                        ? "Thinking..."
                        : isFinishingTurn
                            ? "Finishing your sentence..."
                            : isListening
                                ? "Listening..."
                                : "Speaking..."
            )
            .foregroundStyle(.secondary)

            textPanel(
                "You said:",
                value: recognizedText,
                emptyText: "Nothing yet..."
            )

            textPanel(
                "Final sentence:",
                value: finalRecognizedText,
                emptyText: "Waiting for final result..."
            )

            textPanel(
                "Car Buddy:",
                value: aiResponse,
                emptyText: "No response yet..."
            )

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(
                conversationActive ? "END CONVERSATION" : "ASK AI"
            ) {
                Task {
                    if conversationActive {
                        await endConversation()
                    } else {
                        await startConversation()
                    }
                }
            }
            .font(.headline)
            .buttonStyle(.bordered)

            // Stop the current spoken answer. Listening resumes afterward.
            Button("STOP ANSWERING") {
                speechSynthesizer.stopSpeaking()
            }

            Button("NEW CHAT") {
                Task {
                    await newChat()
                }
            }

            if isWaitingForAI {
                ProgressView("Car Buddy is thinking...")
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
