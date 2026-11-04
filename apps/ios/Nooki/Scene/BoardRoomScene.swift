import RealityKit
import UIKit

private enum Tone {
    static let wall: UInt32 = 0xF6E4C8
    static let wood: UInt32 = 0xB46C3C
    static let woodDark: UInt32 = 0x8C4F2B
    static let woodLight: UInt32 = 0xCF8E58
    static let snow: UInt32 = 0xFFFBF5
    static let cork: UInt32 = 0xC98A55
    static let paper: UInt32 = 0xFBF3E4
    static let honey: UInt32 = 0xE3B45C
    static let ink: UInt32 = 0x5B3A28
    static let twine: UInt32 = 0xB89A78
    static let bulb: UInt32 = 0xFFD27A
}

/// One card on the corkboard: its picture already drawn (photo or note) and its size in meters.
struct BoardPin {
    let id: UUID
    let face: UIImage
    let size: SIMD2<Float>
}

/// A desk against a corkboard wall: fairy lights above, Mochi sitting on the desk with her paper and pencil below.
final class BoardRoomScene: CatRoom {
    static let slots = 8
    /// A card was tapped.
    var onOpen: ((UUID) -> Void)?
    /// The drawing sheet on the desk was tapped.
    var onDraw: (() -> Void)?

    override var framing: Framing {
        Framing(target: [-0.06, 0.6, -0.1], direction: simd_normalize([0, 0.16, 1]), far: 6.2, near: 3.4)
    }
    override var yawLimit: Float { 0.2 }
    override var focusDistance: Float { 1.3 }

    private static let bulbRadius: Float = 0.011
    private static let photoName = "photo"
    /// Face of the corkboard, where the slots sit.
    private static let corkFace: Float = -0.266
    private static let pinTones: [UInt32] = [0xE0554A, 0xE3B45C, 0x6F8FB0, 0x7C9A7E]

    private let sun = Entity()
    private let fill = Entity()
    private let ibl = Entity()
    private var lampLight = Entity()
    private var bulbs: [ModelEntity] = []

    private let board = Entity()
    private var pinIDs: [ObjectIdentifier: UUID] = [:]
    private let sheet = Entity()

    override init() {
        super.init()
        buildFloor()
        buildWalls()
        buildCorkboard()
        buildFairyLights()
        buildDesk()
        buildLamp()
        buildSheet()
        buildDeskProps()
        buildCat(at: [0.27, 0.34, -0.16], rests: [.pi - 0.4], scale: 0.62, wandering: false)
        buildMotes()
        buildLighting()
        setPins([])
    }

    // MARK: - Pins

    /// Rebuilds the board with the first `slots` pins.
    func setPins(_ pins: [BoardPin]) {
        board.children.removeAll()
        pinIDs.removeAll()
        if board.parent == nil { pivot.addChild(board) }

        let shown = pins.prefix(Self.slots)
        for slot in 0..<Self.slots {
            let center = Self.slotCenter(slot)
            guard slot < shown.count else {
                let tone = Self.pinTones[slot % Self.pinTones.count]
                board.sphere(0.009, Clay.matte(tone), at: center + [0, 0, 0.008])
                continue
            }
            addPin(shown[slot], at: center)
        }
        // Built after buildLighting handed out the receiver, so the new cards need it too.
        if let iblReceiver { board.forEachDescendant { $0.components.set(iblReceiver) } }
    }

    /// The centre of a slot on the cork face: two rows of four.
    private static func slotCenter(_ slot: Int) -> SIMD3<Float> {
        let column = slot % 4
        let row = slot / 4
        return [-0.24 + Float(column) * 0.16, row == 0 ? 0.72 : 0.52, corkFace]
    }

