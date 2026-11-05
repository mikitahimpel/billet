import SwiftUI
import UIKit

/// Colors of the polaroid paper family, shared by photos and the notes beside them.
enum PolaroidPaper {
    /// The frame: warm off-white in light, a softer cream on the brown screen in dark so it doesn't glare.
    static let frame = Color(light: Color(hex: 0xFFFBF3), dark: Color(hex: 0xF5E8D3))
    /// Handwriting on the paper.
    static let ink = Color(hex: 0x4A2E1F)
    static let byline = Color(hex: 0x9A7A62)
    /// The empty photo area before a print loads.
    static let blank = Color(hex: 0xE9D6BC)
    /// The milky sheet a fresh print develops out of.
    static let milk = Color(hex: 0xEFE8DC)
    static let tapeTones: [Color] = [.blushPink, .honey, Color(hex: 0x9CC3A4), Color(hex: 0x9DBBF5)]
}

extension UUID {
    /// A small tilt, 2–4° either way, the same for this id every time.
    var polaroidTilt: Angle {
        let b = withUnsafeBytes(of: uuid) { Array($0) }
        let magnitude = 2 + Double(b[5]) / 255 * 2
        return .degrees(b[4].isMultiple(of: 2) ? magnitude : -magnitude)
    }

    /// One of the washi tape colors, the same for this id every time.
    var tapeTone: Color {
        let b = withUnsafeBytes(of: uuid) { Array($0) }
        return PolaroidPaper.tapeTones[Int(b[6]) % PolaroidPaper.tapeTones.count]
    }
}

/// An instant print: the photo on a square in a warm paper frame with a deeper bottom strip, a handwritten caption on
/// the strip and who and when beneath it. `width` sets every proportion, so the same print works as a feed card, a
/// board face or full screen. While `undeveloped` it is a milky blank; turning it off develops the photo over 1.5 s
/// with a soft tap, like a fresh instant.
struct Polaroid<Photo: View>: View {
    let width: CGFloat
    let caption: String
    let byline: String
    var undeveloped = false
    /// Its own drop shadow; off where the print is drawn into a lit 3D scene.
    var lifted = true
    /// Turns the caption into a field on the strip.
    var captionEditor: Binding<String>?
    var captionFocus: FocusState<Bool>.Binding?
    @ViewBuilder var photo: Photo

    private var border: CGFloat { (width * 0.055).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PolaroidPaper.blank
                .aspectRatio(1, contentMode: .fit)
                .overlay { photo }
                .saturation(undeveloped ? 0.1 : 1)
                .overlay { PolaroidPaper.milk.opacity(undeveloped ? 1 : 0) }
                .animation(.easeOut(duration: 1.5), value: undeveloped)
                .clipped()
                // The print sits a hair below the paper's surface.
                .overlay(Rectangle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: width * 0.012) {
                Group {
                    if let captionEditor, let captionFocus {
                        TextField("", text: captionEditor,
                                  prompt: Text("Write a little note…").foregroundStyle(PolaroidPaper.byline.opacity(0.8)))
                            .focused(captionFocus)
                            .submitLabel(.done)
                    } else {
                        Text(caption.isEmpty ? " " : caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .font(.custom("Noteworthy-Bold", size: width * 0.078))
                .foregroundStyle(PolaroidPaper.ink)
                Text(byline)
                    .font(.system(size: max(9, width * 0.05), weight: .medium, design: .rounded))
                    .foregroundStyle(PolaroidPaper.byline)
                    .lineLimit(1)
            }
            .padding(.horizontal, width * 0.012)
            .frame(maxWidth: .infinity, minHeight: width * 0.2, alignment: .leading)
        }
        .padding([.top, .horizontal], border)
        .padding(.bottom, border * 0.6)
        .frame(width: width)
        .background { PaperSheet(cornerRadius: 2.5) }
        .compositingGroup()
        .shadow(color: .black.opacity(lifted ? 0.16 : 0), radius: 1, y: 1)
        .shadow(color: .black.opacity(lifted ? 0.24 : 0), radius: width * 0.05, y: width * 0.035)
        .sensoryFeedback(trigger: undeveloped) { old, new in
            old && !new && AppSettings.haptics ? .impact(flexibility: .soft, intensity: 0.7) : nil
        }
        .accessibilityElement(children: .combine)
    }
}

/// Polaroid paper: the frame color with a soft grain, for prints and the notes that sit with them.
struct PaperSheet: View {
    var color: Color = PolaroidPaper.frame
    var cornerRadius: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(color)
            .overlay {
                Image(uiImage: PaperGrain.tile)
                    .resizable(resizingMode: .tile)
                    .blendMode(.multiply)
                    .opacity(0.4)
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
            }
    }
}

/// A strip of washi tape with slightly ragged ends, holding a print to the board or the page.
struct WashiTape: View {
    let tone: Color
    var width: CGFloat = 46

    var body: some View {
        RaggedStrip()
            .fill(tone.opacity(0.78))
            .overlay {
                RaggedStrip().fill(.white.opacity(0.18)).padding(.vertical, width * 0.09).blendMode(.screen)
            }
            .frame(width: width, height: width * 0.34)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

private nonisolated struct RaggedStrip: Shape {
    func path(in rect: CGRect) -> Path {
        let teeth = 5
        let depth = rect.width * 0.03
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        for i in 1...teeth {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(teeth)
            path.addLine(to: CGPoint(x: rect.maxX - (i.isMultiple(of: 2) ? 0 : depth), y: y))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in stride(from: teeth - 1, through: 0, by: -1) {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(teeth)
            path.addLine(to: CGPoint(x: rect.minX + (i.isMultiple(of: 2) ? 0 : depth), y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// A small tile of light noise, multiplied over paper so it reads as paper rather than flat color.
enum PaperGrain {
    static let tile: UIImage = {
        let side = 96
        var state: UInt32 = 0x9E37_79B9
        var pixels = [UInt8](repeating: 0, count: side * side)
        for i in pixels.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[i] = 226 + UInt8(truncatingIfNeeded: state >> 24) % 30
        }
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        return image.map { UIImage(cgImage: $0, scale: 2, orientation: .up) } ?? UIImage()
    }()
}

extension Moment {
    /// Who and when, as the print's strip shows it: "Anya · Nov 5". `name` is the author's own name.
    func byline(by name: String) -> String { "\(name) · \(date.formatted(.dateTime.month(.abbreviated).day()))" }
}

extension CoupleStore {
    func byline(of moment: Moment) -> String { moment.byline(by: name(of: moment.author)) }
}
