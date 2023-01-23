//
//  MagnificationGestureView.swift
//  damus
//
//  Created by user232838 on 1/5/23.
//

import SwiftUI

struct MagnificationGestureView: View {
    
    @GestureState var magnifyBy = 1.0

    var magnification: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { currentState, gestureState, transaction in
                gestureState = currentState
            }
    }
    
    var body: some View {
        Circle()
            .frame(width: 100, height: 100)
            .scaleEffect(magnifyBy)
            .gesture(magnification)
    }
}

struct MagnificationGestureView_Previews: PreviewProvider {
    static var previews: some View {
        MagnificationGestureView()
    }
}
