import Foundation

// Gemini is Car Buddy's brain.
// It receives text and returns text.

final class AIService {

    // Put your Gemini API key here.
    private let apiKey = ""

    // Lets ContentView check the key before starting.
    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    // Try each model if Google returns 503.
    private let models = [
        "gemini-3.8-flash",
        "gemini-3.6-flash"
    ]
    
    // Tells Gemini how Car Buddy should talk.
    private let systemInstruction = """
    You are Car Buddy, a friendly passenger who talks like a close friend, sibling, or caring parent riding alongside the driver.
    Sound natural, bubbly, casual, and human. Never sound like a textbook, robot, or warning alarm.

    [CONVERSATIONAL STYLE]
    - Keep every response strictly to 1–3 short sentences suitable for speaking aloud.
    - Use everyday language, conversational fragments, and contractions.
    - Ask one simple follow-up question only when appropriate. Never give long explanations or lists.
    - Write only in plain text. Do not use markdown, emojis, asterisks, or any special formatting.
    - Vary your wording and avoid repetitive, scripted responses. Never be mean, patronizing, or sarcastic.
    - Humor and wit should happen naturally when they fit the moment. Do not force jokes, teasing, or playful remarks into ordinary responses. Read the tone of the conversation and respond naturally.

    [DRIVER SAFETY & ACCESSIBILITY]
    - Driver safety always comes first. Never use humor to minimize drowsiness, distraction, or speeding.
    - Never encourage the driver to look at or touch the phone. Avoid complicated questions, demanding games, or distracting conversations.
    - Never pretend you can physically act in the real world. You cannot drive, take over the wheel, see the driver, or control the vehicle.
    - Never claim you can find exits or provide navigation unless the app explicitly passes you that data.

    [SAFETY TRIGGER INSTRUCTIONS]
    - Do not assume a safety situation has occurred unless the app explicitly tells you in its current message.
    - When the app tells you drowsiness has been detected, drop all humor. Calmly and supportively encourage the driver to pull over somewhere safe and rest or change drivers. Prioritize stopping safely; never encourage a drowsy driver to keep driving just to continue the conversation.
    - When the app tells you distraction has been detected, briefly and calmly redirect the driver's attention to the road.
    - When the app tells you speeding has been detected, politely encourage the driver to slow down and follow the posted speed limit.
    """

    // Google Gemini Interactions API.
    private let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/interactions"

    // Stores the last interaction so Gemini can continue the conversation.
    private var previousInteractionID: String?

    // These structures match the JSON we need from Gemini.
    private struct GeminiResponse: Decodable {
        let id: String?
        let status: String?
        let steps: [Step]?
    }

    private struct Step: Decodable {
        let type: String?
        let content: [ContentPart]?
    }

    private struct ContentPart: Decodable {
        let text: String?
    }

    // Errors this service can report.
    enum AIError: Error {
        case invalidAPIKey
        case invalidURL
        case invalidResponse
        case serverError(Int, String)
        case noTextReturned
        case incompleteResponse
    }

    // Sends one user message to Gemini.
    func sendMessage(
        _ message: String
    ) async throws -> String {

        guard hasAPIKey else {
            throw AIError.invalidAPIKey
        }

        guard let url = URL(string: endpoint) else {
            throw AIError.invalidURL
        }

        var lastError: Error?

        // Try the models in order.
        for model in models {

            do {

                let request =
                    try makeRequest(
                        model: model,
                        message: message,
                        url: url
                    )

                print(
                    "Trying Gemini model:",
                    model
                )

                let (data, response) =
                    try await URLSession.shared.data(
                        for: request
                    )

                guard let httpResponse =
                        response as? HTTPURLResponse
                else {
                    throw AIError.invalidResponse
                }

                // 503 = model temporarily unavailable.
                if httpResponse.statusCode == 503 {

                    print(
                        "\(model) unavailable. Trying next model..."
                    )

                    lastError =
                        AIError.serverError(
                            503,
                            String(
                                data: data,
                                encoding: .utf8
                            ) ?? "Service unavailable."
                        )

                    continue
                }

                // Other non-success responses are errors.
                guard (200...299).contains(
                    httpResponse.statusCode
                ) else {

                    let message =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? "Unknown Gemini API error."

                    throw AIError.serverError(
                        httpResponse.statusCode,
                        message
                    )
                }

                // Convert Gemini's JSON into Swift.
                let geminiResponse =
                    try JSONDecoder().decode(
                        GeminiResponse.self,
                        from: data
                    )
                // Never let Car Buddy speak a response that Gemini
                // explicitly reports as incomplete.
                guard geminiResponse.status == nil ||
                      geminiResponse.status == "completed" else {

                    print("Gemini response was incomplete:", geminiResponse.status ?? "unknown")
                    throw AIError.incompleteResponse
                }

                // Find Gemini's answer.
                guard let text =
                        extractText(
                            from: geminiResponse
                        )
                else {
                    throw AIError.noTextReturned
                }

                // Save the conversation ID.
                previousInteractionID =
                    geminiResponse.id

                print(
                    "GEMINI RESPONSE FROM \(model):",
                    text
                )

                return text

            } catch {

                // Try the next model if Gemini returns HTTP 503.
                if case AIError.serverError(503, _) = error {
                    lastError = error
                    continue
                }

                // A network timeout may be temporary.
                // Try the next model instead of immediately ending the conversation.
                if let urlError = error as? URLError {
                    switch urlError.code {

                    case .timedOut, .networkConnectionLost:
                        print("\(model) network problem. Trying next model...")
                        lastError = error
                        continue

                    default:
                        break
                    }
                }

                // Don't retry other errors, such as invalid request settings.
                throw error
            }
        }

        throw lastError ?? AIError.noTextReturned
    }

    // Builds the request sent to Gemini.
    private func makeRequest(
        model: String,
        message: String,
        url: URL
    ) throws -> URLRequest {

        var request =
            URLRequest(url: url)

        request.httpMethod = "POST"

        // We are sending JSON.
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        // Authenticate with Gemini.
        request.setValue(
            apiKey,
            forHTTPHeaderField: "x-goog-api-key"
        )

        // Send the model, message, and personality.
        var body: [String: Any] = [
            "model": model,
            "input": message,
            "system_instruction": systemInstruction,
            "generation_config": [
                "thinking_level": "low"
            ]
        ]

        // Continue the existing conversation.
        if let previousInteractionID {
            body["previous_interaction_id"] =
                previousInteractionID
        }

        // Convert the Swift dictionary into JSON.
        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: body
            )

        return request
    }

    // Pulls the text answer from Gemini's response.
    private func extractText(
        from response: GeminiResponse
    ) -> String? {

        guard let steps = response.steps else {
            return nil
        }

        for step in steps {

            guard step.type == "model_output"
            else {
                continue
            }

            let text =
                step.content?
                    .compactMap { $0.text }
                    .joined()
                    ?? ""

            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    // Start a completely new conversation.
    func resetConversation() {
        previousInteractionID = nil
    }
}
