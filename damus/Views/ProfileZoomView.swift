//
//  ProfileZoomView.swift
//  damus
//
//  Created by Swift on 12/27/22.
//

import SwiftUI

struct ProfileZoomView: View {

    @Environment(\.presentationMode) var presentationMode
    let pubkey: String
    let profiles: Profiles


    @GestureState private var scaleState: CGFloat = 1
    @GestureState private var offsetState = CGSize.zero

    @State private var offset = CGSize.zero
    @State private var scale: CGFloat = 1

    func resetStatus(){
        self.offset = CGSize.zero
        self.scale = 1
    }


    var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($scaleState) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                scale *= value
            }
    }

    var dragGesture: some Gesture {
        DragGesture()
            .updating($offsetState) { currentState, gestureState, _ in
                gestureState = currentState.translation
            }.onEnded { value in
                offset.height += value.translation.height
                offset.width += value.translation.width
            }
    }

    var doubleTapGesture : some Gesture {
        TapGesture(count: 2).onEnded { value in
            resetStatus()
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .top, endPoint: .bottom)
                .edgesIgnoringSafeArea(.all)

            HStack() {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                        .frame(width: 40, height: 40)
                        .padding(20)
                }
            }
            .zIndex(1)

            VStack(alignment: .center) {
                Spacer()
                    .frame(height: 120)

                ProfilePicView(pubkey: pubkey, size: 200.0, highlight: .none, profiles: profiles)
                    .padding(100)
                    .scaledToFit()
                    .scaleEffect(self.scale * scaleState)
                    .offset(x: offset.width + offsetState.width, y: offset.height + offsetState.height)
                    .gesture(SimultaneousGesture(zoomGesture, dragGesture))
                    .gesture(doubleTapGesture)

            }
        }
    }
}
