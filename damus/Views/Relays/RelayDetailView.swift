//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI

struct RelayDetailView: View {
    let relay: String
    
    @State private var networkError = false
    @State private var nip11: RelayNIP11?
    
    var body: some View {
        Group {
            if let nip11 {
                VStack {
                    Text(relay)
                    Text(nip11.name)
                    Text(nip11.description)
                    Text(nip11.pubkey)
                    Text(nip11.contact)
                    Text(nip11.software)
                    HStack {
                        ForEach(nip11.supported_nips, id: \.self) { nip in
                            Text("\(nip)")
                        }
                    }
                }
            } else if networkError{
                Text("error")
            } else {
                ProgressView()
            }
        }
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

struct RelayDetailView_Previews: PreviewProvider {
    static var previews: some View {
        RelayDetailView(relay: "wss://nostr.klabo.blog")
    }
}
