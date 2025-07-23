//
//  DamusPurpleTranslationSetupView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-29.
//

import SwiftUI

fileprivate extension Animation {
    static func content() -> Animation {
        Animation.easeInOut(duration: 1.5).delay(0)
    }
    
    static func delayed_content() -> Animation {
        Animation.easeInOut(duration: 1.5).delay(1)
    }
}

struct DamusPurpleTranslationSetupView: View {
    var damus_state: DamusState
    var next_page: () -> Void
    
    @State var start = false
    @State var show_settings_change_confirmation_dialog = false
    
    // MARK: - Helper functions
    
    func update_user_settings_to_purple() {
        if damus_state.settings.translation_service == .none {
            set_translation_settings_to_purple()
            self.next_page()
        }
        else {
            show_settings_change_confirmation_dialog = true
        }
    }
    
    func set_translation_settings_to_purple() {
        damus_state.settings.translation_service = .purple
        damus_state.settings.auto_translate = true
    }
    
    // MARK: - View layout
    
    var body: some View {
        VStack {
            Image("damus-dark-logo")
                .resizable()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LinearGradient(
                            colors: [DamusColors.lighterPink.opacity(0.8), .white.opacity(0), DamusColors.deepPurple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(radius: 5)
                .padding(20)
                .opacity(start ? 1.0 : 0.0)
                .animation(.content(), value: start)
            
            Text("You unlocked", comment: "Part 1 of 2 in message 'You unlocked automatic translations' the user gets when they sign up for Damus Purple" )
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.black, .black, DamusColors.pink, DamusColors.lighterPink],
                        startPoint: start ? .init(x: -3, y: 4) : .bottomLeading,
                        endPoint: start ? .topTrailing : .init(x: 3, y: -4)
                    )
                )
                .scaleEffect(x: start ? 1 : 0.9, y: start ? 1 : 0.9)
                .opacity(start ? 1.0 : 0.0)
                .animation(.content(), value: start)
            
            Image(systemName: "globe")
                .resizable()
                .frame(width: 96, height: 90)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.black, DamusColors.purple, .white, .white],
                        startPoint: start ? .init(x: -1, y: 1.5) : .bottomLeading,
                        endPoint: start ? .topTrailing : .init(x: 10, y: -11)
                    )
                )
                .animation(Animation.snappy(duration: 2).delay(0), value: start)
                .shadow(
                    color: start ? DamusColors.purple.opacity(0.2) : DamusColors.purple.opacity(0.3),
                    radius: start ? 30 : 10
                )
                .animation(Animation.snappy(duration: 2).delay(0), value: start)
                .scaleEffect(x: start ? 1 : 0.8, y: start ? 1 : 0.8)
                .opacity(start ? 1.0 : 0.0)
                .animation(Animation.snappy(duration: 2).delay(0), value: start)
            
            Text("Automatic translations", comment: "Part 1 of 2 in message 'You unlocked automatic translations' the user gets when they sign up for Damus Purple")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.black, .black, DamusColors.lighterPink, DamusColors.lighterPink],
                        startPoint: start ? .init(x: -3, y: 4) : .bottomLeading,
                        endPoint: start ? .topTrailing : .init(x: 3, y: -4)
                    )
                )
                .scaleEffect(x: start ? 1 : 0.9, y: start ? 1 : 0.9)
                .opacity(start ? 1.0 : 0.0)
                .animation(.content(), value: start)
                .padding(.top, 10)
            
            Text("As part of your Damus Purple membership, you get complimentary and automated translations. Would you like to enable Damus Purple translations?\n\nTip: You can always change this later in Settings → Translations", comment: "Message notifying the user that they get auto-translations as part of their service")
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 20)
                .padding(.top, 50)
                .padding(.bottom, 20)
                .opacity(start ? 1.0 : 0.0)
                .animation(.delayed_content(), value: start)
            
            Button(action: {
                self.update_user_settings_to_purple()
            }, label: {
                HStack {
                    Spacer()
                    Text("Enable Purple auto-translations", comment: "Label for button that allows users to enable Damus Purple translations")
                    Spacer()
                }
            })
            .padding(.horizontal, 30)
            .buttonStyle(GradientButtonStyle())
            .opacity(start ? 1.0 : 0.0)
            .animation(.delayed_content(), value: start)
            
            Button(action: {
                self.next_page()
            }, label: {
                HStack {
                    Spacer()
                    Text("No, thanks", comment: "Label for button that allows users to reject enabling Damus Purple translations")
                    Spacer()
                }
            })
            .padding(.horizontal, 30)
            .foregroundStyle(DamusColors.pink)
            .opacity(start ? 1.0 : 0.0)
            .padding()
            .animation(.delayed_content(), value: start)
        }
        .background(content: {
            ZStack {
                Image("purple-blue-gradient-1")
                    .offset(CGSize(width: 300.0, height: -0.0))
                    .opacity(start ? 1.0 : 0.2)
                    .background(.black)
                Image("stars-bg")
                    .resizable(resizingMode: .stretch)
                    .frame(width: 500, height: 500)
                    .offset(x: -100, y: 50)
                    .scaleEffect(start ? 1 : 0.9)
                    .animation(.content(), value: start)
                Image("purple-blue-gradient-1")
                    .offset(CGSize(width: 300.0, height: -0.0))
                    .opacity(start ? 1.0 : 0.2)
                
            }
        })
        .onAppear(perform: {
            withAnimation(.easeOut(duration: 6), {
                start = true
            })
        })
        .confirmationDialog(
            NSLocalizedString("It seems that you already have a translation service configured. Would you like to switch to Damus Purple as your translator?", comment: "Confirmation dialog question asking users if they want their translation settings to be automatically switched to the Damus Purple translation service"),
            isPresented: $show_settings_change_confirmation_dialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Yes", comment: "User confirm Yes")) {
                set_translation_settings_to_purple()
                self.next_page()
            }.keyboardShortcut(.defaultAction)
            Button(NSLocalizedString("No", comment: "User confirm No"), role: .cancel) {}
        }
    }
}

#Preview {
    DamusPurpleTranslationSetupView(damus_state: test_damus_state, next_page: {})
}
