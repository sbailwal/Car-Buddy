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

        // Use the best installed US English voice.
        utterance.voice =
            bestEnglishVoice()

        // Speaking speed.
        utterance.rate = 0.5

        synthesizer.speak(
            utterance
        )
    }

    // Pick Premium first, then Enhanced, then Default.
    private func bestEnglishVoice()
        -> AVSpeechSynthesisVoice? {

        let voices =
            AVSpeechSynthesisVoice
                .speechVoices()
                .filter {
                    $0.language == "en-US"
                }

        // Use Premium when installed.
        if let premium =
            voices.first(where: {
                $0.quality == .premium
            }) {
            return premium
        }

        // Otherwise use Enhanced.
        if let enhanced =
            voices.first(where: {
                $0.quality == .enhanced
            }) {
            return enhanced
        }

        // Otherwise use the normal English voice.
        return voices.first
    }

    // Stop speaking immediately.
    func stopSpeaking() {

        synthesizer.stopSpeaking(
            at: .immediate
        )
    }
}
