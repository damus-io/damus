//
//  EndBlock.swift
//  damus
//
//  Created by William Casarin on 2022-08-08.
//

import SwiftUI

struct EndBlock: View {
    let height: CGFloat
    
    init () {
        self.height = 80.0
    }
    
    init (height: Float) {
        self.height = CGFloat(height)
    }
    
    var body: some View {
        Color.white.opacity(0)
            .id("endblock")
            .frame(height: height)
    }
}

struct EndBlock_Previews: PreviewProvider {
    static var previews: some View {
        EndBlock()
    }
}
