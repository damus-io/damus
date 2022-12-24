//
//  ProfileZoomView.swift
//  damus
//
//  Created by scoder1747 on 12/27/22.
//
import SwiftUI

struct ProfileZoomView: View {

    @Environment(\.presentationMode) var presentationMode
    let pubkey: String
    let profiles: Profiles
    let contacts: Contacts

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
            Color("DamusDarkGrey") // Or Color("DamusBlack")
                .edgesIgnoringSafeArea(.all)
            
            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .padding(.leading, 20)
            }
            .zIndex(1)

            VStack(alignment: .center) {

                Spacer()
                
                ProfilePicView(pubkey: pubkey, size: 200.0, highlight: .none, profiles: profiles, contacts: contacts)
                    .padding(100)
                    .scaledToFit()
                    .scaleEffect(self.scale * scaleState)
                    .offset(x: offset.width + offsetState.width, y: offset.height + offsetState.height)
                    .gesture(SimultaneousGesture(zoomGesture, dragGesture))
                    .gesture(doubleTapGesture)
                    .modifier(SwipeToDismissModifier(minDistance: nil, onDismiss: {
                        presentationMode.wrappedValue.dismiss()
                    }))
                
                Spacer()

            }
        }
    }
}

struct ProfileZoomView_Previews: PreviewProvider {
    static let pubkey = "ca48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
    
    static var previews: some View {
        ProfileZoomView(
            pubkey: pubkey,
            profiles: make_preview_profiles(pubkey),
            contacts: Contacts(our_pubkey: pubkey)
        )
    }
}
