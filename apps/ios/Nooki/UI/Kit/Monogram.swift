import OurioShared
import SwiftUI
import Design

struct Monogram: View {
    let partner: String
    let profile: CoupleStore
    var size: CGFloat = 46
    /// Among the glass controls of a header: ringed in `Ink.glassFill`, and no shadow of its own.
    var onGlass = false

    /// First partner honey, second terracotta: one warm family, nothing system blue or pink.
    static func colors(_ partner: String, _ profile: CoupleStore) -> [Color] {
        partner == profile.couple.partners.first
            ? [Color(hex: 0xF6C66F), Color(hex: 0xD98A2B)] : [Color(hex: 0xEE9A7E), Color(hex: 0xB9553C)]
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
        .overlay {
            if onGlass {
                Circle().strokeBorder(Ink.glassFill, lineWidth: 2)
            } else {
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), Color(hex: 0xF6D2A8)],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: max(1.5, size * 0.05))
            }
        }
        // Cast by a circle behind, not traced from the photo, so it is drawn once rather than per frame over the room.
        .background {
            if size >= 40, !onGlass {
                Circle().fill(Color(hex: 0x3A1C10))
                    .shadow(color: Color(hex: 0x3A1C10).opacity(0.3), radius: size * 0.08, y: size * 0.04)
            }
        }
    }
}
