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
        // A soft clay ring: lit from above, warm below.
        .overlay {
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), Color(hex: 0xF6D2A8)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: max(1.5, size * 0.05))
        }
        .shadow(color: Color(hex: 0x3A1C10).opacity(size >= 40 ? 0.28 : 0), radius: size * 0.08, y: size * 0.04)
    }
}
