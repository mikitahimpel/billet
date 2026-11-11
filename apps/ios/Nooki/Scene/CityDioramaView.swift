import QuartzCore
import UIKit

/// The street behind the Bedroom's window: four clay image layers that slide against each other as the room turns,
/// cross-faded between day, dusk and night, and a pair of cars on the street that drive on slowly and stand at the
/// crossing. Drawn flat at screen pixels under the room, clipped to the hole in its wall.
@MainActor
final class CityDioramaView: UIView {
    var reduceMotion = false

    private struct Stage: Equatable {
        var unit: CGFloat
        var origin: CGPoint

        /// From a window outline on screen: its bottom edge lines up with the sill.
        init?(window: [CGPoint]) {
            guard let first = window.first else { return nil }
            let box = window.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
            guard box.width > 1 else { return nil }
            unit = box.width / 100
            origin = CGPoint(x: box.minX, y: box.maxY - CityDiorama.stageHeight * unit)
        }

        init(unit: CGFloat, origin: CGPoint) {
            self.unit = unit
            self.origin = origin
        }

        func blended(with live: Stage, follow: CGFloat) -> Stage {
            Stage(
                unit: unit + (live.unit - unit) * follow,
                origin: CGPoint(
                    x: origin.x + (live.origin.x - origin.x) * follow,
                    y: origin.y + (live.origin.y - origin.y) * follow))
        }

        func rect(_ area: CGRect) -> CGRect {
            CGRect(x: origin.x + area.minX * unit, y: origin.y + area.minY * unit, width: area.width * unit,
                   height: area.height * unit)
        }
    }

    /// One picture per time of day, stacked and faded into each other.
    private final class Stack {
        let holder = CALayer()
        let times: [CALayer]
        let name: String

        init(name: String) {
            self.name = name
            times = CityDiorama.times.map { _ in CALayer() }
            for layer in times {
                layer.contentsGravity = .resize
                layer.minificationFilter = .linear
                holder.addSublayer(layer)
            }
        }

        func fade(_ opacities: [Float]) {
            for (layer, opacity) in zip(times, opacities) {
                layer.opacity = opacity
                layer.isHidden = opacity <= 0.001 || layer.contents == nil
            }
        }
    }

    private struct Sprite {
        let holder = CALayer()
        let stack = Stack(name: "cars")
    }

    private let opening = CALayer()
    private let clip = CAShapeLayer()
    private var stacks: [Stack] = []
    private var sprites: [Sprite] = []
    private var traffic = CityTraffic(plan: CityDiorama.plan, seed: 0xC17_CA25)
    private var parked = false
    private var live: Stage?
    private var home: Stage?
    private var outline: [CGPoint] = []
    private var weights: [Float] = [0, 0, 1]
    private var hour: Float = -1
    private var loaded: [String: CGImage] = [:]
    private var loading: Set<String> = []

    private(set) var isReady = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        opening.mask = clip
        layer.addSublayer(opening)
        stacks = CityDiorama.layers.map { Stack(name: $0.name) }
        // The cars go above the street and below a layer in front of them.
        for stack in stacks where stack.name != "near" { opening.addSublayer(stack.holder) }
        for _ in 0..<CityDiorama.plan.capacity {
            let sprite = Sprite()
            sprite.holder.addSublayer(sprite.stack.holder)
            sprite.holder.isHidden = true
            sprites.append(sprite)
            opening.addSublayer(sprite.holder)
        }
        for stack in stacks where stack.name == "near" { opening.addSublayer(stack.holder) }
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Outlines in this view's points; an empty outline hides the view.
    func place(window: [CGPoint], home: [CGPoint], hole: [CGPoint]) {
        let live = Stage(window: window)
        let home = Stage(window: home) ?? live
        guard live != self.live || home != self.home || hole != outline else { return }
        self.live = live
        self.home = home
        outline = hole
        layOut()
    }

    func tick(_ dt: Float, hour: Float) {
        guard live != nil, outline.count > 2 else { return }
        setHour(hour)
        if reduceMotion {
            if !parked {
                traffic.park(lane: 1, x: 0.33, colour: 1)
                parked = true
            }
        } else {
            parked = false
            traffic.step(dt)
        }
        layOutCars()
    }

    // MARK: - Light

    private func setHour(_ hour: Float) {
        guard abs(hour - self.hour) > 0.005 || self.hour < 0 else { return }
        self.hour = hour
        weights = CityDiorama.weights(hour: hour)
        let wanted = Set(neededTimes())
        for time in CityDiorama.times where wanted.contains(time) { load(time) }
        for time in CityDiorama.times where !wanted.contains(time) { unload(time) }
        fade()
    }

    /// The times on show now or within the next half hour either way, so a picture is ready before it fades in.
    private func neededTimes() -> [String] {
        var needed = Set<Int>()
        for offset: Float in [-0.5, 0, 0.5] {
            for (index, weight) in CityDiorama.weights(hour: hour + offset).enumerated() where weight > 0 {
                needed.insert(index)
            }
        }
        return needed.sorted().map { CityDiorama.times[$0] }
    }

    private func fade() {
        let opacities = CityDiorama.opacities(weights)
        for stack in stacks + sprites.map(\.stack) { stack.fade(opacities) }
        let shown = CityDiorama.times.indices.filter { weights[$0] > 0 }
        isReady = shown.allSatisfy { index in
            CityDiorama.layers.allSatisfy { loaded["\($0.name)_\(CityDiorama.times[index])"] != nil }
        }
    }

