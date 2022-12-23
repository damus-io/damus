//
//  EditMetadataView.swift
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

struct EditMetadataView: View {
    let damus_state: DamusState
    @State var display_name: String
    @State var about: String
    @State var picture: String
    @State var nip05: String
    @State var name: String
    @State var lud06: String
    @State var lud16: String
    @State private var showAlert = false
    
    init (damus_state: DamusState) {
        self.damus_state = damus_state
        let data = damus_state.profiles.lookup(id: damus_state.pubkey)
        
        name = data?.name ?? ""
        display_name = data?.display_name ?? ""
        about = data?.about ?? ""
        picture = data?.picture ?? ""
        nip05 = data?.nip05 ?? ""
        lud06 = data?.lud06 ?? ""
        lud16 = data?.lud16 ?? ""
    }
    
    func save() {
        let metadata = NostrMetadata(
            display_name: display_name,
            name: name,
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
            HStack {
                Spacer()
                ProfilePicView(pubkey: damus_state.pubkey, size: PPM_SIZE, highlight: .none, profiles: damus_state.profiles, picture: picture)
                Spacer()
            }
            .padding([.top], 30)
            Form {
                Section("Your Name") {
                    TextField("Satoshi Nakamoto", text: $display_name)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Username") {
                    TextField("satoshi", text: $name)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)

                }
                
                Section ("Profile Picture") {
                    TextField("https://example.com/pic.jpg", text: $picture)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)

                }
                
                Section("About Me") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $about)
                            .textInputAutocapitalization(.sentences)
                        if about.isEmpty {
                            Text("Absolute boss")
                                .offset(x: 0, y: 7)
                                .foregroundColor(Color(uiColor: .placeholderText))
                        }
                    }
                }
                
                Section(content: {
                    TextField("Lightning Address", text: $lud16)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    TextField("LNURL", text: $lud06)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }, header: {
                    Text("Bitcoin Lightning Tips")
                }, footer: {
                    Text("Only one needs to be set")
                })
                                
                Section(content: {
                    TextField("example.com", text: $nip05)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }, header: {
                    Text("NIP-05 Verification")
                }, footer: {
                    Text("\(name)@\(nip05) will be used for verification")
                })
                
                Button("Save") {
                    save()
                    showAlert = true
                }.alert(isPresented: $showAlert) {
                    Alert(title: Text("Saved"), message: Text("Your metadata has been saved."), dismissButton: .default(Text("OK")))
                }
            }
        }
    }
}

struct EditMetadataView_Previews: PreviewProvider {
    static var previews: some View {
        EditMetadataView(damus_state: test_damus_state())
    }
}
