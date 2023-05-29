//
//  EULAView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

let eula = """
**End User License Agreement**

**Introduction**

This End User License Agreement ("EULA") is a legal agreement between you and Damus Nostr Inc. for the use of our mobile application Damus. By installing, accessing, or using our application, you agree to be bound by the terms and conditions of this EULA.

**Prohibited Content and Conduct**

You agree not to use our application to create, upload, post, send, or store any content that:

* Is illegal, infringing, or fraudulent
* Is defamatory, libelous, or threatening
* Is pornographic, obscene, or offensive
* Is discriminatory or promotes hate speech
* Is harmful to minors
* Is intended to harass or bully others
* Is intended to impersonate others

**You also agree not to engage in any conduct that:**

* Harasses or bullies others
* Impersonates others
* Is intended to intimidate or threaten others
* Is intended to promote or incite violence

**Consequences of Violation**

Any violation of this EULA, including the prohibited content and conduct outlined above, may result in the termination of your access to our application.

**Disclaimer of Warranties and Limitation of Liability**

Our application is provided "as is" and "as available" without warranty of any kind, either express or implied, including but not limited to the implied warranties of merchantability and fitness for a particular purpose. We do not guarantee that our application will be uninterrupted or error-free. In no event shall Damus Nostr Inc. be liable for any damages whatsoever, including but not limited to direct, indirect, special, incidental, or consequential damages, arising out of or in connection with the use or inability to use our application.

**Changes to EULA**

We reserve the right to update or modify this EULA at any time and without prior notice. Your continued use of our application following any changes to this EULA will be deemed to be your acceptance of such changes.

**Contact Information**

If you have any questions about this EULA, please contact us at damus@jb55.com

**Acceptance of Terms**

By using our Application, you signify your acceptance of this EULA. If you do not agree to this EULA, you may not use our Application.

"""

struct EULAView: View {
    @State private var login = false
    @State var accepted = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            ScrollView {
                NavigationLink(destination: LoginView(accepted: $accepted), isActive: $login) {
                    EmptyView()
                }
                
                Text(Markdown.parse(content: eula))
                    .padding()
            }
            .padding(EdgeInsets(top: 20, leading: 10, bottom: 50, trailing: 10))
            
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Text("Reject", comment:  "Button to reject the end user license agreement, which disallows the user from being let into the app.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 75, maxHeight: 12, alignment: .center)
                        .padding()
                        .foregroundColor(Color.white)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(DamusColors.darkGrey, strokeBorder: DamusColors.mediumGrey, lineWidth: 1)
                        }
                    }
                    
                    Button(action: {
                        accepted = true
                        login.toggle()
                    }) {
                        HStack {
                            Text("Accept", comment:  "Button to accept the end user license agreement before being allowed into the app.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 75, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                }
                .padding(.trailing, 30)
            }
        }
        .background(
            Image("eula-bg")
                .resizable()
                .blur(radius: 70)
                .ignoresSafeArea(),
            alignment: .top
        )
        .navigationTitle("EULA")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
    }
}

struct EULAView_Previews: PreviewProvider {
    static var previews: some View {
        EULAView()
    }
}
