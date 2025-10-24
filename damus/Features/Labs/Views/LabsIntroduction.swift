//
//  LabsIntroduction.swift
//  damus
//
//  Created by eric on 10/17/25.
//

import SwiftUI


struct LabsIntroductionView: View {
    
    let damus_state: DamusState
    
    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 30) {
                PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Purple subscribers get first access to new and experimental features — fresh ideas straight from the lab.", comment: "Damus purple subscription pitch"))
                    .multilineTextAlignment(.center)
                
                HStack {
                    NavigationLink(destination: DamusPurpleView(damus_state: damus_state)) {
                        HStack(spacing: 10) {
                            Spacer()
                            Text("Learn more about Purple")
                                .foregroundColor(Color.white)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(PinkGradient)
                        }
                    }
                }
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
        LabsIntroductionView(damus_state: test_damus_state)
    }
}