    /// Hands each pin its place on the board from its own id, so a card stays put between launches.
    private static func layout(_ id: UUID) -> (offset: SIMD2<Float>, tilt: Float, tone: UInt32) {
        let b = withUnsafeBytes(of: id.uuid) { Array($0) }
        let offset = SIMD2<Float>(
            (Float(b[0]) / 255 - 0.5) * 0.024,
            (Float(b[1]) / 255 - 0.5) * 0.024
        )
        return (offset, (Float(b[2]) / 255 - 0.5) * 0.14, pinTones[Int(b[3]) % pinTones.count])
    }

    private func addPin(_ pin: BoardPin, at slot: SIMD3<Float>) {
        let layout = Self.layout(pin.id)
        let card = board.group(at: slot + [layout.offset.x, layout.offset.y, 0], rotation: .z(layout.tilt))
        card.name = "pin"
        card.box(pin.size.x + 0.006, pin.size.y + 0.006, 0.002, r: 0.001, Clay.matte(0xFFFBF3), at: .zero)
        let face = card.model(.generatePlane(width: pin.size.x, height: pin.size.y), Self.faceMaterial(pin.face),
                               at: [0, 0, 0.0015])
        face.name = Self.photoName
        card.sphere(0.009, Clay.matte(layout.tone), at: [0, pin.size.y / 2 - 0.012, 0.008])
        Self.tappable(card, size: [pin.size.x + 0.006, pin.size.y + 0.006, 0.03], at: [0, 0, 0.008])
        pinIDs[ObjectIdentifier(card)] = pin.id
    }

    /// A card's picture in its own colors, lit like the room.
    private static func faceMaterial(_ image: UIImage) -> PhysicallyBasedMaterial {
        guard let cg = image.cgImage,
              let texture = try? TextureResource(image: cg, options: .init(semantic: .color)) else {
            return Clay.matte(0xFFFBF3, roughness: 1)
        }
        var m = Clay.matte(0xFFFFFF, roughness: 0.55)
        m.baseColor = .init(tint: .white, texture: .init(texture))
        return m
    }

    // MARK: - Taps

    override func tapped(_ entity: Entity) {
        var node: Entity? = entity
        while let n = node {
            if let id = pinIDs[ObjectIdentifier(n)] {
                onOpen?(id)
                return
            }
            if n === sheet {
                onDraw?()
                return
            }
            node = n.parent
        }
    }

    override func doubleTapped(_ entity: Entity) {
        var node: Entity? = entity
        while let n = node {
            if pinIDs[ObjectIdentifier(n)] != nil,
               let photo = n.children.first(where: { $0.name == Self.photoName }) {
                return focus(on: photo)
            }
            node = n.parent
        }
    }

    override func tick(_ dt: Float) {
        super.tick(dt)
        let t = time
        for (i, bulb) in bulbs.enumerated() {
            let s = 1 + 0.22 * sin(t * 2.1 + Float(i) * 1.3)
            bulb.scale = .init(repeating: Self.bulbRadius * s)
        }
    }

    // MARK: - Structure

    private func buildFloor() {
        pivot.box(1.2, 0.1, 0.7, r: 0.03, Clay.matte(Tone.woodDark), at: [0, -0.05, -0.05])
        for i in 0..<7 {
            let tone = i.isMultiple(of: 2) ? Tone.wood : Tone.woodLight
            pivot.box(1.16, 0.014, 0.092, r: 0.004, Clay.matte(tone, roughness: 0.7),
                      at: [0, 0.007, -0.36 + Float(i) * 0.1])
        }
    }

