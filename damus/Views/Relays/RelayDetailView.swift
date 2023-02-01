//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI
import WrappingHStack

struct RelayDetailView: View {
    let relay: String
    
    @State private var networkError: String?
    @State private var nip11: RelayNIP11?

    var body: some View {
        Group {
            if let nip11 {
                VStack(alignment: .leading, spacing: 8) {
                    
                    RelayDetailItemView(label: NSLocalizedString("Name", comment: "Label to display relay name."), detail: nip11.name)
                    RelayDetailItemView(label: NSLocalizedString("Relay", comment: "Label to display relay address."), detail: relay)
                    RelayDetailItemView(label: NSLocalizedString("Description", comment: "Label to display relay description."), detail: nip11.description)
                    RelayDetailItemView(label: NSLocalizedString("Public Key", comment: "Label to display relay contact public key."), detail: nip11.pubkey)
                    RelayDetailItemView(label: NSLocalizedString("Contact", comment: "Label to display relay contact information."), detail: nip11.contact)
                    RelayDetailItemView(label: NSLocalizedString("Software", comment: "Label to display relay software."), detail: nip11.software)
                    
                    Text(NSLocalizedString("Supported NIPs", comment: "Label to display relay's supported NIPs."))
                        .font(.subheadline.weight(.bold))
                    
                    WrappingHStack(nip11.supported_nips, id: \.self) { nip in
                        RelayNIPDetailView(nip: nip)
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
}

struct RelayNIPDetailView: View {
    let nip: Int
    
    @Environment(\.openURL) var openURL
    
    var body: some View {
        Button {
            if let url = NIPURLBuilder.url(forNIP: nip) {
                openURL(url)
            }
        } label: {
            Text("\(nip)")
                .font(.body)
                .foregroundColor(.white)
                .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5))
                .background(.purple)
        }
    }
}

struct RelayDetailItemView: View {
    let label: String
    let detail: String
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.bold))
            Spacer()
            Text(detail)
                .font(.caption)
        }
    }
}

struct RelayDetailView_Previews: PreviewProvider {
    static var previews: some View {
        RelayDetailView(relay: "wss://nostr.klabo.blog")
    }
}
