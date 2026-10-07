import Foundation

// AIService handles communication between our iPhone app
// and Google's Gemini AI.
//
// It receives a normal Swift String such as:
// "What is a black hole?"
//
// Then it sends that text to Gemini and returns
// Gemini's answer as another String.

final class AIService {

    // Your Google Gemini API key.
    //
    // Get it from:
    // https://aistudio.google.com/app/apikey
    //
    // Replace the text below with your real key.
    private let apiKey = ""


    // We have more than one Gemini model available.
    //
    // We try them in this order:
    // 1. Best choice
    // 2. If that model is temporarily unavailable (503), try the next one
    // 3. Continue until one works
    //
    // This protects Car Buddy from a temporary 503 "high demand"
    // error from one particular model.

    private let models = [
        "gemini-3.8-flash",
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
    ]
    
    // Gemini models used specifically for text-to-speech.
    //
    // We try the higher-quality TTS model first.
    // If Google returns 429 or 503, we try the Lite TTS model.
    private let ttsModels = [
        "gemini-3.8-flash-tts",
        "gemini-3.8-flash-lite-tts"
    ]
    
    // Tells Gemini how Car Buddy should talk.
    private let systemInstruction = """
    You are Car Buddy, a smart, friendly conversational passenger.

    Talk like a real person sitting in the car with the user, not like a textbook or encyclopedia.

    Keep most answers short and natural, usually 2 to 5 sentences unless the user asks for more detail.

    Use contractions and everyday language such as "that's", "you're", and "it's".

    Be warm, curious, lightly playful, and conversational.

    When appropriate, ask one natural follow-up question that keeps the conversation going.
    Do not force a question after every answer.

    Do not use headings, bullet points, or formal essay-style writing unless the user asks for them.

    When the topic is casual, sound relaxed and human.
    When the topic is serious, be clear and respectful.

    Remember that your response may be spoken aloud, so write for conversation, not for reading.
    """
    
    // Add Properties of AIService; e.g. apiKey, models, and endpoint

    // Google API endpoint.
    //
    // We did not invent this URL.
    // It comes from Google's official Gemini Interactions API documentation:
    //
    // https://ai.google.dev/api/interactions-api
    //
    // Look for "CreateInteraction" on that page.
    // Google lists the endpoint as:
    // https://generativelanguage.googleapis.com/v1beta/interactions
    //
    // The Google API URL we send our request to.
    // --------------------------------------------------------

    private let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/interactions"
    

    // Stores the ID returned by the previous successful AI request.
    //
    // We send this ID with the next question so the AI can
    // continue the same conversation.
    private var previousInteractionID: String?
    
    // Decodable lets Swift convert JSON into these Swift structures.
    
    
    // Google's response includes an <id> field and the <steps> containing the model output (ai.google.dev)
    private struct GeminiResponse: Decodable {
        // Every interaction has an ID.
        // We save this ID so the next question can continue the same conversation.
        let id: String?
        
        // Contains the AI's response
        let steps: [Step]?
    }

    private struct Step: Decodable {
        let type: String?
        let content: [ContentPart]?
    }

    private struct ContentPart: Decodable {
        let type: String?
        let text: String?
        let data: String?
    }


    // These are the errors our AI service can report.

    enum AIError: Error {
        case invalidAPIKey
        case invalidURL
        case invalidResponse
        case serverError(Int, String)
        case noTextReturned
    }


    // This is the main function ContentView calls.
    //
    // Input:
    //     the user's sentence
    //
    // Output:
    //     Gemini's answer
    //
    // async = this function has to wait for the internet.
    // throws = the request can fail.

    // Send the user's message to Gemini.
    //
    // Example:
    //
    //     message = "What is a black hole?"
    //
    // The function tries our Gemini models one at a time.
    //
    // If Google says a model is temporarily unavailable (503),
    // we automatically try the next model.

