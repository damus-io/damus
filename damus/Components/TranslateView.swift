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
    case translating
    case translated(Translated)
    case not_needed
}

struct TranslateView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind
    
    @ObservedObject var translations_model: TranslationModel
    
    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self._translations_model = ObservedObject(wrappedValue: damus_state.events.get_cache_data(event.id).translations_model)
    }
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            translate()
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
    
    func translate() {
        Task {
            guard let note_language = translations_model.note_language else {
                return
            }
            let res = await translate_note(profiles: damus_state.profiles, privkey: damus_state.keypair.privkey, event: event, settings: damus_state.settings, note_lang: note_language)
            DispatchQueue.main.async {
                self.translations_model.state = res
            }
        }
    }
    
    func attempt_translation() {
        guard should_translate(event: event, our_keypair: damus_state.keypair, settings: damus_state.settings, note_lang: self.translations_model.note_language), damus_state.settings.auto_translate else {
            return
        }
        
        translate()
    }
    
    func should_transl(_ note_lang: String) -> Bool {
        should_translate(event: event, our_keypair: damus_state.keypair, settings: damus_state.settings, note_lang: note_lang)
    }
    
    var body: some View {
        Group {
            switch self.translations_model.state {
            case .havent_tried:
                if damus_state.settings.auto_translate {
                    Text("")
                } else if let note_lang = translations_model.note_language, should_transl(note_lang)  {
                        TranslateButton
                } else {
                    Text("")
                }
            case .translating:
                Text("")
            case .translated(let translated):
                let languageName = Locale.current.localizedString(forLanguageCode: translated.language)
                TranslatedView(lang: languageName, artifacts: translated.artifacts)
            case .not_needed:
                Text("")
            }
        }
        .task {
            attempt_translation()
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

func translate_note(profiles: Profiles, privkey: String?, event: NostrEvent, settings: UserSettingsStore, note_lang: String) async -> TranslateStatus {
    
    // If the note language is different from our preferred languages, send a translation request.
    let translator = Translator(settings)
    let originalContent = event.get_content(privkey)
    let translated_note = try? await translator.translate(originalContent, from: note_lang, to: current_language())
    
    guard let translated_note else {
        // if its the same, give up and don't retry
        return .not_needed
    }
    
    guard originalContent != translated_note else {
        // if its the same, give up and don't retry
        return .not_needed
    }

    // Render translated note
    let translated_blocks = event.get_blocks(content: translated_note)
    let artifacts = render_blocks(blocks: translated_blocks, profiles: profiles)
    
    // and cache it
    return .translated(Translated(artifacts: artifacts, language: note_lang))
}

func current_language() -> String {
    if #available(iOS 16, *) {
        return Locale.current.language.languageCode?.identifier ?? "en"
    } else {
        return Locale.current.languageCode ?? "en"
    }
}
    
