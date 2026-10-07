import AVFoundation

// Handles Car Buddy's spoken voice.
//
// First tries Gemini's natural voice.
// If Gemini TTS fails, Apple speech is used automatically.

@MainActor
final class SpeechSynthesizer {

    // Apple's built-in text-to-speech system.
    private let synthesizer =
        AVSpeechSynthesizer()

    // Holds Gemini's generated WAV audio while it plays.
    private var audioPlayer:
        AVAudioPlayer?

    enum SpeechResult {
        case natural
        case fallback(String)
    }

    // Try natural Gemini speech first.
    //
    // If that fails, immediately use Apple's voice
    // so Car Buddy can still talk.
    func speak(
        _ text: String,
        using aiService: AIService
    ) async -> SpeechResult {

        // Stop anything that may already be playing.
        stopSpeaking()

        do {

            // Ask Gemini for natural speech audio.
            let audioData =
                try await aiService.generateSpeech(
                    text
                )

            // Tell iPhone that we are going to play audio.
            try AVAudioSession.sharedInstance()
                .setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: []
                )

            try AVAudioSession.sharedInstance()
                .setActive(true)

            // Create an audio player from Gemini's WAV data.
            let player =
                try AVAudioPlayer(
                    data: audioData
                )

            audioPlayer = player

            player.prepareToPlay()
            player.play()

            print("Playing natural Gemini voice")

            return .natural

        } catch let error as AIService.AIError {

            print(
                "Gemini TTS error:",
                error
            )

            // Give the user a useful explanation.
            switch error {

            case .serverError(429, _):

                speakWithAppleVoice(text)

                return .fallback(
                    "Natural voice quota reached — using iPhone voice."
                )

            case .serverError(503, _):

                speakWithAppleVoice(text)

                return .fallback(
                    "Natural voice service is busy — using iPhone voice."
                )

            default:

                speakWithAppleVoice(text)

                return .fallback(
                    "Natural voice unavailable — using iPhone voice."
                )
            }

        } catch {

            // Network timeout, no internet, audio decoding error, etc.
            print(
                "Gemini TTS unavailable:",
                error
            )

            speakWithAppleVoice(text)

            return .fallback(
                "Natural voice unavailable — using iPhone voice."
            )
        }
    }

    // Apple's reliable fallback voice.
    private func speakWithAppleVoice(
        _ text: String
    ) {

        let utterance =
            AVSpeechUtterance(
                string: text
            )

        utterance.voice =
            AVSpeechSynthesisVoice(
                language: "en-US"
            )

        utterance.rate = 0.5

        synthesizer.speak(
            utterance
        )
    }

    // Stops both Gemini audio and Apple's voice.
    func stopSpeaking() {

        audioPlayer?.stop()
        audioPlayer = nil

        synthesizer.stopSpeaking(
            at: .immediate
        )
    }
}