    private func key(_ name: String, _ time: String) -> String { "\(name)_\(time)" }

    private func load(_ time: String) {
        for name in CityDiorama.layers.map(\.name) + ["cars"] {
            let key = key(name, time)
            guard loaded[key] == nil, !loading.contains(key) else { continue }
            loading.insert(key)
            Task { [weak self] in
                let image = await Task.detached { Self.decode(key) }.value
                guard let self else { return }
                loading.remove(key)
                guard let image else { return }
                loaded[key] = image
                attach(key, image)
                fade()
            }
        }
    }

    private func unload(_ time: String) {
        for name in CityDiorama.layers.map(\.name) + ["cars"] {
            let key = key(name, time)
            guard loaded.removeValue(forKey: key) != nil else { continue }
            attach(key, nil)
        }
    }

    private func attach(_ key: String, _ image: CGImage?) {
        guard let split = key.lastIndex(of: "_"), let index = CityDiorama.times.firstIndex(of: String(key[key.index(after: split)...]))
        else { return }
        let name = String(key[..<split])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if name == "cars" {
            for sprite in sprites { sprite.stack.times[index].contents = image }
        } else {
            stacks.first { $0.name == name }?.times[index].contents = image
        }
    }

    private nonisolated static func decode(_ key: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "webp", subdirectory: "CityDiorama")
            ?? Bundle.main.url(forResource: key, withExtension: "webp"),
            let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        return (image.preparingForDisplay() ?? image).cgImage
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layOut()
    }

    private func layOut() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let live, let home, outline.count > 2 else {
            opening.isHidden = true
            return
        }
        opening.isHidden = false
        opening.frame = bounds
        clip.frame = bounds
        clip.path = Self.path(outline, grownBy: 1.03)
        for (stack, entry) in zip(stacks, CityDiorama.layers) {
            let stage = home.blended(with: live, follow: entry.follow)
            var frame = stage.rect(CityDiorama.imageRect)
            if entry.follow == 0 { frame = Self.covering(frame, opening: Self.bounds(outline)) }
            stack.holder.frame = frame
            for layer in stack.times { layer.frame = stack.holder.bounds }
        }
        if hour < 0 { setHour(Daylight.localHour()) }
        layOutCars()
    }

    private func layOutCars() {
        guard let live, let home, outline.count > 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let street = home.blended(with: live, follow: CityDiorama.layers.first { $0.name == "street" }?.follow ?? 0.62)
        let picture = street.rect(CityDiorama.imageRect)
        let window = Self.bounds(outline)
        for index in sprites.indices {
            let sprite = sprites[index]
            guard let car = traffic.slots[index] else {
                sprite.holder.isHidden = true
                continue
            }
            let lane = CityDiorama.plan.lanes[car.lane]
            let scale = CityDiorama.cars.scales[car.lane]
            let width = picture.width * scale / CGFloat(CityDiorama.cars.cells)
            let height = picture.height * scale * 213 / CityDiorama.size.height
            let centre = CGPoint(
                x: picture.minX + CGFloat(car.x) * picture.width,
                y: picture.minY + CGFloat(lane.y) * picture.height - height / 2)
            let box = CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
            sprite.holder.isHidden = !box.intersects(window)
            guard !sprite.holder.isHidden else { continue }
            sprite.holder.bounds = CGRect(origin: .zero, size: box.size)
            sprite.holder.position = centre
            sprite.holder.transform = CATransform3DMakeScale(CGFloat(lane.direction), 1, 1)
            sprite.stack.holder.frame = sprite.holder.bounds
            for layer in sprite.stack.times {
                layer.frame = sprite.stack.holder.bounds
                layer.contentsRect = CGRect(x: CGFloat(car.colour) / CGFloat(CityDiorama.cars.cells), y: 0,
                                            width: 1 / CGFloat(CityDiorama.cars.cells), height: 1)
            }
        }
    }

    /// The sky doesn't move with the room, so the opening can turn past its edge; it grows, keeping its shape, and
    /// slides until the whole opening is inside it.
    private static func covering(_ frame: CGRect, opening: CGRect) -> CGRect {
        let need = opening.insetBy(dx: -opening.width * 0.04, dy: -opening.height * 0.04)
        let scale = max(1, need.width / frame.width, need.height / frame.height)
        var out = frame.insetBy(dx: -frame.width * (scale - 1) / 2, dy: -frame.height * (scale - 1) / 2)
        out.origin.x = min(out.minX, need.minX)
        out.origin.x = max(out.minX, need.maxX - out.width)
        out.origin.y = min(out.minY, need.minY)
        out.origin.y = max(out.minY, need.maxY - out.height)
        return out
    }

    private static func bounds(_ points: [CGPoint]) -> CGRect {
        points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Grown about its middle so its edges hide behind the wall.
    private static func path(_ points: [CGPoint], grownBy factor: CGFloat) -> CGPath {
        let count = CGFloat(points.count)
        let centre = CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
        let path = CGMutablePath()
        path.addLines(between: points.map {
            CGPoint(x: centre.x + ($0.x - centre.x) * factor, y: centre.y + ($0.y - centre.y) * factor)
        })
        path.closeSubpath()
        return path
    }
}
