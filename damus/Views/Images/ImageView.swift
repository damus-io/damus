//
//  ImageView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI

struct ImageView: View {
    let video_controller: VideoController
    let urls: [MediaUrl]
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedIndex = 0
    @State var showMenu = true
    
    let settings: UserSettingsStore
    
    var tabViewIndicator: some View {
        HStack(spacing: 10) {
            ForEach(urls.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color(UIColor.label) : Color.secondary)
                    .frame(width: 7, height: 7)
                    .onTapGesture {
                        selectedIndex = index
                    }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(Capsule())
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(urls.indices, id: \.self) { index in
                    ZoomableScrollView {
                        ImageContainerView(video_controller: video_controller, url: urls[index], settings: settings)
                            .aspectRatio(contentMode: .fit)
                            .padding(.top, Theme.safeAreaInsets?.top)
                            .padding(.bottom, Theme.safeAreaInsets?.bottom)
                    }
                    .modifier(SwipeToDismissModifier(minDistance: 50, onDismiss: {
                        presentationMode.wrappedValue.dismiss()
                    }))
                    .ignoresSafeArea()
                    .tag(index)
                }
            }
            .ignoresSafeArea()
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .gesture(TapGesture(count: 2).onEnded {
                // Prevents menu from hiding on double tap
            })
            .gesture(TapGesture(count: 1).onEnded {
                showMenu.toggle()
            })
            .overlay(
                GeometryReader { geo in
                    VStack {
                        if showMenu {
                            NavDismissBarView()
                            Spacer()
                            
                            if (urls.count > 1) {
                                tabViewIndicator
                            }
                        }
                    }
                    .animation(.easeInOut, value: showMenu)
                    .padding(.bottom, geo.safeAreaInsets.bottom == 0 ? 12 : 0)
                }
            )
        }
    }
}

struct ImageView_Previews: PreviewProvider {
    static var previews: some View {
        let url: MediaUrl = .image(URL(string: "https://jb55.com/red-me.jpg")!)
        ImageView(video_controller: test_damus_state.video, urls: [url], settings: test_damus_state.settings)
    }
}
