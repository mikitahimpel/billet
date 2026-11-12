import Foundation

/// How wide a view the room is framed for. The camera's field of view is vertical, so a narrower screen would see
/// less of the room's width; the fit keeps the width an iPhone SE shows and spends the extra height instead.
enum RoomFit {
    /// Width over height of the screen the room's framing is drawn for (iPhone SE, 375 x 667).
    static let referenceAspect: Float = 375.0 / 667.0

    /// The vertical field of view, in degrees, that shows at least what `degrees` shows at the reference aspect
    /// across the width of a view `aspect` wide. Wider views keep `degrees`.
    static func verticalFieldOfView(_ degrees: Float, aspect: Float) -> Float {
        guard aspect > 0, aspect < referenceAspect else { return degrees }
        let half = tan(degrees * .pi / 360) * referenceAspect / aspect
        return 2 * atan(half) * 180 / .pi
    }
}
