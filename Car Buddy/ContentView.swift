import SwiftUI

// ============================================================
// ContentView
// ============================================================
//
// This is the main screen of Car Buddy.
//
// We now have THREE important systems:
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
// ============================================================


struct ContentView: View {

    // ========================================================
    // MARK: - Screen State
    // ========================================================

    // true  = Car Buddy is listening
    // false = Car Buddy is not listening
    @State private var isListening = false


    // Latest speech-recognition result, changes while user is speaking.
    @State private var recognizedText = ""

    // THIS is the sentence we will send to the AI.
    @State private var finalRecognizedText = ""

    // AI response, e.g. aiResponse = "A black hole is a region ..."
    @State private var aiResponse = ""

    // Keeps track of whether we are currently waiting for an AI response.
    @State private var isWaitingForAI = false // false = not waiting


    // ========================================================
    // MARK: - Managers - Services used by ContentView
    // ========================================================
    
    // Controls the microphone.
    private let audioManager = AudioManager()

    // Controls speech-to-text.
    private let speechRecognizer = SpeechRecognizer()

    // Controls text-to-speech.
    private let speechSynthesizer = SpeechSynthesizer()
    
    // Sends the user's message to the AI.
    private let aiService = AIService()

    //===========
    // Functions
    //=============
    
    // Function 1 — Start listening
    // Starts the microphone and speech recognition.
    private func startListening(autoAskAI: Bool = false) async {

        // Clear the previous turn before listening again.
        recognizedText = ""
        finalRecognizedText = ""
        aiResponse = ""
        
        // Ask for microphone permission.
        let microphonePermission =
            await audioManager.requestMicrophonePermission()

        guard microphonePermission else {
            print("Microphone permission denied.")
            return
        }

        // Ask for speech-recognition permission.
        let speechPermission =
            await speechRecognizer.requestPermission()

        guard speechPermission else {
            print("Speech recognition permission denied.")
            return
        }

        // Start speech recognition.
        let recognitionStarted =
            speechRecognizer.startRecognition { text, isFinal in

                Task { @MainActor in

                    // Show the words while the user is speaking.
                    recognizedText = text

                    // Save the completed sentence.
                    if isFinal {

                        // Save the completed sentence.
                        finalRecognizedText = text

                        // AI TALK mode: now that we definitely have
                        // the final sentence, send it to the AI.
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

        // Start the microphone and send its audio
        // to SpeechRecognizer.
        let microphoneStarted =
            audioManager.startListening { buffer in
                speechRecognizer.appendAudioBuffer(buffer)
            }

        guard microphoneStarted else {
            speechRecognizer.stopRecognition()
            print("Microphone failed to start.")
            return
        }

        // The app is now listening.
        isListening = true
    }
    
    
    // Function 2 — Ask the AI
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

            // Display the response.
            aiResponse = response

            // Speak the response.
            speechSynthesizer.speak(response)

        } catch {

            print("AI ERROR:", error)
        }

        isWaitingForAI = false
    }
    
    
    // Stops the microphone and speech recognition.
    private func stopListening() {

        // Stop receiving microphone audio.
        audioManager.stopListening()

        // Stop speech recognition.
        speechRecognizer.stopRecognition()

        // Update the screen.
        isListening = false
    }
    
    
    // ========================================================
    // User Interface
    // ========================================================

    var body: some View {

        VStack(spacing: 25) {

            // App title
            Text("CAR BUDDY")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Listening status
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
            }

//            // =================================================
//            // TALK / STOP BUTTON -- we will comment out this block of code as we are now using integrated button that sends message directly to AI
//            // =================================================
//
//           // Start or stop normal listening.
//
//            Button(
//                isListening ? "STOP" : "TALK"
//            ) {
//
//                if isListening {
//
//                    // Stop the current listening session.
//                    stopListening()
//
//                } else {
//
//                    // Start listening.
//                    Task {
//                        await startListening()
//                    }
//                }
//            }
//            .font(.title2)
//            .buttonStyle(.borderedProminent)
//            .controlSize(.large)

            
            // =================================================
            // AI TALK + STOP TALKING BUTTON
            // =================================================
            // One button for the complete voice interaction.
            //
            // First tap: start listening
            // Second tap: stop listening and ask the AI

            // AI TALK:
            // first tap = listen
            // second tap = stop listening
            // final speech result = automatically sent to AI

            Button(
                isListening ? "DONE ASKING" : "ASK AI"
            ) {

                if isListening {

                    // Stop listening.
                    //
                    // startListening(autoAskAI: true) will send the
                    // final sentence to askAI() when the final result arrives.
                    stopListening()

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
                // To intrupt it from answering midway
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
            }
            
            // ------------------------------------------------
            // Show a waiting message while the AI is working.
            // ------------------------------------------------

            if isWaitingForAI {

                ProgressView("Car Buddy is thinking...")
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
