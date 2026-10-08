import AVFoundation

// Apple's built-in text-to-speech.
// Gemini is not used for voice.

@MainActor
final class SpeechSynthesizer {

    // Apple's speech engine.
    private let synthesizer =
        AVSpeechSynthesizer()

    // Speak the AI response.
    func speak(_ text: String) {

        let utterance =
            AVSpeechUtterance(
                string: text
            )

        // Use Apple's US English voice.
        utterance.voice =
            AVSpeechSynthesisVoice(
                language: "en-US"
            )
        
        // Speaking speed.
        utterance.rate = 0.5

        synthesizer.speak(
            utterance
        )
    }

    // Wait until Apple finishes speaking.
    func waitUntilFinished() async {

        while synthesizer.isSpeaking {

            try? await Task.sleep(
                nanoseconds:
                    100_000_000
            )
        }
    }

    // Stop speaking immediately.
    func stopSpeaking() {

        synthesizer.stopSpeaking(
            at: .immediate
        )
    }
}
