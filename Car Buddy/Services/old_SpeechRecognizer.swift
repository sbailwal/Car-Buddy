//import Speech
//import AVFoundation
//
//// ============================================================
//// SpeechRecognizer
//// ============================================================
////
//// This class is responsible for taking spoken language
//// and turning it into written text.
////
//// Think of the Car Buddy audio system as two separate jobs:
////
//// 1. AudioManager
////    ----------------
////    Gets sound from the iPhone microphone.
////
//// 2. SpeechRecognizer
////    ------------------
////    Takes that microphone audio and asks Apple's
////    Speech framework to figure out what words were spoken.
////
//// So the overall flow will eventually be:
////
////      YOU SPEAK
////         ↓
////      Microphone
////         ↓
////      AudioManager
////         ↓
////      Audio Buffer
////         ↓
////      SpeechRecognizer
////         ↓
////      Apple's Speech Recognition
////         ↓
////      TEXT
////
//// Example:
////
//// You say:
////     "What is a black hole?"
////
//// SpeechRecognizer eventually gives us:
////
////     "What is a black hole?"
////
//// Later, that text will be sent to our AI.
//// ============================================================
//
//final class SpeechRecognizer {
//
//    // ========================================================
//    // MARK: - Speech Recognizer
//    // ========================================================
//
//    // SFSpeechRecognizer is Apple's object for speech
//    // recognition.
//    //
//    // "SFSpeechRecognizer" comes from Apple's Speech framework.
//    //
//    // We ask Apple to create a recognizer for:
//    //
//    //     English - United States
//    //
//    // "Locale" means the language/region being used.
//    //
//    // "en-US" means:
//    //
//    //     en = English
//    //     US = United States
//    //
//    // IMPORTANT:
//    //
//    // SFSpeechRecognizer(...) returns an OPTIONAL value.
//    //
//    // Optional means:
//    //
//    //     "There may be an object here..."
//    //
//    // or
//    //
//    //     "There may NOT be an object here."
//    //
//    // Swift represents that possibility with:
//    //
//    //     ?
//    //
//    // So Swift sees this property as:
//    //
//    //     SFSpeechRecognizer?
//    //
//    // Later, we safely "unwrap" this optional before
//    // trying to use the recognizer.
//    private let speechRecognizer =
//        SFSpeechRecognizer(
//            locale: Locale(identifier: "en-US")
//        )
//
//
//    // ========================================================
//    // MARK: - Recognition Request
//    // ========================================================
//
//    // SFSpeechAudioBufferRecognitionRequest is an Apple object
//    // that receives chunks of audio from the microphone.
//    //
//    // Think of it like a bucket that we keep putting
//    // small pieces of microphone audio into.
//    //
//    // Example:
//    //
//    // Microphone audio
//    //      ↓
//    // [small audio chunk]
//    //      ↓
//    // recognitionRequest
//    //      ↓
//    // [another audio chunk]
//    //      ↓
//    // recognitionRequest
//    //      ↓
//    // and so on...
//    //
//    // Apple then analyzes those audio chunks to determine
//    // what words were spoken.
//    //
//    // The "?" means this property is optional.
//    //
//    // Why?
//    //
//    // Because we don't have a recognition request
//    // until we actually start a recognition session.
//    private var recognitionRequest:
//        SFSpeechAudioBufferRecognitionRequest?
//
//
//    // ========================================================
//    // MARK: - Recognition Task
//    // ========================================================
//
//    // A "task" represents work that is currently happening.
//    //
//    // In our case, this task represents the speech-recognition
//    // process that is currently running.
//    //
//    // While this task is active, Apple is processing
//    // the microphone audio and producing recognized text.
//    //
//    // Again, this is optional because there may or may not
//    // currently be a recognition task running.
//    private var recognitionTask:
//        SFSpeechRecognitionTask?
//
//
//    // ========================================================
//    // MARK: - Request Speech Permission
//    // ========================================================
//
//    // Before an iPhone app can use Apple's speech-recognition
//    // system, iOS asks the user for permission.
//    //
//    // Example:
//    //
//    // "Car Buddy uses speech recognition so you can talk
//    //  to the assistant."
//    //
//    // The user can tap:
//    //
//    //     Allow
//    //
//    // or
//    //
//    //     Don't Allow
//    //
//    // This function asks iOS for that permission.
//    //
//    // It returns a Bool:
//    //
//    //     true  = permission was granted
//    //     false = permission was denied
//    //
//    // "async" means:
//    //
//    //     This function may have to wait for something
//    //     to finish before it can give us the answer.
//    func requestPermission() async -> Bool {
//
//        // ----------------------------------------------------
//        // Apple's permission API uses a completion handler.
//        // ----------------------------------------------------
//        //
//        // A completion handler is simply a function that
//        // Apple calls later when the permission decision
//        // has been completed.
//        //
//        // Older Apple APIs often work this way:
//        //
//        //     "Start something now,
//        //      and I'll call your function later."
//        //
//        // Swift's modern style uses async/await instead.
//        //
//        // withCheckedContinuation allows us to bridge
//        // Apple's completion-handler API into modern
//        // Swift async/await code.
//        await withCheckedContinuation { continuation in
//
//            // Ask iOS for speech-recognition permission.
//            SFSpeechRecognizer.requestAuthorization { status in
//
//                // "status" tells us what the user decided.
//                //
//                // Apple gives us several possible statuses.
//                //
//                // The one we care about is:
//                //
//                //     .authorized
//                //
//                // which means:
//                //
//                //     "The user allowed speech recognition."
//                //
//                // We compare the status to .authorized.
//                //
//                // If they match:
//                //     true
//                //
//                // Otherwise:
//                //     false
//                continuation.resume(
//                    returning: status == .authorized
//                )
//            }
//        }
//    }
//
//
//    // ========================================================
//    // MARK: - Start Recognition
//    // ========================================================
//
//    // This function starts Apple's speech-recognition process.
//    //
//    // We will eventually call this when the user presses
//    // the TALK button.
//    //
//    // "onResult" is a function that we pass INTO this function.
//    //
//    // This is called a "closure" in Swift.
//    //
//    // In simple terms:
//    //
//    // We are telling SpeechRecognizer:
//    //
//    //     "When you get some recognized text,
//    //      call this function and give me the text."
//    //
//    // For example:
//    //
//    // Apple recognizes:
//    //
//    //     "What is a black hole?"
//    //
//    // Then SpeechRecognizer calls:
//    //
//    //     onResult("What is a black hole?", true)
//    //
//    // The second value tells us whether Apple considers
//    // that result final.
//    //
//    // The return value is:
//    //
//    //     true  = recognition started successfully
//    //     false = recognition could not start
//    func startRecognition(
//        onResult: @escaping (String, Bool) -> Void
//    ) -> Bool {
//
//        // ====================================================
//        // STEP 1: Safely get the speech recognizer
//        // ====================================================
//
//        // Remember:
//        //
//        // Our property is:
//        //
//        //     SFSpeechRecognizer?
//        //
//        // That means the recognizer might not exist.
//        //
//        // We cannot safely do:
//        //
//        //     speechRecognizer.isAvailable
//        //
//        // because Swift would complain:
//        //
//        //     "Value of optional type 'SFSpeechRecognizer?'
//        //      must be unwrapped..."
//        //
//        // "guard let" safely unwraps the optional.
//        //
//        // In plain English:
//        //
//        //     "If the speech recognizer exists,
//        //      give me the real object.
//        //
//        //      If it doesn't exist,
//        //      stop this function."
//        guard let speechRecognizer = speechRecognizer,
//              speechRecognizer.isAvailable else {
//
//            // This message appears in Xcode's console
//            // if speech recognition cannot currently be used.
//            print("Speech recognition is not available.")
//
//            // Tell the caller that recognition did not start.
//            return false
//        }
//
//
//        // ====================================================
//        // STEP 2: Stop an old recognition task
//        // ====================================================
//
//        // It is possible that an earlier recognition session
//        // is still running.
//        //
//        // We do NOT want two recognition sessions running
//        // at the same time.
//        //
//        // So we cancel the previous task first.
//        recognitionTask?.cancel()
//
//        // Set the property to nil.
//        //
//        // nil means:
//        //
//        //     "There is currently no object here."
//        recognitionTask = nil
//
//
//        // ====================================================
//        // STEP 3: Create a new audio recognition request
//        // ====================================================
//
//        // Create a fresh recognition request.
//        //
//        // This is the "bucket" that will receive
//        // microphone audio.
//        let request =
//            SFSpeechAudioBufferRecognitionRequest()
//
//
//        // ====================================================
//        // STEP 4: Ask Apple for partial results
//        // ====================================================
//
//        // "shouldReportPartialResults = true" means:
//        //
//        //     "Give us recognized text before the user
//        //      has completely finished speaking."
//        //
//        // This is useful because we eventually want
//        // Car Buddy to feel responsive.
//        //
//        // Example:
//        //
//        // The user is still speaking:
//        //
//        //     "What is the weather going to..."
//        //
//        // Apple may temporarily give us:
//        //
//        //     "What is the weather going to"
//        //
//        // Then later:
//        //
//        //     "What is the weather going to be tomorrow?"
//        //
//        // The final result will come later.
//        request.shouldReportPartialResults = true
//
//
//        // ====================================================
//        // STEP 5: Save the request
//        // ====================================================
//
//        // We store the request in our property.
//        //
//        // Why?
//        //
//        // Because another function will need to access
//        // this request later to add microphone audio to it.
//        //
//        // That other function will be:
//        //
//        //     appendAudioBuffer(...)
//        //
//        recognitionRequest = request
//
//
//        // ====================================================
//        // STEP 6: Start Apple's recognition task
//        // ====================================================
//
//        // This starts the actual speech-recognition process.
//        //
//        // Apple will process the audio we add to the request.
//        //
//        // The closure after "with:" is called the
//        // "result handler".
//        //
//        // Apple calls it whenever a recognition result
//        // becomes available.
//        recognitionTask =
//            speechRecognizer.recognitionTask(
//                with: request
//            ) { result, error in
//
//                // =================================================
//                // STEP 7: Check whether Apple gave us a result
//                // =================================================
//
//                // "result" contains Apple's speech-recognition
//                // result.
//                //
//                // It is optional because Apple might instead
//                // report an error.
//                //
//                // "if let" safely unwraps the optional.
//                if let result = result {
//
//                    // -------------------------------------------------
//                    // Get the best text Apple has recognized so far.
//                    // -------------------------------------------------
//                    //
//                    // "bestTranscription" represents Apple's
//                    // best interpretation of the spoken audio.
//                    //
//                    // "formattedString" converts that transcription
//                    // into an ordinary Swift String.
//                    //
//                    // String is simply text.
//                    //
//                    // Example:
//                    //
//                    //     "What is a black hole?"
//                    let text =
//                        result.bestTranscription.formattedString
//
//
//                    // -------------------------------------------------
//                    // Send the recognized text back to the caller.
//                    // -------------------------------------------------
//                    //
//                    // Remember the function we received earlier:
//                    //
//                    //     onResult
//                    //
//                    // We now call it.
//                    //
//                    // First value:
//                    //     recognized text
//                    //
//                    // Second value:
//                    //     whether this is the final result
//                    onResult(
//                        text,
//                        result.isFinal
//                    )
//
//
//                    // Print the recognized text in Xcode's console.
//                    //
//                    // This is VERY useful while developing because
//                    // we can see exactly what Apple thinks we said.
//                    print("Recognized speech:", text)
//
//
//                    // -------------------------------------------------
//                    // Check whether this is the final result.
//                    // -------------------------------------------------
//                    //
//                    // result.isFinal is:
//                    //
//                    //     true  = Apple considers this final
//                    //     false = Apple is still producing results
//                    //
//                    // Eventually, we will use the final text
//                    // to send the user's question to the AI.
//                    if result.isFinal {
//
//                        print(
//                            "Final speech result:",
//                            text
//                        )
//                    }
//                }
//
//
//                // =================================================
//                // STEP 8: Check for an error
//                // =================================================
//
//                // "error" is optional because speech recognition
//                // might succeed without an error.
//                //
//                // If there IS an error, we want to print it.
//                if let error = error {
//
//                    // Print the error so we can diagnose
//                    // problems during development.
//                    print(
//                        "Speech recognition error:",
//                        error
//                    )
//                }
//            }
//
//
//        // ====================================================
//        // STEP 9: Report that recognition started
//        // ====================================================
//
//        // We reached this point without failing.
//        //
//        // Therefore, our recognition task was successfully
//        // created.
//        print("Speech recognition started")
//
//
//        // Tell the caller that startup succeeded.
//        return true
//    }
//
//
//    // ========================================================
//    // MARK: - Send Microphone Audio to Speech Recognition
//    // ========================================================
//
//    // This function takes one small piece of microphone audio
//    // and sends it to Apple's speech-recognition request.
//    //
//    // "AVAudioPCMBuffer" is Apple's object representing
//    // a chunk of audio data.
//    //
//    // Think of it like:
//    //
//    //     microphone sound
//    //           ↓
//    //     small audio chunk
//    //           ↓
//    //     AVAudioPCMBuffer
//    //
//    // Eventually AudioManager will call this function
//    // over and over as microphone audio arrives.
//    func appendAudioBuffer(
//        _ buffer: AVAudioPCMBuffer
//    ) {
//
//        // Add the microphone audio chunk to the
//        // speech-recognition request.
//        //
//        // The ? here means:
//        //
//        //     "Only do this if recognitionRequest exists."
//        //
//        // If there is no active request, nothing happens.
//        recognitionRequest?.append(buffer)
//    }
//
//
//    // ========================================================
//    // MARK: - Stop Recognition
//    // ========================================================
//
//    // This function stops the current speech-recognition session.
//    //
//    // We will use this when the user stops talking
//    // or presses the STOP button.
//    func stopRecognition() {
//
//        // ----------------------------------------------------
//        // Tell Apple we are finished sending audio.
//        // ----------------------------------------------------
//        //
//        // "endAudio()" means:
//        //
//        //     "No more microphone audio is coming."
//        //
//        // Apple can then finish processing whatever audio
//        // is still waiting.
//        recognitionRequest?.endAudio()
//
//
//        // ----------------------------------------------------
//        // Finish the recognition task.
//        // ----------------------------------------------------
//        //
//        // This tells the current recognition task to finish.
//        recognitionTask?.finish()
//
//
//        // ----------------------------------------------------
//        // Remove references to the old session.
//        // ----------------------------------------------------
//        //
//        // nil means:
//        //
//        //     "There is no active request/task anymore."
//        recognitionRequest = nil
//        recognitionTask = nil
//
//
//        // Print a helpful message in Xcode's console.
//        print("Speech recognition stopped")
//    }
//}
