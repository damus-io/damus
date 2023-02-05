//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI

enum NostrPostResult {
    case post(NostrPost, onlyToRelayIds: [String]?)
    case cancel
}

let POST_PLACEHOLDER = NSLocalizedString("Type your post here...", comment: "Text box prompt to ask user to type their post.")

struct PostView: View {
    @State var isPresentingRelaysScreen: Bool = false
    @StateObject var relaysScreenState: BroadcastToRelaysView.ViewState
    @State var post: String = ""
    @FocusState var focus: Bool
    
    let replying_to: NostrEvent?
    let references: [ReferencedId]
    let damus_state: DamusState

    @Environment(\.presentationMode) var presentationMode

    init(replying_to: NostrEvent?, references: [ReferencedId], damus_state: DamusState) {
        _relaysScreenState = StateObject(wrappedValue: BroadcastToRelaysView.ViewState(state: damus_state))
        
        self.replying_to = replying_to
        self.references = references
        self.damus_state = damus_state
    }
    
    enum FocusField: Hashable {
      case post
    }

    func cancel() {
        NotificationCenter.default.post(name: .post, object: NostrPostResult.cancel)
        dismiss()
    }

    func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }

    func send_post() {
        var kind: NostrKind = .text
        if replying_to?.known_kind == .chat {
            kind = .chat
        }
        let content = self.post.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let new_post = NostrPost(content: content, references: references, kind: kind)

        NotificationCenter.default.post(name: .post,
                                        object: NostrPostResult.post(new_post,
                                                                     onlyToRelayIds: relaysScreenState.limitingRelayIds))
        dismiss()
    }

    var is_post_empty: Bool {
        return post.allSatisfy { $0.isWhitespace }
    }

    var body: some View {
        NavigationView {
            VStack {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $post)
                        .focused($focus)
                        .textInputAutocapitalization(.sentences)
                    
                    if post.isEmpty {
                        Text(POST_PLACEHOLDER)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .foregroundColor(Color(uiColor: .placeholderText))
                            .allowsHitTesting(false)
                    }
                }
                
                // This if-block observes @ for tagging
                if let searching = get_searching_string(post) {
                    VStack {
                        Spacer()
                        UserSearch(damus_state: damus_state, search: searching, post: $post)
                    }.zIndex(1)
                }
            }
            .onAppear() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.focus = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel out of posting a note.")) {
                        self.cancel()
                    }
                    .foregroundColor(.primary)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { isPresentingRelaysScreen.toggle() }) {
                            Image(systemName: "network")
                                .foregroundColor(.primary)
                                .overlay {
                                    if relaysScreenState.hasExcludedRelays {
                                        Circle()
                                            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 5]))
                                    }
                                }
                        }
                    }
                    Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
                        self.send_post()
                    }
                    .disabled(is_post_empty)
                }
            }
            .sheet(isPresented: $isPresentingRelaysScreen, content: {
                BroadcastToRelaysView(state: relaysScreenState, broadCastEvent: nil)
            })
            .padding()
        }
    }
}

func get_searching_string(_ post: String) -> String? {
    guard let last_word = post.components(separatedBy: .whitespacesAndNewlines).last else {
        return nil
    }
    
    guard last_word.count >= 2 else {
        return nil
    }
    
    guard last_word.first! == "@" else {
        return nil
    }
    
    // don't include @npub... strings
    guard last_word.count != 64 else {
        return nil
    }
    
    return String(last_word.dropFirst())
}
