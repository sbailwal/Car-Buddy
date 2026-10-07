import AVFoundation

// ============================================================
// AudioManager
// ============================================================
//
// PURPOSE:
//
// AudioManager is responsible for getting live audio from
// the iPhone's microphone.
//
// Think of this class as:
//
//     "The person operating the microphone."
//
// Its job is NOT to understand what you are saying.
//
// Its job is only:
//
//     Microphone
//         ↓
//     receive audio
//         ↓
//     give audio to the next part of the app
//
// The next part will be SpeechRecognizer.
//
// Eventually:
//
//     YOU SPEAK
//         ↓
//     Microphone
//         ↓
//     AudioManager
//         ↓
//     SpeechRecognizer
//         ↓
//     TEXT
// ============================================================


final class AudioManager {

    // ========================================================
    // MARK: - Audio Engine
    // ========================================================

    // AVAudioEngine is Apple's system for working with
    // live audio.
    //
    // We use one audio engine to receive microphone audio.
    private let audioEngine = AVAudioEngine()


    // ========================================================
    // MARK: - Microphone Permission
    // ========================================================

    // This function asks iOS for permission to use
    // the microphone.
    //
    // It returns:
    //
    //     true  = user allowed microphone access
    //     false = user denied microphone access
    //
    // "async" means the function may need to WAIT for iOS
    // to finish asking the user.
    func requestMicrophonePermission() async -> Bool {

        // Ask Apple's AVFAudio system for microphone permission.
        return await AVAudioApplication.requestRecordPermission()
    }


    // ========================================================
    // MARK: - Start Listening
    // ========================================================

    // This function starts receiving audio from the microphone.
    //
    // "onAudio" is a CLOSURE.
    //
    // A closure is basically a function we can hand to
    // another function.
    //
    // We are saying:
    //
    //     "AudioManager, whenever you receive a new piece
    //      of microphone audio, call this function."
    //
    // The function receives:
    //
    //     AVAudioPCMBuffer
    //
    // which is one small chunk of audio.
    //
    // The function returns:
    //
    //     true  = microphone started
    //     false = microphone could not start
    func startListening(
        onAudio: @escaping (AVAudioPCMBuffer) -> Void
    ) -> Bool {

        // ====================================================
        // STEP 1 — Get the microphone input node
        // ====================================================

        // AVAudioEngine contains different audio nodes.
        //
        // The input node represents audio COMING INTO
        // the app.
        //
        // In our case:
        //
        //     iPhone microphone
        //            ↓
        //       inputNode
        let inputNode = audioEngine.inputNode


        // ====================================================
        // STEP 2 — Find the microphone's audio format
        // ====================================================

        // The microphone has an audio format.
        //
        // The format contains information such as:
        //
        //     sample rate
        //     channel count
        //     audio format
        //
        // We ask Apple's audio system what format the
        // microphone is currently producing.
        let recordingFormat =
            inputNode.outputFormat(forBus: 0)


        // ====================================================
        // STEP 3 — Make sure the format is valid
        // ====================================================

        // Earlier, when testing the Simulator, we encountered
        // a crash caused by an invalid audio format.
        //
        // For example:
        //
        //     sample rate = 0
        //     channel count = 0
        //
        // That is not usable microphone audio.
        //
        // So we check BEFORE installing the microphone tap.
        guard recordingFormat.sampleRate > 0,
              recordingFormat.channelCount > 0 else {

            print("No usable microphone input.")

            // Tell ContentView:
            //
            // "The microphone did not start."
            return false
        }


        // ====================================================
        // STEP 4 — Remove an old microphone tap
        // ====================================================

        // A "tap" is a listener attached to an audio node.
        //
        // It allows us to receive copies of incoming audio.
        //
        // Apple allows only ONE tap on a particular bus.
        //
        // Therefore we remove an old tap before installing
        // a new one.
        //
        // This is especially important when the user:
        //
        //     TALK → STOP → TALK
        //
        // without this cleanup, a second tap could cause
        // problems.
        inputNode.removeTap(onBus: 0)


        // ====================================================
        // STEP 5 — Install the microphone tap
        // ====================================================

        // Now we attach our listener to the microphone.
        //
        // Every time new microphone audio arrives,
        // Apple's audio system calls the code inside:
        //
        //     { buffer, _ in
        //
        //             ...
        //
        //     }
        //
        // "buffer" is the audio chunk.
        //
        // We then give that buffer to "onAudio".
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { buffer, _ in

            // ------------------------------------------------
            // Send this audio chunk to the caller.
            // ------------------------------------------------
            //
            // In our Car Buddy app, the caller will be
            // ContentView.
            //
            // ContentView will immediately send this
            // buffer to SpeechRecognizer.
            onAudio(buffer)


            // Print this so we can see in Xcode that
            // the microphone is actually producing audio.
            print("Receiving microphone audio")
        }


        // ====================================================
        // STEP 6 — Prepare the audio engine
        // ====================================================

        // prepare() gets the audio engine ready to run.
        audioEngine.prepare()


        // ====================================================
        // STEP 7 — Start the audio engine
        // ====================================================

        // Starting the audio engine can fail.
        //
        // Therefore we use:
        //
        //     do
        //     try
        //     catch
        //
        // "try" means:
        //
        //     "This operation might fail."
        //
        // "catch" handles the failure.
        do {

            // Actually start microphone audio processing.
            try audioEngine.start()


            // This tells us the microphone successfully started.
            print("Microphone started")


            // Tell ContentView that startup succeeded.
            return true

        } catch {

            // Something prevented the microphone from starting.
            print(
                "Could not start microphone:",
                error
            )


            // Tell ContentView that startup failed.
            return false
        }
    }


    // ========================================================
    // MARK: - Stop Listening
    // ========================================================

    // This function stops receiving microphone audio.
    func stopListening() {

        // Remove the microphone tap.
        //
        // This disconnects our listener from the microphone.
        audioEngine.inputNode.removeTap(onBus: 0)


        // Stop the audio engine.
        audioEngine.stop()


        // Print a message so we can verify the stop operation.
        print("Microphone stopped")
    }
}
