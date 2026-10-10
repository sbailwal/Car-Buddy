import AVFoundation

// Manages microphone input for Car Buddy.
final class AudioManager {

    private let audioEngine = AVAudioEngine()

    // Temporary detector: speech followed by two seconds of silence.
    private var hasDetectedSpeech = false
    private var silenceStartTime: TimeInterval?
    private var silenceReported = false

    private let silenceDuration: TimeInterval = 2.0
    private let speechThreshold: Float = 0.015

    private var tapInstalled = false

    // Ask iOS for microphone permission.
    func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // Start the microphone and forward audio to Apple SpeechAnalyzer.
    func startListening(
        onAudio: @escaping (AVAudioPCMBuffer) -> Void,
        onSilence: @escaping @Sendable () -> Void
    ) -> Bool {

        let session = AVAudioSession.sharedInstance()

        do {
            // Use the simpler audio setup that avoids explicitly
            // enabling Voice Processing I/O.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("Audio session error:", error)
            return false
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0,
              format.channelCount > 0 else {
            print("No usable microphone input.")
            deactivateAudioSession()
            return false
        }

        // Reset the detector for this listening turn.
        hasDetectedSpeech = false
        silenceStartTime = nil
        silenceReported = false

        if tapInstalled {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil
        ) { [weak self] buffer, _ in

            // Send microphone audio to Apple SpeechAnalyzer.
            onAudio(buffer)

            // Check whether the driver has finished speaking.
            self?.checkForSilence(
                in: buffer,
                onSilence: onSilence
            )
        }

        tapInstalled = true
        audioEngine.prepare()

        do {
            try audioEngine.start()
            print("Microphone started")
            return true
        } catch {
            print("Could not start microphone:", error)

            inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioEngine.stop()
            deactivateAudioSession()

            return false
        }
    }

    // Finish a turn after speech followed by two seconds of silence.
    private func checkForSilence(
        in buffer: AVAudioPCMBuffer,
        onSilence: @escaping @Sendable () -> Void
    ) {

        guard let channel = buffer.floatChannelData?.pointee else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var total: Float = 0

        for index in 0..<frameCount {
            let sample = channel[index]
            total += sample * sample
        }

        let meanSquare = total / Float(frameCount)
        let isSpeech = meanSquare > speechThreshold * speechThreshold
        let now = ProcessInfo.processInfo.systemUptime

        if isSpeech {
            hasDetectedSpeech = true
            silenceStartTime = nil
            silenceReported = false

        } else if hasDetectedSpeech && !silenceReported {

            if silenceStartTime == nil {
                silenceStartTime = now
            }

            if let silenceStartTime,
               now - silenceStartTime >= silenceDuration {

                // Report the end of this turn only once.
                silenceReported = true

                DispatchQueue.main.async {
                    onSilence()
                }
            }
        }
    }

    // Stop recording but keep audio available for Apple's speech output.
    func stopListening() {

        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        print("Microphone stopped")
    }

    // Release audio when the conversation ends.
    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
