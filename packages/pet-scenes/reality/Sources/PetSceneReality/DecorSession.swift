import CoreGraphics
import Foundation
import Pet
import RealityKit
import simd

/// One step of decorating that can be undone.
enum DecorStep: Equatable {
  /// A piece was moved or turned from `from`.
  case moved(String, from: DecorBox)
  /// A piece from the closet was put in the room.
  case added(RoomLayout.Placement.ID)
  /// A piece went back to the closet from `box`.
  case putAway(ShopItem.ID, box: DecorBox)
}

/// Decorating one room: which piece is picked up, where it would go and whether it can, the
/// marker under it, and the steps to undo. The room gives it the pieces and the surfaces they
/// stand on: the floor, and others such as a seat's top or a table's. Each piece keeps to its own
/// surface. A surface is a plane in its parent's space, so a table's top moves with the table;
/// a piece's footprint is on its parent's x and z, and it rests at the height it was registered.
@MainActor
final class DecorSession {
  struct Piece {
    var holder: Entity
    /// Where it stood before anything moved it.
    var home: DecorBox
    /// The shop placement it shows, for a piece bought in the shop.
    var placement: RoomLayout.Placement.ID?
    /// The surface it stands on.
    var surface = DecorSession.floor
    /// Its height in its parent's space when it rests.
    var rest: Float = 0
  }

  /// A surface other than the floor: where its marker hangs, and how high over the surface.
  struct Surface {
    /// The entity whose space the surface is in, or nil for the floor's.
    var parent: Entity?
    var markerHeight: Float
  }

  nonisolated static let floor = "floor"

  /// The marker that shows under the piece picked up, added to the room by its owner.
  let marker = Entity()
  /// Where pieces may stand, by surface.
  private(set) var plans: [String: DecorPlan]
  private var surfaces: [String: Surface] = [:]
  /// The floor's plan.
  var plan: DecorPlan { plans[Self.floor] ?? DecorPlan(minimum: .zero, maximum: .zero, grid: 1) }
  /// The entity the marker hangs from on the floor, kept when it moves to another surface.
  private var floorParent: Entity?
  private(set) var pieces: [String: Piece] = [:]
  private(set) var selected: String?
  /// Where the piece picked up would go, and whether it can.
  private(set) var candidate: (box: DecorBox, fit: DecorPlan.Fit)?
  private(set) var history = DecorHistory<DecorStep>()
  /// True while decorating, so the room's pieces answer to touch.
  var isOn = false {
    didSet { if !isOn { deselect() } }
  }

  /// What blocks pieces on a surface for now, by name, asked as a piece there is picked up: the
  /// cat lying on the seat, say.
  var blockers: ((String) -> [String: DecorBox])?
  /// Told where a piece now stands, after a move that stuck or an undo.
  var onMoved: ((String, Piece, DecorBox) -> Void)?
  /// Told when the selection, the fit or what can be undone changes, for the controls.
  var onChange: (() -> Void)?

  /// How high a piece picked up floats, in the room's units.
  private let liftHeight: Float
  private var lift: Float = 0
  /// Seconds the ring under the piece picked up has been breathing.
  private var breath: Float = 0
  private var grab = SIMD2<Float>.zero
  private var turnStart: Float?
  /// True while a finger moves the piece picked up.
  private(set) var isDragging = false
  /// True while two fingers turn it.
  var isTurning: Bool { turnStart != nil }
  /// A piece to pick up as soon as it is registered, such as one just taken from the closet.
  var selectWhenRegistered: String?
  private var shown: [String: SIMD2<Float>] = [:]
  private var shownYaw: [String: Float] = [:]
  private var settling: [String: Float] = [:]

  private static let followRate: Float = 22
  private static let liftRate: Float = 14

  /// How high over the floor the marker lies, clear of rugs.
  private let markerHeight: Float
  /// How far the marker reaches past the footprint on each side.
  private let markerMargin: Float

