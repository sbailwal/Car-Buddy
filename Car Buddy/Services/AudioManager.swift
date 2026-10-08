import AVFoundation

// Controls the iPhone microphone.

final class AudioManager {

    private let audioEngine =
        AVAudioEngine()

    // Used to detect when the user stops talking.
    private var hasDetectedSpeech = false
    private var silenceStartTime:
        TimeInterval?

    private var silenceReported = false

    // How long the user must be quiet before
    // Car Buddy treats the turn as finished.
    private let silenceDuration:
        TimeInterval = 1.5

    // Audio level above this counts as speech.
    private let speechThreshold:
        Float = 0.015

    // Ask iOS for microphone permission.
    func requestMicrophonePermission()
        async -> Bool {

        return await
            AVAudioApplication
                .requestRecordPermission()
    }

    // Start the microphone and watch for silence.
    func startListening(
        onAudio:
            @escaping (AVAudioPCMBuffer) -> Void,
        onSilence:
            @escaping @Sendable () -> Void
    ) -> Bool {

        // This app both records and plays audio.
        let session =
            AVAudioSession.sharedInstance()

        do {

            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            
            // Reduce Car Buddy's own voice being picked up by the mic.
            if session.isEchoCancelledInputAvailable {
                try? session.setPrefersEchoCancelledInput(true)
            }
            
            try session.setActive(true)

        } catch {

            print(
                "Could not configure audio session:",
                error
            )

            return false
        }

        let inputNode =
            audioEngine.inputNode

        let recordingFormat =
            inputNode.outputFormat(
                forBus: 0
            )

        guard recordingFormat.sampleRate > 0,
              recordingFormat.channelCount > 0
        else {

            print(
                "No usable microphone input."
            )

            return false
        }

        // Reset silence detection for this turn.
        hasDetectedSpeech = false
        silenceStartTime = nil
        silenceReported = false

        // Remove any old tap.
        inputNode.removeTap(
            onBus: 0
        )

        // Use the microphone's real format.
        // SpeechRecognizer converts it later.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil
        ) { [weak self] buffer, _ in

            // Send audio to SpeechAnalyzer.
            onAudio(buffer)

            // Check for the end of speech.
            self?.checkForSilence(
                in: buffer,
                onSilence: onSilence
            )
        }

        audioEngine.prepare()

        do {

            try audioEngine.start()

            print("Microphone started")

            return true

        } catch {

            print(
                "Could not start microphone:",
                error
            )

            inputNode.removeTap(
                onBus: 0
            )

            return false
        }
    }

    // Detect silence after the user has spoken.
    private func checkForSilence(
        in buffer: AVAudioPCMBuffer,
        onSilence:
            @escaping @Sendable () -> Void
    ) {

        guard let channel =
                buffer.floatChannelData?.pointee
        else {
            return
        }

        let frameCount =
            Int(buffer.frameLength)

        guard frameCount > 0 else {
            return
        }

        var total: Float = 0

        for index in 0..<frameCount {

            let sample =
                channel[index]

            total += sample * sample
        }

        let meanSquare =
            total / Float(frameCount)

        let thresholdSquared =
            speechThreshold *
            speechThreshold

        let isSpeech =
            meanSquare >
            thresholdSquared

        let now =
            ProcessInfo
                .processInfo
                .systemUptime

        if isSpeech {

            // We know the user has spoken.
            hasDetectedSpeech = true

            // Speech means the silence timer is reset.
            silenceStartTime = nil
            silenceReported = false

        } else if hasDetectedSpeech &&
                    !silenceReported {

            if silenceStartTime == nil {
                silenceStartTime = now
            }

            if let silenceStartTime,
               now - silenceStartTime >=
                    silenceDuration {

                silenceReported = true

                // Tell ContentView on the main thread.
                DispatchQueue.main.async {
                    onSilence()
                }
            }
        }
    }

    // Stop the microphone.
    func stopListening() {

        audioEngine.inputNode.removeTap(
            onBus: 0
        )

        audioEngine.stop()

        print("Microphone stopped")

        try? AVAudioSession.sharedInstance()
            .setActive(
                false,
                options:
                    .notifyOthersOnDeactivation
            )
    }
}
