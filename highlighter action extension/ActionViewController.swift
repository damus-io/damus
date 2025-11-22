//
//  ActionViewController.swift
//  highlighter action extension
//
//  Created by Daniel D’Aquino on 2024-08-09.
//

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
import SwiftUI

struct ShareExtensionView: View {
    @State var highlighter_state: HighlighterState = .loading
    let extensionContext: NSExtensionContext
    @State var state: DamusState? = nil
    @State var signedEvent: String? = nil
    
    @State private var selectedText = ""
    @State private var selectedTextHeight: CGFloat = .zero
    @State private var selectedTextWidth: CGFloat = .zero
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        VStack(spacing: 15) {
            if let state {
                switch self.highlighter_state {
                    case .loading:
                        ProgressView()
                    case .no_highlight_text:
                        Group {
                            Text("No text selected", comment: "Title indicating that a highlight cannot be posted because no text was selected.")
                                .font(.largeTitle)
                                .multilineTextAlignment(.center)
                                .padding()
                            Text("You cannot post a highlight because you have selected no text on the page! Please close this, select some text, and try again.", comment: "Label explaining a highlight cannot be made because there was no selected text, and some instructions on how to resolve the issue")
                                .multilineTextAlignment(.center)
                            Button(action: {
                                self.done()
                            }, label: {
                                Text("Close", comment: "Button label giving the user the option to close the sheet from which they were trying to post a highlight")
                            })
                            .foregroundStyle(.secondary)
                        }
                    case .not_logged_in:
                        Group {
                            Text("Not logged in", comment: "Title indicating that a highlight cannot be posted because the user is not logged in.")
                                .font(.largeTitle)
                                .multilineTextAlignment(.center)
                                .padding()
                            Text("You cannot post a highlight because you are not logged in with a private key! Please close this, login with a private key (or nsec), and try again.", comment: "Label explaining a highlight cannot be made because the user is not logged in")
                                .multilineTextAlignment(.center)
                            Button(action: {
                                self.done()
                            }, label: {
                                Text("Close", comment: "Button label giving the user the option to close the sheet from which they were trying to post a highlight")
                            })
                            .foregroundStyle(.secondary)
                        }
                    case .loaded(let highlighted_text, let source_url):
                        PostView(
                            action: .highlighting(HighlightContentDraft(selected_text: highlighted_text, source: .external_url(source_url))),
                            damus_state: state
                        )
                    case .failed(let error):
                        Group {
                            Text("Error", comment: "Title indicating that an error has occurred.")
                                .font(.largeTitle)
                                .multilineTextAlignment(.center)
                                .padding()
                            Text("An unexpected error occurred. Please contact Damus support via [Nostr](damus:npub18m76awca3y37hkvuneavuw6pjj4525fw90necxmadrvjg0sdy6qsngq955) or [email](support@damus.io) with the error message below.", comment: "Label explaining there was an error, and suggesting next steps")
                                .multilineTextAlignment(.center)
                            Text("Error: \(error)")
                            Button(action: {
                                self.done()
                            }, label: {
                                Text("Close", comment: "Button label giving the user the option to close the sheet from which they were trying to post a highlight")
                            })
                            .foregroundStyle(.secondary)
                        }
                    case .posted(event: let event):
                        Group {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                            Text("Posted", comment: "Title indicating that the user has posted a highlight successfully")
                                .font(.largeTitle)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                            
                            Link(destination: URL(string: "damus:\(event.id.bech32)")!, label: {
                                Text("Go to the app", comment: "Button label giving the user the option to go to the app after posting a highlight")
                            })
                            .buttonStyle(GradientButtonStyle())
                            Button(action: {
                                self.done()
                            }, label: {
                                Text("Close", comment: "Button label giving the user the option to close the sheet from which they posted a highlight")
                            })
                            .foregroundStyle(.secondary)
                        }
                    case .cancelled:
                        Group {
                            Text("Cancelled", comment: "Title indicating that the user has cancelled.")
                                .font(.largeTitle)
                                .padding()
                            Button(action: {
                                self.done()
                            }, label: {
                                Text("Close", comment: "Button label giving the user the option to close the sheet from which they were trying to post a highlight")
                            })
                            .foregroundStyle(.secondary)
                        }
                    case .posting:
                        Group {
                            ProgressView()
                                .frame(width: 20, height: 20)
                            Text("Posting", comment: "Title indicating that the highlight post is being published to the network")
                                .font(.largeTitle)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                            Text("Your highlight is being broadcasted to the network. Please wait.", comment: "Label explaining there their highlight publishing action is in progress")
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                }
            }
        }
        .onAppear(perform: {
            self.loadSharedUrl()
            guard let keypair = get_saved_keypair() else { return }
            guard keypair.privkey != nil else {
                self.highlighter_state = .not_logged_in
                return
            }
            self.state = DamusState(keypair: keypair)
            Task { await self.state?.nostrNetwork.connect() }
        })
        .onChange(of: self.highlighter_state) {
            if case .cancelled = highlighter_state {
                self.done()
            }
        }
        .onReceive(handle_notify(.post)) { post_notification in
            switch post_notification {
            case .post(let post):
                Task { await self.post(post) }
            case .cancel:
                self.highlighter_state = .cancelled
            }
        }
        .onChange(of: scenePhase) { (phase: ScenePhase) in
            guard let state else { return }
            switch phase {
            case .background:
                print("txn: 📙 HIGHLIGHTER BACKGROUNDED")
                Task { @MainActor in
                    state.ndb.close()
                }
                break
            case .inactive:
                print("txn: 📙 HIGHLIGHTER INACTIVE")
                break
            case .active:
                print("txn: 📙 HIGHLIGHTER ACTIVE")
                Task { await state.nostrNetwork.ping() }
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { obj in
            guard let state else { return }
            print("txn: 📙 HIGHLIGHTER ACTIVE NOTIFY")
            if state.ndb.reopen() {
                print("txn: HIGHLIGHTER NOSTRDB REOPENED")
            } else {
                print("txn: HIGHLIGHTER NOSTRDB FAILED TO REOPEN closed: \(state.ndb.is_closed)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { obj in
            guard let state else { return }
            print("txn: 📙 HIGHLIGHTER BACKGROUNDED")
            Task { @MainActor in
                state.ndb.close()
            }
        }
    }
    
    func loadSharedUrl() {
        guard
           let extensionItem = extensionContext.inputItems.first as? NSExtensionItem,
           let itemProvider = extensionItem.attachments?.first else {
            self.highlighter_state = .failed(error: "Can't get itemProvider")
            return
        }
        
        let propertyList = UTType.propertyList.identifier
        if itemProvider.hasItemConformingToTypeIdentifier(propertyList) {
            itemProvider.loadItem(forTypeIdentifier: propertyList, options: nil, completionHandler: { (item, error) -> Void in
                guard let dictionary = item as? NSDictionary else { return }
                if error != nil {
                    self.highlighter_state = .failed(error: "Error loading plist item: \(error?.localizedDescription ?? "Unknown")")
                    return
                }
                OperationQueue.main.addOperation {
                    if let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                       let urlString = results["URL"] as? String,
                       let selection = results["selectedText"] as? String,
                       let url = URL(string: urlString) {
                        guard selection != "" else {
                            self.highlighter_state = .no_highlight_text
                            return
                        }
                        self.highlighter_state = .loaded(highlighted_text: selection, source_url: url)
                    }
                    else {
                        self.highlighter_state = .failed(error: "Cannot load results")
                    }
                }
            })
        }
        else {
            self.highlighter_state = .failed(error: "No plist detected")
        }
    }
    
    func post(_ post: NostrPost) async {
        self.highlighter_state = .posting
        guard let state else {
            self.highlighter_state = .failed(error: "Damus state not initialized")
            return
        }
        guard let full_keypair = state.keypair.to_full() else {
            self.highlighter_state = .not_logged_in
            return
        }
        guard let posted_event = post.to_event(keypair: full_keypair, clientTag: state.clientTagComponents) else {
            self.highlighter_state = .failed(error: "Cannot convert post data into a nostr event")
            return
        }
        await state.nostrNetwork.postbox.send(posted_event, on_flush: .once({ flushed_event in
            if flushed_event.event.id == posted_event.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {  // Offset labor perception bias
                    self.highlighter_state = .posted(event: flushed_event.event)
                })
            }
            else {
                self.highlighter_state = .failed(error: "Flushed event is not the event we just tried to post.")
            }
        }))
    }
    
    func done() {
        self.extensionContext.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    enum HighlighterState: Equatable {
        case loading
        case no_highlight_text
        case not_logged_in
        case loaded(highlighted_text: String, source_url: URL)
        case posting
        case posted(event: NostrEvent)
        case cancelled
        case failed(error: String)
    }
}

class ActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.tintColor = UIColor(DamusColors.purple)
        
        DispatchQueue.main.async {
            let contentView = UIHostingController(rootView: ShareExtensionView(extensionContext: self.extensionContext!))
            self.addChild(contentView)
            self.view.addSubview(contentView.view)
            
            // set up constraints
            contentView.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
            contentView.view.bottomAnchor.constraint (equalTo: self.view.bottomAnchor).isActive = true
            contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
            contentView.view.rightAnchor.constraint (equalTo: self.view.rightAnchor).isActive = true
        }
    }
}