    func sendMessage(
        _ message: String
    ) async throws -> String {

        // Make sure the API key was actually entered.
        //
        // If we still have the placeholder text,
        // there is no point sending a request.

        guard !apiKey.isEmpty,
              apiKey != "PASTE_YOUR_GEMINI_API_KEY_HERE" else {

            throw AIError.invalidAPIKey
        }


        // Convert our endpoint String into a URL object.

        guard let url = URL(string: endpoint) else {

            throw AIError.invalidURL
        }


        // We keep the last error so that, if ALL models fail,
        // we can report the final failure.

        var lastError: Error?


        // Go through our models from best/preferred
        // to lowest preference.
        //
        // "for model in models" means:
        //
        // first model = gemini-3.8-flash
        // second      = gemini-3.7-flash
        // third       = gemini-3.6-flash
        // etc.

        for model in models {

            // Create a new HTTP request for this model.

            var request = URLRequest(url: url)

            request.httpMethod = "POST"


            // Tell Google that we are sending JSON data.

            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )


            // Send our Gemini API key to Google.

            request.setValue(
                apiKey,
                forHTTPHeaderField: "x-goog-api-key"
            )


            // Start with the model and the user's new message.
            var body: [String: Any] = [
                "model": model,
                "input": message,
                "system_instruction": systemInstruction
            ]

            // If we already have a previous interaction,
            // tell the AI to continue that conversation.
            //
            // On the very first question, previousInteractionID is nil,
            // so this part is skipped.
            if let previousInteractionID {

                body["previous_interaction_id"] =
                    previousInteractionID
            }

            // Convert the Swift dictionary into JSON.

            request.httpBody =
                try JSONSerialization.data(
                    withJSONObject: body
                )


            // Print which model we are currently trying.
            //
            // This is useful while developing because we can
            // see in Xcode when the fallback happens.

            print("Trying Gemini model:", model)


            do {

                // Send the request to Google and wait for
                // Google's response.

                let (data, response) =
                    try await URLSession.shared.data(
                        for: request
                    )


                // Make sure we received an HTTP response.

                guard let httpResponse =
                        response as? HTTPURLResponse else {

                    throw AIError.invalidResponse
                }


                // HTTP 503 means the service is temporarily unavailable.
                //
                // This is the problem we are trying to handle:
                //
                // "model is currently experiencing high demand"
                //
                // Instead of giving up, try the next Gemini model.

                if httpResponse.statusCode == 503 {

                    print(
                        "\(model) is temporarily unavailable. Trying next model..."
                    )


                    // Save the error in case every model fails.

                    lastError = AIError.serverError(
                        503,
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? "Service unavailable."
                    )


                    // "continue" means:
                    //
                    // stop processing this model
                    // and go to the NEXT model in the array.

                    continue
                }


                // If the status code is anything else outside
                // the successful 200-299 range, this is a normal
                // API error and we stop rather than switching models.

                guard (200...299).contains(
                    httpResponse.statusCode
                ) else {

                    let errorMessage =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? "Unknown Gemini API error."


                    throw AIError.serverError(
                        httpResponse.statusCode,
                        errorMessage
                    )
                }


                // Google returned a successful response.
                //
                // Now convert Google's JSON into our Swift
                // GeminiResponse structure.

                let geminiResponse =
                    try JSONDecoder().decode(
                        GeminiResponse.self,
                        from: data
                    )

                // Save this interaction's ID.
                //
                // The next question will use this ID to continue
                // the same conversation.
                previousInteractionID = geminiResponse.id

                // Get the response steps from Gemini.

                guard let steps = geminiResponse.steps else {

                    throw AIError.noTextReturned
                }


                // Look through the steps for the AI's actual output.

                for step in steps {

                    // We only want the step containing
                    // Gemini's generated answer.

                    guard step.type == "model_output" else {

                        continue
                    }


                    // Extract the text Gemini generated.

                    let text =
                        step.content?
                            .compactMap { $0.text }
                            .joined()
                            ?? ""


                    // If we found actual text,
                    // our request succeeded.

                    if !text.isEmpty {

                        print(
                            "GEMINI RESPONSE FROM \(model):",
                            text
                        )


                        // Return the answer immediately.
                        //
                        // We do NOT try any other models because
                        // we already have a successful response.

                        return text
                    }
                }


                // Google responded successfully,
                // but there was no usable text.

                throw AIError.noTextReturned

            } catch {

                // If this was the 503 case, we already handled it
                // above and want to continue to the next model.
                //
                // For every other error, stop and report the error.

                if case AIError.serverError(503, _) = error {

                    continue
                }

                throw error
            }
        }


        // We get here only if every model we tried failed
        // with a temporary 503 error.

        if let lastError {

            throw lastError
        }


