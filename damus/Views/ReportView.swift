//
//  ReportView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct ReportView: View {
    let pool: RelayPool
    let target: ReportTarget
    let privkey: String
     
    @State var report_sent: Bool = false
    @State var report_id: String = ""
    
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
    
    func do_send_report(type: ReportType) {
        guard let ev = send_report(privkey: privkey, pool: pool, target: target, type: type) else {
            return
        }
        
        guard let note_id = bech32_note_id(ev.id) else {
            return
        }
        
        report_sent = true
        report_id = note_id
    }
    
    var MainForm: some View {
        VStack {
            
            Text("Report", comment: "Label indicating that the current view is for the user to report content.")
                .font(.headline)
                .padding()
            
        Form {
            Section(content: {
                Button(NSLocalizedString("It's spam", comment: "Button for user to report that the account or content has spam.")) {
                    do_send_report(type: .spam)
                }
                
                Button(NSLocalizedString("Nudity or explicit content", comment: "Button for user to report that the account or content has nudity or explicit content.")) {
                    do_send_report(type: .explicit)
                }
                
                       Button(NSLocalizedString("Illegal content", comment: "Button for user to report that the account or content has illegal content.")) {
                    do_send_report(type: .illegal)
                }
                
                if case .user = target {
                    Button(NSLocalizedString("They are impersonating someone", comment: "Button for user to report that the account is impersonating someone.")) {
                        do_send_report(type: .impersonation)
                    }
                }
            }, header: {
                Text("What do you want to report?", comment: "Header text to prompt user what issue they want to report.")
            }, footer: {
                Text("Your report will be sent to the relays you are connected to", comment: "Footer text to inform user what will happen when the report is submitted.")
            })
        }
        }
    }
}

func send_report(privkey: String, pool: RelayPool, target: ReportTarget, type: ReportType) -> NostrEvent? {
    let report = Report(type: type, target: target, message: "")
    guard let ev = create_report_event(privkey: privkey, report: report) else {
        return nil
    }
    pool.send(.event(ev))
    return ev
}

struct ReportView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        VStack {
        
        ReportView(pool: ds.pool, target: ReportTarget.user(""), privkey: "")
        
            ReportView(pool: ds.pool, target: ReportTarget.user(""), privkey: "", report_sent: true, report_id: "report_id")
            
        }
    }
}
