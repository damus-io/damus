//
//  DamusPurpleMarketingContentView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import SwiftUI

extension DamusPurpleView {
    struct MarketingContentView: View {
        let purple: DamusPurple
        
        var body: some View {
            VStack(alignment: .leading, spacing: 30) {
                PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Help us stay independent in our mission for Freedom tech with our Purple subscription, and look cool doing it!", comment: "Damus purple subscription pitch"))
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 20) {
                    PurpleViewPrimitives.IconOnBoxView(name: "heart.fill")
                    
                    VStack(alignment: .leading) {
                        PurpleViewPrimitives.TitleView(text: NSLocalizedString("Help Build The Future", comment: "Title for funding future damus development"))
                        
                        PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Support Damus development to help build the future of decentralized communication on the web.", comment: "Reason for supporting damus development"))
                    }
                }
                
                HStack(spacing: 20) {
                    PurpleViewPrimitives.IconOnBoxView(name: "ai-3-stars.fill")
                    
                    VStack(alignment: .leading) {
                        PurpleViewPrimitives.TitleView(text: NSLocalizedString("Exclusive features", comment: "Features only available on subscription service"))
                            .padding(.bottom, -3)
                        
                        HStack(spacing: 3) {
                            Image("calendar")
                                .resizable()
                                .frame(width: 15, height: 15)
                            
                            Text(NSLocalizedString("Coming soon", comment: "Feature is still in development and will be available soon"))
                                .font(.caption)
                                .bold()
                        }
                        .foregroundColor(DamusColors.pink)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(DamusColors.lightBackgroundPink)
                        .cornerRadius(30.0)
                        
                        PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Be the first to access upcoming premium features: Automatic translations, longer note storage, and more", comment: "Description of new features to be expected"))
                            .padding(.top, 3)
                    }
                }
                
                HStack(spacing: 20) {
                    PurpleViewPrimitives.IconOnBoxView(name: "badge")
                    
                    VStack(alignment: .leading) {
                        PurpleViewPrimitives.TitleView(text: NSLocalizedString("Supporter Badge", comment: "Title for supporter badge"))
                        
                        PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Get a special badge on your profile to show everyone your contribution to Freedom tech", comment: "Supporter badge description"))
                    }
                }
                
                HStack {
                    Spacer()
                    Link(
                        purple.enable_purple_iap_support ?
                            NSLocalizedString("Learn more about the features", comment: "Label for a link to the Damus website, to allow the user to learn more about the features of Purple")
                            :
                            NSLocalizedString("Coming soon! Visit our website to learn more", comment: "Label announcing Purple, and inviting the user to learn more on the website"),
                        destination: purple.environment.damus_website_url()
                    )
                    .foregroundColor(DamusColors.pink)
                    .padding()
                    Spacer()
                }
                
            }
            .padding([.trailing, .leading], 30)
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    DamusPurpleView.MarketingContentView(purple: test_damus_state.purple)
}
