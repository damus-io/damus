//
//  CreateAccountView.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI
import Combine

struct CreateAccountView: View, KeyboardReadable {
    @StateObject var account: CreateAccountModel = CreateAccountModel()
    @StateObject var profileUploadObserver = ImageUploadingObserver()
    var nav: NavigationCoordinator
    @State var keyboardVisible: Bool = false
    @State var showPrivateKeyWarning: Bool = false
    let maxViewportHeightForAdaptiveContentSize: CGFloat = 975 // 956px height = iPhone 16 Pro Max
    
    func SignupForm<FormContent: View>(@ViewBuilder content: () -> FormContent) -> some View {
        return VStack(alignment: .leading, spacing: 10.0, content: content)
    }
    
    func regen_key() {
        let keypair = generate_new_keypair()
        self.account.pubkey = keypair.pubkey
        self.account.privkey = keypair.privkey
    }

    /// Checks whether any signup field contains what appears to be a private key.
    ///
    /// Reads `account.name` and `account.about`, splits each on whitespace, and
    /// calls `containsPrivateKeyMaterial` on every token.  Returns `true` as soon
    /// as any token matches; returns `false` if none do.
    func fieldsContainPrivateKey() -> Bool {
        let fieldsToCheck = [account.name, account.about]
        for field in fieldsToCheck {
            for token in field.components(separatedBy: .whitespaces) {
                if containsPrivateKeyMaterial(token) {
                    return true
                }
            }
        }
        return false
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                Spacer()

                VStack(alignment: .center) {
                    let screenHeight = UIScreen.main.bounds.height
                    let style = EditPictureControl.Style(
                        size: keyboardVisible && screenHeight < maxViewportHeightForAdaptiveContentSize ? 25 : 75,
                        first_time_setup: true
                    )

                    EditPictureControl(
                        uploader: MediaUploader.nostrBuild,
                        context: .profile_picture,
                        keypair: account.keypair,
                        pubkey: account.pubkey,
                        style: style,
                        current_image_url: $account.profile_image,
                        upload_observer: profileUploadObserver,
                        callback: uploadedProfilePicture
                    )
                        .shadow(radius: 2)
                }
                
                SignupForm {
                    FormLabel(NSLocalizedString("Name", comment: "Label to prompt name entry."), optional: false)
                        .foregroundColor(DamusColors.neutral6)
                    FormTextInput(NSLocalizedString("Satoshi Nakamoto", comment: "Name of Bitcoin creator(s)."), text: $account.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_name_field.rawValue)
                    
                    FormLabel(NSLocalizedString("Bio", comment: "Label to prompt bio entry for user to describe themself."), optional: true)
                        .foregroundColor(DamusColors.neutral6)
                    FormTextInput(NSLocalizedString("Absolute legend.", comment: "Example Bio"), text: $account.about)
                        .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_bio_field.rawValue)
                }
                .padding(.top, 25)
                
                Button(action: {
                    if fieldsContainPrivateKey() {
                        showPrivateKeyWarning = true
                    } else {
                        nav.push(route: Route.SaveKeys(account: account))
                    }
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
                .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_next_button.rawValue)
                .alert(
                    NSLocalizedString("Private Key Detected", comment: "Alert title warning that a private key was found in a signup field."),
                    isPresented: $showPrivateKeyWarning
                ) {
                    Button(NSLocalizedString("Go Back", comment: "Alert button to go back and remove the private key from the signup field."), role: .cancel) {
                        showPrivateKeyWarning = false
                    }
                    Button(NSLocalizedString("Continue Anyway", comment: "Alert button to continue signup even though a private key may be present in a field."), role: .destructive) {
                        nav.push(route: Route.SaveKeys(account: account))
                    }
                } message: {
                    Text("One of your profile fields appears to contain a private key (nsec or hex). Sharing your private key publicly will compromise your account. Please go back and remove it.", comment: "Alert message warning the user that their private key may have been entered into a profile field during signup.")
                }
                
                LoginPrompt()
                    .padding(.top)
                
                Spacer()
            }
            .padding()
        }
        .background(DamusBackground(maxHeight: UIScreen.main.bounds.size.height/2), alignment: .top)
        .dismissKeyboardOnTap()
        .onReceive(keyboardPublisher) { visible in
            withAnimation {
                self.keyboardVisible = visible
            }
        }
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

/// Returns `true` when `text` looks like a private key that should not appear in a profile field.
///
/// Two patterns are matched:
/// - A bech32-encoded private key whose HRP is "nsec" (e.g. `nsec1…`).
/// - A 64-character hexadecimal string (any case), which is the raw representation
///   of a 256-bit private key.
func containsPrivateKeyMaterial(_ text: String) -> Bool {
    // Bech32-encoded private key (nsec1…)
    if let key = decode_bech32_key(text), case .sec = key {
        return true
    }
    // Raw hex private key: exactly 64 hex characters
    if text.count == 64, hex_decode(text) != nil {
        return true
    }
    return false
}