    private func buildWalls() {
        let wall = Clay.matte(Tone.wall, roughness: 0.95)
        let wood = Clay.matte(Tone.wood)
        let snow = Clay.matte(Tone.snow, roughness: 0.6)

        pivot.box(1.2, 1.0, 0.05, r: 0.01, wall, at: [0, 0.5, -0.325])
        pivot.box(1.2, 0.05, 0.014, r: 0.004, Clay.matte(Tone.woodDark), at: [0, 0.025, -0.293])
        pivot.box(1.26, 0.065, 0.085, r: 0.015, wood, at: [0, 1.02, -0.3])

        // Snow resting on the top beam.
        pivot.box(0.18, 0.045, 0.09, r: 0.02, snow, at: [-0.36, 1.072, -0.3])
        pivot.box(0.32, 0.05, 0.09, r: 0.022, snow, at: [0.06, 1.075, -0.3])
        pivot.sphere(0.045, snow, at: [0.38, 1.075, -0.3], scale: [1.3, 0.85, 1.2])
    }

    private func buildCorkboard() {
        pivot.box(0.74, 0.44, 0.03, r: 0.008, Clay.matte(Tone.woodDark), at: [0, 0.62, -0.29])
        pivot.box(0.70, 0.40, 0.012, r: 0.004, Clay.matte(Tone.cork, roughness: 1), at: [0, 0.62, -0.272])
    }

    private func buildFairyLights() {
        let material = Clay.glow(Tone.bulb, intensity: 2.5)
        let twine = Clay.matte(Tone.twine, roughness: 1)
        func point(_ t: Float) -> SIMD3<Float> {
            [-0.45 + t * 0.9, 0.88 - 0.04 * abs(sin(t * .pi * 2)), -0.27]
        }
        for i in 0..<13 {
            let t = Float(i) / 12
            bulbs.append(pivot.sphere(Self.bulbRadius, material, at: point(t)))
        }
        for i in 0..<12 {
            let a = point(Float(i) / 12), b = point(Float(i + 1) / 12)
            let d = b - a
            pivot.box(simd_length(d) + 0.004, 0.003, 0.003, r: 0, twine, at: (a + b) / 2,
                      rotation: .z(atan2(d.y, d.x)))
        }
    }

    private func buildDesk() {
        let wood = Clay.matte(Tone.wood)
        let woodLight = Clay.matte(Tone.woodLight)
        let woodDark = Clay.matte(Tone.woodDark)

        pivot.box(0.9, 0.03, 0.34, r: 0.008, wood, at: [0, 0.325, -0.12])
        pivot.box(0.26, 0.31, 0.3, r: 0.006, wood, at: [-0.3, 0.155, -0.12])
        for y: Float in [0.23, 0.09] {
            pivot.box(0.22, 0.12, 0.01, r: 0.003, woodLight, at: [-0.3, y, 0.031])
            pivot.box(0.04, 0.015, 0.012, r: 0.004, Clay.matte(Tone.honey), at: [-0.3, y, 0.038])
        }
        for z: Float in [0.0, -0.25] {
            pivot.box(0.035, 0.31, 0.035, r: 0.006, woodDark, at: [0.41, 0.155, z])
        }
    }

    private func buildLamp() {
        Props.bookStack(pivot, at: [-0.33, 0.34, -0.2], tones: [0x6F8FB0, 0xE98A5B], rotation: .y(0.2))
        let metal = Clay.matte(Tone.woodDark)
        pivot.cylinder(0.012, 0.045, metal, at: [-0.33, 0.375, -0.2])
        pivot.box(0.012, 0.13, 0.012, r: 0.003, metal, at: [-0.308, 0.437, -0.2], rotation: .z(-0.35))
        pivot.cylinder(0.06, 0.05, Clay.glow(0xF7ECD8, intensity: 0.8), at: [-0.27, 0.5, -0.16],
                       rotation: .z(0.5))
        lampLight = pivot.group(at: [-0.27, 0.46, -0.12])
    }

