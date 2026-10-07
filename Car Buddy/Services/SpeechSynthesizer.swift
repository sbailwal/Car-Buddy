import AVFoundation

// Converts text into speech on the iPhone.

@MainActor
final class SpeechSynthesizer {

    // Apple's built-in text-to-speech system.
    private let synthesizer = AVSpeechSynthesizer()


    // Speaks the text we give it.
    func speak(_ text: String) {

        // Create a speech request from the text.
        let utterance = AVSpeechUtterance(
            string: text
        )

        // Use a US English voice.
        utterance.voice =
            AVSpeechSynthesisVoice(
                language: "en-US"
            )

        // Set the speaking speed.
        utterance.rate = 0.5

        // Tell the iPhone to speak.
        synthesizer.speak(utterance)
    }


    // Stops speaking immediately.

    func stopSpeaking() {

        synthesizer.stopSpeaking(
            at: .immediate
        )
    }
}
