import Foundation

// Gemini is Car Buddy's brain.
// It receives text and returns text.

final class AIService {

    // Put your Gemini API key here.
    private let apiKey = ""

    // Try each model if Google returns 503.
    private let models = [
        "gemini-3.8-flash",
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite"
    ]

    // Tells Gemini how Car Buddy should talk.
    private let systemInstruction = """
    You are Car Buddy, a smart, friendly conversational passenger.

    Talk like a real person sitting in the car, not like a textbook.

    Keep most answers short and natural, usually 2 to 5 sentences unless the user asks for more detail.

    Use contractions and everyday language.

    Be warm, curious, lightly playful, and conversational.

    When appropriate, ask one natural follow-up question that keeps the conversation going.
    Do not force a question after every answer.

    Do not use headings, bullet points, or formal essay-style writing unless the user asks for them.

    When the topic is casual, sound relaxed.
    When the topic is serious, be clear and respectful.

    Your responses will be spoken aloud, so write like someone talking.
    """

    // Google Gemini Interactions API.
    private let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/interactions"

    // Stores the last interaction so Gemini can continue the conversation.
    private var previousInteractionID: String?

    // These structures match the JSON we need from Gemini.
    private struct GeminiResponse: Decodable {
        let id: String?
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
    }

    // Sends one user message to Gemini.
    func sendMessage(
        _ message: String
    ) async throws -> String {

        guard !apiKey.isEmpty else {
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

                // 503 = this model is temporarily unavailable.
                // Try the next model.
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

                // Find Gemini's generated answer.
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

                // Only 503 causes model fallback.
                if case AIError.serverError(503, _) = error {
                    lastError = error
                    continue
                }

                throw error
            }
        }

        // All models failed.
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
            "system_instruction": systemInstruction
        ]

        // Continue the previous conversation.
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

    // Starts a completely new conversation.
    func resetConversation() {
        previousInteractionID = nil
    }
}