  init(plan: DecorPlan, liftHeight: Float, markerHeight: Float? = nil, markerMargin: Float? = nil) {
    plans = [Self.floor: plan]
    self.liftHeight = liftHeight
    self.markerHeight = markerHeight ?? liftHeight * 0.06
    self.markerMargin = markerMargin ?? liftHeight * 0.6
    marker.name = "decor-marker"
    marker.isEnabled = false
  }

  // MARK: - Pieces

  /// Adds a surface other than the floor, such as a seat's top, for pieces registered on it.
  func addSurface(_ key: String, plan: DecorPlan, parent: Entity?, markerHeight: Float) {
    plans[key] = plan
    surfaces[key] = Surface(parent: parent, markerHeight: markerHeight)
  }

  /// The surface the piece `name` stands on.
  func surface(of name: String) -> String { pieces[name]?.surface ?? Self.floor }

  /// The plan of the surface the piece `name` stands on.
  func plan(of name: String) -> DecorPlan? { plans[surface(of: name)] }

  /// Whether `box` is somewhere the piece `name` could stand on its surface: finite, and with its
  /// middle no further than half a unit past the surface's edges. Anything else is bad data,
  /// saved by an older release or sent by a partner, and the piece stays where the room put it.
  func canStand(_ name: String, at box: DecorBox) -> Bool {
    guard let plan = plan(of: name),
      box.centre.x.isFinite, box.centre.y.isFinite, box.yaw.isFinite, abs(box.yaw) <= 2 * .pi
    else { return false }
    let margin: SIMD2<Float> = [0.5, 0.5]
    return all(box.centre .>= plan.minimum - margin) && all(box.centre .<= plan.maximum + margin)
  }

  /// The piece `name`'s holder and the height it rests at in its parent's space.
  func rest(of name: String) -> (holder: Entity, height: Float)? {
    pieces[name].map { ($0.holder, $0.rest) }
  }

  private func boxOf(_ name: String) -> DecorBox? { plans[surface(of: name)]?.pieces[name] }

  private func setBox(_ name: String, _ box: DecorBox?) {
    plans[surface(of: name)]?.pieces[name] = box
  }

  /// Makes a piece movable, standing where its holder stands now, on `surface`. A piece that
  /// `slidesOnly` keeps its depth and turn, moving only along the surface's width.
  func register(
    _ name: String, holder: Entity, half: SIMD2<Float>, placement: RoomLayout.Placement.ID? = nil,
    isFlat: Bool = false, surface: String = DecorSession.floor, slidesOnly: Bool = false
  ) {
    let box = DecorBox(
      centre: SIMD2(holder.position.x, holder.position.z), half: half,
      yaw: Self.yaw(of: holder.orientation))
    pieces[name] = Piece(
      holder: holder, home: box, placement: placement, surface: surface,
      rest: holder.position.y)
    plans[surface]?.pieces[name] = box
    if isFlat { plans[surface]?.flat.insert(name) } else { plans[surface]?.flat.remove(name) }
    if slidesOnly {
      plans[surface]?.slidesOnly.insert(name)
    } else {
      plans[surface]?.slidesOnly.remove(name)
    }
    if selectWhenRegistered == name, isOn {
      selectWhenRegistered = nil
      select(name: name)
    }
  }

  func unregister(_ name: String) {
    if selected == name { deselect() }
    let surface = surface(of: name)
    pieces[name] = nil
    plans[surface]?.pieces[name] = nil
    plans[surface]?.flat.remove(name)
    plans[surface]?.slidesOnly.remove(name)
    shown[name] = nil
    settling[name] = nil
  }

  func addFixed(_ name: String, _ box: DecorBox, on surface: String = DecorSession.floor) {
    plans[surface]?.fixed[name] = box
  }

  /// Something on `surface` that blocks pieces for now, such as the cat lying there, or nil to
  /// clear it.
  func setBlocker(_ name: String, _ box: DecorBox?, on surface: String) {
    plans[surface]?.fixed[name] = box
  }

