//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI

struct RelayDetailView: View {
    let relay: String
    
    @State private var networkError: String?
    @State private var nip11: RelayNIP11?
    
    var body: some View {
        Group {
            if let nip11 {
                VStack(alignment: .leading) {
                    Form {
                        Section(NSLocalizedString("Name", comment: "Label to display relay name.")) {
                            Text(nip11.name)
                        }
                        Section(NSLocalizedString("Relay", comment: "Label to display relay address.")) {
                            Text(relay)
                        }
                        Section(NSLocalizedString("Description", comment: "Label to display relay description.")) {
                            Text(nip11.description)
                        }
                        Section(NSLocalizedString("Public Key", comment: "Label to display relay contact public key.")) {
                            Text(nip11.pubkey)
                        }
                        Section(NSLocalizedString("Contact", comment: "Label to display relay contact information.")) {
                            Text(nip11.contact)
                        }
                        Section(NSLocalizedString("Software", comment: "Label to display relay software.")) {
                            Text(nip11.software)
                        }
                        Section(NSLocalizedString("Version", comment: "Label to display relay software version.")) {
                            Text(nip11.version)
                        }
                        Section(NSLocalizedString("Supported NIPs", comment: "Label to display relay's supported NIPs.")) {
                            Text(nipsList(nips: nip11.supported_nips))
                        }
                    }
                }
                .padding()
            } else if let networkError {
                Text(networkError)
                    .foregroundColor(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(nip11?.name ?? "")
        .onAppear {
            let urlString = relay.replacingOccurrences(of: "wss://", with: "https://")
            if let url = URL(string: urlString) {
                var request = URLRequest(url: url)
                request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    
                    if error != nil {
                        networkError = error?.localizedDescription
                    }
                    
                    guard let data else {
                        return
                    }
                    
                    let nip11 = try? JSONDecoder().decode(RelayNIP11.self, from: data)
                    self.nip11 = nip11
                }
                task.resume()
            }
        }
    }
    
    private func nipsList(nips: [Int]) -> AttributedString {
        var attrString = AttributedString()
        let lastNipIndex = nips.count - 1
        for (index, nip) in nips.enumerated() {
            if let link = NIPURLBuilder.url(forNIP: nip) {
                let nipString = NIPURLBuilder.formatNipNumber(nip: nip)
                var nipAttrString = AttributedString(stringLiteral: nipString)
                nipAttrString.link = link
                attrString = attrString + nipAttrString
                if index < lastNipIndex {
                    attrString = attrString + AttributedString(stringLiteral: ", ")
                }
            }
        }
        return attrString
    }
}

struct RelayDetailView_Previews: PreviewProvider {
    static var previews: some View {
        RelayDetailView(relay: "wss://nostr.klabo.blog")
    }
}
