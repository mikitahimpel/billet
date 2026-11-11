import DecorInterface
import FeatureGames
import GamesInterface
import Observation
import Pet
import RealityKit
import RoomInterface
import SwiftUI
import WidgetInterface
import WidgetKit
import WindowViews
import Wire

/// The room's one handle for the rest of the app: it owns the scenes, the corner a game is played in and the
/// cat's coarse status, takes commands (`RoomControlling`) and reports taps as `RoomEvent`s. The shell holds it
/// and never reads a scene.
@MainActor
@Observable
final class RoomController: RoomControlling, CatStatusProviding {
    let events: AsyncStream<RoomEvent>
    @ObservationIgnored private let emit: AsyncStream<RoomEvent>.Continuation

    private(set) var status = CatStatus()
    /// The label of the animation Play all is showing, while it plays.
    private(set) var showcase: String?
    private(set) var game: MiniGame?
    /// Where the game is played, while one is.
    private(set) var scenery: GameScenery = .room
    /// The corner the game is played in, while its scenery is one.
    private(set) var corner: TabletopRoom?
    /// Bumped for every pet, so the heart bubble pulses.
    private(set) var petPulse = 0

    private(set) var home: DioramaScene?
    private(set) var city: CityRoomScene?
    private(set) var board: BoardRoomScene?
    private(set) var shown: RoomScene = .home
    /// The cat's life the brain runs on; `connectCat` makes it the pair's.
    @ObservationIgnored let catLife: CatLife
    @ObservationIgnored let probe = RoomProbe()
    @ObservationIgnored private var publishedNeeds: CatNeedsGlance?

    @ObservationIgnored private let usesStandIn: Bool
    @ObservationIgnored private let ownLoop: Bool
    /// The renderer and frame loop the room draws with when Labs asks for them, kept for the app's life: the room's
    /// entities live in it, and a renderer freed and made again would draw them blank.
    @ObservationIgnored private(set) lazy var loop: RoomRenderLoop? = ownLoop ? RoomRenderLoop() : nil
    @ObservationIgnored private lazy var standIn = CatRoom()
    /// An empty room the room's view holds while no room can be seen (see `RoomStage`).
    @ObservationIgnored private(set) lazy var offStage = CatRoom()
    @ObservationIgnored private var polaroids: [UIImage] = []
    @ObservationIgnored private var motes = false
    @ObservationIgnored let decorStage = DecorStage()
    @ObservationIgnored var decor = RoomDecor()
    @ObservationIgnored var decorRetries = 0
    @ObservationIgnored private var sway = true
    @ObservationIgnored private var pins: [BoardPin] = []
    /// The scenery last picked for each game, for the next time it is played.
    @ObservationIgnored private var picked: [MiniGame: GameScenery] = [:]
    @ObservationIgnored private var partnerNotice = PartnerNoticeMachine.State.away
    @ObservationIgnored private let defaults: UserDefaults
    /// A homecoming not told yet: since when this phone was away, and until when the partner's care still counts as
    /// news, as the journal may arrive a little after the app opens.
    @ObservationIgnored private var homecoming: (since: Date, until: Date)?

    /// How long after opening the partner's care, once it arrives, is still told.
    static let homecomingWindow: TimeInterval = 30

