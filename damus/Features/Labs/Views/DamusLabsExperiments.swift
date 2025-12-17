//
//  DamusLabsExpirements.swift
//  damus
//
//  Created by eric on 10/24/25.
//

import SwiftUI

struct DamusLabsExperiments: View {
    
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @State var show_live_explainer: Bool = false
    @State var show_favorites_explainer: Bool = false
    @State var show_client_tag_explainer: Bool = false
    
    let live_label = NSLocalizedString("Live", comment: "Label for a toggle that enables an experimental feature")
    let favorites_label = NSLocalizedString("Favorites", comment: "Label for a toggle that enables an experimental feature")
    let client_tag_label = NSLocalizedString("Client Tags", comment: "Label for a toggle that enables an experimental feature")
    
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
                
                LabsToggleView(toggleName: live_label, systemImage: "record.circle", isOn: $settings.live, showInfo: $show_live_explainer)
                LabsToggleView(toggleName: favorites_label, systemImage: "heart.fill", isOn: $settings.enable_favourites_feature, showInfo: $show_favorites_explainer)
                LabsToggleView(toggleName: client_tag_label, systemImage: "tag", isOn: $settings.enable_client_tag_labels, showInfo: $show_client_tag_explainer)

            }
            .padding([.trailing, .leading], 20)
            .padding(.bottom, 50)
            
            Image("damooseLabs")
                .resizable()
                .accessibilityHidden(true)
                .aspectRatio(contentMode: .fill)
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $show_live_explainer) {
            LabsExplainerView(
                labName: live_label,
                systemImage: "record.circle",
                labDescription: NSLocalizedString("This will allow you to see all the real-time live streams happening on Nostr! As well as let you view and interact in the Live Chat. Please keep in mind this is still a work in progress and issues are expected. When enabled you will see the Live option in your side menu.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_favorites_explainer) {
            LabsExplainerView(
                labName: favorites_label,
                systemImage: "heart.fill",
                labDescription: NSLocalizedString("This will allow you to pick users to be part of your favorites list. You can also switch your profile timeline to only see posts from your favorite contacts.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_client_tag_explainer) {
            LabsExplainerView(
                labName: client_tag_label,
                systemImage: "tag",
                labDescription: NSLocalizedString("This adds a \"via ClientName\" indicator beside timestamps so you can see which nostr app posted an event. Expect occasional missing data while we continue improving client tag detection.", comment: "Damus Labs feature explanation"))
        }
    }
}

#Preview {
    PurpleBackdrop {
        DamusLabsExperiments(damus_state: test_damus_state, settings: test_damus_state.settings)
    }
}
