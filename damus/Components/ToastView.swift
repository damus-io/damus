//
//  ToastView.swift
//  damus
//
//  Created by Sanjay Siddharth on 08/04/25.
//

import SwiftUI

struct ToastView: View {
    var style: ToastStyle
    var message: String
    @State var completedEvents = 1.0
    
    var body: some View {
        HStack{
            if let iconName = style.iconName{
                Image(systemName: iconName)
                    .foregroundStyle(style.color)
            }
            else{
                ProgressView(value: completedEvents)
                    .progressViewStyle(.circular)
            }
            Text(message)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .background(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.damusAdaptableBlack.opacity(0.2),lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(radius: 5.0, x:0 , y: 5)
        )
        .padding()
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.3), value: message)

    }
    
}

#Preview {
    ToastView(style: .initial, message: "Your note has been posted to 10/14 relays")
    ToastView(style: .error, message: "Could not post your note")

}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State var timer: Timer?
    let style: ToastStyle
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top){
            content
            
            if let message = message {
                ToastView(style: style, message: message)
                    .padding(.top, 50)
                    .animation(.easeInOut, value: message)
                    .onChange(of: message){ _ in
                        restartTimer()
                    }
                    .onAppear{
                        restartTimer()
                    }
            }
        }
    }
    private func restartTimer(){
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            message = nil
        }
    }
}

struct Toast: Equatable {
    var style: ToastStyle
    var message: String
    var Duration: Double = 3
    var width: Double = .infinity
}

enum ToastStyle{
    case success
    case error
    case initial
    
}

extension ToastStyle{
    var iconName: String? {
        switch self {
        case .error: 
            return "xmark.circle.fill"
        case .success: 
            return "checkmark"
        case .initial:
            return nil
        }
    }
    var color: Color {
        switch self {
        case .error:
            return Color.red
        case .success:
            return Color.green
        case .initial:
            return Color.black
        }
    }
}

extension View{
    func postConfirmationToast(message: Binding<String?>, style: ToastStyle) -> some View {
        self.modifier(ToastModifier(message: message, style: style))
    }
}
