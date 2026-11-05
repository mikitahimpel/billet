import SwiftUI

/// The seated cat in her coat, big and sharp, on a warm glow with a soft shadow under her paws. Drawn from the coat
/// carousel's render, so it is the same cat the room shows.
struct CatHero: View {
    var coat: CatCoat = .current()
    /// The height; the render is 3:4.
    let size: CGFloat

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0xFFD9A8).opacity(0.5), Color(hex: 0xF4BF7E).opacity(0.18), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: size * 0.55)
                .frame(width: size * 1.2, height: size * 1.2)

            Ellipse()
                .fill(.black.opacity(0.45))
                .frame(width: size * 0.46, height: size * 0.06)
                .blur(radius: size * 0.03)
                .offset(y: size * 0.41)

            if let image = UIImage(named: coat.portrait) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