    /// `usesStandIn` leaves the real room out (UI tests, where RealityKit can't draw) and gives games a bare one.
    init(usesStandIn: Bool = UserDefaults.standard.bool(forKey: "uitestNoRoom"), catLife: CatLife = CatRoom.catLife,
         defaults: UserDefaults = .standard) {
        self.usesStandIn = usesStandIn
        #if DEBUG || LABS_YES
        ownLoop = PerfLabMachine.State.saved(in: defaults).isOn(.ownLoop)
        #else
        ownLoop = false
        #endif
        self.catLife = catLife
        self.defaults = defaults
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    // MARK: Loading

    /// Builds Mochi's room. Called after the first frame, so launch shows the backdrop.
    func load() {
        guard home == nil, !usesStandIn else { return }
        let room = DioramaScene()
        home = room
        room.pivot.addChild(decorStage.root)
        wire(room)
        showDecor(decor)
        if !polaroids.isEmpty { room.setPolaroids(polaroids) }
    }

    /// Returns once the room looks finished, or after `timeout`.
    func ready(timeout: Duration) async {
        await ScreenFrames.until(timeout: timeout) { [weak self] in self?.isReady != false }
    }

    var isStandIn: Bool { usesStandIn }
    var hasHome: Bool { home != nil }
    var hasBoard: Bool { board != nil }
    var isReady: Bool { home?.isReady == true }
    var cityWindowView: CityWindowView? { city?.windowView }

    var current: CatRoom? {
        guard home != nil else { return nil }
        return scene(for: shown)
    }

    func scene(for kind: RoomScene) -> CatRoom? {
        guard let home else { return nil }
        switch kind {
        case .home: return home
        case .city: return city ?? home
        case .board: return board ?? home
        }
    }

    private func wire(_ room: CatRoom) {
        room.onShowcase = { [weak self] label in withAnimation(.snappy(duration: 0.25)) { self?.showcase = label } }
        if !motes { Self.show(motes: false, in: room) }
        room.swaying = sway
    }

    /// Lets every room sway and pulse, or holds it still.
    func setSway(_ on: Bool) {
        guard on != sway else { return }
        sway = on
        for room in [home, city, board].compactMap({ $0 }) { room.swaying = on }
    }

    /// Shows or hides the dust motes in every room, those built now and those built later.
    func showMotes(_ on: Bool) {
        guard on != motes else { return }
        motes = on
        for room in [home, city, board].compactMap({ $0 }) { Self.show(motes: on, in: room) }
    }

    /// A disabled emitter is not simulated, where one left on is stepped every frame the room is drawn.
    private static func show(motes on: Bool, in room: CatRoom) {
        func visit(_ entity: Entity) {
            if entity.components.has(ParticleEmitterComponent.self) { entity.isEnabled = on }
            entity.children.forEach(visit)
        }
        visit(room.root)
    }

    // MARK: Showing a room

    /// Makes `target` the room that is driven, stopping the one before it. A room is built on first use, unless
    /// `prepare` built it before, and kept: building the City on the main thread costs a switch its frames, and
    /// a stopped room only holds memory.
    func show(_ target: RoomScene) {
        guard target != shown else { return }
        scene(for: shown)?.stop()
        prepare(target)
        shown = target
    }

    /// Builds `target` without showing it, for a moment when the room is off screen and a dropped frame can't be
    /// seen, so the first switch to it only shows it.
    func prepare(_ target: RoomScene) {
        guard home != nil else { return }
        switch target {
        case .home: break
        case .board:
            if board == nil { board = makeBoard() }
        case .city:
            if city == nil {
                let built = CityRoomScene()
                wire(built)
                city = built
            }
        }
    }

    func perfShown(_ kind: RoomKind) {
        guard let current else { return }
        OurioPerf.shown(current, kind: kind)
        if kind == .home, game == nil, let game = OurioPerf.game() { play(game) }
    }

    /// Returns once the room has drawn a frame it had not, or after `timeout`.
    func nextFrame(timeout: Duration = .seconds(2)) async {
        guard let room = current else { return }
        let start = room.frame
        await ScreenFrames.until(timeout: timeout) { room.frame != start }
    }

    func stop() { current?.stop() }

    // MARK: What the room shows

    func setPolaroids(_ images: [UIImage]) {
        polaroids = images
        home?.setPolaroids(images)
    }

    func setPins(_ pins: [BoardPin]) {
        self.pins = pins
        board?.setPins(pins)
    }

    private func makeBoard() -> BoardRoomScene {
        let room = BoardRoomScene()
        wire(room)
        room.onOpen = { [emit] in emit.yield(.pinOpened($0)) }
        room.onDraw = { [emit] in emit.yield(.drawAsked) }
        room.setPins(pins)
        return room
    }

    func petted() { emit.yield(.catPetted) }

    func decorTouched(_ gesture: DecorGesture) { emit.yield(.decor(gesture)) }

    func careAsked() { emit.yield(.careAsked) }

    /// The partner's phone opened the app: the cat perks up and glances off toward the door.
    func partnerSeen(here: Bool, visible: Bool) {
        let (next, outputs) = PartnerNoticeMachine.transition(partnerNotice, .input(partnerHere: here, visible: visible))
        partnerNotice = next
        for output in outputs {
            switch output {
            case .notice: current?.director?.partnerArrived()
            }
        }
    }

    // MARK: The pair's cat

    /// Raises the pair's cat from its room through `client`, or this phone's own with nil.
    func connectCat(_ client: CatEventsClient?, pair: CatPair?) async {
        await catLife.connect(client, pair: pair)
        tellHomecoming()
    }

    func syncCat() async {
        await catLife.sync()
        tellHomecoming()
    }

    /// True while something still waits on the network.
    func flushCat() async -> Bool { await catLife.flush() }

    func catEntryArrived(_ entry: CatEntry) {
        catLife.received(entry)
        tellHomecoming()
    }

    /// Opening after `CatDirector.greetAfter` away is a homecoming, read before her greeting moves the mark.
    func cameHome(now: Date = .now) {
        guard let last = CatDirector.lastSeen(in: defaults), now.timeIntervalSince(last) >= CatDirector.greetAfter
        else { return }
        homecoming = (last, now.addingTimeInterval(Self.homecomingWindow))
    }

    /// Tells what the partner did while this phone was away, once, if it has arrived in time.
    func tellHomecoming(now: Date = .now) {
        guard let homecoming else { return }
        guard now <= homecoming.until else {
            self.homecoming = nil
            return
        }
        let care = catLife.partnerCare(since: homecoming.since)
        guard !care.isEmpty else { return }
        self.homecoming = nil
        emit.yield(.partnerCared(care))
    }

    /// The journal entry a room socket resumes after; nil follows none.
    var lastCatSeq: Int? { catLife.lastSeq }

    func clearShowcase() { showcase = nil }

    // MARK: RoomControlling

    func purr() {
        petPulse += 1
        current?.purr()
    }

    func feed() { current?.director?.feed() }

    func appOpened() {
        cameHome()
        tellHomecoming()
        current?.appOpened()
    }

    func playAll() { current?.playAll() }

    func play(_ game: MiniGame) {
        scenery = GameScenery.start(game, last: picked[game])
        if scenery.isCorner, !usesStandIn { corner = TabletopRoom(scenery: scenery) }
        withAnimation(.easeInOut(duration: 0.25)) { self.game = game }
    }

    func endGame() {
        if let corner, let room = current { corner.leave(to: room) }
        withAnimation(.easeInOut(duration: 0.25)) { game = nil }
        corner = nil
    }

    /// Moves the game being played to `next`: one corner is dressed as another with the game carrying on; between the
    /// room and a corner the game starts over there, once the game layer has closed it here.
    func showScenery(_ next: GameScenery) {
        guard let game, next != scenery, GameScenery.options(for: game).contains(next) else { return }
        picked[game] = next
        let was = scenery
        withAnimation(.easeInOut(duration: 0.25)) { scenery = next }
        guard !usesStandIn else { return }
        switch (was.isCorner, next.isCorner) {
        case (true, true): corner?.dress(next)
        case (false, true): corner = TabletopRoom(scenery: next)
        case (true, false):
            if let corner, let room = current { corner.leave(to: room) }
            corner = nil
        case (false, false): break
        }
    }

    /// True while the game is played in a corner of its own, not in the room.
    var playsInCorner: Bool { scenery.isCorner && !usesStandIn }

    /// The room a game in the room itself is played in.
    var gameRoom: CatRoom? { current ?? (usesStandIn ? standIn : nil) }

    // MARK: Status

    /// Reads her status now and then once a second, until cancelled.
    func watchStatus() async {
        while !Task.isCancelled {
            refreshStatus()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func refreshStatus() {
        let director = current?.director
        let next = CatStatus(rounding: director?.needs, mind: director?.mind)
        if next != status { status = next }
        publishNeeds(director?.needs)
    }

    /// Hands her needs to the widgets, which reload only when what she asks for changes.
    private func publishNeeds(_ needs: PetNeeds?) {
        guard let needs else { return }
        let glance = CatNeedsGlance(full: needs.full, rested: needs.rested, loved: needs.loved,
                                    playful: needs.playful, lowBelow: LifeConfig.standard.lowBelow, savedAt: .now)
        guard glance.differsForWidgets(from: publishedNeeds) else { return }
        publishedNeeds = glance
        glance.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
