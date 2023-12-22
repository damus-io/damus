//
//  CameraView.swift
//  damus
//
//  Created by Suhail Saqan on 8/5/23.
//

import SwiftUI
import Combine
import AVFoundation

struct CameraView: View {
    let damus_state: DamusState
    let action: (([MediaItem]) -> Void)
    
    @Environment(\.presentationMode) var presentationMode
    
    @StateObject var model: CameraModel
    
    @State var currentZoomFactor: CGFloat = 1.0
    
    public init(damus_state: DamusState, action: @escaping (([MediaItem]) -> Void)) {
        self.damus_state = damus_state
        self.action = action
        _model = StateObject(wrappedValue: CameraModel())
    }
    
    var captureButton: some View {
        Button {
            if model.isRecording {
                withAnimation {
                    model.stopRecording()
                }
            } else {
                withAnimation {
                    model.capturePhoto()
                }
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill( model.isRecording ? .red : DamusColors.black)
                    .frame(width: model.isRecording ? 85 : 65, height: model.isRecording ? 85 : 65, alignment: .center)
                
                Circle()
                    .stroke( model.isRecording ? .red : DamusColors.white, lineWidth: 4)
                    .frame(width: model.isRecording ? 95 : 75, height: model.isRecording ? 95 : 75, alignment: .center)
            }
            .frame(alignment: .center)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded({ value in
                if (!model.isCameraButtonDisabled) {
                    withAnimation {
                        model.startRecording()
                        model.captureMode = .video
                    }
                }
            })
        )
        .buttonStyle(.plain)
    }
    
    var capturedPhotoThumbnail: some View {
        ZStack {
            if model.thumbnail != nil {
                Image(uiImage: model.thumbnail.thumbnailImage!)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if model.isPhotoProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: DamusColors.white))
            }
        }
    }
    
    var closeButton: some View {
        Button {
            presentationMode.wrappedValue.dismiss()
            model.stop()
        } label: {
            HStack {
                Image(systemName: "xmark")
                    .font(.system(size: 24))
            }
            .frame(minWidth: 40, minHeight: 40)
        }
        .accentColor(DamusColors.white)
    }
    
    var flipCameraButton: some View {
        Button(action: {
            model.flipCamera()
        }, label: {
            HStack {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 20))
            }
            .frame(minWidth: 40, minHeight: 40)
        })
        .accentColor(DamusColors.white)
    }

    var toggleFlashButton: some View {
        Button(action: {
            model.switchFlash()
        }, label: {
            HStack {
                Image(systemName: model.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20))
            }
            .frame(minWidth: 40, minHeight: 40)
        })
        .accentColor(model.isFlashOn ? .yellow : DamusColors.white)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { reader in
                ZStack {
                    DamusColors.black.edgesIgnoringSafeArea(.all)
                    
                    CameraPreview(session: model.session)
                        .padding(.bottom, 175)
                        .edgesIgnoringSafeArea(.all)
                        .gesture(
                            DragGesture().onChanged({ (val) in
                                if abs(val.translation.height) > abs(val.translation.width) {
                                    let percentage: CGFloat = -(val.translation.height / reader.size.height)
                                    let calc = currentZoomFactor + percentage
                                    let zoomFactor: CGFloat = min(max(calc, 1), 5)
                                    
                                    currentZoomFactor = zoomFactor
                                    model.zoom(with: zoomFactor)
                                }
                            })
                        )
                        .onAppear {
                            model.configure()
                        }
                        .alert(isPresented: $model.showAlertError, content: {
                            Alert(title: Text(model.alertError.title), message: Text(model.alertError.message), dismissButton: .default(Text(model.alertError.primaryButtonTitle), action: {
                                model.alertError.primaryAction?()
                            }))
                        })
                        .overlay(
                            Group {
                                if model.willCapturePhoto {
                                    Color.black
                                }
                            }
                        )
                    
                    VStack {
                        if !model.isRecording {
                            HStack {
                                closeButton
                                
                                Spacer()
                                
                                HStack {
                                    flipCameraButton
                                    toggleFlashButton
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer()
                        
                        HStack(alignment: .center) {
                            if !model.mediaItems.isEmpty {
                                NavigationLink(destination: CameraMediaView(video_controller: damus_state.video, urls: model.mediaItems.map { mediaItem in
                                    switch mediaItem.type {
                                    case .image:
                                        return .image(mediaItem.url)
                                    case .video:
                                        return .video(mediaItem.url)
                                    }
                                }, settings: damus_state.settings)
                                    .navigationBarBackButtonHidden(true)
                                ) {
                                    capturedPhotoThumbnail
                                }
                                .frame(width: 100, alignment: .leading)
                            }
                            
                            Spacer()
                            
                            captureButton
                            
                            Spacer()
                            
                            if !model.mediaItems.isEmpty {
                                Button(action: {
                                    action(model.mediaItems)
                                    presentationMode.wrappedValue.dismiss()
                                    model.stop()
                                }) {
                                    Text("Upload")
                                        .frame(width: 100, height: 40, alignment: .center)
                                        .foregroundColor(DamusColors.white)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 24)
                                                .stroke(DamusColors.white, lineWidth: 2)
                                        }
                                }
                            }
                        }
                        .frame(height: 100)
                        .padding([.horizontal, .vertical], 20)
                    }
                }
            }
        }
    }
}