  /// Whether the piece `name` can be turned.
  func canTurn(_ name: String) -> Bool { plan(of: name)?.slidesOnly.contains(name) == false }

  /// Puts a piece where something outside decorating says, such as the stored layout or a change
  /// from the shop, keeping the plan in step with it.
  func place(_ name: String, at box: DecorBox) {
    guard let piece = pieces[name] else { return }
    if let current = boxOf(name), simd_distance(current.centre, box.centre) < 0.0001,
      abs(current.yaw - box.yaw) < 0.0001
    {
      return
    }
    setBox(name, box)
    guard selected != name else { return }
    stand(piece, at: box)
    shown[name] = nil
  }

  /// The name of the piece `entity` is part of, if any.
  func piece(containing entity: Entity) -> String? {
    var current: Entity? = entity
    while let entity = current {
      if let name = pieces.first(where: { $0.value.holder === entity })?.key { return name }
      current = entity.parent
    }
    return nil
  }

  func name(of placement: RoomLayout.Placement.ID) -> String? {
    pieces.first { $0.value.placement == placement }?.key
  }

  /// Every piece back where it first stood.
  func resetAll() -> [String] {
    deselect()
    history.clear()
    var moved: [String] = []
    for (name, piece) in pieces where piece.placement == nil {
      guard boxOf(name) != piece.home else { continue }
      setBox(name, piece.home)
      stand(piece, at: piece.home)
      onMoved?(name, piece, piece.home)
      moved.append(name)
    }
    onChange?()
    return moved
  }

  // MARK: - Picking up

  /// Picks up the piece `entity` belongs to. Returns whether there was one.
  @discardableResult
  func select(_ entity: Entity) -> Bool {
    guard let name = piece(containing: entity) else { return false }
    select(name: name)
    return true
  }

  func select(name: String) {
    guard let piece = pieces[name], let box = boxOf(name) else { return }
    if let selected, selected != name { settleSelected() }
    if floorParent == nil { floorParent = marker.parent }
    let parent = surfaces[piece.surface]?.parent ?? floorParent
    if let parent, marker.parent !== parent { marker.setParent(parent) }
    for (blocker, area) in blockers?(piece.surface) ?? [:] {
      plans[piece.surface]?.fixed[blocker] = area
    }
    selected = name
    candidate = (box, .free)
    lift = 0
    marker.isEnabled = true
    onChange?()
  }

  func deselect() {
    guard selected != nil else { return }
    settleSelected()
    selected = nil
    candidate = nil
    marker.isEnabled = false
    onChange?()
  }

  /// A finger starts moving the piece picked up, from the floor point `point`.
  func beginDrag(at point: SIMD2<Float>) {
    guard let selected, let box = boxOf(selected) else { return }
    grab = box.centre - point
    isDragging = true
    onChange?()
  }

  /// The finger is over the floor point `point`.
  func drag(to point: SIMD2<Float>) {
    guard isDragging, let selected, let current = candidate else { return }
    candidate = plan(of: selected)?.candidate(for: selected, at: point + grab, yaw: current.box.yaw)
    onChange?()
  }

  /// The finger lifts: a free spot is kept, a blocked one sends the piece back.
  func endDrag() {
    guard isDragging else { return }
    isDragging = false
    commit()
  }

  /// A two-finger twist begins on the piece picked up.
  func beginTurn() {
    guard let selected, canTurn(selected), let box = boxOf(selected) else { return }
    turnStart = candidate?.box.yaw ?? box.yaw
    onChange?()
  }

  /// Turns by `angle` radians since the twist began; clockwise on screen turns clockwise from above.
  func turn(by angle: Float) {
    guard let selected, let start = turnStart, let current = candidate else { return }
    let yaw = start - angle
    candidate = plan(of: selected)?.candidate(for: selected, at: current.box.centre, yaw: yaw)
    onChange?()
  }

  func endTurn() {
    guard turnStart != nil else { return }
    turnStart = nil
    if !isDragging { commit() }
  }

