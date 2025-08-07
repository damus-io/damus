import SwiftUI

struct FavoriteButtonView: View {
    let pubkey: Pubkey
    let damus_state: DamusState
    
    @State private var is_favorite: Bool
    
    init(pubkey: Pubkey, damus_state: DamusState) {
        self.pubkey = pubkey
        self.damus_state = damus_state
        self._is_favorite = State(initialValue: damus_state.favorites.isFavorite(pubkey))
    }
    
    var body: some View {
        Button(action: {
            damus_state.favorites.toggleFavorite(pubkey)
            is_favorite.toggle()
        }) {
            Image(is_favorite ? "star.fill" : "star")
                .foregroundColor(is_favorite ? .green : .primary)
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
