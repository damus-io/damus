//
//  QRCodeView.swift
//  damus
//
//  Created by eric on 1/27/23.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import CodeScanner


struct QRCodeView: View {
    let damus_state: DamusState
    @State var pubkey: Pubkey
    
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0

    @ViewBuilder
    func navImage(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .frame(width: 33, height: 33)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
    }
    
    var navBackButton: some View {
        Button {
            dismiss()
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
                    self.qrCameraView
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
            let profile = try? damus_state.profiles.lookup(id: pubkey)

            ProfilePicView(pubkey: pubkey, size: 90.0, highlight: .custom(DamusColors.white, 3.0), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, damusState: damus_state)
                    .padding(.top, 20)
            
            if let display_name = profile?.display_name {
                Text(display_name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
            }
            if let name = profile?.name {
                Text(verbatim: "@" + name)
                    .font(.body)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Image(uiImage: generateQRCode(pubkey: "nostr:" + pubkey.npub))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 100, maxWidth: 300, minHeight: 100, maxHeight: 300)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(DamusColors.white, lineWidth: 5.0)
                    .scaledToFit())
                .shadow(radius: 10)

            Spacer()
            
            // apply the same styling to both text-views without code duplication
            Group {
                if damus_state.pubkey.npub == pubkey.npub {
                    Text("Follow me on Nostr", comment: "Text on QR code view to prompt viewer looking at screen to follow the user.")
                } else {
                    Text("Follow \(profile?.display_name ?? profile?.name ?? "") on Nostr", comment: "Text on QR code view to prompt viewer looking at screen to follow the user.")
                }
            }
            .font(.system(size: 24, weight: .heavy))
            .padding(.top, 10)
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
            .padding(20)
        }
    }
    
