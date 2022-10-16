//
//  ImageCarousel.swift
//  damus
//
//  Created by William Casarin on 2022-10-16.
//

import SwiftUI
import Kingfisher

struct ImageViewer: View {
    let urls: [URL]
    
    var body: some View {
        TabView {
            ForEach(urls, id: \.absoluteString) { url in
                VStack{
                    Text(url.lastPathComponent)
                    
                    KFImage(url)
                        .loadDiskFileSynchronously()
                        .scaleFactor(UIScreen.main.scale)
                        .fade(duration: 0.1)
                        .tabItem {
                            Text(url.absoluteString)
                        }
                        .id(url.absoluteString)
                }
            }
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

struct ImageCarousel: View {
    var urls: [URL]
    
    @State var open_sheet: Bool = false
    @State var current_url: URL? = nil
    
    var body: some View {
        TabView {
            ForEach(urls, id: \.absoluteString) { url in
                KFImage(url)
                    .loadDiskFileSynchronously()
                    .scaleFactor(UIScreen.main.scale)
                    .fade(duration: 0.1)
                    .tabItem {
                        Text(url.absoluteString)
                    }
                    .id(url.absoluteString)
            }
        }
        .sheet(isPresented: $open_sheet) {
            ImageViewer(urls: urls)
        }
        .frame(height: 200)
        .onTapGesture {
            open_sheet = true
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        ImageCarousel(urls: [URL(string: "https://jb55.com/red-me.jpg")!])
    }
}
