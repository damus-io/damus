//
//  DamusLabsExpirements.swift
//  damus
//
//  Created by eric on 10/24/25.
//

import SwiftUI


struct DamusLabsExpirements: View {
    
    let damus_state: DamusState
    
    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 30) {
                PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("As a subscriber, you’re getting an early look at new and innovative tools. These are beta features — still being tested and tuned. Try them out, share your thoughts, and help us perfect what’s next.", comment: "Damus Labs explainer"))
                    .multilineTextAlignment(.center)
                
                
                HStack {
                    Spacer()
                    Text("Features coming soon!")
                        .font(.title2)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .padding(.bottom, 2)
                    Spacer()
                }
                .padding(15)
                .background(DamusColors.neutral6)
                .cornerRadius(15)
                .padding(.top, 10)
                
            }
            .padding([.trailing, .leading], 30)
            .padding(.bottom, 20)
            
            Image("damooseLabs")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}


#Preview {
    PurpleBackdrop {
        DamusLabsExpirements(damus_state: test_damus_state)
    }
}
