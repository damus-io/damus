//
//  Translations.swift
//  damus
//
//  Created by Terry Yiu on 3/29/23.
//

import Foundation
import NaturalLanguage

class Translations: ObservableObject {
    private static let languageDetectionMinConfidence = 0.5

    @Published var translations: [NostrEvent: String] = [:]
    @Published var languages: [NostrEvent: String] = [:]

    let settings: UserSettingsStore

    let translator: Translator

    let targetLanguage = currentLanguage()
    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })

    init(_ settings: UserSettingsStore) {
        self.settings = settings
        self.translator = Translator(settings)
    }

    /**
     Attempts to detect the language of the content of a given nostr event using Apple's offline NaturalLanguage API.
     The detected language will be returned only if it has a 50% or more confidence.
     This is a best effort guess and could be incorrect.
     */
    func detectLanguage(_ event: NostrEvent, state: DamusState) -> String? {
        if let cachedLanguage = languages[event] {
            return cachedLanguage
        }

        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        let originalBlocks = event.blocks(state.keypair.privkey)
        let originalOnlyText = originalBlocks.compactMap { $0.is_text }.joined(separator: " ")

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= Translations.languageDetectionMinConfidence })?.key.rawValue else {
            return nil
        }

        // Remove the variant component and just take the language part as translation services typically only supports the variant-less language.
        // Moreover, speakers of one variant can generally understand other variants.
        let language = localeToLanguage(locale)
        languages[event] = language
        return language
    }

    func translate(_ event: NostrEvent, state: DamusState) async -> TranslationWithLanguage? {
        guard shouldTranslate(event, state: state) else {
            return nil
        }

        guard let noteLanguage = detectLanguage(event, state: state) else {
            return nil
        }

        let translationWithLanguage: TranslationWithLanguage

        if let cachedTranslation = translations[event] {
            translationWithLanguage = TranslationWithLanguage(translation: cachedTranslation, language: noteLanguage)
        } else {
            do {
                guard let _translationWithLanguage = try await translator.translate(event.get_content(state.keypair.privkey), from: noteLanguage, to: targetLanguage) else {
                    return nil
                }

                translationWithLanguage = _translationWithLanguage
                translations[event] = translationWithLanguage.translation
                languages[event] = translationWithLanguage.language
            } catch {
                return nil
            }
        }

        // If the translated content is identical to the original content, don't return the translation.
        if translationWithLanguage.translation == event.get_content(state.keypair.privkey) {
            languages[event] = targetLanguage
            return nil
        } else {
            return translationWithLanguage
        }
    }

    func shouldTranslate(_ event: NostrEvent, state: DamusState) -> Bool {
        // Do not translate self-authored content because if the language recognizer guesses the wrong language for your own note,
        // it's annoying and unexpected for the translation to show up.
        if event.pubkey == state.pubkey && state.is_privkey_user {
            return false
        }

        // Avoid translating notes if language cannot be detected or if it is in one of the user's preferred languages.
        guard let noteLanguage = detectLanguage(event, state: state), !preferredLanguages.contains(noteLanguage) else {
            return false
        }

        switch settings.translation_service {
        case .none:
            return false
        case .libretranslate:
            return URLComponents(string: settings.libretranslate_url) != nil
        case .deepl:
            return settings.deepl_api_key != ""
        }
    }
}
