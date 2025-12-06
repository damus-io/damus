//
//  EditMetadataView.swift
//  damus
//
//  Created by Thomas Tastet on 23/12/2022.
//

import SwiftUI
import Combine

let BANNER_HEIGHT: CGFloat = 150.0;
fileprivate let Scroll_height: CGFloat = 700.0

struct EditMetadataView: View {
    let damus_state: DamusState
    @State var display_name: String
    @State var about: String
    @State var picture: String
    @State var banner: String
    @State var nip05: String
    @State var name: String
    @State var ln: String
    @State var website: String

    @State var confirm_ln_address: Bool = false
    @State var confirm_save_alert: Bool = false
    
    @StateObject var profileUploadObserver = ImageUploadingObserver()
    @StateObject var bannerUploadObserver = ImageUploadingObserver()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        let data = damus_state.profiles.lookup(id: damus_state.pubkey)

        _name = State(initialValue: data?.name ?? "")
        _display_name = State(initialValue: data?.display_name ?? "")
        _about = State(initialValue: data?.about ?? "")
        _website = State(initialValue: data?.website ?? "")
        _picture = State(initialValue: data?.picture ?? "")
        _banner = State(initialValue: data?.banner ?? "")
        _nip05 = State(initialValue: data?.nip05 ?? "")
        _ln = State(initialValue: data?.lud16 ?? data?.lud06 ?? "")
    }
    
    func to_profile() -> Profile {
        let new_nip05 = nip05.isEmpty ? nil : nip05
        let new_picture = picture.isEmpty ? nil : picture
        let new_banner = banner.isEmpty ? nil : banner
        let new_lud06 = ln.contains("@") ? nil : ln
        let new_lud16 = ln.contains("@") ? ln : nil

        let profile = Profile(name: name, display_name: display_name, about: about, picture: new_picture, banner: new_banner, website: website, lud06: new_lud06, lud16: new_lud16, nip05: new_nip05, damus_donation: nil)

        return profile
    }
    
    func save() async {
        let profile = to_profile()
        guard let keypair = damus_state.keypair.to_full(),
              let metadata_ev = make_metadata_event(keypair: keypair, metadata: profile)
        else {
            return
        }

        await damus_state.nostrNetwork.postbox.send(metadata_ev)
    }

    func is_ln_valid(ln: String) -> Bool {
        return ln.contains("@") || ln.lowercased().starts(with: "lnurl")
    }
    
    var nip05_parts: NIP05? {
        return NIP05.parse(nip05)
    }
    
    func topSection(topLevelGeo: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                let offset = geo.frame(in: .global).minY
                EditBannerImageView(damus_state: damus_state, viewModel: bannerUploadObserver, callback: uploadedBanner(image_url:), safeAreaInsets: topLevelGeo.safeAreaInsets, banner_image: URL(string: banner))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: offset > 0 ? BANNER_HEIGHT + offset : BANNER_HEIGHT)
                    .clipped()
                    .offset(y: offset > 0 ? -offset : 0) // Pin the top
            }
            .frame(height: BANNER_HEIGHT)
            VStack(alignment: .leading) {
                let pfp_size: CGFloat = 90.0

                HStack(alignment: .center) {
                    EditProfilePictureView(profile_url: URL(string: picture), pubkey: damus_state.pubkey, damus_state: damus_state, size: pfp_size, uploadObserver: profileUploadObserver, callback: uploadedProfilePicture(image_url:))
                        .offset(y: -(pfp_size/2.0)) // Increase if set a frame

                   Spacer()
                }.padding(.bottom,-(pfp_size/2.0))
            }
            .padding(.horizontal,18)
            .padding(.top,BANNER_HEIGHT)
        }
    }
    
    func navImage(img: String) -> some View {
        Image(img)
            .frame(width: 33, height: 33)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
    }
    
    var navBackButton: some View {
        HStack {
            Button {
                if didChange() {
                    confirm_save_alert.toggle()
                } else {
                    presentationMode.wrappedValue.dismiss()
                }
            } label: {
                navImage(img: "chevron-left")
            }
            Spacer()
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            self.content(topLevelGeo: proxy)
        }
    }
    
    func content(topLevelGeo: GeometryProxy) -> some View {
        VStack(alignment: .leading) {
            ScrollView(showsIndicators: false) {
                self.topSection(topLevelGeo: topLevelGeo)
                
                Form {
                    Section(NSLocalizedString("Your Name", comment: "Label for Your Name section of user profile form.")) {
                        let display_name_placeholder = "Satoshi Nakamoto"
                        TextField(display_name_placeholder, text: $display_name)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }
                    
                    Section(NSLocalizedString("Username", comment: "Label for Username section of user profile form.")) {
                        let username_placeholder = "satoshi"
                        TextField(username_placeholder, text: $name)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                        
                    }
                    
                    Section(NSLocalizedString("Website", comment: "Label for Website section of user profile form.")) {
                        TextField(NSLocalizedString("https://jb55.com", comment: "Placeholder example text for website URL for user profile."), text: $website)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }
                    
                    Section(NSLocalizedString("About Me", comment: "Label for About Me section of user profile form.")) {
                        let placeholder = NSLocalizedString("Absolute Boss", comment: "Placeholder text for About Me description.")
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $about)
                                .textInputAutocapitalization(.sentences)
                                .frame(minHeight: 45, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            Text(about.isEmpty ? placeholder : about)
                                .padding(4)
                                .opacity(about.isEmpty ? 1 : 0)
                                .foregroundColor(Color(uiColor: .placeholderText))
                        }
                    }
                    
                    Section(NSLocalizedString("Bitcoin Lightning Tips", comment: "Label for Bitcoin Lightning Tips section of user profile form.")) {
                        TextField(NSLocalizedString("Lightning Address or LNURL", comment: "Placeholder text for entry of Lightning Address or LNURL."), text: $ln)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .onReceive(Just(ln)) { newValue in
                                self.ln = newValue.trimmingCharacters(in: .whitespaces)
                            }
                    }
                    
                    Section(content: {
                        TextField(NSLocalizedString("jb55@jb55.com", comment: "Placeholder example text for identifier used for Nostr addresses."), text: $nip05)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .onReceive(Just(nip05)) { newValue in
                                self.nip05 = newValue.trimmingCharacters(in: .whitespaces)
                            }
                    }, header: {
                        Text("Nostr Address", comment: "Label for the Nostr Address section of user profile form.")
                    }, footer: {
                        switch validate_nostr_address(nip05: nip05_parts, nip05_str: nip05) {
                        case .empty:
                            // without this, the keyboard dismisses unnecessarily when the footer changes state
                            Text("")
                        case .valid:
                            Text("")
                        case .invalid:
                            Text("'\(nip05)' is an invalid Nostr address. It should look like an email address.", comment: "Description of why the Nostr address is invalid.")
                        }
                    })
                    
                    
                }
                .frame(height: Scroll_height)
            }
            
            Button(action: {
                if !ln.isEmpty && !is_ln_valid(ln: ln) {
                    confirm_ln_address = true
                } else {
                    Task {
                        await save()
                        dismiss()
                    }
                }
            }, label: {
                Text(NSLocalizedString("Save", comment: "Button for saving profile."))
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            })
            .buttonStyle(GradientButtonStyle(padding: 15))
            .padding(.horizontal, 10)
            .padding(.bottom, 10 + tabHeight)
            .disabled(!didChange())
            .opacity(!didChange() ? 0.5 : 1)
            .disabled(profileUploadObserver.isLoading || bannerUploadObserver.isLoading)
            .alert(NSLocalizedString("Invalid Tip Address", comment: "Title of alerting as invalid tip address."), isPresented: $confirm_ln_address) {
                Button(NSLocalizedString("Ok", comment: "Button to dismiss the alert.")) {
                }
            } message: {
                Text("The address should either begin with LNURL or should look like an email address.", comment: "Giving the description of the alert message.")
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                navBackButton
            }
        }
        .alert(NSLocalizedString("Discard changes?", comment: "Alert user that changes have been made."), isPresented: $confirm_save_alert) {
            Button(NSLocalizedString("No", comment: "Do not discard changes."), role: .cancel) {
            }
            Button(NSLocalizedString("Yes", comment: "Agree to discard changes made to profile.")) {
                dismiss()
            }
        }
    }
    
    func uploadedProfilePicture(image_url: URL?) {
        picture = image_url?.absoluteString ?? ""
    }
    
    func uploadedBanner(image_url: URL?) {
        banner = image_url?.absoluteString ?? ""
    }
    
    func didChange() -> Bool {
        let data = damus_state.profiles.lookup(id: damus_state.pubkey)
        
        if data?.name ?? "" != name {
            return true
        }
        
        if data?.display_name ?? "" != display_name {
            return true
        }
        
        if data?.about ?? "" != about {
            return true
        }
        
        if data?.website ?? "" != website {
            return true
        }
        
        if data?.picture ?? "" != picture {
            return true
        }
        
        if data?.banner ?? "" != banner {
            return true
        }

        if data?.nip05 ?? "" != nip05 {
            return true
        }
        
        if data?.lud16 ?? data?.lud06 ?? "" != ln {
            return true
        }
        
        return false
    }
}

struct EditMetadataView_Previews: PreviewProvider {
    static var previews: some View {
        EditMetadataView(damus_state: test_damus_state)
    }
}

enum NIP05ValidationResult {
    case empty
    case invalid
    case valid
}

func validate_nostr_address(nip05: NIP05?, nip05_str: String) -> NIP05ValidationResult {
    guard nip05 != nil else {
        // couldn't parse
        if nip05_str.isEmpty {
            return .empty
        } else {
            return .invalid
        }
    }

    // could parse so we valid.
    return .valid
}
