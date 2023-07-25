//
//  EditMetadataView.swift
//  damus
//
//  Created by Thomas Tastet on 23/12/2022.
//

import SwiftUI
import Combine

let BANNER_HEIGHT: CGFloat = 150.0;

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
    let profile: Profile?
    
    @Environment(\.dismiss) var dismiss

    @State var confirm_ln_address: Bool = false
    
    @StateObject var profileUploadObserver = ImageUploadingObserver()
    @StateObject var bannerUploadObserver = ImageUploadingObserver()
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        let data = damus_state.profiles.lookup(id: damus_state.pubkey)
        self.profile = data
        
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
        let profile = self.profile ?? Profile()
        
        profile.name = name
        profile.display_name = display_name
        profile.about = about
        profile.website = website
        profile.nip05 = nip05.isEmpty ? nil : nip05
        profile.picture = picture.isEmpty ? nil : picture
        profile.banner = banner.isEmpty ? nil : banner
        profile.lud06 = ln.contains("@") ? nil : ln
        profile.lud16 = ln.contains("@") ? ln : nil
        
        return profile
    }
    
    func save() {
        let profile = to_profile()
        guard let keypair = damus_state.keypair.to_full(),
              let metadata_ev = make_metadata_event(keypair: keypair, metadata: profile)
        else {
            return
        }

        damus_state.postbox.send(metadata_ev)
    }

    func is_ln_valid(ln: String) -> Bool {
        return ln.contains("@") || ln.lowercased().starts(with: "lnurl")
    }
    
    var nip05_parts: NIP05? {
        return NIP05.parse(nip05)
    }
    
    var TopSection: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                EditBannerImageView(damus_state: damus_state, viewModel: bannerUploadObserver, callback: uploadedBanner(image_url:))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: BANNER_HEIGHT)
                    .clipped()
            }.frame(height: BANNER_HEIGHT)
            VStack(alignment: .leading) {
                let pfp_size: CGFloat = 90.0

                HStack(alignment: .center) {
                    EditProfilePictureView(pubkey: damus_state.pubkey, damus_state: damus_state, size: pfp_size, uploadObserver: profileUploadObserver, callback: uploadedProfilePicture(image_url:))
                        .offset(y: -(pfp_size/2.0)) // Increase if set a frame

                   Spacer()
                }.padding(.bottom,-(pfp_size/2.0))
            }
            .padding(.horizontal,18)
            .padding(.top,BANNER_HEIGHT)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            TopSection
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
                
                Section (NSLocalizedString("Profile Picture", comment: "Label for Profile Picture section of user profile form.")) {
                    TextField(NSLocalizedString("https://example.com/pic.jpg", comment: "Placeholder example text for profile picture URL."), text: $picture)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section (NSLocalizedString("Banner Image", comment: "Label for Banner Image section of user profile form.")) {
                                    TextField(NSLocalizedString("https://example.com/pic.jpg", comment: "Placeholder example text for profile picture URL."), text: $banner)
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
                            .frame(minHeight: 20, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        Text(about.isEmpty ? placeholder : about)
                            .padding(.leading, 4)
                            .opacity(about.isEmpty ? 1 : 0)
                            .foregroundColor(Color(uiColor: .placeholderText))
                    }
                }
                
                Section(NSLocalizedString("Bitcoin Lightning Tips", comment: "Label for Bitcoin Lightning Tips section of user profile form.")) {
                    TextField(NSLocalizedString("Lightning Address or LNURL", comment: "Placeholder text for entry of Lightning Address or LNURL."), text: $ln)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
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

                Button(NSLocalizedString("Save", comment: "Button for saving profile.")) {
                    if !ln.isEmpty && !is_ln_valid(ln: ln) {
                        confirm_ln_address = true
                    } else {
                        save()
                        dismiss()
                    }
                }
                .disabled(profileUploadObserver.isLoading || bannerUploadObserver.isLoading)
                .alert(NSLocalizedString("Invalid Tip Address", comment: "Title of alerting as invalid tip address."), isPresented: $confirm_ln_address) {
                    Button(NSLocalizedString("Ok", comment: "Button to dismiss the alert.")) {
                    }
                } message: {
                    Text("The address should either begin with LNURL or should look like an email address.", comment: "Giving the description of the alert message.")
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
    }
    
    func uploadedProfilePicture(image_url: URL?) {
        picture = image_url?.absoluteString ?? ""
    }
    
    func uploadedBanner(image_url: URL?) {
        banner = image_url?.absoluteString ?? ""
    }
}

struct EditMetadataView_Previews: PreviewProvider {
    static var previews: some View {
        EditMetadataView(damus_state: test_damus_state())
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
