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
    /// The mini-game being played, if any.
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
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    /// `usesStandIn` leaves the real room out (UI tests, where RealityKit can't draw) and gives games a bare one.
    init(usesStandIn: Bool = UserDefaults.standard.bool(forKey: "uitestNoRoom"), catLife: CatLife = CatRoom.catLife) {
        self.usesStandIn = usesStandIn
        self.catLife = catLife
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    deinit { statusTask?.cancel() }

    // MARK: Loading

    /// Builds Mochi's room and starts reading her status. Called after the first frame, so launch shows the backdrop.
    func load() {
        guard home == nil, !usesStandIn else { return }
        let room = DioramaScene()
        home = room
        wire(room)
        if !polaroids.isEmpty { room.setPolaroids(polaroids) }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    var isStandIn: Bool { usesStandIn }
    var hasHome: Bool { home != nil }
    var hasBoard: Bool { board != nil }
    var isReady: Bool { home?.isReady == true }
    var cityWindowView: FlatWindowView? { city?.windowView }

    /// The room the screen shows now.
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
        if let current { NookiPerf.shown(current, kind: kind) }
    }

    /// Returns once the room has drawn a frame it had not, or after `timeout`.
    func nextFrame(timeout: Duration = .seconds(2)) async {
        guard let room = current else { return }
        let start = room.frame
        let deadline = ContinuousClock.now + timeout
        while room.frame == start, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(8))
        }
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

    // MARK: The pair's cat

    /// Raises the pair's cat from its room through `client`, or this phone's own with nil.
    func connectCat(_ client: CatEventsClient?, pair: CatPair?) async {
        await catLife.connect(client, pair: pair)
    }

    /// Catches up on the journal and sends what waited offline.
    func syncCat() async { await catLife.sync() }

    func catEntryArrived(_ entry: CatEntry) { catLife.received(entry) }

    /// The journal entry a room socket resumes after; nil follows none.
    var lastCatSeq: Int? { catLife.lastSeq }

    func clearShowcase() { showcase = nil }

    // MARK: RoomControlling

    func purr() {
        petPulse += 1
        current?.purr()
    }

    func feed() { current?.director?.feed() }

    func appOpened() { current?.appOpened() }

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

    func refreshStatus() {
        let director = current?.director
        let next = CatStatus(rounding: director?.needs, mind: director?.mind)
        if next != status { status = next }
    }
}
