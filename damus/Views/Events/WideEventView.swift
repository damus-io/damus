//
//  WideEventView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI

struct WideEventView: View {
    let event: NostrEvent
    
    var body: some View {
        EmptyView()
    }
}

struct WideEventView_Previews: PreviewProvider {
    static var previews: some View {
        WideEventView(event: test_event)
    }
}
