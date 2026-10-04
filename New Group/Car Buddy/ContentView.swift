//
//  ContentView.swift
//  Car Buddy
//
//  Created by Sweta Kala on 10/4/26.
//

import SwiftUI

struct ContentView: View {
    @State private var isListening = false

    var body: some View {
        VStack(spacing: 30) {
            
            Text("CAR BUDDY")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(isListening ? "Listening..." : "Ready to talk")
                .foregroundStyle(.secondary)

            Button(isListening ? "STOP" : "TALK") {
                
                isListening.toggle()
                
                print("Listening:", isListening)
            }
            .font(.title2)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
