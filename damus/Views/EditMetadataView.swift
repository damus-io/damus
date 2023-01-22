//
//  EditMetadataView.swift
//  damus
//
//  Created by Thomas Tastet on 23/12/2022.
//

import SwiftUI

let PPM_SIZE: CGFloat = 80.0
let BANNER_HEIGHT: CGFloat = 150.0;

func isHttpsUrl(_ string: String) -> Bool {
    let urlRegEx = "^https://.*$"
    let urlTest = NSPredicate(format:"SELF MATCHES %@", urlRegEx)
    return urlTest.evaluate(with: string)
}

func isImage(_ urlString: String) -> Bool {
    let imageTypes = ["image/jpg", "image/jpeg", "image/png", "image/gif", "image/tiff", "image/bmp", "image/webp"]

    guard let url = URL(string: urlString) else {
        return false
    }

    var result = false
    let semaphore = DispatchSemaphore(value: 0)

    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            print(error)
            semaphore.signal()
            return
        }

        guard let httpResponse = response as? HTTPURLResponse,
              let contentType = httpResponse.allHeaderFields["Content-Type"] as? String else {
            semaphore.signal()
            return
        }

        if imageTypes.contains(contentType.lowercased()) {
            result = true
        }

        semaphore.signal()
    }

    task.resume()
    semaphore.wait()

    return result
}

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
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    init (damus_state: DamusState) {
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
    
    func imageBorderColor() -> Color {
            colorScheme == .light ? Color("DamusWhite") : Color("DamusBlack")
        }
    
    func save() {
        let metadata = NostrMetadata(
            display_name: display_name,
            name: name,
            about: about,
            website: website,
            nip05: nip05.isEmpty ? nil : nip05,
            picture: picture.isEmpty ? nil : picture,
            banner: banner.isEmpty ? nil : banner,
            lud06: ln.contains("@") ? nil : ln,
            lud16: ln.contains("@") ? ln : nil
        );
        
        let m_metadata_ev = make_metadata_event(keypair: damus_state.keypair, metadata: metadata)
        
        if let metadata_ev = m_metadata_ev {
            damus_state.pool.send(.event(metadata_ev))
        }
    }
    
    var nip05_parts: NIP05? {
        return NIP05.parse(nip05)
    }
    
    var TopSection: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                BannerImageView(pubkey: damus_state.pubkey, profiles: damus_state.profiles)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: BANNER_HEIGHT)
                    .clipped()
            }.frame(height: BANNER_HEIGHT)
            VStack(alignment: .leading) {
                let pfp_size: CGFloat = 90.0

                HStack(alignment: .center) {
                    ProfilePicView(pubkey: damus_state.pubkey, size: pfp_size, highlight: .custom(imageBorderColor(), 4.0), profiles: damus_state.profiles)
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
                    TextField("Satoshi Nakamoto", text: $display_name)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section(NSLocalizedString("Username", comment: "Label for Username section of user profile form.")) {
                    TextField("satoshi", text: $name)
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
                    TextField(NSLocalizedString("jb55@jb55.com", comment: "Placeholder example text for identifier used for NIP-05 verification."), text: $nip05)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }, header: {
                    Text("NIP-05 Verification", comment: "Label for NIP-05 Verification section of user profile form.")
                }, footer: {
                    if let parts = nip05_parts {
                        Text("'\(parts.username)' at '\(parts.host)' will be used for verification", comment: "Description of how the nip05 identifier would be used for verification.")
                    } else {
                        Text("'\(nip05)' is an invalid nip05 identifier. It should look like an email.", comment: "Description of why the nip05 identifier is invalid.")
                    }
                })

                Button(NSLocalizedString("Save", comment: "Button for saving profile.")) {
                    save()
                    dismiss()
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct EditMetadataView_Previews: PreviewProvider {
    static var previews: some View {
        EditMetadataView(damus_state: test_damus_state())
    }
}
