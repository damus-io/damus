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
    
    var body: some View {
        HStack{
            Image(systemName: style.iconName)
                .foregroundStyle(style.color)
            Text(message)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.purple, lineWidth: 0.5)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white)
                )
                .shadow(color: .purple.opacity(0.35), radius: 6)
        )
        .padding()
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.3), value: message)
    }
}

#Preview {
    ToastView(style: .success, message: "Your note has been posted to 10/14 relays")
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
    
}

extension ToastStyle{
    var iconName: String {
        switch self {
        case .error: 
            return "xmark.circle.fill"
        case .success: 
            return "checkmark"
        }
    }
    var color: Color {
        switch self {
        case .error:
            return Color.red
        case .success:
            return Color.green
        }
        
    }
}

extension View{
    func postConfirmationToast(message: Binding<String?>, style: ToastStyle) -> some View {
        self.modifier(ToastModifier(message: message, style: style))
    }
}
