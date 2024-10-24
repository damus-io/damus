//
//  CreateAccountView.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct CreateAccountView: View {
    @StateObject var account: CreateAccountModel = CreateAccountModel()
    @StateObject var profileUploadObserver = ImageUploadingObserver()
    var nav: NavigationCoordinator
    
    func SignupForm<FormContent: View>(@ViewBuilder content: () -> FormContent) -> some View {
        return VStack(alignment: .leading, spacing: 10.0, content: content)
    }
    
    func regen_key() {
        let keypair = generate_new_keypair()
        self.account.pubkey = keypair.pubkey
        self.account.privkey = keypair.privkey
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                Spacer()
                VStack(alignment: .center) {
                   
                    EditPictureControl(uploader: .nostrBuild, keypair: account.keypair, pubkey: account.pubkey, size: 75, setup: true, image_url: $account.profile_image , uploadObserver: profileUploadObserver, callback: uploadedProfilePicture)
                        .shadow(radius: 2)
                        .padding(.top, 100)
                    
                    Text("Add Photo", comment: "Label to indicate user can add a photo.")
                        .bold()
                        .foregroundColor(DamusColors.neutral6)
                }
                
                SignupForm {
                    FormLabel(NSLocalizedString("Name", comment: "Label to prompt name entry."), optional: false)
                        .foregroundColor(DamusColors.neutral6)
                    FormTextInput(NSLocalizedString("Satoshi Nakamoto", comment: "Name of Bitcoin creator(s)."), text: $account.name)
                        .textInputAutocapitalization(.words)

                    FormLabel(NSLocalizedString("Bio", comment: "Label to prompt bio entry for user to describe themself."), optional: true)
                        .foregroundColor(DamusColors.neutral6)
                    FormTextInput(NSLocalizedString("Absolute legend.", comment: "Example Bio"), text: $account.about)
                }
                .padding(.top, 25)

                Button(action: {
                    nav.push(route: Route.SaveKeys(account: account))
                }) {
                    HStack {
                        Text("Next", comment: "Button to continue with account creation.")
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(profileUploadObserver.isLoading || account.name.isEmpty)
                .opacity(profileUploadObserver.isLoading || account.name.isEmpty ? 0.5 : 1)
                .padding(.top, 20)
                
                LoginPrompt()
                    .padding(.top)
                
                Spacer()
            }
            .padding()
        }
        .background(DamusBackground(maxHeight: UIScreen.main.bounds.size.height/2), alignment: .top)
        .dismissKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
    }
    
    func uploadedProfilePicture(image_url: URL?) {
        account.profile_image = image_url
    }
}

struct LoginPrompt: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        HStack {
            Text("Already on Nostr?", comment: "Ask the user if they already have an account on Nostr")
                .foregroundColor(DamusColors.neutral6)

            Button(NSLocalizedString("Login", comment: "Button to navigate to login view.")) {
                self.dismiss()
            }

            Spacer()
        }
    }
}

struct BackNav: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Image("chevron-left")
            .foregroundColor(DamusColors.adaptableBlack)
            .onTapGesture {
                self.dismiss()
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CreateAccountModel(display_name: "", name: "jb55", about: "")
        return CreateAccountView(account: model, nav: .init())
    }
}

func FormTextInput(_ title: String, text: Binding<String>) -> some View {
    return TextField("", text: text)
        .placeholder(when: text.wrappedValue.isEmpty) {
            Text(title).foregroundColor(.gray.opacity(0.5))
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.gray.opacity(0.5), lineWidth: 1)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundColor(.damusAdaptableWhite)
                }
        }
        .font(.body.bold())
}

func FormLabel(_ title: String, optional: Bool = false) -> some View {
    return HStack {
        Text(title)
                .bold()
        if optional {
            Text("optional", comment: "Label indicating that a form input is optional.")
                .font(.callout)
                .foregroundColor(DamusColors.mediumGrey)
        } else {
            Text("required", comment: "Label indicating that a form input is required.")
                .font(.callout)
                .foregroundColor(DamusColors.mediumGrey)
        }
    }
}

