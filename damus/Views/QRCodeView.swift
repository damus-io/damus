//
//  QRCodeView.swift
//  damus
//
//  Created by eric on 1/27/23.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ProfileScanResult: Equatable {
    let pubkey: Pubkey

    init?(hex: String) {
        guard let pk = hex_decode(hex).map({ bytes in Pubkey(Data(bytes)) }) else {
            return nil
        }

        self.pubkey = pk
    }
    
    init?(string: String) {
        var str = string
        guard str.count != 0 else {
            return nil
        }
        
        if str.hasPrefix("nostr:") {
            str.removeFirst("nostr:".count)
        }
        
        if let decoded = hex_decode(str),
           str.count == 64
        {
            self.pubkey = Pubkey(Data(decoded))
            return
        }
        
        if str.starts(with: "npub"),
           let b32 = try? bech32_decode(str)
        {
            self.pubkey = Pubkey(b32.data)
            return
        }
        
        return nil
    }
}

struct QRCodeView: View {
    let damus_state: DamusState
    @State var pubkey: Pubkey
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedTab = 0
    @State var scanResult: ProfileScanResult? = nil
    @State var profile: Profile? = nil
    @State var error: String? = nil
    @State private var outerTrimEnd: CGFloat = 0

    var animationDuration: Double = 0.5
    
    let generator = UIImpactFeedbackGenerator(style: .light)

    @ViewBuilder
    func navImage(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .frame(width: 33, height: 33)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
    }
    
    var navBackButton: some View {
        Button {
            presentationMode.wrappedValue.dismiss()
        } label: {
            navImage(systemImage: "chevron.left")
        }
    }
    
    var customNavbar: some View {
        HStack {
            navBackButton
            Spacer()
        }
        .padding(.top, 5)
        .padding(.horizontal)
        .accentColor(DamusColors.white)
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .center) {
                ZStack(alignment: .topLeading) {
                    DamusGradient()
                }
                TabView(selection: $selectedTab) {
                    QRView
                        .tag(0)
                    QRCameraView()
                        .tag(1)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .onAppear {
                    UIScrollView.appearance().isScrollEnabled = false
                }
                .gesture(
                    DragGesture()
                        .onChanged { _ in }
                )
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .overlay(customNavbar, alignment: .top)
    }
    
    var QRView: some View {
        VStack(alignment: .center) {
            let profile_txn = damus_state.profiles.lookup(id: pubkey, txn_name: "qrview-profile")
            let profile = profile_txn?.unsafeUnownedValue
            let our_profile = profile_txn.flatMap({ ptxn in
                damus_state.ndb.lookup_profile_with_txn(damus_state.pubkey, txn: ptxn)?.profile
            })

            if our_profile?.picture != nil {
                ProfilePicView(pubkey: pubkey, size: 90.0, highlight: .custom(DamusColors.white, 3.0), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                    .padding(.top, 50)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 60))
                    .padding(.top, 50)
            }
            
            if let display_name = profile?.display_name {
                Text(display_name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
            }
            if let name = profile?.name {
                Text("@" + name)
                    .font(.body)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Image(uiImage: generateQRCode(pubkey: "nostr:" + pubkey.npub))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(DamusColors.white, lineWidth: 5.0))
                .shadow(radius: 10)

            Spacer()
            
            Text("Follow me on Nostr", comment: "Text on QR code view to prompt viewer looking at screen to follow the user.")
                .font(.system(size: 24, weight: .heavy))
                .padding(.top)
                .foregroundColor(.white)
            
            Text("Scan the code", comment: "Text on QR code view to prompt viewer to scan the QR code on screen with their device camera.")
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                selectedTab = 1
            }) {
                HStack {
                    Text("Scan Code", comment: "Button to switch to scan QR Code page.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding(50)
        }
    }
    
    func QRCameraView() -> some View {
        return VStack(alignment: .center) {
            Text("Scan a user's pubkey", comment: "Text to prompt scanning a QR code of a user's pubkey to open their profile.")
                .padding(.top, 50)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
            
            Spacer()

            CodeScannerView(codeTypes: [.qr], scanMode: .continuous, simulatedData: "npub1k92qsr95jcumkpu6dffurkvwwycwa2euvx4fthv78ru7gqqz0nrs2ngfwd", shouldVibrateOnSuccess: false) { result in
                switch result {
                case .success(let success):
                    handleProfileScan(success.string)
                case .failure(let failure):
                    self.error = failure.localizedDescription
                }
            }
            .scaledToFit()
            .frame(width: 300, height: 300)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DamusColors.white, lineWidth: 5.0))
            .overlay(RoundedRectangle(cornerRadius: 10).trim(from: 0.0, to: outerTrimEnd).stroke(DamusColors.black, lineWidth: 5.5)
            .rotationEffect(.degrees(-90)))
            .shadow(radius: 10)
            
            Spacer()
            
            Spacer()
            
            Button(action: {
                selectedTab = 0
            }) {
                HStack {
                    Text("View QR Code", comment: "Button to switch to view users QR Code")
                        .fontWeight(.semibold)
                }
                .frame( maxWidth: .infinity, maxHeight: 12, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding(50)
        }
    }
    
    func handleProfileScan(_ scanned_str: String) {
        guard let result = ProfileScanResult(string: scanned_str) else {
            self.error = "Invalid profile QR"
            return
        }
        
        self.error = nil

        guard result != self.scanResult else {
            return
        }
        
        generator.impactOccurred()
        cameraAnimate {
            scanResult = result
            
            find_event(state: damus_state, query: .profile(pubkey: result.pubkey)) { res in
                guard let res else {
                    error = "Profile not found"
                    return
                }
                
                switch res {
                case .invalid_profile:
                    error = "Profile was found but was corrupt."
                    
                case .profile:
                    show_profile_after_delay()
                    
                case .event:
                    print("invalid search result")
                }
                
            }
        }
    }
    
    func show_profile_after_delay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            if let scanResult {
                damus_state.nav.push(route: Route.ProfileByKey(pubkey: scanResult.pubkey))
                presentationMode.wrappedValue.dismiss()
            }
        }
    }

    func cameraAnimate(completion: @escaping () -> Void) {
        outerTrimEnd = 0.0
        withAnimation(.easeInOut(duration: animationDuration)) {
            outerTrimEnd = 1.05 // Set to 1.05 instead of 1.0 since sometimes `completion()` runs before the value reaches 1.0. This ensures the animation is done.
        }
        completion()
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
        QRCodeView(damus_state: test_damus_state, pubkey: test_note.pubkey)
    }
}

