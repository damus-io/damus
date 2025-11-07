//
//  DamusLabsExpirements.swift
//  damus
//
//  Created by eric on 10/24/25.
//

import SwiftUI

struct DamusLabsExpirements: View {
    
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @State var show_live_explainer: Bool = false
    
    var body: some View {
        ScrollView {
            
            LabsLogoView()
            
            VStack(alignment: .leading, spacing: 30) {
                PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("As a subscriber, you’re getting an early look at new and innovative tools. These are beta features — still being tested and tuned. Try them out, share your thoughts, and help us perfect what’s next.", comment: "Damus Labs explainer"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                
                HStack {
                    Spacer()
                    Text(NSLocalizedString("More features coming soon!", comment: ""))
                        .font(.title2)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .padding(.bottom, 2)
                    Spacer()
                }
                .padding(15)
                .background(DamusColors.black)
                .cornerRadius(15)
                .padding(.top, 10)
                
                LabsToggleView(toggleName: "Live", systemImage: "record.circle", isOn: $settings.live, showInfo: $show_live_explainer)

            }
            .padding([.trailing, .leading], 20)
            .padding(.bottom, 50)
            
            Image("damooseLabs")
                .resizable()
                .aspectRatio(contentMode: .fill)
            
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $show_live_explainer) {
            LabsExplainerView(
                labName: "Live",
                systemImage: "record.circle",
                labDescription: "This will allow you to see all the real-time live streams happening on Nostr! As well as let you view and interact in the Live Chat. Please keep in mind this is still a work in progress and issues are expected. When enabled you will see the Live option in your side menu.")
        }

    }
}

#Preview {
    PurpleBackdrop {
        DamusLabsExpirements(damus_state: test_damus_state, settings: test_damus_state.settings)
    }
}
