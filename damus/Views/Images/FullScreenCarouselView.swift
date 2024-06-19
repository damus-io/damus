//
//  FullScreenCarouselView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI

struct FullScreenCarouselView<Content: View>: View {
    let video_controller: VideoController
    let urls: [MediaUrl]
    
    @Environment(\.presentationMode) var presentationMode
    
    @State var showMenu = true
    
    let settings: UserSettingsStore
    @Binding var selectedIndex: Int
    let content: (() -> Content)?
    
    init(video_controller: VideoController, urls: [MediaUrl], showMenu: Bool = true, settings: UserSettingsStore, selectedIndex: Binding<Int>, @ViewBuilder content: @escaping () -> Content) {
        self.video_controller = video_controller
        self.urls = urls
        self._showMenu = State(initialValue: showMenu)
        self.settings = settings
        _selectedIndex = selectedIndex
        self.content = content
    }
    
    init(video_controller: VideoController, urls: [MediaUrl], showMenu: Bool = true, settings: UserSettingsStore, selectedIndex: Binding<Int>) {
        self.video_controller = video_controller
        self.urls = urls
        self._showMenu = State(initialValue: showMenu)
        self.settings = settings
        _selectedIndex = selectedIndex
        self.content = nil
    }
    
    var background: some ShapeStyle {
        if case .video = urls[safe: selectedIndex] {
            return AnyShapeStyle(Color.black)
        }
        else {
            return AnyShapeStyle(.regularMaterial)
        }
    }
    
    var background_color: UIColor {
        return .black
    }
    
    var body: some View {
        ZStack {
            Color(self.background_color)
                .ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(urls.indices, id: \.self) { index in
                    VStack {
                        if case .video = urls[safe: index] {
                            ImageContainerView(video_controller: video_controller, url: urls[index], settings: settings)
                                .clipped()  // SwiftUI hack from https://stackoverflow.com/a/74401288 to make playback controls show up within the TabView
                                .aspectRatio(contentMode: .fit)
                                .padding(.top, Theme.safeAreaInsets?.top)
                                .padding(.bottom, Theme.safeAreaInsets?.bottom)
                                .modifier(SwipeToDismissModifier(minDistance: 50, onDismiss: {
                                    presentationMode.wrappedValue.dismiss()
                                }))
                                .ignoresSafeArea()
                        }
                        else {
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
                        }
                    }.tag(index)
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
                            NavDismissBarView(showBackgroundCircle: false)
                                .foregroundColor(.white)
                            Spacer()
                            
                            if urls.count > 1 {
                                PageControlView(currentPage: $selectedIndex, numberOfPages: urls.count)
                                    .frame(maxWidth: 0, maxHeight: 0)
                                    .padding(.top, 5)
                            }
                            
                            self.content?()
                        }
                    }
                    .animation(.easeInOut, value: showMenu)
                    .padding(.bottom, geo.safeAreaInsets.bottom == 0 ? 12 : 0)
                }
            )
        }
    }
}

fileprivate struct FullScreenCarouselPreviewView<Content: View>: View {
    @State var selectedIndex: Int = 0
    let url: MediaUrl = .image(URL(string: "https://jb55.com/red-me.jpg")!)
    let test_video_url: MediaUrl = .video(URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!)
    let custom_content: (() -> Content)?
    
    init(content: (() -> Content)? = nil) {
        self.custom_content = content
    }
    
    var body: some View {
        FullScreenCarouselView(video_controller: test_damus_state.video, urls: [test_video_url, url], settings: test_damus_state.settings, selectedIndex: $selectedIndex) {
            self.custom_content?()
        }
            .environmentObject(OrientationTracker())
    }
}

struct FullScreenCarouselView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FullScreenCarouselPreviewView<AnyView>()
                .previewDisplayName("No custom content on overlay")
            
            FullScreenCarouselPreviewView(content: {
                HStack {
                    Spacer()
                    
                    Text(verbatim: "Some content")
                        .padding()
                        .foregroundColor(.white)
                        
                    Spacer()
                }.background(.ultraThinMaterial)
            })
                .previewDisplayName("Custom content on overlay")
        }
    }
}
