import SwiftUI

// ============================================================
// ContentView
// ============================================================
//
// This is the main screen of Car Buddy.
//
// We now have FOUR important systems:
//
// 1. AudioManager
//      Gets sound from the microphone.
//
// 2. SpeechRecognizer
//      Turns microphone audio into text.
//
// 3. AIService
//      Receives the user's final sentence and returns
//      an AI response.
//
// 4. SpeechSynthesizer
//      Speaks the AI response.
//
// The flow is now:
//
//     YOU SPEAK
//         ↓
//     Microphone
//         ↓
//     AudioManager
//         ↓
//     SpeechRecognizer
//         ↓
//     finalRecognizedText
//         ↓
//     AIService
//         ↓
//     AI response
//         ↓
//     SpeechSynthesizer
//         ↓
//     YOU HEAR CAR BUDDY
// ============================================================

struct ContentView: View {

    // ========================================================
    // MARK: - Screen State
    // ========================================================

    // true  = Car Buddy is listening
    // false = Car Buddy is not listening
    @State private var isListening = false

    // Message shown when natural Gemini voice is unavailable.
    //
    // Examples:
    // "Natural voice quota reached — using iPhone voice."
    // "Natural voice service is busy — using iPhone voice."
    @State private var speechStatusMessage = ""

    // Latest speech-recognition result.
    // Changes while the user is speaking.
    @State private var recognizedText = ""

    // This is the sentence we send to the AI.
    @State private var finalRecognizedText = ""

    // AI response.
    @State private var aiResponse = ""

    // true = waiting for the AI response
    // false = not waiting
    @State private var isWaitingForAI = false

    // ========================================================
    // MARK: - Managers / Services
    // ========================================================

    // Controls the microphone.
    private let audioManager = AudioManager()

    // Controls speech-to-text.
    private let speechRecognizer = SpeechRecognizer()

    // Controls text-to-speech.
    private let speechSynthesizer = SpeechSynthesizer()

    // Sends the user's message to the AI.
    private let aiService = AIService()

    // ========================================================
    // MARK: - Functions
    // ========================================================

