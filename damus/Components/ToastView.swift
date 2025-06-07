//
//  ToastView.swift
//  damus
//
//  Created by Sanjay Siddharth on 08/04/25.
//

import SwiftUI

// Generic Toast View UI using which we build other custom Toasts

struct GenericToastView<Content:View>: View {
//    var style: ToastStyle
//    var message: String
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
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
//        .animation(.easeInOut(duration: 0.3))

    }
    
}

// Example implementation of a toast which shows a user on how many relays a post has been sucessfully posted to .

struct PostConfirmationToastView: View {
    var message : String
    let style: ToastStyle
    var body: some View {
        GenericToastView{
            HStack{
                if let iconName = style.iconName{
                    Image(systemName: iconName)
                        .foregroundStyle(style.color)
                }
                Text(message)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
    }
}
// Current implementation uses separate ViewModifiers for each type of Toast.
// FUTURE WORK: Can be improved to use one ViewModifier for all kinds of toasts .

struct PostConfirmationToastModifier: ViewModifier {
    @Binding var message: String?
    @State var timer: Timer?
    let style: ToastStyle
    @State private var offset = CGSize.zero
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top){
            
            content
            
            if let message = message {
                PostConfirmationToastView(message: message, style: style)
                    .padding(.top, 50)
                    .offset(x:offset.width)
                    .gesture(
                        DragGesture()
                            .onChanged{gesture in
                                offset = gesture.translation
                            }
                            .onEnded{_ in
                                if abs(offset.width)>100 {
                                    withAnimation{
                                        self.message=nil
                                        offset = CGSize.zero
                                    }
                                }
                                else{
                                    offset = CGSize.zero
                                }
                                
                            }
                    )
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

extension View{
    func postConfirmationToast(message: Binding<String?>, style: ToastStyle) -> some View {
        self.modifier(PostConfirmationToastModifier(message: message, style: style))
    }
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

