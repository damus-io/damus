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
    
    @State private var networkError = false
    @State private var nip11: RelayNIP11?
    
    var body: some View {
        Group {
            if let nip11 {
                VStack(alignment: .leading, spacing: 8) {
                    
                    RelayDetailItemView(label: "Name", detail: nip11.name)
                    RelayDetailItemView(label: "Relay", detail: relay)
                    RelayDetailItemView(label: "Description", detail: nip11.description)
                    RelayDetailItemView(label: "Public Key", detail: nip11.pubkey)
                    RelayDetailItemView(label: "Contact", detail: nip11.contact)
                    RelayDetailItemView(label: "Software", detail: nip11.software)
                    
                    Text("Supported NIPs")
                        .font(.subheadline.weight(.bold))
                    
                    WrappingHStack(nip11.supported_nips, id: \.self) { nip in
                        RelayNIPDetailView(nip: nip)
                    }
                }
                .padding()
            } else if networkError {
                Text("error")
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
                        networkError = true
                    }
                    
                    guard let data else {
                        return
                    }
                    
                    do {
                        let decoder = JSONDecoder()
                        let nip11 = try? decoder.decode(RelayNIP11.self, from: data)
                        self.nip11 = nip11
                    } catch {
                        print(data, response, error)
                    }
                }
                task.resume()
            }
        }
    }
}

struct RelayNIPDetailView: View {
    let nip: Int
    var body: some View {
        
        Button {
            print("GO TO NIP")
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
