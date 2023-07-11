//
//  RelativeTime.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct RelativeTime: View {
    @ObservedObject var time: RelativeTimeModel
    
    var body: some View {
        Text(verbatim: "\(time.value)")
            .font(.system(size: 16))
            .foregroundColor(.gray)
    }
}


struct RelativeTime_Previews: PreviewProvider {
    static var previews: some View {
        RelativeTime(time: RelativeTimeModel())
    }
}
