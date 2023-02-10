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
    let nip11: RelayMetadata
    
    @State private var errorString: String?
    @State var conn_color: Color
    
    @Environment(\.dismiss) var dismiss
    
    func FieldText(_ str: String?) -> some View {
        Text(str ?? "No data available")
    }
    
    var body: some View {
        Group {
            if let nip11 {
                Form {
                    if let pubkey = nip11.pubkey {
                        Section(NSLocalizedString("Admin", comment: "Label to display relay contact user.")) {
                            UserView(damus_state: state, pubkey: pubkey)
                        }
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
                        FieldText(nip11.description)
                    }
                    Section(NSLocalizedString("Contact", comment: "Label to display relay contact information.")) {
                        FieldText(nip11.contact)
                    }
                    Section(NSLocalizedString("Software", comment: "Label to display relay software.")) {
                        FieldText(nip11.software)
                    }
                    Section(NSLocalizedString("Version", comment: "Label to display relay software version.")) {
                        FieldText(nip11.version)
                    }
                    if let nips = nip11.supported_nips, nips.count > 0 {
                        Section(NSLocalizedString("Supported NIPs", comment: "Label to display relay's supported NIPs.")) {
                            Text(nipsList(nips: nips))
                        }
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
        .onReceive(handle_notify(.switched_timeline)) { notif in
            dismiss()
        }
        .navigationTitle(nip11.name ?? "")
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
        let metadata = RelayMetadata(name: "name", description: "desc", pubkey: "pubkey", contact: "contact", supported_nips: [1,2,3], software: "software", version: "version", limitation: Limitations.empty)
        RelayDetailView(state: test_damus_state(), relay: "relay", nip11: metadata, conn_color: .green)
    }
}
