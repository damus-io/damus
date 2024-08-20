//
//  NostrBuildGIFGrid.swift
//  damus
//
//  Created by eric on 8/14/24.
//

import SwiftUI
import Kingfisher


struct NostrBuildGIFGrid: View {
    let damus_state: DamusState
    @State var results:[NostrBuildGif] = []
    @State var cursor: Int = 0
    @State var errorAlert: Bool = false
    @SceneStorage("NostrBuildGIFGrid.show_nsfw_alert") var show_nsfw_alert : Bool = true
    @SceneStorage("NostrBuildGIFGrid.persist_nsfw_alert") var persist_nsfw_alert : Bool = true
    @Environment(\.dismiss) var dismiss

    var onSelect:(String) -> ()
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var TopBar: some View {
        VStack {
            HStack(spacing: 5.0) {

                Button(action: {
                    Task {
                        cursor -= pageSize
                        do {
                            let response = try await makeGIFRequest(cursor: cursor)
                            self.results = response.gifs
                        } catch {
                            print(error.localizedDescription)
                        }
                    }
                }, label: {
                    Text("Back", comment: "Button to go to previous page.")
                        .padding(10)
                })
                .buttonStyle(NeutralButtonStyle())
                .opacity(cursor > 0 ? 1 : 0)
                .disabled(cursor == 0)

                Spacer()
                
                Image("nostrbuild")
                    .resizable()
                    .frame(width: 40, height: 40)
                
                Spacer()

                Button(NSLocalizedString("Next", comment: "Button to go to next page.")) {
                    Task {
                        cursor += pageSize
                        do {
                            let response = try await makeGIFRequest(cursor: cursor)
                            self.results = response.gifs
                        } catch {
                            print(error.localizedDescription)
                        }
                    }
                }
                .bold()
                .buttonStyle(GradientButtonStyle(padding: 10))
            }
            
            Divider()
                .foregroundColor(DamusColors.neutral3)
                .padding(.top, 5)
        }
        .frame(height: 30)
        .padding()
        .padding(.top, 15)
    }
    
    var body: some View {
        VStack {
            TopBar
            ScrollView {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach($results) { gifResult in
                        VStack {
                            if let url = URL(string: gifResult.url.wrappedValue) {
                                ZStack {
                                    KFAnimatedImage(url)
                                        .imageContext(.note, disable_animation: damus_state.settings.disable_animation)
                                        .cancelOnDisappear(true)
                                        .configure { view in
                                            view.framePreloadCount = 3
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12.0))
                                        .frame(width: 120, height: 120)
                                        .aspectRatio(contentMode: .fill)
                                        .onTapGesture {
                                            onSelect(url.absoluteString)
                                            dismiss()
                                        }
                                    if persist_nsfw_alert {
                                        Blur()
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
        }
        .padding()
        .alert("Error", isPresented: $errorAlert) {
            Button(NSLocalizedString("OK", comment: "Exit this view")) {
                dismiss()
            }
        } message: {
            Text("Failed to load GIFs")
        }
        .alert("NSFW", isPresented: $show_nsfw_alert) {
            Button(NSLocalizedString("Cancel", comment: "Exit this view")) {
                dismiss()
            }
            Button(NSLocalizedString("Proceed", comment: "Button to continue")) {
                show_nsfw_alert = false
                persist_nsfw_alert = false
            }
        } message: {
            Text("NSFW means \"Not Safe For Work\". The content in this view may be inappropriate to view in some situations and may contain explicit images.", comment: "Warning to the user that there may be content that is not safe for work.")
        }
        .onAppear {
            Task {
                await initial()
            }
            if persist_nsfw_alert {
                show_nsfw_alert = true
            }
        }
    }
    
    func initial() async {
        do {
            let response = try await makeGIFRequest(cursor: cursor)
            self.results = response.gifs
        } catch {
            print(error)
            errorAlert = true
        }

    }
}

struct NostrBuildGIFGrid_Previews: PreviewProvider {
    static var previews: some View {
        NostrBuildGIFGrid(damus_state: test_damus_state) { gifURL in
            print("GIF URL: \(gifURL)")
        }
    }
}
