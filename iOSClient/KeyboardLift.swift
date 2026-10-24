import CoreGraphics

/// How far the picture slides up while the software keyboard is up, so the Mac's caret stays above it
/// (docs/keyboard-auto-plan.md, D4 and D5). The picture keeps its size: the video and the input view
/// over it move up together inside their panel, its top going out of view, and only as far as the
/// caret needs; a caret already clear of the keyboard moves nothing.
///
/// Everything is in the input view's own points as it sits with no lift: the caret (the Mac's report,
/// or the last tap when the Mac says nothing), the keyboard's top, the view's height. Pure: CoreGraphics
/// only, checked in Tests/checks/keyboard-lift.
enum KeyboardLift {
    /// The room kept between the caret's bottom and the keyboard (its Mac keys bar included).
    static let margin: CGFloat = 12
    /// The room kept above the caret when the lift would push it out of the top.
    static let topMargin: CGFloat = 12
    /// A tap stands in for the caret when the Mac gives none: a line this tall, centred on it.
    static let tapLine: CGFloat = 24

    /// The lift for `caret` over a keyboard whose top is at `keyboardTop` (nil: none docked: down, a
    /// hardware keyboard's hold, iPadOS's floating keyboard), in a view `height` tall, moving from
    /// `current`. It changes only when the caret would be covered (up just enough to clear it) or
    /// pushed out of the top (down until it shows), so typing along one line keeps the picture still
    /// and a new line under the keyboard moves it one step. Never below zero, and never so far that the
    /// view's bottom rises above the keyboard. No caret: as it is, within those bounds.
    static func lift(caret: CGRect?, keyboardTop: CGFloat?, height: CGFloat, current: CGFloat) -> CGFloat {
        guard let keyboardTop, height > 0 else { return 0 }
        let most = max(0, height - keyboardTop)
        var lift = current
        if let caret {
            if caret.minY - lift < topMargin { lift = caret.minY - topMargin }
            if caret.maxY - lift > keyboardTop - margin { lift = caret.maxY + margin - keyboardTop }
        }
        return min(max(lift, 0), most)
    }

    /// The caret for a tap at `point`, when the Mac reports none.
    static func caret(forTap point: CGPoint) -> CGRect {
        CGRect(x: point.x, y: point.y - tapLine / 2, width: 0, height: tapLine)
    }

    /// The Mac's caret, as fractions of the frame, in a view where the frame is drawn at `video`.
    static func caret(x: Double, y: Double, w: Double, h: Double, in video: CGRect) -> CGRect? {
        guard video.width > 0, video.height > 0 else { return nil }
        return CGRect(x: video.minX + CGFloat(x) * video.width, y: video.minY + CGFloat(y) * video.height,
                      width: CGFloat(w) * video.width, height: CGFloat(h) * video.height)
    }

    /// The keyboard's top in the view as it sits with no lift, when it is docked: as wide as the screen
    /// and reaching its bottom (`frame`, on `screen`). Measured against the panel the view slides in,
    /// which never moves (`viewTop`, in the window, as `frameTop` is): the view's own place is part way
    /// through a slide while one runs. A floating or split keyboard, an empty input view and a keyboard
    /// going down count as none.
    static func keyboardTop(frame: CGRect, screen: CGRect, frameTop: CGFloat, viewTop: CGFloat) -> CGFloat? {
        guard frame.height > 0, frame.width >= screen.width - 1, frame.maxY >= screen.maxY - 1 else { return nil }
        return frameTop - viewTop
    }
}
