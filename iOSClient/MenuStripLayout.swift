import CoreGraphics

/// The Mac's menu bar as a thin strip along the top of the stream (2026-10-25): the streamed app's
/// menu titles in a row, as the Mac draws them, each opening its menu where it sits
/// (`MacMenuStrip`). Settings › Mac menu bar turns it on and off (`StreamClient.menuStripKey`). It
/// sits under the landscape bar, and at the screen's top edge while the bar is hidden, so the menus
/// are one tap away whether the bar shows or not.
///
/// Where each title goes, from the titles' widths alone (the glue measures them in the strip's
/// font): left to right from `side`, each `titlePad` either side of its words; never across the
/// fold's band in the iPhone Duo's book pose (a title that would cross it starts after it); never
/// into `trailingRoom` (the stashed bar's tab, over the strip's end while the bar is hidden). Titles
/// that do not all fit leave the first that does not and every one after it to the `more` button
/// (»), at the strip's trailing end, in the Mac's order, so the order on screen and in the overflow
/// is always the Mac's.
struct MenuStripLayout: Equatable {
    static let height: CGFloat = 32
    static let side: CGFloat = 8
    static let titlePad: CGFloat = 10
    static let moreWidth: CGFloat = 40

    struct Slot: Equatable {
        /// The title's index in the Mac's top level.
        let index: Int
        let frame: CGRect
    }

    /// The titles shown, in the Mac's order.
    let slots: [Slot]
    /// The » button, when some titles did not fit.
    let more: CGRect?
    /// The titles in the » button's menu, in the Mac's order.
    let overflow: [Int]

    /// `fold`: the fold's band in the strip's own coordinates (the book pose), nil elsewhere.
    init(width: CGFloat, titleWidths: [CGFloat], fold: ClosedRange<CGFloat>? = nil, trailingRoom: CGFloat = 0) {
        let end = width - Self.side - max(0, trailingRoom)
        let all = Self.place(titleWidths, from: Self.side, to: end, fold: fold)
        if all.count == titleWidths.count {
            slots = all
            more = nil
            overflow = []
            return
        }
        let moreX = end - Self.moreWidth
        let shown = Self.place(titleWidths, from: Self.side, to: moreX, fold: fold)
        slots = shown
        overflow = Array(shown.count..<titleWidths.count)
        more = moreX >= Self.side ? CGRect(x: moreX, y: 0, width: Self.moreWidth, height: Self.height) : nil
    }

    /// The titles from the first, left to right, until one does not fit before `end`.
    private static func place(_ widths: [CGFloat], from start: CGFloat, to end: CGFloat,
                              fold: ClosedRange<CGFloat>?) -> [Slot] {
        var out: [Slot] = []
        var x = start
        for (i, w) in widths.enumerated() {
            let width = max(0, w) + 2 * titlePad
            if let fold, x < fold.upperBound, x + width > fold.lowerBound { x = fold.upperBound }
            guard x + width <= end else { break }
            out.append(Slot(index: i, frame: CGRect(x: x, y: 0, width: width, height: height)))
            x += width
        }
        return out
    }
}
