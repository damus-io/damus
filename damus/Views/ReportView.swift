//
//  ReportView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

fileprivate extension ReportTarget {
    func reportTags(type: ReportType) -> [[String]] {
        switch self {
        case .user(let pubkey):
            return [["p", pubkey.hex(), type.rawValue]]
        case .note(let notet):
            return [["e", notet.note_id.hex(), type.rawValue],
                    ["p", notet.pubkey.hex()]]
        }
    }
}

struct ReportView: View {
    let postbox: PostBox
    let target: ReportTarget
    let keypair: FullKeypair

    @State var report_sent: Bool = false
    @State var report_id: String = ""
    @State var report_message: String = ""
    @State var selected_report_type: ReportType?
    
    var body: some View {
        if report_sent {
            Success
        } else {
            MainForm
        }
    }
    
    var Success: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("Report sent!", comment: "Message indicating that a report was successfully sent to relay servers.")
                .font(.headline)
            
            Text("Relays have been notified and clients will be able to use this information to filter content. Thank you!", comment: "Description of what was done as a result of sending a report to relay servers.")
            
            Text("Report ID:", comment: "Label indicating that the text underneath is the identifier of the report that was sent to relay servers.")
            
            Text(report_id)
            
            Button(NSLocalizedString("Copy Report ID", comment: "Button to copy report ID.")) {
                UIPasteboard.general.string = report_id
                let g = UIImpactFeedbackGenerator(style: .medium)
                g.impactOccurred()
            }
        }
        .padding()
    }
    
    func do_send_report() {
        guard let selected_report_type,
              let ev = NostrEvent(content: report_message, keypair: keypair.to_keypair(), kind: 1984, tags: target.reportTags(type: selected_report_type)) else {
            return
        }
        
        postbox.send(ev)
        
        report_sent = true
        report_id = bech32_note_id(ev.id)
    }

    var send_report_button_text: String {
        switch target {
        case .note:
            return NSLocalizedString("Report Note", comment: "Button to report a note.")
        case .user:
            return NSLocalizedString("Report User", comment: "Button to report a user.")
        }
    }
    
    var MainForm: some View {
        VStack {
            
            Text("Report", comment: "Label indicating that the current view is for the user to report content.")
                .font(.headline)
                .padding()
            
            Form {
                Section(content: {
                    Picker("", selection: $selected_report_type) {
                        ForEach(ReportType.allCases, id: \.self) { report_type in
                            // Impersonation type is not supported when reporting notes.
                            switch target {
                            case .note:
                                if report_type != .impersonation {
                                    Text(verbatim: String(describing: report_type))
                                        .tag(Optional(report_type))
                                }
                            case .user:
                                Text(verbatim: String(describing: report_type))
                                    .tag(Optional(report_type))
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }, header: {
                    Text("What do you want to report?", comment: "Header text to prompt user what issue they want to report.")
                })

                Section(content: {
                    TextField(NSLocalizedString("Optional", comment: "Prompt to enter optional additional information when reporting an account or content."), text: $report_message, axis: .vertical)
                }, header: {
                    Text("Additional information", comment: "Header text to prompt user to optionally provide additional information when reporting a user or note.")
                })

                Section(content: {
                    Button(send_report_button_text) {
                        do_send_report()
                    }
                    .disabled(selected_report_type == nil)
                }, footer: {
                    Text("Your report will be sent to the relays you are connected to", comment: "Footer text to inform user what will happen when the report is submitted.")
                })
            }
        }
    }
}

struct ReportView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        VStack {
        
            ReportView(postbox: ds.postbox, target: ReportTarget.user(test_pubkey), keypair: test_keypair.to_full()!)

            ReportView(postbox: ds.postbox, target: ReportTarget.user(test_pubkey), keypair: test_keypair.to_full()!, report_sent: true, report_id: "report_id")

        }
    }
}
