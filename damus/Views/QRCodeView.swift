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
        
            VStack(alignment: .center) {
                
                Spacer()
                
                if let key = maybe_key {
                    Image(uiImage: generateQRCode(pubkey: "nostr:" + key))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding()
                    
                    Text(key)
                        .font(.headline)
                        .foregroundColor(Color(.white))
                        .padding()
                }
                
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