    private func buildSheet() {
        sheet.position = [-0.02, 0.342, -0.04]
        sheet.orientation = .y(0.04)
        pivot.addChild(sheet)

        sheet.box(0.3, 0.003, 0.2, r: 0.001, Clay.matte(Tone.paper, roughness: 1), at: .zero)
        sheet.model(.generatePlane(width: 0.26, height: 0.086), Self.drawHereMaterial(),
                    at: [0, 0.002, -0.025], rotation: .x(-.pi / 2))

        let pencil = sheet.group(at: [0.1, 0.006, 0.075], rotation: .y(0.25))
        pencil.cylinder(0.14, 0.006, Clay.matte(Tone.honey), at: .zero, rotation: .z(.pi / 2))
        pencil.sphere(0.006, Clay.matte(0xF4A6A6), at: [0.074, 0, 0], scale: [2.2, 1, 1])

        Self.tappable(sheet, size: [0.32, 0.03, 0.22], at: .zero)
    }

    /// "draw here" and a curved arrow on a clear sheet, so only the ink shows on the paper.
    private static func drawHereMaterial() -> PhysicallyBasedMaterial {
        let size = CGSize(width: 512, height: 170)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let ink = UIColor(hex: Tone.ink)
            let font = UIFont(name: "Noteworthy-Bold", size: 84) ?? .systemFont(ofSize: 84, weight: .bold)
            ("draw here" as NSString).draw(at: CGPoint(x: 6, y: 40), withAttributes: [
                .font: font, .foregroundColor: ink,
            ])

            ink.setStroke()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: 344, y: 138))
            arrow.addQuadCurve(to: CGPoint(x: 470, y: 70), controlPoint: CGPoint(x: 470, y: 146))
            arrow.move(to: CGPoint(x: 448, y: 92))
            arrow.addLine(to: CGPoint(x: 470, y: 70))
            arrow.addLine(to: CGPoint(x: 488, y: 94))
            arrow.lineWidth = 7
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.stroke()
        }

        guard let cg = image.cgImage,
              let texture = try? TextureResource(image: cg, options: .init(semantic: .color)) else {
            return Clay.matte(Tone.paper, roughness: 1)
        }
        var m = Clay.matte(0xFFFFFF, roughness: 1)
        m.baseColor = .init(tint: .white, texture: .init(texture))
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        return m
    }

    private func buildDeskProps() {
        pivot.box(0.07, 0.025, 0.07, r: 0.003, Clay.matte(0xFFD86A), at: [-0.22, 0.353, 0.0], rotation: .y(-0.25))
        Props.snakePlant(pivot, at: [0.1, 0.34, -0.24], pot: 0xE9D9B8)
        pivot.cylinder(0.07, 0.03, Clay.matte(0xF2E6D2, roughness: 0.4), at: [0.33, 0.375, 0.03])
        pivot.box(0.012, 0.035, 0.03, r: 0.006, Clay.matte(0xF2E6D2, roughness: 0.4), at: [0.362, 0.378, 0.03])
    }

    private func buildLighting() {
        receiveAmbient(from: ibl)
        if let image = Self.gradientImage(top: Daylight.rgb(0xFFE7C4), bottom: Daylight.rgb(0xB97A45)) {
            Task { [weak self] in
                guard let env = try? await EnvironmentResource(equirectangular: image), let self else { return }
                ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: -0.4))
            }
        }

        var sunLight = DirectionalLightComponent(color: UIColor(hex: 0xFFE2B8), intensity: 300)
        sunLight.isRealWorldProxy = false
        sun.components.set(sunLight)
        Self.castShadow(sun)
        sun.look(at: .zero, from: [1.0, 1.5, 1.2], relativeTo: pivot)
        pivot.addChild(sun)

        // Soft light from the viewer's side, so the wall reads straight on.
        fill.components.set(DirectionalLightComponent(color: UIColor(hex: 0xFFE2C4), intensity: 220))
        fill.look(at: .zero, from: [1.5, 1.4, 1.6], relativeTo: nil)
        root.addChild(fill)

        var p = PointLightComponent(color: UIColor(hex: 0xFFC27A), intensity: 900, attenuationRadius: 1.0)
        p.attenuationFalloffExponent = 2
        lampLight.components.set(p)

        addBloom()
    }
}
