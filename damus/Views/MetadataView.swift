//
//  MetadataView.swift
//  damus
//
//  Created by Thomas Tastet on 23/12/2022.
//

import SwiftUI

let PPM_SIZE: CGFloat = 80.0

func isHttpsUrl(_ string: String) -> Bool {
    let urlRegEx = "^https://.*$"
    let urlTest = NSPredicate(format:"SELF MATCHES %@", urlRegEx)
    return urlTest.evaluate(with: string)
}

func isImage(_ urlString: String) -> Bool {
    let imageTypes = ["image/jpg", "image/jpeg", "image/png", "image/gif", "image/tiff", "image/bmp"]

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

struct MetadataView: View {
    let damus_state: DamusState
    @State var name: String = ""
    @State var about: String = ""
    @State var picture: String = ""
    @State var nip05: String = ""
    @State var nickname: String = ""
    @State var lud06: String = ""
    @State var lud16: String = ""
    @State private var showAlert = false
    
    // Image preview
    @State var profiles = Profiles()
    @State private var timer: Timer?
    
    @StateObject var profileModel: ProfileModel
    
    func save() {
        let metadata = NostrMetadata(
            display_name: name,
            name: nickname,
            about: about,
            website: nil,
            nip05: nip05.isEmpty ? nil : nip05,
            picture: picture.isEmpty ? nil : picture,
            lud06: lud06.isEmpty ? nil : lud06,
            lud16: lud16.isEmpty ? nil : lud16
        );
        
        let m_metadata_ev = make_metadata_event(keypair: damus_state.keypair, metadata: metadata)
        
        if let metadata_ev = m_metadata_ev {
            damus_state.pool.send(.event(metadata_ev))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Form {
                HStack {
                    Spacer()
                    ProfilePicView(pubkey: "0", size: PPM_SIZE, highlight: .none, profiles: profiles)
                    Spacer()
                }
                Section("Your Nostr Profile") {
                    TextField("Your username", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("Your @", text: $nickname)
                        .textInputAutocapitalization(.never)
                    TextField("Profile Picture Url", text: $picture)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: picture) { newValue in
                            self.timer?.invalidate()
                            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
                                profiles = Profiles()
                                let tmp_profile = Profile(name: "0", display_name: "0", about: "0", picture: isHttpsUrl(picture) && isImage(picture) ? picture : nil, website: nil, nip05: "", lud06: nil, lud16: nil)
                                let ts_profile = TimestampedProfile(profile: tmp_profile, timestamp: 0)
                                profiles.add(id: "0", profile: ts_profile)
                            }
                        }
                    TextField("NIP-05 Verification Domain (eg: example.com)", text: $nip05)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Description") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $about)
                            .textInputAutocapitalization(.sentences)
                        if about.isEmpty {
                            Text("Type your description here...")
                                .offset(x: 0, y: 7)
                                .foregroundColor(Color(uiColor: .placeholderText))
                        }
                    }
                }
                
                Section("Advanced") {
                    TextField("LNURL", text: $lud06)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    TextField("LN Address", text: $lud16)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                
                Button("Save") {
                    save()
                    showAlert = true
                }.alert(isPresented: $showAlert) {
                    Alert(title: Text("Saved"), message: Text("Your metadata has been saved."), dismissButton: .default(Text("OK")))
                }
            }
        }
        .onAppear() {
            profileModel.subscribe()
            
            let data = damus_state.profiles.lookup(id: profileModel.pubkey)
            
            name = data?.display_name ?? name
            nickname = data?.name ?? name
            about = data?.about ?? about
            picture = data?.picture ?? picture
            nip05 = data?.nip05 ?? nip05
            lud06 = data?.lud06 ?? lud06
            lud16 = data?.lud16 ?? lud16
        }
        .onDisappear {
            profileModel.unsubscribe()
        }
    }
}

struct MetadataView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        let profile_model = ProfileModel(pubkey: ds.pubkey, damus: ds)
        MetadataView(damus_state: ds, profileModel: profile_model)
    }
}
