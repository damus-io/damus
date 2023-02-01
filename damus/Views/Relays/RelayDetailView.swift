//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI

struct RelayDetailView: View {
    let state: DamusState
    let relay: String
    
    @State private var errorString: String?
    @State private var nip11: RelayNIP11?
    
    @State var conn_color: Color
        
    var body: some View {
        Group {
            if let nip11 {
                Form {
                    Section(NSLocalizedString("Admin", comment: "Label to display relay contact user.")) {
                        UserView(damus_state: state, pubkey: nip11.pubkey)
                    }
                    Section(NSLocalizedString("Relay", comment: "Label to display relay address.")) {
                        HStack {
                            Text(relay)
                            Spacer()
                            Circle()
                                .frame(width: 8.0, height: 8.0)
                                .foregroundColor(conn_color)
                        }
                    }
                    Section(NSLocalizedString("Description", comment: "Label to display relay description.")) {
                        Text(nip11.description)
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
            } else if let errorString {
                Text(errorString)
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(nip11?.name ?? "")
        .task {
            var urlString = relay.replacingOccurrences(of: "wss://", with: "https://")
            urlString = urlString.replacingOccurrences(of: "ws://", with: "http://")
            
            guard let url = URL(string: urlString) else {
                return
            }
            
            var request = URLRequest(url: url)
            request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")
            
            var res: (Data, URLResponse)? = nil
            
            do {
                res = try await URLSession.shared.data(for: request)
            } catch {
                errorString = error.localizedDescription
                return
            }
            
            guard let data = res?.0 else {
                errorString = "Relay not responding to metadata request"
                return
            }
            
            do {
                let nip11 = try JSONDecoder().decode(RelayNIP11.self, from: data)
                self.nip11 = nip11
            } catch {
                errorString = error.localizedDescription
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
        RelayDetailView(state: test_damus_state(), relay: "wss://nostr.klabo.blog", conn_color: .green)
    }
}
