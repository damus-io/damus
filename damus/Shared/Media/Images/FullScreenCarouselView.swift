//
//  FullScreenCarouselView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI

struct FullScreenCarouselView<Content: View>: View {
    @ObservedObject var video_coordinator: DamusVideoCoordinator
    let urls: [MediaUrl]
    
    @Environment(\.presentationMode) var presentationMode
    
    @State var showMenu = true
    @State private var imageDict: [URL: UIImage] = [:]
    let settings: UserSettingsStore
    @ObservedObject var carouselSelection: CarouselSelection
    let content: (() -> Content)?
    
    init(video_coordinator: DamusVideoCoordinator, urls: [MediaUrl], showMenu: Bool = true, settings: UserSettingsStore, selectedIndex: Binding<Int>, @ViewBuilder content: @escaping () -> Content) {
        self.video_coordinator = video_coordinator
        self.urls = urls
        self._showMenu = State(initialValue: showMenu)
        self.settings = settings
        self._carouselSelection = ObservedObject(initialValue: CarouselSelection(index: selectedIndex.wrappedValue))
        self.content = content
    }
    
    init(video_coordinator: DamusVideoCoordinator, urls: [MediaUrl], showMenu: Bool = true, settings: UserSettingsStore, selectedIndex: Binding<Int>) {
        self.video_coordinator = video_coordinator
        self.urls = urls
        self._showMenu = State(initialValue: showMenu)
        self.settings = settings
        self._carouselSelection = ObservedObject(initialValue: CarouselSelection(index: selectedIndex.wrappedValue))
        self.content = nil
    }
    
    var background: some ShapeStyle {
        if case .video = urls[safe: carouselSelection.index] {
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
            
            TabView(selection: $carouselSelection.index) {
                ForEach(urls.indices, id: \.self) { index in
                    VStack {
                        if case .video = urls[safe: index] {
                            ImageContainerView(
                                video_coordinator: video_coordinator,
                                url: urls[index],
                                settings: settings,
                                imageDict: $imageDict
                            )
                            .modifier(SwipeToDismissModifier(minDistance: 50, onDismiss: {
                                presentationMode.wrappedValue.dismiss()
                            }))
                            .ignoresSafeArea()
                        }
                        else {
                            ZoomableScrollView {
                                ImageContainerView(video_coordinator: video_coordinator, url: urls[index], settings: settings, imageDict: $imageDict)
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
                            HStack {
                                Button(action: {
                                    presentationMode.wrappedValue.dismiss()
                                }, label: {
                                    Image(systemName: "xmark")
                                        .frame(width: 44, height: 44)
                                })
                                .buttonStyle(PlayerCircleButtonStyle())
                                .accessibilityLabel(Text("Close video"))
                                .accessibilityHint(Text("Returns to the previous view"))
                                
                                Spacer()

                                if let url = urls[safe: carouselSelection.index],
                                   let image = imageDict[url.url] {
                                    
                                    ShareLink(item: Image(uiImage: image),
                                              preview: SharePreview(NSLocalizedString("Shared Picture",
                                                                                      comment: "Label for the preview of the image being picture"),
                                                                    image: Image(uiImage: image))) {
                                        Image(systemName: "ellipsis")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(PlayerCircleButtonStyle())
                                    .accessibilityLabel(Text("Share image"))
                                    .accessibilityHint(Text("Opens sharing options for this item"))
                                }
                            }
                            .padding()
                            
                            Spacer()
                            
                            VStack {
                                if urls.count > 1 {
                                    PageControlView(currentPage: $carouselSelection.index, numberOfPages: urls.count)
                                        .frame(maxWidth: 0, maxHeight: 0)
                                        .padding(.top, 5)
                                }
                                
                                if let focused_video = video_coordinator.focused_video {
                                    DamusVideoControlsView(video: focused_video)
                                }
                                
                                self.content?()
                            }
                            .padding(.top, 5)
                            .background(Color.black.opacity(0.7))
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
        FullScreenCarouselView(video_coordinator: test_damus_state.video, urls: [test_video_url, url], settings: test_damus_state.settings, selectedIndex: $selectedIndex) {
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

/// Class to define object for monitoring selectedIndex and updating mutlples views
final class CarouselSelection: ObservableObject {
    @Published var index: Int
    init(index: Int) {
        self.index = index
    }
}
