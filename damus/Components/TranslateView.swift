//
//  TranslateButton.swift
//  damus
//
//  Created by William Casarin on 2023-02-02.
//

import SwiftUI
import NaturalLanguage


struct Translated: Equatable {
    let artifacts: NoteArtifactsSeparated
    let language: String
}

enum TranslateStatus: Equatable {
    case havent_tried
    case translating
    case translated(Translated)
    case not_needed
}

fileprivate let MIN_UNIQUE_CHARS = 2

struct TranslateView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind

    @Binding var isAppleTranslationPopoverPresented: Bool

    @ObservedObject var translations_model: TranslationModel
    
    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind, isAppleTranslationPopoverPresented: Binding<Bool>) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self._isAppleTranslationPopoverPresented = isAppleTranslationPopoverPresented
        self._translations_model = ObservedObject(wrappedValue: damus_state.events.get_cache_data(event.id).translations_model)
    }
    
    var TranslateButton: some View {
        Button(NSLocalizedString("Translate Note", comment: "Button to translate note from different language.")) {
            if damus_state.settings.translation_service == .none {
                isAppleTranslationPopoverPresented = true
            } else {
                translate()
            }
        }
        .translate_button_style()
    }
    
    func TranslatedView(lang: String?, artifacts: NoteArtifactsSeparated, font_size: Double) -> some View {
        return VStack(alignment: .leading) {
            let translatedFromLanguageString = String(format: NSLocalizedString("Translated from %@", comment: "Button to indicate that the note has been translated from a different language."), lang ?? "ja")
            Text(translatedFromLanguageString)
                .foregroundColor(.gray)
                .font(.footnote)
                .padding([.top, .bottom], 10)

            if self.size == .selected {
                SelectableText(damus_state: damus_state, event: event, attributedString: artifacts.content.attributed, size: self.size)
            } else {
                artifacts.content.text
                    .font(eventviewsize_to_font(self.size, font_size: font_size))
            }
        }
    }
    
    func translate() {
        Task {
            guard let note_language = translations_model.note_language else {
                return
            }
            let res = await translate_note(profiles: damus_state.profiles, keypair: damus_state.keypair, event: event, settings: damus_state.settings, note_lang: note_language, purple: damus_state.purple)
            DispatchQueue.main.async {
                self.translations_model.state = res
            }
        }
    }
        
    func should_transl(_ note_lang: String) -> Bool {
        guard should_translate(event: event, our_keypair: damus_state.keypair, note_lang: note_lang) else {
            return false
        }

        if TranslationService.isAppleTranslationPopoverSupported {
            return damus_state.settings.translation_service == .none || damus_state.settings.can_translate
        } else {
            return damus_state.settings.can_translate
        }
    }
    
    var body: some View {
        Group {
            switch self.translations_model.state {
            case .havent_tried:
                if damus_state.settings.auto_translate && damus_state.settings.translation_service != .none {
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
                TranslatedView(lang: languageName, artifacts: translated.artifacts, font_size: damus_state.settings.font_size)
            case .not_needed:
                Text("")
            }
        }
    }
    
    func translationMeetsStringDistanceRequirements(original: String, translated: String) -> Bool {
        return levenshteinDistanceIsGreaterThanOrEqualTo(from: original, to: translated, threshold: MIN_UNIQUE_CHARS)
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
    @State static var isAppleTranslationPopoverPresented: Bool = false

    static var previews: some View {
        let ds = test_damus_state
        TranslateView(damus_state: ds, event: test_note, size: .normal, isAppleTranslationPopoverPresented: $isAppleTranslationPopoverPresented)
    }
}

func translate_note(profiles: Profiles, keypair: Keypair, event: NostrEvent, settings: UserSettingsStore, note_lang: String, purple: DamusPurple) async -> TranslateStatus {

    // If the note language is different from our preferred languages, send a translation request.
    let translator = Translator(settings, purple: purple)
    let originalContent = event.get_content(keypair)
    let translated_note = try? await translator.translate(originalContent, from: note_lang, to: current_language())
    
    guard let translated_note else {
        // if its the same, give up and don't retry
        return .not_needed
    }
    
    guard originalContent != translated_note else {
        // if its the same, give up and don't retry
        return .not_needed
    }
    
    guard translationMeetsStringDistanceRequirements(original: originalContent, translated: translated_note) else {
        return .not_needed
    }

    // Render translated note
    // TODO: fix translated blocks
    //let translated_blocks = parse_note_content(content: .content(translated_note, event.tags))
    //let artifacts = render_blocks(blocks: translated_blocks, profiles: profiles, can_hide_last_previewable_refs: true)
    
    return .not_needed

    // and cache it
    //return .translated(Translated(artifacts: artifacts, language: note_lang))
}

func current_language() -> String {
    if #available(iOS 16, *) {
        return Locale.current.language.languageCode?.identifier ?? "en"
    } else {
        return Locale.current.languageCode ?? "en"
    }
}
    
func levenshteinDistanceIsGreaterThanOrEqualTo(from source: String, to target: String, threshold: Int) -> Bool {
    let sourceCount = source.count
    let targetCount = target.count
    
    // Early return if the difference in lengths is already greater than or equal to the threshold,
    // indicating the edit distance meets the condition without further calculation.
    if abs(sourceCount - targetCount) >= threshold {
        return true
    }
    
    var matrix = [[Int]](repeating: [Int](repeating: 0, count: targetCount + 1), count: sourceCount + 1)

    for i in 0...sourceCount {
        matrix[i][0] = i
    }

    for j in 0...targetCount {
        matrix[0][j] = j
    }

    for i in 1...sourceCount {
        var rowMin = Int.max
        for j in 1...targetCount {
            let sourceIndex = source.index(source.startIndex, offsetBy: i - 1)
            let targetIndex = target.index(target.startIndex, offsetBy: j - 1)

            let cost = source[sourceIndex] == target[targetIndex] ? 0 : 1
            matrix[i][j] = min(
                matrix[i - 1][j] + 1,    // Deletion
                matrix[i][j - 1] + 1,    // Insertion
                matrix[i - 1][j - 1] + cost  // Substitution
            )
            rowMin = min(rowMin, matrix[i][j])
        }
        // If the minimum edit distance found in any row is already greater than or equal to the threshold,
        // you can conclude the edit distance meets the criteria.
        if rowMin >= threshold {
            return true
        }
    }

    return matrix[sourceCount][targetCount] >= threshold
}

func translationMeetsStringDistanceRequirements(original: String, translated: String) -> Bool {
    return levenshteinDistanceIsGreaterThanOrEqualTo(from: original, to: translated, threshold: MIN_UNIQUE_CHARS)
}
