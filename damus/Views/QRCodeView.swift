//
//  QRCodeView.swift
//  damus
//
//  Created by eric on 1/27/23.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let damus_state: DamusState
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode

    var maybe_key: String? {
        guard let key = bech32_pubkey(damus_state.pubkey) else {
            return nil
        }

        return key
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            
            ZStack(alignment: .topLeading) {
                DamusGradient()
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .padding(.leading, 20)
                }
                .zIndex(1)
            }
        
            VStack(alignment: .center) {
                let profile = damus_state.profiles.lookup(id: damus_state.pubkey)
                
                if (damus_state.profiles.lookup(id: damus_state.pubkey)?.picture) != nil {
                    ProfilePicView(pubkey: damus_state.pubkey, size: 90.0, highlight: .custom(Color("DamusWhite"), 4.0), profiles: damus_state.profiles)
                        .padding(.top, 50)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color("DamusWhite"))
                        .padding(.top, 50)
                }
                
                if let display_name = profile?.display_name {
                    Text(display_name)
                        .foregroundColor(Color("DamusWhite"))
                        .font(.system(size: 24, weight: .heavy))
                }
                if let name = profile?.name {
                    Text("@" + name)
                        .foregroundColor(Color("DamusWhite"))
                        .font(.body)
                }
                
                Spacer()
                
                if let key = maybe_key {
                    Image(uiImage: generateQRCode(pubkey: "nostr:" + key))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding()
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color("DamusWhite"), lineWidth: 1))
                        .shadow(radius: 10)
                }
                
                Spacer()
                
                Text("Follow me on nostr", comment: "Text on QR code view to prompt viewer looking at screen to follow the user.")
                    .foregroundColor(Color("DamusWhite"))
                    .font(.system(size: 24, weight: .heavy))
                    .padding(.top)
                
                Text("Scan the code", comment: "Text on QR code view to prompt viewer to scan the QR code on screen with their device camera.")
                    .foregroundColor(Color("DamusWhite"))
                    .font(.system(size: 18, weight: .ultraLight))
                
                Spacer()
            }
            
        }
        .modifier(SwipeToDismissModifier(minDistance: nil, onDismiss: {
            presentationMode.wrappedValue.dismiss()
        }))
    }
    
    func generateQRCode(pubkey: String) -> UIImage {
        let data = pubkey.data(using: String.Encoding.ascii)
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(data, forKey: "inputMessage")
        let qrImage = qrFilter?.outputImage
        
        let colorInvertFilter = CIFilter(name: "CIColorInvert")
        colorInvertFilter?.setValue(qrImage, forKey: "inputImage")
        let outputInvertedImage = colorInvertFilter?.outputImage
        
        let maskToAlphaFilter = CIFilter(name: "CIMaskToAlpha")
        maskToAlphaFilter?.setValue(outputInvertedImage, forKey: "inputImage")
        let outputCIImage = maskToAlphaFilter?.outputImage

        let context = CIContext()
        let cgImage = context.createCGImage(outputCIImage!, from: outputCIImage!.extent)!
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView_Previews: PreviewProvider {
    static var previews: some View {
        QRCodeView(damus_state: test_damus_state())
    }
}
