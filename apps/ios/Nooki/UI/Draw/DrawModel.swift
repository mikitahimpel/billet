import FeatureCanvas
import Foundation
import Ink
import Observation
import QuartzCore
import SwiftUI
import Transport
import Wire

/// The lock-screen drawing: this phone's strokes, the partner's strokes when both have the canvas open, and sending
/// the finished drawing as a note.
@MainActor
@Observable
final class DrawModel {
    enum Tool { case pen, eraser }

    enum SendState: Equatable { case idle, sending, failed }

    /// Marker width as a fraction of the canvas width: about 12 points on a 390-point phone.
    static let penWidth = 0.032
    /// How close to a stroke the eraser has to pass, as a fraction of the canvas width.
    static let eraserReach = 0.04

    var tool = Tool.pen
    var ink = PaletteInk.free
    var wallpaper = riddleWallpaper
    static let riddleWallpaper = LockWallpaper.blush
    var photo: UIImage?
    private(set) var sendState = SendState.idle

    /// This phone's finished strokes, oldest first.
    private(set) var strokes: [Stroke] = []
    /// The stroke under the finger.
    private(set) var current: Stroke?
    /// Earlier versions of `strokes`. Snapshots rather than single strokes, so undo also brings back what the
    /// eraser or a clear took.
    private var undoStack: [[Stroke]] = []
    private var erasing = false

    private var batcher = LiveStrokeBatcher()
    private var ticker: Task<Void, Never>?

    /// The pair's room socket; nil without a server or a partner, and then the canvas is this phone's alone.
    let room: LiveRoom?
    let partnerName: String

    init(room: LiveRoom?, partnerName: String) {
        self.room = room
        self.partnerName = partnerName
        room?.onClear = { [weak self] in self?.wipe() }
    }

    // MARK: What is on the canvas

    /// The partner's strokes, finished and in progress.
    var partnerStrokes: [Stroke] {
        guard let room else { return [] }
        return room.state.strokes + room.state.openStrokes.keys.sorted().compactMap { room.state.openStrokes[$0] }
    }

    /// Everything on the canvas, as it is sent.
    var drawing: [Stroke] { (room?.state.strokes ?? []) + strokes }

    var isPartnerDrawing: Bool { room?.state.partner == .drawing }
    var isEmpty: Bool { drawing.isEmpty }
    var canUndo: Bool { current == nil && !undoStack.isEmpty }

    // MARK: Lifecycle

    func appeared() {
        room?.connect()
        room?.setDrawing(true)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                self?.tick()
            }
        }
    }

    func disappeared() {
        finishStroke()
        ticker?.cancel()
        room?.setDrawing(false)
        room?.disconnect()
    }

    // MARK: Drawing

    /// The finger at `point` (unit-square coordinates) while it is down.
    func touch(_ point: Point) {
        switch tool {
        case .pen: draw(point)
        case .eraser: erase(at: point)
        }
    }

    func lift() {
        erasing = false
        finishStroke()
    }

    private func draw(_ point: Point) {
        let now = CACurrentMediaTime()
        guard let stroke = current else {
            current = Stroke(color: PaletteInk.wire(ink.dark), width: Self.penWidth, points: [point])
            send(batcher.begin(color: PaletteInk.wire(ink.dark), width: Self.penWidth, at: point, time: now))
            return
        }
        current = Stroke(color: stroke.color, width: stroke.width, points: stroke.points + [point])
        send(batcher.add(point, time: now))
    }

    private func finishStroke() {
        guard let stroke = current else { return }
        current = nil
        send(batcher.end())
        undoStack.append(strokes)
        strokes.append(stroke)
    }

    /// Takes away this phone's strokes that the eraser passes over; the partner's are theirs to erase.
    private func erase(at point: Point) {
        let reach = Self.eraserReach
        let kept = strokes.filter { stroke in
            !stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) < reach + stroke.width / 2 }
        }
        guard kept.count != strokes.count else { return }
        if !erasing { undoStack.append(strokes) }
        erasing = true
        strokes = kept
    }

    func undo() {
        guard canUndo, let previous = undoStack.popLast() else { return }
        strokes = previous
    }

    /// Wipes the canvas for both partners. Undo brings this phone's strokes back.
    func clear() {
        finishStroke()
        guard !isEmpty else { return }
        room?.sendLive(.clear)
        wipe()
    }

    private func wipe() {
        current = nil
        if !strokes.isEmpty { undoStack.append(strokes) }
        strokes = []
    }

    private func tick() {
        send(batcher.tick(time: CACurrentMediaTime()))
    }

    private func send(_ frames: [ClientMessage]) {
        for frame in frames { room?.sendLive(frame) }
    }

    // MARK: Sending

    /// Sends the drawing as a note (the image to /v1/media, then the compact strokes to /v1/notes) and keeps it in
    /// Moments. Without a server it only goes to Moments.
    func send(api: APIClient?, canvas: CGSize, state: HomeState) async -> Bool {
        await send { drawing in
            if let api {
                do {
                    try await Self.post(drawing, canvas: canvas, paper: wallpaper.paper, api: api)
                } catch {
                    return false
                }
            }
            if let keepsake = DrawingImage.keepsake(drawing, canvas: canvas, wallpaper: wallpaper, photo: photo) {
                state.journal.addMoment(keepsake, caption: "For \(partnerName)")
            }
            return true
        }
    }

    /// Hands the finished drawing to `deliver`, which says whether it went, and keeps `sendState` while it runs. A
    /// note and a Draw & guess riddle go out through it.
    func send(_ deliver: ([Stroke]) async -> Bool) async -> Bool {
        finishStroke()
        let drawing = self.drawing
        guard !drawing.isEmpty, sendState != .sending else { return false }
        sendState = .sending
        let sent = await deliver(drawing)
        sendState = sent ? .idle : .failed
        return sent
    }

    private static func post(_ drawing: [Stroke], canvas: CGSize, paper: PaperColor, api: APIClient) async throws {
        let (png, compact) = try encoded(drawing, canvas: canvas)
        let upload = try await api.uploadImage(png)
        _ = try await api.sendNote(
            .drawing(key: .make(), compact: compact, image: upload.image, paper: paper))
    }

    /// The drawing as it is sent: its PNG for /v1/media and its compact strokes.
    static func encoded(_ drawing: [Stroke], canvas: CGSize) throws -> (png: Data, compact: CompactStrokes) {
        guard let png = DrawingImage.png(drawing, canvas: canvas) else { throw InkError.encodingFailed }
        return (png, try InkEncoder.encodeWithinBudget(drawing))
    }
}

/// Renders a drawing to images.
@MainActor
enum DrawingImage {
    /// The ink alone on a clear background, the canvas's shape: what widgets and history lay on their wallpaper.
    static func png(_ strokes: [Stroke], canvas: CGSize) -> Data? {
        let renderer = ImageRenderer(content: InkLayer(strokes: strokes).frame(width: canvas.width, height: canvas.height))
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }

    /// The drawing on its wallpaper, for Moments.
    static func keepsake(_ strokes: [Stroke], canvas: CGSize, wallpaper: LockWallpaper, photo: UIImage?) -> UIImage? {
        let content = ZStack {
            LockWallpaperView(wallpaper: wallpaper, photo: photo)
            InkLayer(strokes: strokes)
        }
        .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.uiImage
    }
}
