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
                damus_state.contactCards.toggleFavorite(
                    pubkey,
                    postbox: damus_state.nostrNetwork.postbox,
                    keyPair: damus_state.keypair.to_full()
                )
            favorite.toggle()
        }) {
            Image(favorite ? "heart.fill" : "heart")
                .foregroundColor(favorite ? DamusColors.purple : .primary)
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(PlainButtonStyle())
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
