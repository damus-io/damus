//
//  ShareViewController.swift
//  share extension
//
//  Created by Swift on 11/4/24.
//

import SwiftUI
import Social
import UniformTypeIdentifiers

let this_app: UIApplication = UIApplication()

class ShareViewController: SLComposeServiceViewController {
    private var contentView: UIHostingController<ShareExtensionView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.tintColor = UIColor(DamusColors.purple)
        
        DispatchQueue.main.async {
            let contentView = UIHostingController(rootView: ShareExtensionView(extensionContext: self.extensionContext!,
                                                                               dismissParent: { [weak self] in
                self?.dismissSelf()
            }
                                                                              ))
            self.addChild(contentView)
            self.contentView = contentView
            self.view.addSubview(contentView.view)
            
            // set up constraints
            contentView.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
            contentView.view.bottomAnchor.constraint (equalTo: self.view.bottomAnchor).isActive = true
            contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
            contentView.view.rightAnchor.constraint (equalTo: self.view.rightAnchor).isActive = true
        }
    }
    
    func dismissSelf() {
        super.didSelectCancel()
    }
}

struct ShareExtensionView: View {
    @State private var share_state: ShareState = .loading
    let extensionContext: NSExtensionContext
    @State private var state: DamusState? = nil
    @State private var preUploadedMedia: [PreUploadedMedia] = []
    var dismissParent: (() -> Void)?
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        VStack(spacing: 15) {
                switch self.share_state {
                case .loading:
                    ProgressView()
                case .no_content:
                    Group {
                        Text("No content available to share", comment: "Title indicating that there was no available content to share")
                            .font(.largeTitle)
                            .multilineTextAlignment(.center)
                            .padding()
                        Text("There is no content available to share at this time. Please close this view and try again.", comment: "Label explaining that no content is available to share and instructing the user to close the view and try again.")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: {
                            self.done()
                        }, label: {
                            Text("Close", comment: "Button label giving the user the option to close the view when no content is available to share")
                        })
                        .foregroundStyle(.secondary)
                    }
                case .not_logged_in:
                    Group {
                        Text("Not Logged In", comment: "Title indicating that sharing cannot proceed because the user is not logged in.")
                            .font(.largeTitle)
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Text("You cannot share content because you are not logged in. Please close this view, log in to your account, and try again.", comment: "Label explaining that sharing cannot proceed because the user is not logged in.")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: {
                            self.done()
                        }, label: {
                            Text("Close", comment: "Button label giving the user the option to close the sheet due to not being logged in.")
                        })
                        .foregroundStyle(.secondary)
                    }
                case .loaded(let content):
                    PostView(
                        action: .sharing(content),
                        damus_state: state!  // state will have a value at this point
                    )
                case .cancelled:
                    Group {
                        Text("Cancelled", comment: "Title indicating that the user has cancelled.")
                            .font(.largeTitle)
                            .padding()
                        Button(action: {
                            self.done()
                        }, label: {
                            Text("Close", comment: "Button label giving the user the option to close the sheet from which they were trying to share.")
                        })
                        .foregroundStyle(.secondary)
                    }
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
                            done()
                        }, label: {
                            Text("Close", comment: "Button label giving the user the option to close the sheet from which they were trying share.")
                        })
                        .foregroundStyle(.secondary)
                    }
                case .posted(event: let event):
                    Group {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                        Text("Shared", comment: "Title indicating that the user has shared content successfully")
                            .font(.largeTitle)
                            .multilineTextAlignment(.center)
                            .padding(.bottom)
                        
                        Link(destination: URL(string: "damus:\(event.id.bech32)")!, label: {
                            Text("Go to the app", comment: "Button label giving the user the option to go to the app after sharing content")
                        })
                        .buttonStyle(GradientButtonStyle())
                        
                        Button(action: {
                            self.done()
                        }, label: {
                            Text("Close", comment: "Button label giving the user the option to close the sheet from which they shared content")
                        })
                        .foregroundStyle(.secondary)
                    }
                case .posting:
                    Group {
                        ProgressView()
                            .frame(width: 20, height: 20)
                        Text("Sharing", comment: "Title indicating that the content is being published to the network")
                            .font(.largeTitle)
                            .multilineTextAlignment(.center)
                            .padding(.bottom)
                        Text("Your content is being broadcasted to the network. Please wait.", comment: "Label explaining that their content sharing action is in progress")
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
        }
        .onAppear(perform: {
            if setDamusState() {
                self.loadSharedContent()
            }
        })
        .onDisappear {
            Task { @MainActor in
                self.state?.ndb.close()
            }
        }
        .onReceive(handle_notify(.post)) { post_notification in
            switch post_notification {
            case .post(let post):
                Task { await self.post(post) }
            case .cancel:
                self.share_state = .cancelled
                dismissParent?()
            }
        }
        .onChange(of: scenePhase) { (phase: ScenePhase) in
            guard let state else { return }
            switch phase {
            case .background:
                print("txn: 📙 SHARE BACKGROUNDED")
                Task { @MainActor in
                    state.ndb.close()
                }
                break
            case .inactive:
                print("txn: 📙 SHARE INACTIVE")
                break
            case .active:
                print("txn: 📙 SHARE ACTIVE")
                Task { await state.nostrNetwork.ping() }
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { obj in
            guard let state else { return }
            print("SHARE ACTIVE NOTIFY")
            if state.ndb.reopen() {
                print("SHARE NOSTRDB REOPENED")
            } else {
                print(" SHARE NOSTRDB FAILED TO REOPEN closed: \(state.ndb.is_closed)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { obj in
            guard let state else { return }
            print("txn: 📙 SHARE BACKGROUNDED")
            Task { @MainActor in
                state.ndb.close()
            }
        }
    }
    
    func post(_ post: NostrPost) async {
        self.share_state = .posting
        guard let state else {
            self.share_state = .failed(error: "Damus state not initialized")
            return
        }
        guard let full_keypair = state.keypair.to_full() else {
            self.share_state = .not_logged_in
            return
        }
        guard let posted_event = post.to_event(keypair: full_keypair, clientTag: state.clientTagComponents) else {
            self.share_state = .failed(error: "Cannot convert post data into a nostr event")
            return
        }
        await state.nostrNetwork.postbox.send(posted_event, on_flush: .once({ flushed_event in
            if flushed_event.event.id == posted_event.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {  // Offset labor perception bias
                    self.share_state = .posted(event: flushed_event.event)
                })
            }
            else {
                self.share_state = .failed(error: "Flushed event is not the event we just tried to post.")
            }
        }))
    }
    
    @discardableResult
    private func setDamusState() -> Bool {
        guard let keypair = get_saved_keypair(),
              keypair.privkey != nil else {
            self.share_state = .not_logged_in
            return false
        }
        state = DamusState(keypair: keypair)
        Task { await state?.nostrNetwork.connect() }
        return true
    }
    
    func loadSharedContent() {
        guard let extensionItem = extensionContext.inputItems.first as? NSExtensionItem else {
            share_state = .failed(error: "Unable to get item provider")
            return
        }
        
        var title = ""
        
        // Check for the attributed text from the extension item
        if let attributedContentData = extensionItem.userInfo?[NSExtensionItemAttributedContentTextKey] as? Data {
            if let attributedText = try? NSAttributedString(data: attributedContentData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                let plainText = attributedText.string
                print("Extracted Text: \(plainText)")
                title = plainText
            } else {
                print("Failed to decode RTF content.")
            }
        } else {
            print("Content is not in RTF format or data is unavailable.")
        }
        
        // Iterate through all attachments to handle multiple images
        for itemProvider in extensionItem.attachments ?? [] {
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, error) in
                    if let url = item as? URL {
                        
                        attemptAcquireResourceAndChooseMedia(
                            url: url,
                            fallback: processImage,
                            unprocessedEnum: {.unprocessed_image($0)},
                            processedEnum: {.processed_image($0)})
                        
                    } else if let image = item as? UIImage {
                        // process it directly if shared item is uiimage (example: image shared from Facebook, Signal apps)
                        chooseMedia(PreUploadedMedia.uiimage(image))
                    } else {
                        self.share_state = .failed(error: "Failed to load image content")
                    }
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.movie.identifier) { (item, error) in
                    if let url = item as? URL {
                        attemptAcquireResourceAndChooseMedia(
                            url: url,
                            fallback: processVideo,
                            unprocessedEnum: {.unprocessed_video($0)},
                            processedEnum: {.processed_video($0)}
                        )
                        
                    } else {
                        self.share_state = .failed(error: "Failed to load video content")
                    }
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (item, error) in
                    // Sharing URLs from iPhone/Safari to Damus also follows this pathway
                    // Sharing Photos or Links from macOS/Finder or macOS/Safari to Damus sets item-provider conforming to UTType.url.identifier and therefore takes this pathway
                    
                    if let url = item as? URL {
                        // Sharing Photos from macOS/Finder
                        if url.absoluteString.hasPrefix("file:///") {
                            attemptAcquireResourceAndChooseMedia(
                                url: url,
                                fallback: processImage,
                                unprocessedEnum: {.unprocessed_image($0)},
                                processedEnum: {.processed_image($0)})
                            
                        } else {
                            // Sharing URLs from iPhone/Safari to Damus
                            self.share_state = .loaded(ShareContent(title: title, content: .link(url)))
                        }
                    } else if let data = item as? Data,
                              let string = String(data: data, encoding: .utf8),
                              let url = URL(string: string)  {
                            // Sharing Links from macOS/Safari, does not provide title
                            self.share_state = .loaded(ShareContent(title: "", content: .link(url)))
                    } else {
                        self.share_state = .failed(error: "Failed to load text content")
                    }
                }
            } else {
                share_state = .no_content
            }
        }
        
        func attemptAcquireResourceAndChooseMedia(url: URL, fallback: (URL) -> URL?, unprocessedEnum: (URL) -> PreUploadedMedia, processedEnum: (URL) -> PreUploadedMedia) {
            if url.startAccessingSecurityScopedResource() {
                // Have permission from system to use url out of scope
                print("Acquired permission to security scoped resource")
                chooseMedia(unprocessedEnum(url))
            } else {
                // Need to copy URL to non-security scoped location
                guard let newUrl = fallback(url) else { return }
                chooseMedia(processedEnum(newUrl))
            }
        }
        
        func chooseMedia(_ media: PreUploadedMedia) {
            self.preUploadedMedia.append(media)
            if extensionItem.attachments?.count == preUploadedMedia.count {
                self.share_state = .loaded(ShareContent(title: "", content: .media(preUploadedMedia)))
            }
        }
    }
    
    private func done() {
        extensionContext.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private enum ShareState {
        case loading
        case no_content
        case not_logged_in
        case loaded(ShareContent)
        case failed(error: String)
        case cancelled
        case posting
        case posted(event: NostrEvent)
    }
}
