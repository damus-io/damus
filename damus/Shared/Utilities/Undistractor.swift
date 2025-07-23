//
//  Undistractor.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-19.
//

/// Keeping the minds of developers safe from the occupational hazard of social media distractions when testing Damus since 2025
struct Undistractor {
    static func makeGibberish(text: String) -> String {
        let lowercaseLetters = "abcdefghijklmnopqrstuvwxyz"
        let uppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        var transformedText = ""

        for char in text {
            if lowercaseLetters.contains(char) {
                if let randomLetter = lowercaseLetters.randomElement() {
                    transformedText.append(randomLetter)
                }
            } else if uppercaseLetters.contains(char) {
                if let randomLetter = uppercaseLetters.randomElement() {
                    transformedText.append(randomLetter)
                }
            } else {
                transformedText.append(char)
            }
        }
        return transformedText
    }
}
