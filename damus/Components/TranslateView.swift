//
//  TranslateButton.swift
//  damus
//
//  Created by William Casarin on 2023-02-02.
//

import SwiftUI
import NaturalLanguage


struct Translated: Equatable {
    let artifacts: NoteArtifacts
    let language: String
}

enum TranslateStatus: Equatable {
    case havent_tried
    case trying
    case translating
    case translated(Translated)
    case not_needed
}

struct TranslateView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind
    let currentLanguage: String
    
    @State var translated: TranslateStatus
    
    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        
        if #available(iOS 16, *) {
            self.currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            self.currentLanguage = Locale.current.languageCode ?? "en"
        }
        
        if let cached = damus_state.events.lookup_translated_artifacts(evid: event.id) {
            self._translated = State(initialValue: cached)
        } else {
            let initval: TranslateStatus = self.damus_state.settings.auto_translate ? .trying : .havent_tried
            self._translated = State(initialValue: initval)
        }
    }
    
    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            self.translated = .trying
        }
        .translate_button_style()
    }
    
    func TranslatedView(lang: String?, artifacts: NoteArtifacts) -> some View {
        return VStack(alignment: .leading) {
            Text(String(format: NSLocalizedString("Translated from %@", comment: "Button to indicate that the note has been translated from a different language."), lang ?? "ja"))
                .foregroundColor(.gray)
                .font(.footnote)
                .padding([.top, .bottom], 10)
            
            if self.size == .selected {
                SelectableText(attributedString: artifacts.content.attributed, size: self.size)
            } else {
                artifacts.content.text
                    .font(eventviewsize_to_font(self.size))
            }
        }
    }
    
    func failed_attempt() {
        DispatchQueue.main.async {
            self.translated = .not_needed
            damus_state.events.store_translation_artifacts(evid: event.id, translated: .not_needed)
        }
    }
    
    func attempt_translation() async {
        guard case .trying = translated else {
            return
        }
        
        guard damus_state.settings.can_translate(damus_state.pubkey) else {
            return
        }
        
        let note_lang = event.note_language(damus_state.keypair.privkey) ?? currentLanguage
        
        // Don't translate if its in our preferred languages
        guard !preferredLanguages.contains(note_lang) else {
            failed_attempt()
            return
        }
        
        DispatchQueue.main.async {
            self.translated = .translating
        }
        
        // If the note language is different from our preferred languages, send a translation request.
        let translator = Translator(damus_state.settings)
        let originalContent = event.get_content(damus_state.keypair.privkey)
        let translated_note = try? await translator.translate(originalContent, from: note_lang, to: currentLanguage)
        
        guard let translated_note else {
            // if its the same, give up and don't retry
            failed_attempt()
            return
        }
        
        guard originalContent != translated_note else {
            // if its the same, give up and don't retry
            failed_attempt()
            return
        }

        // Render translated note
        let translated_blocks = event.get_blocks(content: translated_note)
        let artifacts = render_blocks(blocks: translated_blocks, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
        
        // and cache it
        DispatchQueue.main.async {
            self.translated = .translated(Translated(artifacts: artifacts, language: note_lang))
            damus_state.events.store_translation_artifacts(evid: event.id, translated: self.translated)
        }
    }
    
    var body: some View {
        Group {
            switch translated {
            case .havent_tried:
                if damus_state.settings.auto_translate {
                    Text("")
                } else {
                    TranslateButton
                }
            case .trying:
                Text("")
            case .translating:
                Text("Translating...", comment: "Text to display when waiting for the translation of a note to finish processing before showing it.")
                    .foregroundColor(.gray)
                    .font(.footnote)
                    .padding([.top, .bottom], 10)
            case .translated(let translated):
                let languageName = Locale.current.localizedString(forLanguageCode: translated.language)
                TranslatedView(lang: languageName, artifacts: translated.artifacts)
            case .not_needed:
                Text("")
            }
        }
        .onChange(of: translated) { val in
            guard case .trying = translated else {
                return
            }
            
            Task {
                await attempt_translation()
            }
        }
        .task {
            await attempt_translation()
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