    var qrCameraView: some View {
        QRCameraView(damusState: damus_state, bottomContent: {
            Button(action: {
                selectedTab = 0
            }) {
                HStack {
                    Text("View QR Code", comment: "Button to switch to view users QR Code")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, maxHeight: 12, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding(50)
        }, dismiss: dismiss)
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

/// A view that scans for pubkeys/npub QR codes and displays a profile when needed.
///
/// ## Implementation notes:
///
/// - Marked as `fileprivate` since it is a relatively niche view, but can be made public with some adaptation if reuse is needed
/// - The main state is tracked by a single enum, to ensure mutual exclusion of states (only one of the states can be active at a time), and that the info for each state is there when needed — both enforced at compile-time
fileprivate struct QRCameraView<Content: View>: View {
    
    // MARK: Input parameters
    
    var damusState: DamusState
    /// A custom view to display on the bottom of the camera view
    var bottomContent: () -> Content
    var dismiss: DismissAction
    
    
    // MARK: State properties
    
    /// The main state of this view.
    @State var scannerState: ScannerState = .scanning {
        didSet {
            switch (oldValue, scannerState) {
                case (.scanning, .scanSuccessful), (.incompatibleQRCodeFound, .scanSuccessful):
                    generator.impactOccurred()  // Haptic feedback upon a successful scan
                default:
                    break
            }
        }
    }
    
    
    // MARK: Helper properties and objects
    
    let generator = UIImpactFeedbackGenerator(style: .light)
    /// A timer that ticks every second.
    /// We need this to dismiss the incompatible QR code message automatically once the user is no longer pointing the camera at it
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    /// This is used to create a nice border animation when a scan is successful
    ///
    /// Computed property to simplify state management
    var outerTrimEnd: CGFloat {
        switch scannerState {
            case .scanning, .error, .incompatibleQRCodeFound:
                return 0.0
            case .scanSuccessful:
                return 1.0
        }
    }
    
    /// A computed binding that indicates if there is an error to be displayed.
    ///
    /// This property is computed based on the main state `scannerState`, and is used to manage the error sheet without adding any extra state variables
    var errorBinding: Binding<ScannerError?> {
        Binding(
            get: {
                guard case .error(let error) = scannerState else { return nil }
                return error
            },
            set: { newError in
                guard let newError else {
                    self.scannerState = .scanning
                    return
                }
                self.scannerState = .error(newError)
            })
    }
    
    /// A computed binding that indicates if there is a profile scan result to be displayed
    ///
    /// This property is computed based on the main state `scannerState`, and is used to manage the profile sheet without adding any extra state variables
    var profileScanResultBinding: Binding<ProfileScanResult?> {
        Binding(
            get: {
                guard case .scanSuccessful(result: let scanResult) = scannerState else { return nil }
                return scanResult
            },
            set: { newProfileScanResult in
                guard let newProfileScanResult else {
                    self.scannerState = .scanning
                    return
                }
                self.scannerState = .scanSuccessful(result: newProfileScanResult)
            })
    }
    
    
    // MARK: View layouts
    
    var body: some View {
        VStack(alignment: .center) {
            Text("Scan a user's pubkey", comment: "Text to prompt scanning a QR code of a user's pubkey to open their profile.")
                .padding(.top, 50)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
            
            Spacer()
            
            CodeScannerView(codeTypes: [.qr], scanMode: .continuous, scanInterval: 1, showViewfinder: true, simulatedData: "npub1k92qsr95jcumkpu6dffurkvwwycwa2euvx4fthv78ru7gqqz0nrs2ngfwd", shouldVibrateOnSuccess: false) { result in
                self.handleNewProfileScanInfo(result)
            }
            .scaledToFit()
            .frame(maxWidth: 300, maxHeight: 300)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DamusColors.white, lineWidth: 5.0).scaledToFit())
            .overlay(RoundedRectangle(cornerRadius: 10).trim(from: 0.0, to: outerTrimEnd).stroke(DamusColors.black, lineWidth: 5.5)
                .rotationEffect(.degrees(-90)).scaledToFit())
            .shadow(radius: 10)
            
            Spacer()
            
            self.hintMessage
            
            Spacer()
            
            self.bottomContent()
        }
        // Show an error sheet if we are on an error state
        .sheet(item: self.errorBinding, content: { error in
            self.errorSheet(error: error)
        })
        // Show the profile sheet if we have successfully scanned
        .sheet(item: self.profileScanResultBinding, content: { scanResult in
            ProfileActionSheetView(damus_state: self.damusState, pubkey: scanResult.pubkey, onNavigate: {
                dismiss()
            })
            .tint(DamusColors.adaptableBlack)
            .presentationDetents([.large])
        })
        // Dismiss an incompatible QR code message automatically after a second or two of pointing it elsewhere.
        .onReceive(timer) { _ in
            switch self.scannerState {
                case .incompatibleQRCodeFound(scannedAt: let date):
                    if abs(date.timeIntervalSinceNow) > 1.5 {
                        self.scannerState = .scanning
                    }
                default:
                    break
            }
        }
    }
    
    var hintMessage: some View {
        HStack {
            switch self.scannerState {
                case .scanning:
                    Text("Point your camera to a QR code…", comment: "Text on QR code camera view instructing user to point to QR code")
                case .incompatibleQRCodeFound:
                    Text("Sorry, this QR code looks incompatible with Damus. Please try another one.", comment: "Text on QR code camera view telling the user a QR is incompatible")
                case .scanSuccessful:
                    Text("Found profile!", comment: "Text on QR code camera view telling user that profile scan was successful.")
                case .error:
                    Text("Error, please try again", comment: "Text on QR code camera view indicating an error")
            }
        }
        .foregroundColor(.white)
        .padding()
    }
    
    func errorSheet(error: ScannerError) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
            Text("Error", comment: "Headline label for an error sheet on the QR code scanner")
                .font(.headline)
            Text(error.localizedDescription)
        }
        .presentationDetents([.medium])
        .tint(DamusColors.adaptableBlack)
    }
    
    
    // MARK: Scanning and state management logic
    
