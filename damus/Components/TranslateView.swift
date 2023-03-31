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
    @State var show_translated_note: Bool = false
    @State var translated_artifacts: NoteArtifacts? = nil
    @State var translatable: Bool = false

    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            show_translated_note = true
            processTranslation()
        }
        .translate_button_style()
    }

    func processTranslation() {
        guard noteLanguage != nil && !checkingTranslationStatus && translatable else {
            return
        }

        checkingTranslationStatus = true
        show_translated_note = true

        Task {
            let translationWithLanguage = await damus_state.translations.translate(event, state: damus_state)
            DispatchQueue.main.async {
                guard translationWithLanguage != nil else {
                    noteLanguage = currentLanguage
                    checkingTranslationStatus = false
                    translatable = false
                    return
                }

                noteLanguage = translationWithLanguage!.language

                // Render translated note.
                let translatedBlocks = event.get_blocks(content: translationWithLanguage!.translation)
                translated_artifacts = render_blocks(blocks: translatedBlocks, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)

                checkingTranslationStatus = false
            }
        }
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
    
    func CheckingStatus() -> some View {
        return Button(NSLocalizedString("Translating...", comment: "Button to indicate that the note is in the process of being translated from a different language.")) {
            show_translated_note = false
        }
        .translate_button_style()
    }
    
    func MainContent(note_lang: String) -> some View {
        return Group {
            if translatable {
                let languageName = Locale.current.localizedString(forLanguageCode: note_lang)
                if let lang = languageName, show_translated_note {
                    if checkingTranslationStatus {
                        CheckingStatus()
                    } else if let artifacts = translated_artifacts {
                        Translated(lang: lang, artifacts: artifacts)
                    }
                } else {
                    TranslateButton
                }
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
            DispatchQueue.main.async {
                currentLanguage = damus_state.translations.targetLanguage
                noteLanguage = damus_state.translations.detectLanguage(event, state: damus_state)
                translatable = damus_state.translations.shouldTranslate(event, state: damus_state)

                let autoTranslate = damus_state.settings.auto_translate
                if autoTranslate {
                    processTranslation()
                }
                show_translated_note = autoTranslate
            }
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