    // Function 1 — Start listening
    //
    // Starts the microphone and SpeechAnalyzer.
    private func startListening(
        autoAskAI: Bool = false
    ) async {

        // Clear the previous turn before listening again.
        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""

        // Clear any previous voice-status message.
        speechStatusMessage = ""

        // Ask for microphone permission.
        let microphonePermission =
            await audioManager.requestMicrophonePermission()

        guard microphonePermission else {
            print("Microphone permission denied.")
            return
        }

        // Start SpeechAnalyzer.
        //
        // The speech system is now on-device,
        // so we no longer ask for the old
        // SFSpeechRecognizer permission.
        let recognitionStarted =
            await speechRecognizer.startRecognition {
                text,
                isFinal in

                Task { @MainActor in

                    // Show the live recognized text.
                    recognizedText = text

                    // Save the final sentence.
                    if isFinal {

                        finalRecognizedText = text

                        // AI TALK:
                        // automatically send the final sentence
                        // to the AI.
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

        // Get the audio handler that converts microphone
        // audio into the format SpeechAnalyzer needs.
        let audioHandler =
            speechRecognizer.makeAudioHandler()

        // Start the microphone.
        //
        // AudioManager sends each microphone buffer
        // to this handler.
        let microphoneStarted =
            audioManager.startListening(
                onAudio: audioHandler
            )

        guard microphoneStarted else {

            // Finish SpeechAnalyzer because the microphone
            // could not be started.
            await speechRecognizer.stopRecognition()

            print("Microphone failed to start.")
            return
        }

        // The app is now listening.
        isListening = true
    }

    // ========================================================
    // Function 2 — Ask the AI
    // ========================================================
    //
    // Sends the completed sentence to the AI,
    // displays the response, and speaks it.
    private func askAI() async {

        guard !finalRecognizedText.isEmpty else {
            print("No final sentence to send.")
            return
        }

        isWaitingForAI = true

        do {

            // Send the user's sentence to the AI.
            let response =
                try await aiService.sendMessage(
                    finalRecognizedText
                )

            // Display the AI response.
            aiResponse = response

            // Try the natural Gemini voice.
            //
            // If Gemini TTS fails, SpeechSynthesizer
            // automatically falls back to Apple's voice.
            let speechResult =
                await speechSynthesizer.speak(
                    response,
                    using: aiService
                )

            // Show the result of the voice attempt.
            switch speechResult {

            case .natural:

                // Natural Gemini voice worked.
                // No warning is needed.
                speechStatusMessage = ""

            case .fallback(let message):

                // Gemini voice was unavailable,
                // so Apple voice was used instead.
                speechStatusMessage = message
            }

        } catch {

            print("AI ERROR:", error)
        }

        isWaitingForAI = false
    }

    // ========================================================
    // Function 3 — Stop listening
    // ========================================================
    //
    // Stops the microphone and finishes SpeechAnalyzer.
    private func stopListening() async {

        // Stop receiving microphone audio.
        audioManager.stopListening()

        // Let SpeechAnalyzer finish processing
        // the audio it already received.
        await speechRecognizer.stopRecognition()

        // Update the screen.
        isListening = false
    }

    // ========================================================
    // MARK: - User Interface
    // ========================================================

    var body: some View {

        VStack(spacing: 25) {

            // =================================================
            // APP TITLE
            // =================================================

            Text("CAR BUDDY")
                .font(.largeTitle)
                .fontWeight(.bold)

            // =================================================
            // LISTENING STATUS
            // =================================================

            Text(
                isListening
                ? "Listening..."
                : "Ready to talk"
            )
            .foregroundStyle(.secondary)

            // =================================================
            // LIVE SPEECH
            // =================================================

            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text("You said:")
                    .font(.headline)

                // Display the latest recognized speech.
                //
                // This can be a partial result.
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

            // =================================================
            // FINAL SENTENCE
            // =================================================

            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text("Final sentence:")
                    .font(.headline)

                // Display the final recognized sentence.
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

            // =================================================
            // AI RESPONSE
            // =================================================

            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                Text("Car Buddy:")
                    .font(.headline)

                // Display the AI's response.
                //
                // Before we ask the AI anything,
                // show a placeholder.
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

                // =================================================
                // VOICE STATUS MESSAGE
                // =================================================
                //
                // This only appears when the natural Gemini
                // voice could not be used and Apple voice
                // was used as the fallback.

                if !speechStatusMessage.isEmpty {

                    Text(speechStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }

            // =================================================
            // TALK / STOP BUTTON
            // =================================================
            //
            // This old separate TALK/STOP button is intentionally
            // commented out because AI TALK now handles the
            // complete interaction.

            /*
            Button(
                isListening ? "STOP" : "TALK"
            ) {

                if isListening {

                    Task {
                        await stopListening()
                    }

                } else {

                    Task {
                        await startListening()
                    }
                }
            }
            .font(.title2)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            */

            // =================================================
            // AI TALK BUTTON
            // =================================================
            //
            // First tap:
            //      Start listening
            //
            // Second tap:
            //      Stop listening
            //
            // The final speech result is then
            // automatically sent to the AI.

            Button(
                isListening
                ? "DONE ASKING"
                : "ASK AI"
            ) {

                if isListening {

                    // Stop listening and finalize the sentence.
                    Task {
                        await stopListening()
                    }

                } else {

                    // Start listening in AI TALK mode.
                    Task {
                        await startListening(
                            autoAskAI: true
                        )
                    }
                }
            }
            .font(.headline)
            .buttonStyle(.bordered)

            // =================================================
            // STOP TALKING BUTTON
            // =================================================

            Button("STOP ANSWERING") {

                // Stop the current AI speech immediately.
                speechSynthesizer.stopSpeaking()
            }

            // =================================================
            // NEW CHAT BUTTON
            // =================================================

            Button("NEW CHAT") {

                // Forget the previous AI conversation.
                aiService.resetConversation()

                // Clear the text currently displayed on screen.
                recognizedText = ""
                finalRecognizedText = ""
                aiResponse = ""

                // Clear any old voice-status message.
                speechStatusMessage = ""
            }

            // =================================================
            // WAITING MESSAGE
            // =================================================

            if isWaitingForAI {

                ProgressView(
                    "Car Buddy is thinking..."
                )
            }
        }
        .padding()
    }
}

// ============================================================
// MARK: - Preview
// ============================================================

#Preview {
    ContentView()
}
