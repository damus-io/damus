//
//  EditAccountButton.swift
//  damus
//
//  Created by Sam DuBois on 12/21/22.
//

import SwiftUI

struct EditAccountButton: View {
    
    @EnvironmentObject var viewModel: DamusViewModel
    
    @State private var presentEditAccountView: Bool = false
    
    var body: some View {
        Button {
            presentEditAccountView.toggle()
        } label: {
            Text("Edit")
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .background(viewModel.damus_state != nil ? hex_to_rgb(viewModel.damus_state!.pubkey) : .black)
                .cornerRadius(20)
        }
         .sheet(isPresented: $presentEditAccountView, content: {
            EditAccountView()
        })

    }
}


struct EditAccountButton_Previews: PreviewProvider {
    static var previews: some View {
        EditAccountButton()
            .environmentObject(DamusViewModel())
    }
}
