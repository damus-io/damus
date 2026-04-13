import SwiftUI

struct FavoriteButtonView: View {
    let pubkey: Pubkey
    let damus_state: DamusState
    
    @State private var favorite: Bool
    
    init(pubkey: Pubkey, damus_state: DamusState) {
        self.pubkey = pubkey
        self.damus_state = damus_state
        self._favorite = State(initialValue: damus_state.contactCards.isFavorite(pubkey))
    }
    
    var body: some View {
        Button(
            action: {
                guard let keypair = damus_state.keypair.to_full() else { return }

                damus_state.contactCards.toggleFavorite(
                    pubkey,
                    postbox: damus_state.nostrNetwork.postbox,
                    keyPair: keypair
                )
                favorite = damus_state.contactCards.isFavorite(pubkey)
        }) {
            Image(favorite ? "heart.fill" : "heart")
                .foregroundColor(favorite ? DamusColors.purple : .primary)
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(PlainButtonStyle())
        .onReceive(handle_notify(.favoriteUpdated)) { _ in
            favorite = damus_state.contactCards.isFavorite(pubkey)
        }
    }
}

struct FavoriteButtonView_Previews: PreviewProvider {
    static var previews: some View {
        FavoriteButtonView(
            pubkey: test_pubkey,
            damus_state: test_damus_state
        )
    }
} 
