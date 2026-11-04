import SwiftUI

struct Monogram: View {
    let partner: String
    let profile: CoupleStore
    var size: CGFloat = 46

    /// First partner blue, second pink, as everywhere else in the app.
    static func colors(_ partner: String, _ profile: CoupleStore) -> [Color] {
        partner == profile.couple.partners.first
            ? [Color(hex: 0x9DBBF5), Color(hex: 0x6C89D9)] : [Color(hex: 0xF9B8CB), Color(hex: 0xE287A9)]
    }

    var body: some View {
        Group {
            if let photo = profile.photos[partner] {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Text(profile.initial(of: partner))
                    .font(.system(size: size * 0.41, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: Self.colors(partner, profile), startPoint: .topLeading,
                                               endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
    }
}