  /// Turns the piece picked up a quarter of the way round, or as far short of that as fits.
  func rotateStep() {
    guard let selected, canTurn(selected), let box = boxOf(selected), let plan = plan(of: selected)
    else { return }
    for steps in [6, 3, 9, 12] {
      let yaw = box.yaw - Float(steps) * plan.turnStep
      if let next = plan.candidate(for: selected, at: box.centre, yaw: yaw), next.fit.isFree {
        candidate = next
        commit()
        return
      }
    }
    candidate = plan.candidate(for: selected, at: box.centre, yaw: box.yaw - .pi / 2)
    onChange?()
    commit()
  }

  private func commit() {
    guard let selected, let piece = pieces[selected], let candidate,
      let before = boxOf(selected)
    else { return }
    if candidate.fit.isFree, candidate.box != before {
      setBox(selected, candidate.box)
      history.record(.moved(selected, from: before))
      onMoved?(selected, piece, candidate.box)
    } else {
      self.candidate = (before, .free)
    }
    onChange?()
  }

  private func settleSelected() {
    if isDragging || turnStart != nil {
      isDragging = false
      turnStart = nil
      commit()
    }
    guard let selected else { return }
    settling[selected] = 0
  }

  // MARK: - Undo

  /// Undoes the newest step. A step that changed the closet is handed back for the owner to undo.
  func undo() -> DecorStep? {
    guard let step = history.undo() else { return nil }
    if case .moved(let name, let from) = step, let piece = pieces[name] {
      setBox(name, from)
      if selected == name { candidate = (from, .free) } else { stand(piece, at: from) }
      shown[name] = nil
      onMoved?(name, piece, from)
    }
    onChange?()
    return step
  }

  func record(_ step: DecorStep) {
    history.record(step)
    onChange?()
  }

  // MARK: - Updates

  /// Eases the piece picked up towards where it would go, lifts it, and settles what was let go.
  func step(_ delta: Float, reduceMotion: Bool) {
    let follow = reduceMotion ? 1 : 1 - exp(-Self.followRate * delta)
    if let selected, let piece = pieces[selected], let candidate {
      let goal = reduceMotion ? 0 : liftHeight
      lift += (goal - lift) * (reduceMotion ? 1 : 1 - exp(-Self.liftRate * delta))
      let from = shown[selected] ?? SIMD2(piece.holder.position.x, piece.holder.position.z)
      let at = from + (candidate.box.centre - from) * follow
      shown[selected] = at
      let fromYaw = shownYaw[selected] ?? Self.yaw(of: piece.holder.orientation)
      let yaw = fromYaw + Self.wrapped(candidate.box.yaw - fromYaw) * follow
      shownYaw[selected] = yaw
      piece.holder.position = [at.x, piece.rest + lift, at.y]
      piece.holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
      placeMarker(candidate.box, fit: candidate.fit)
      breath += delta
      let calm = reduceMotion || !candidate.fit.isFree
      marker.components.set(
        OpacityComponent(opacity: calm ? 1 : 0.8 + 0.2 * (0.5 + 0.5 * cos(breath * 2.4))))
    } else {
      breath = 0
    }
    for (name, elapsed) in settling {
      guard let piece = pieces[name], let box = boxOf(name) else {
        settling[name] = nil
        continue
      }
      let next = elapsed + delta
      let done = reduceMotion || next >= 0.45
      let start = shown[name] ?? box.centre
      let at = start + (box.centre - start) * min(next / 0.2, 1)
      let height = done ? 0 : Self.bounce(next) * liftHeight * 3
      piece.holder.position = [at.x, piece.rest + height, at.y]
      piece.holder.orientation = simd_quatf(angle: box.yaw, axis: [0, 1, 0])
      if done {
        settling[name] = nil
        shown[name] = nil
        shownYaw[name] = nil
      } else {
        settling[name] = next
      }
    }
  }

  /// True while a piece is picked up or settling.
  var isMoving: Bool { selected != nil || !settling.isEmpty }

