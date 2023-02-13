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
                Text(NSLocalizedString("End User License Agreement", comment: "Title of the EULA page"))
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                // Introduction
                Group {
                    Text(NSLocalizedString("Introduction", comment:"Introduction heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                         Text(NSLocalizedString("This End User License Agreement (EULA) is a legal agreement between you and Damus Nostr Inc. for the use of our mobile application Damus. By installing, accessing, or using our application, you agree to be bound by the terms and conditions of this EULA.", comment: "Introduction paragraph in the EULA"))
                        .padding()
                }

                // Prohibited Content and Conduct
                Group {
                    Text(NSLocalizedString("Prohibited Content and Conduct", comment: "Prohibited Content and Conduct heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text(NSLocalizedString("You agree not to use our application to create, upload, post, send, or store any content that:", comment: "First paragraph of the Prohibited Content and Conduct heading in the EULA"))

                    VStack(alignment:.leading) {
                        Label(NSLocalizedString("Is illegal, infringing, or fraudulent", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is defamatory, libelous, or threatening", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is pornographic, obscene, or offensive", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is discriminatory or promotes hate speech", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is harmful to minors", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is intended to harass or bully others", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is intended to impersonate others", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                    }
                    .padding()
                    
                    Text(NSLocalizedString("You also agree not to engage in any conduct that:",comment: "Second paragraph of the Prohibited Content and Conduct heading in the EULA"))
                    
                    VStack(alignment:.leading) {
                        Label(NSLocalizedString("Harasses or bullies others", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Impersonates others", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is intended to intimidate or threaten others", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                        Label(NSLocalizedString("Is intended to promote or incite violence", comment: "Bullet point in EULA"),systemImage: "exclamationmark.square")
                    }
                    .padding()
                }
                
                // Consequences of Violation
                Group {
                    Text(NSLocalizedString("Consequences of Violation",comment: "Consequences of Violation heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text(NSLocalizedString("Any violation of this EULA, including the prohibited content and conduct outlined above, may result in the termination of your access to our application.", comment: "Consequences of Violation paragraph in the EULA"))
                    .padding()
                }

                // Disclaimer of Warranties and Limitation of Liability
                Group {
                    Text(NSLocalizedString("Disclaimer of Warranties and Limitation of Liability", comment: "Disclaimer of Warranties and Limitation of Liability heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text(NSLocalizedString("Our application is provided \"as is\" and \"as available\" without warranty of any kind, either express or implied, including but not limited to the implied warranties of merchantability and fitness for a particular purpose. We do not guarantee that our application will be uninterrupted or error-free. In no event shall Damus Nostr Inc. be liable for any damages whatsoever, including but not limited to direct, indirect, special, incidental, or consequential damages, arising out of or in connection with the use or inability to use our application.", comment: "Disclaimer of Warranties and Limitation of Liability paragraph in the EULA"))
                    .padding()
                }

                // Changes to EULA
                Group {
                    Text(NSLocalizedString("Changes to EULA",comment:"Changes to EULA heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                         Text(NSLocalizedString("We reserve the right to update or modify this EULA at any time and without prior notice. Your continued use of our application following any changes to this EULA will be deemed to be your acceptance of such changes.", comment:"Changes to EULA paragraph in the EULA"))
                    .padding()
                }

                // Contact information
                Group {
                        Text(NSLocalizedString("Contact Information",comment:"Contact Information heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                    Text(NSLocalizedString("If you have any questions about this EULA, please contact us at damus@jb55.com",comment:"Contact Information paragraph in the EULA"))
                        .padding()
                }

                // Acceptance of Terms
                Group {
                        Text(NSLocalizedString("Acceptance of Terms",comment:"Acceptance of Terms heading in the EULA"))
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    
                        Text(NSLocalizedString("By using our Application, you signify your acceptance of this EULA. If you do not agree to this EULA, you may not use our Application.",comment: "Acceptance of Terms paragraph in the EULA"))
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
