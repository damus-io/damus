//
//  IconLabel.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI
import UIKit

struct IconLabel: View {
    let text: String
    let img_name: String
    let img_color: Color
    
    init(_ text: String, img_name: String, color: Color) {
        self.text = text
        self.img_name = img_name
        self.img_color = color
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: img_name)
                .foregroundColor(img_color)
                .frame(width: 20)
                .padding([.trailing], 20)
            Text(text)
        }
    }}

struct IconLabel_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            Section {
                IconLabel(NSLocalizedString("Keys", comment: "Settings section for managing keys"), img_name: "key.fill", color: .orange)
            
                IconLabel(NSLocalizedString("Local Notifications", comment: "Section header for damus local notifications user configuration"), img_name: "bell.fill", color: .blue)
            
                IconLabel(NSLocalizedString("Appearance", comment: "Section header for text and appearance settings"), img_name: "textformat", color: .red)
            }
        }
    }
}