  /// Height of a piece settling after it is let go: a small hop that dies away.
  static func bounce(_ elapsed: Float) -> Float {
    0.35 * exp(-7 * elapsed) * abs(cos(elapsed * 10))
  }

  private func placeMarker(_ box: DecorBox, fit: DecorPlan.Fit) {
    let height = selected.flatMap { surfaces[surface(of: $0)]?.markerHeight } ?? markerHeight
    marker.position = [box.centre.x, height, box.centre.y]
    marker.orientation = simd_quatf(angle: box.yaw, axis: [0, 1, 0])
    marker.scale = [box.half.x * 2 + markerMargin * 2, 1, box.half.y * 2 + markerMargin * 2]
    let isFree = fit.isFree
    guard markerIsFree != isFree, let model = marker.children.first as? ModelEntity else { return }
    markerIsFree = isFree
    model.model?.materials = [Self.markerMaterial(free: isFree)]
  }

  private var markerIsFree: Bool?

  /// Builds the marker, one unit square to be scaled to each footprint: a soft glowing ring on the
  /// floor round the piece, with a faint wash inside it.
  func buildMarker() {
    guard marker.children.isEmpty else { return }
    let plane = ModelEntity(
      mesh: .generatePlane(width: 1, depth: 1, cornerRadius: 0),
      materials: [Self.markerMaterial(free: true)])
    marker.addChild(plane)
    marker.position.y = markerHeight
  }

  private static func markerMaterial(free: Bool) -> UnlitMaterial {
    let tint: UnlitMaterial.Color =
      free
      ? .init(red: 1, green: 0.84, blue: 0.48, alpha: 1)
      : .init(red: 0.96, green: 0.36, blue: 0.28, alpha: 1)
    // Untouched by the room's tone mapping, so the ring stays bright over a lamp-lit floor.
    var material = UnlitMaterial(applyPostProcessToneMap: false)
    material.color = .init(tint: tint)
    if let ring = ringTexture {
      material.blending = .transparent(opacity: .init(scale: 1, texture: .init(ring)))
    } else {
      material.blending = .transparent(opacity: .init(floatLiteral: 0.5))
    }
    return material
  }

  private static let ringTexture: TextureResource? = {
    guard let image = ringImage(pixels: 128) else { return nil }
    return try? TextureResource(image: image, options: .init(semantic: .raw))
  }()

  /// How opaque the marker is across its square, white for solid: a rounded ring a little in from
  /// the edge, glowing to both sides, round a faint wash.
  nonisolated static func ringImage(pixels: Int) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    let side = CGFloat(pixels)
    context.setFillColor(gray: 0, alpha: 1)
    let square = CGRect(x: 0, y: 0, width: side, height: side)
    let ring = square.insetBy(dx: side * 0.15, dy: side * 0.15)
    context.fill(square)
    let path = CGPath(
      roundedRect: ring, cornerWidth: ring.width * 0.24, cornerHeight: ring.height * 0.24,
      transform: nil)
    context.addPath(path)
    context.setFillColor(gray: 1, alpha: 0.18)
    context.fillPath()
    context.setShadow(offset: .zero, blur: side * 0.09, color: CGColor(gray: 1, alpha: 1))
    context.addPath(path)
    context.setStrokeColor(gray: 1, alpha: 1)
    context.setLineWidth(side * 0.045)
    context.strokePath()
    return context.makeImage()
  }

  private func stand(_ piece: Piece, at box: DecorBox) {
    let holder = piece.holder
    holder.position = [box.centre.x, piece.rest, box.centre.y]
    holder.orientation = simd_quatf(angle: box.yaw, axis: [0, 1, 0])
  }

  static func yaw(of orientation: simd_quatf) -> Float {
    let turned = orientation.act([1, 0, 0])
    return atan2(-turned.z, turned.x)
  }

  private static func wrapped(_ angle: Float) -> Float { atan2(sin(angle), cos(angle)) }
}
