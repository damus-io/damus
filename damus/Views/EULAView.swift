//
//  EULAView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct EULAView: View {
    var state: SetupState?
    @Environment(\.dismiss) var dismiss
    @State var accepted = false

    var body: some View {
        ZStack {
            DamusGradient()
            
            ScrollView {
                //Text("End User License Agreement", comment: "Label indicating that the below text is the EULA, an acronym for End User License Agreement.")
                //    .font(.title.bold())
                //    .foregroundColor(.white)
                
                Divider()
                
                // Introduction
                Group {
                    Text("Introduction")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    Text("This End User License Agreement (EULA) is a legal agreement between you and Damus Nostr Inc. for the use of our mobile application Damus. By installing, accessing, or using our application, you agree to be bound by the terms and conditions of this EULA.")
                        .padding()
                }

                // Prohibited Content and Conduct
                Group {
                    Text("Prohibited Content and Conduct")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text("You agree not to use our application to create, upload, post, send, or store any content that:")
                    
                    VStack(alignment:.leading) {
                        Label("Is illegal, infringing, or fraudulent",systemImage: "exclamationmark.square")
                        Label("Is defamatory, libelous, or threatening",systemImage: "exclamationmark.square")
                        Label("Is pornographic, obscene, or offensive",systemImage: "exclamationmark.square")
                        Label("Is discriminatory or promotes hate speech",systemImage: "exclamationmark.square")
                        Label("Is harmful to minors",systemImage: "exclamationmark.square")
                        Label("Is intended to harass or bully others",systemImage: "exclamationmark.square")
                        Label("Is intended to impersonate others",systemImage: "exclamationmark.square")
                    }
                    .padding()
                    
                    Text("You also agree not to engage in any conduct that:")
                    
                    VStack(alignment:.leading) {
                        Label("Harasses or bullies others",systemImage: "exclamationmark.square")
                        Label("Impersonates others",systemImage: "exclamationmark.square")
                        Label("Is intended to intimidate or threaten others",systemImage: "exclamationmark.square")
                        Label("Is intended to promote or incite violence",systemImage: "exclamationmark.square")
                    }
                    .padding()
                }
                
                // Consequences of Violation
                Group {
                    Text("Consequences of Violation")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text("Any violation of this EULA, including the prohibited content and conduct outlined above, may result in the termination of your access to our application.")
                    .padding()
                }

                // Disclaimer of Warranties and Limitation of Liability
                Group {
                    Text("Disclaimer of Warranties and Limitation of Liability")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text("Our application is provided \"as is\" and \"as available\" without warranty of any kind, either express or implied, including but not limited to the implied warranties of merchantability and fitness for a particular purpose. We do not guarantee that our application will be uninterrupted or error-free. In no event shall Damus Nostr Inc. be liable for any damages whatsoever, including but not limited to direct, indirect, special, incidental, or consequential damages, arising out of or in connection with the use or inability to use our application.")
                    .padding()
                }

                // Changes to EULA
                Group {
                    Text("Changes to EULA")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text("We reserve the right to update or modify this EULA at any time and without prior notice. Your continued use of our application following any changes to this EULA will be deemed to be your acceptance of such changes.")
                    .padding()
                }

                // Contact information
                Group {
                    Text("Contact Information")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text("If you have any questions about this EULA, please contact us at damus@jb55.com")
                        .padding()
                }

                // Acceptance of Terms
                Group {
                    Text("Acceptance of Terms")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text("By using our Application, you signify your acceptance of this EULA. If you do not agree to this EULA, you may not use our Application.")
                    .padding()
                }

                if state == .create_account {
                    NavigationLink(destination: CreateAccountView(), isActive: $accepted) {
                        EmptyView()
                    }
                } else {
                    NavigationLink(destination: LoginView(), isActive: $accepted) {
                        EmptyView()
                    }
                }
                
                // Buttons
                Group {
                    DamusWhiteButton(NSLocalizedString("Accept", comment: "Button to accept the end user license agreement before being allowed into the app.")) {
                        accepted = true
                    }
                    .padding()
                    
                    DamusWhiteButton(NSLocalizedString("Reject", comment: "Button to reject the end user license agreement, which disallows the user from being let into the app.")) {
                        dismiss()
                    }
                    .padding()
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
        .foregroundColor(.white)
    }
}

struct EULAView_Previews: PreviewProvider {
    static var previews: some View {
        EULAView()
    }
}
