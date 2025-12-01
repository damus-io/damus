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
    @State var show_vines_explainer: Bool = false
    @State var show_vine_prefetch_explainer: Bool = false
    
    let live_label = NSLocalizedString("Live", comment: "Label for a toggle that enables an experimental feature")
    let favorites_label = NSLocalizedString("Favorites", comment: "Label for a toggle that enables an experimental feature")
    let vines_label = NSLocalizedString("Vines", comment: "Label for a toggle that enables an experimental feature")
    let vines_prefetch_label = NSLocalizedString("Prefetch vines on cellular", comment: "Label for a toggle that allows vine prefetching on cellular.")
    
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
                LabsToggleView(toggleName: vines_label, systemImage: "video", isOn: $settings.enable_vine_feature, showInfo: $show_vines_explainer)
                if settings.enable_vine_feature {
                    LabsToggleView(toggleName: vines_prefetch_label, systemImage: "antenna.radiowaves.left.and.right", isOn: $settings.prefetch_vines_on_cellular, showInfo: $show_vine_prefetch_explainer)
                }

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
        .sheet(isPresented: $show_vines_explainer) {
            LabsExplainerView(
                labName: vines_label,
                systemImage: "video",
                labDescription: NSLocalizedString("Enables the Vines tab so you can browse short Divine videos inside Damus. This is still experimental and requires the Divine relay.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_vine_prefetch_explainer) {
            LabsExplainerView(
                labName: vines_prefetch_label,
                systemImage: "antenna.radiowaves.left.and.right",
                labDescription: NSLocalizedString("Prefetches upcoming Vines even on cellular connections. This may use additional mobile data.", comment: "Explainer for Vine cellular prefetch toggle."))
        }
    }
}

#Preview {
    PurpleBackdrop {
        DamusLabsExperiments(damus_state: test_damus_state, settings: test_damus_state.settings)
    }
}
