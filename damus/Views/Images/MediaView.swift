//
//  MediaView.swift
//  damus
//
//  Created by William Casarin on 2023-06-05.
//

import SwiftUI

/*
 struct MediaView: View {
 let geo: GeometryProxy
 let url: MediaUrl
 let index: Int
 
 var body: some View {
 Group {
 switch url {
 case .image(let url):
 Img(geo: geo, url: url, index: index)
 .onTapGesture {
 open_sheet = true
 }
 case .video(let url):
 DamusVideoPlayer(url: url, model: video_model(url), video_size: $video_size)
 .onChange(of: video_size) { size in
 guard let size else { return }
 
 let fill = ImageFill.calculate_image_fill(geo_size: geo.size, img_size: size, maxHeight: maxHeight, fillHeight: fillHeight)
 
 print("video_size changed \(size)")
 if self.image_fill == nil {
 print("video_size firstImageHeight \(fill.height)")
 firstImageHeight = fill.height
 state.events.get_cache_data(evid).media_metadata_model.fill = fill
 }
 
 self.image_fill = fill
 }
 }
 }
 }
 }
 
 struct MediaView_Previews: PreviewProvider {
 static var previews: some View {
 MediaView()
 }
 }
 */