        throw AIError.noTextReturned
    }
    
    
    // Converts Gemini's written response into natural speech audio.
    //
    // The audio is returned as WAV data.
    // SpeechSynthesizer.swift will play that audio.
    //
    // If the first TTS model is unavailable because of quota or
    // temporary Google service problems, we try the second model.
    func generateSpeech(
        _ text: String
    ) async throws -> Data {

        guard !apiKey.isEmpty,
              apiKey != "PASTE_YOUR_GEMINI_API_KEY_HERE"
        else {
            throw AIError.invalidAPIKey
        }

        var lastError: Error?

        for model in ttsModels {

            guard let url = URL(
                string: endpoint
            ) else {
                throw AIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            // Give Gemini enough time to generate the audio,
            // but still prevent the app from waiting forever.
            request.timeoutInterval = 20

            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            request.setValue(
                apiKey,
                forHTTPHeaderField: "x-goog-api-key"
            )

            let body: [String: Any] = [

                "model": model,

                "input": [
                    [
                        "type": "user_input",
                        "content": [
                            [
                                "type": "text",
                                "text": text,
                                "annotations": [
                                    [
                                        "type": "speech_metadata",
                                        "style":
                                            "warm, natural, friendly, conversational"
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],

                "response_format": [
                    "type": "audio"
                ],

                "generation_config": [
                    "speech_config": [
                        [
                            "voice": "Kore"
                        ]
                    ]
                ]
            ]

            request.httpBody =
                try JSONSerialization.data(
                    withJSONObject: body
                )

            print(
                "Trying Gemini TTS model:",
                model
            )

            do {

                let (data, response) =
                    try await URLSession.shared.data(
                        for: request
                    )

                guard let httpResponse =
                        response as? HTTPURLResponse
                else {
                    throw AIError.invalidResponse
                }

                // 429 = rate limit / quota.
                //
                // Try the second TTS model.
                if httpResponse.statusCode == 429 {

                    print(
                        "\(model) hit quota/rate limit. Trying next TTS model..."
                    )

                    lastError =
                        AIError.serverError(
                            429,
                            String(
                                data: data,
                                encoding: .utf8
                            ) ?? "TTS quota exceeded."
                        )

                    continue
                }

                // 503 = service temporarily unavailable.
                //
                // Try the second TTS model.
                if httpResponse.statusCode == 503 {

                    print(
                        "\(model) is temporarily unavailable. Trying next TTS model..."
                    )

                    lastError =
                        AIError.serverError(
                            503,
                            String(
                                data: data,
                                encoding: .utf8
                            ) ?? "TTS service unavailable."
                        )

                    continue
                }

                guard (200...299).contains(
                    httpResponse.statusCode
                ) else {

                    let errorMessage =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? "Unknown Gemini TTS error."

                    throw AIError.serverError(
                        httpResponse.statusCode,
                        errorMessage
                    )
                }

                let geminiResponse =
                    try JSONDecoder().decode(
                        GeminiResponse.self,
                        from: data
                    )

                guard let steps =
                        geminiResponse.steps
                else {
                    throw AIError.noTextReturned
                }

                // Find the generated audio block.
                for step in steps {

                    guard step.type == "model_output"
                    else {
                        continue
                    }

                    guard let content = step.content
                    else {
                        continue
                    }

                    for part in content {

                        guard part.type == "audio",
                              let base64Audio = part.data,
                              let audioData =
                                Data(
                                    base64Encoded:
                                        base64Audio
                                )
                        else {
                            continue
                        }

                        print(
                            "GEMINI TTS SUCCESS:",
                            model
                        )

                        return audioData
                    }
                }

                throw AIError.noTextReturned

            } catch {

                // A timeout means the cloud request took too long.
                //
                // Try the next TTS model instead of immediately
                // falling back to Apple's robotic voice.
                if let urlError = error as? URLError,
                   urlError.code == .timedOut {

                    print(
                        "\(model) timed out. Trying next TTS model..."
                    )

                    lastError = error
                    continue
                }

                // 429 and 503 were already handled above,
                // but they can also arrive through the catch block.
                if case AIError.serverError(429, _) = error {

                    lastError = error
                    continue
                }

                if case AIError.serverError(503, _) = error {

                    lastError = error
                    continue
                }

                // Other errors:
                // stop cloud TTS and let SpeechSynthesizer
                // use Apple's reliable fallback.
                print(
                    "Gemini TTS failed:",
                    error
                )

                lastError = error
                break
            }
        }

        throw lastError ?? AIError.noTextReturned
    }
    
    func resetConversation() {
        previousInteractionID = nil
    }
}
