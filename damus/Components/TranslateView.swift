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

    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            show_translated_note = true
        }
        .translate_button_style()
    }
    
    func Translated(lang: String, artifacts: NoteArtifacts) -> some View {
        return Group {
            Button(String(format: NSLocalizedString("Translated from %@", comment: "Button to indicate that the note has been translated from a different language."), lang)) {
                show_translated_note = false
            }
            .translate_button_style()
            
            SelectableText(attributedString: artifacts.content, size: self.size)
        }
    }
    
    func MainContent(note_lang: String) -> some View {
        return Group {
            let languageName = Locale.current.localizedString(forLanguageCode: note_lang)
            if let languageName, let translated_artifacts, show_translated_note {
                Translated(lang: languageName, artifacts: translated_artifacts)
            } else if !damus_state.settings.auto_translate {
                TranslateButton
            } else {
                Text("")
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
            guard noteLanguage == nil && !checkingTranslationStatus && damus_state.settings.can_translate(damus_state.pubkey) else {
                return
            }
            
            checkingTranslationStatus = true

            if #available(iOS 16, *) {
                currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            } else {
                currentLanguage = Locale.current.languageCode ?? "en"
            }

            noteLanguage = event.note_language(damus_state.keypair.privkey) ?? currentLanguage
            
            guard let note_lang = noteLanguage else {
                noteLanguage = currentLanguage
                translated_note = nil
                checkingTranslationStatus = false
                return
            }
            
            if !preferredLanguages.contains(note_lang) {
                do {
                    // If the note language is different from our preferred languages, send a translation request.
                    let translator = Translator(damus_state.settings)
                    let originalContent = event.get_content(damus_state.keypair.privkey)
                    translated_note = try await translator.translate(originalContent, from: note_lang, to: currentLanguage)

                    if originalContent == translated_note {
                        // If the translation is the same as the original, don't bother showing it.
                        noteLanguage = currentLanguage
                        translated_note = nil
                    }
                } catch {
                    // If for whatever reason we're not able to figure out the language of the note, or translate the note, fail gracefully and do not retry. It's not the end of the world. Don't want to take down someone's translation server with an accidental denial of service attack.
                    noteLanguage = currentLanguage
                    translated_note = nil
                }
            }

            if let translated_note {
                // Render translated note.
                let translated_blocks = event.get_blocks(content: translated_note)
                translated_artifacts = render_blocks(blocks: translated_blocks, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
            }

            checkingTranslationStatus = false

            show_translated_note = damus_state.settings.auto_translate
        }
    }
}

extension View {
    func translate_button_style() -> some View {
        return self
            .font(.footnote)
            .contentShape(Rectangle())
            .padding([.top, .bottom], 10)
    }
}

struct TranslateView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        TranslateView(damus_state: ds, event: test_event, size: .normal)
    }
}
