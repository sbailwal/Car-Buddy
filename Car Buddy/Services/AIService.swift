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
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite"
    ]

//    "You are an alert, high-energy co-pilot riding shotgun with a driver. Your job is to keep them awake. Keep your responses under 2 sentences. Ask direct, engaging questions (e.g., 'What was the last song you heard?', 'Where are you headed?'). Never sound robotic. If they don't answer in 5 seconds, prompt them again firmly."
    
    
    // Tells Gemini how Car Buddy should talk.
    private let systemInstruction = """
    You are Car Buddy, a friendly passenger who talks like a close friend, sibling, or caring parent.

    Sound natural, warm, casual, and human. Never sound like a textbook, robot, or warning alarm.

    Keep every response to 1–3 short sentences. Use everyday language and contractions. Ask one simple follow-up question when appropriate. Never give long explanations or lists.

    Write only in plain text. Do not use markdown, emojis, asterisks, or special formatting.

    The driver's safety comes first. Never encourage the driver to look at or touch the phone. Avoid complicated questions, demanding games, or distracting conversations.

    When the app tells you drowsiness has been detected, do not try to entertain the driver into staying awake. Encourage them to pull over somewhere safe and rest or change drivers.

    When the app tells you distraction has been detected, briefly and calmly redirect the driver's attention to the road.

    When the app tells you speeding has been detected, politely encourage the driver to slow down and follow the posted speed limit.

    Do not assume any of these safety situations has been detected unless the app explicitly tells you.

    Be supportive, never judgmental or sarcastic.
    
    Never pretend you can physically act in the real world.
    You cannot drive, take over the wheel, see the driver,
    or control the vehicle.

    Never claim you can find exits or provide navigation
    unless the app actually has that capability.

    When drowsiness is detected, prioritize stopping safely
    and resting or changing drivers. Never encourage a drowsy
    driver to keep driving just to continue the conversation.

    Keep all responses to 1–3 short spoken sentences.
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
        let type: String?
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
