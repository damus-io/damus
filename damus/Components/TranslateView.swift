//
//  TranslateButton.swift
//  damus
//
//  Created by William Casarin on 2023-02-02.
//

import SwiftUI
import NaturalLanguage

struct TranslateView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind
    
    @State var checkingTranslationStatus: Bool = false
    @State var currentLanguage: String = "en"
    @State var noteLanguage: String? = nil
    @State var translated_note: String? = nil
    @State var show_translated_note: Bool = false
    @State var translated_artifacts: NoteArtifacts? = nil
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            show_translated_note = true
        }
        .translate_button_style()
    }
    
    func Translated(lang: String, artifacts: NoteArtifacts) -> some View {
        return Group {
            Button(NSLocalizedString("Translated from \(lang)", comment: "Button to indicate that the note has been translated from a different language.")) {
                show_translated_note = false
            }
            .translate_button_style()
            
            Text(artifacts.content)
                .font(eventviewsize_to_font(size))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    func CheckingStatus(lang: String) -> some View {
        return Button(NSLocalizedString("Translating from \(lang)...", comment: "Button to indicate that the note is in the process of being translated from a different language.")) {
            show_translated_note = false
        }
        .translate_button_style()
    }
    
    func MainContent(note_lang: String) -> some View {
        return Group {
            let languageName = Locale.current.localizedString(forLanguageCode: note_lang)
            if let lang = languageName, show_translated_note {
                if checkingTranslationStatus {
                    CheckingStatus(lang: lang)
                } else if let artifacts = translated_artifacts {
                    Translated(lang: lang, artifacts: artifacts)
                }
            } else {
                TranslateButton
            }
        }
    }
    
    var body: some View {
        Group {
            if let note_lang = noteLanguage, noteLanguage != currentLanguage {
                MainContent(note_lang: note_lang)
            } else {
                Text("")
            }
        }
        .task {
            let translate_url = damus_state.settings.libretranslate_url
            let api_key = damus_state.settings.libretranslate_api_key
            
            guard noteLanguage == nil && !checkingTranslationStatus && translate_url != "" else {
                return
            }
            
            checkingTranslationStatus = true

            if #available(iOS 16, *) {
                currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            } else {
                currentLanguage = Locale.current.languageCode ?? "en"
            }

            // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in.
            let content = event.get_content(damus_state.keypair.privkey)
            noteLanguage = NLLanguageRecognizer.dominantLanguage(for: content)?.rawValue ?? currentLanguage

            if let lang = noteLanguage, noteLanguage != currentLanguage {
                // If the detected dominant language is a variant, remove the variant component and just take the language part as LibreTranslate typically only supports the variant-less language.
                if #available(iOS 16, *) {
                    noteLanguage = Locale.LanguageCode(stringLiteral: lang).identifier(.alpha2)
                } else {
                    noteLanguage = Locale.canonicalLanguageIdentifier(from: lang)
                }
            }
            
            guard let note_lang = noteLanguage else {
                noteLanguage = currentLanguage
                translated_note = nil
                checkingTranslationStatus = false
                return
            }
            
            if note_lang != currentLanguage {
                do {
                    // If the note language is different from our language, send a translation request.
                    let translator = Translator(translate_url, apiKey: api_key)
                    translated_note = try await translator.translate(content, from: note_lang, to: currentLanguage)
                } catch {
                    // If for whatever reason we're not able to figure out the language of the note, or translate the note, fail gracefully and do not retry. It's not the end of the world. Don't want to take down someone's translation server with an accidental denial of service attack.
                    noteLanguage = currentLanguage
                    translated_note = nil
                }
            }

            if let translated = translated_note {
                // Render translated note.
                let blocks = event.get_blocks(content: translated)
                let show_images = should_show_images(contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                translated_artifacts = render_blocks(blocks: blocks, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey, show_images: show_images)
            }

            checkingTranslationStatus = false
        
        }
    }
}

struct TranslateView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        TranslateView(damus_state: ds, event: test_event, size: .selected)
    }
}
