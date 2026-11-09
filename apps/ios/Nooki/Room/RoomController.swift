import GamesInterface
import Observation
import Pet
import RoomInterface
import SwiftUI
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
    /// Where feed, water and brush are played, while one is.
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

    @ObservationIgnored private let usesStandIn: Bool
    @ObservationIgnored private lazy var standIn = CatRoom()
    @ObservationIgnored private var polaroids: [UIImage] = []
    @ObservationIgnored private var pins: [BoardPin] = []
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
        wire(room)
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
    var cityWindowView: FlatWindowView? { city?.windowView }

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
    }

    // MARK: Showing a room

    /// Makes `target` the room that is driven, stopping the one before it. The City is built here and released when
    /// the Room comes back; the corkboard is built on first use and kept.
    func show(_ target: RoomScene) {
        guard target != shown else { return }
        let previous = shown
        scene(for: previous)?.stop()
        shown = target
        switch target {
        case .board:
            if board == nil { board = makeBoard() }
        case .city:
            if city == nil {
                let built = CityRoomScene()
                wire(built)
                city = built
            }
        case .home:
            if previous == .city {
                city?.stop()
                city = nil
            }
        }
    }

    func perfShown(_ kind: RoomKind) {
        if let current { OurioPerf.shown(current, kind: kind) }
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

    func careAsked() { emit.yield(.careAsked) }

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
        if Self.usesCorner(game), !usesStandIn { corner = TabletopRoom() }
        withAnimation(.easeInOut(duration: 0.25)) { self.game = game }
    }

    func endGame() {
        if let corner, let room = current { corner.leave(to: room) }
        withAnimation(.easeInOut(duration: 0.25)) { game = nil }
        corner = nil
    }

    /// The laser stays in the room; the others have their own scene.
    static func usesCorner(_ game: MiniGame) -> Bool { game != .laser }

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
    }
}