    /// A base handler anytime the scanner sends new info,
    ///
    /// Behavior depends on the current state. In some states we completely ignore new scanner info (e.g. when looking at a profile)
    /// This function mutates our state
    func handleNewProfileScanInfo(_ scanInfo: Result<ScanResult, ScanError>) {
        switch scannerState {
            case .scanning, .incompatibleQRCodeFound:
                withAnimation {
                    self.scannerState = self.processScanAndComputeNextState(scanInfo)
                }
            case .scanSuccessful, .error:
                return  // We don't want new scan results to pop-up while in these states
        }
    }
    
    /// Processes a QR code scan, and computes the next state to be applied to the view
    func processScanAndComputeNextState(_ scanInfo: Result<ScanResult, ScanError>) -> ScannerState {
        switch scanInfo {
            case .success(let successfulScan):
                guard let result = ProfileScanResult(string: successfulScan.string) else {
                    return .incompatibleQRCodeFound(scannedAt: Date.now)
                }
                return .scanSuccessful(result: result)
            case .failure(let error):
                return .error(.scanError(error))
        }
    }
    
    // MARK: Helper types
    
    /// A custom type for `QRCameraView` to track the state of the scanner.
    ///
    /// This is done to avoid having multiple independent variables to track the state, which increases the chance of state inconsistency.
    /// By using this we guarantee at compile-time that we will always be in one state at a time, and that the state is coherent/consistent/clear.
    enum ScannerState {
        /// Camera is on and actively scanning new QR codes
        case scanning
        /// Scan and decoding was successful. Show profile.
        case scanSuccessful(result: ProfileScanResult)
        /// Tell the user they scanned a QR code that is incompatible
        case incompatibleQRCodeFound(scannedAt: Date)
        /// There was an error. Display a human readable and actionable message
        case error(ScannerError)
    }
    
    /// Represents an error in this view, to be displayed to the user
    ///
    /// **Implementation notes:**
    /// 1. This is identifiable because it that is needed for the error sheet view
    /// 2. Currently there is only one error type (`ScanError`), but this is still used to allow us to customize it and add future error types outside the scanner.
    enum ScannerError: Error, Identifiable {
        case scanError(ScanError)
        
        var localizedDescription: String {
            switch self {
                case .scanError(let scanError):
                    switch scanError {
                        case .badInput:
                            NSLocalizedString("The camera could not be accessed.", comment: "Camera's bad input error label")
                        case .badOutput:
                            NSLocalizedString("The camera was not capable of scanning the requested codes.", comment: "Camera's bad output error label")
                        case .initError(_):
                            NSLocalizedString("There was an unexpected error in initializing the camera.", comment: "Camera's initialization error label")
                        case .permissionDenied:
                            NSLocalizedString("Camera's permission was denied. You can change this in iOS settings.", comment: "Camera's permission denied error label")
                    }
            }
        }
        var id: String { return self.localizedDescription }
    }
    
    /// A struct that holds results of a profile scan
    struct ProfileScanResult: Equatable, Identifiable {
        var id: Pubkey { return self.pubkey }
        let pubkey: Pubkey

        init?(hex: String) {
            guard let pk = hex_decode(hex).map({ bytes in Pubkey(Data(bytes)) }) else {
                return nil
            }

            self.pubkey = pk
        }
        
        init?(string: String) {
            var str = string.trimmingCharacters(in: ["\n", "\t", " "])
            guard str.count != 0 else {
                return nil
            }

            if str.hasPrefix("nostr:") {
                str.removeFirst("nostr:".count)
            }

            let bech32 = Bech32Object.parse(str)
            switch bech32 {
            case .nprofile(let nprofile):
                self.pubkey = nprofile.author
            case .npub(let pubkey):
                self.pubkey = pubkey
            default:
                return nil
            }
        }
    }
}


// MARK: - Previews

struct QRCodeView_Previews: PreviewProvider {
    static var previews: some View {
        QRCodeView(damus_state: test_damus_state, pubkey: test_note.pubkey)
    }
}

