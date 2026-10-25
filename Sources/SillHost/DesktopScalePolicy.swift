import CoreGraphics
import Foundation

/// The Desktop's text size (`Viewport.desktop`, `WindowList.desktopScale`): which of the Mac
/// display's own modes the Desktop streams at for a device's text size, and when the display goes
/// back to its own mode. Pure: plain values in, a mode out; DisplayResolution.swift lists, applies
/// and remembers the modes, StreamCoordinator says what streams. Checked by Tests/checks/desktop-scale.
///
/// The rule. A device's `scale` is relative to today's look: 1.0 (or nil) is the display's own mode,
/// the one it had before Sill changed anything (`original`), unchanged; any other scale picks, among
/// the display's scaled modes of the original's shape, the one whose text on the device comes
/// nearest to `scale` times the original's (nearest in ratio, a tie going to the larger point size,
/// More Space). With the Desktop fitted whole into the device's panel, a mode's text is
/// `fit(mode) / fit(original)` the original's, `fit` being the panel's device points per Mac point;
/// for the same shape that is simply the original's point width over the mode's (1512 / 1147 = 1.32
/// for a 14-inch MacBook Pro's Larger Text).
///
/// Absolute device points per Mac point (the scale a window is fitted at) would not do for the
/// Desktop: a phone shows a whole 1512-point desktop at about 0.4, so every scale from 0.5 up would
/// land on the smallest mode, and 1.0 could never mean "as it is today".
enum DesktopScalePolicy {
    /// One of the display's modes, as `CGDisplayMode` describes it.
    struct Mode: Hashable, CustomStringConvertible {
        /// `ioDisplayModeID`. Not unique on its own (a HiDPI mode and its low-resolution twin can
        /// share it), so a mode is matched by every field (`==`).
        var id: Int32
        /// Points: what the Desktop's windows are laid out in.
        var width: Int
        var height: Int
        /// The framebuffer: twice the points for a HiDPI ("Retina") mode.
        var pixelWidth: Int
        var pixelHeight: Int
        /// Hz; 0 when the display does not say (some built-in panels).
        var refresh: Double
        /// `isUsableForDesktopGUI()`.
        var usable: Bool = true

        var isHiDPI: Bool { pixelWidth > width }
        var aspect: Double { height > 0 ? Double(width) / Double(height) : 0 }
        var description: String { "\(width)×\(height) pt" }
    }

    /// Modes whose width-to-height ratio is within this fraction of the original's count as its shape.
    static let aspectTolerance = 0.01
    /// A scale this close to 1 is 1: the display's own mode.
    static let unchangedBand = 0.005
    /// Refresh rates this close are the same rate (59.94 and 60).
    static let refreshTolerance = 0.5

    // MARK: Which mode

    /// The modes a scale may pick: usable for the desktop, the original's shape (±`aspectTolerance`),
    /// HiDPI when the original is HiDPI (a Retina display never drops to blurry low-resolution
    /// modes; a low-resolution original may go either way), one per point size. For each point size
    /// the original itself when it is that size, else the one most like it: the same HiDPI-ness,
    /// the refresh rate nearest the original's (rates within `refreshTolerance` of each other count as
    /// one), then the most pixels.
    static func candidates(_ modes: [Mode], original: Mode) -> [Mode] {
        let shape = original.aspect
        var best: [String: Mode] = [:]
        for m in modes where m.usable && m.width > 0 && m.height > 0 {
            guard shape > 0, abs(m.aspect / shape - 1) <= aspectTolerance else { continue }
            if original.isHiDPI && !m.isHiDPI { continue }
            let size = "\(m.width)x\(m.height)"
            if let held = best[size], !isBetter(m, than: held, original: original) { continue }
            best[size] = m
        }
        best["\(original.width)x\(original.height)"] = original
        return best.values.sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    }

    /// Between two modes of one point size: the one more like the original.
    static func isBetter(_ a: Mode, than b: Mode, original o: Mode) -> Bool {
        if (a.isHiDPI == o.isHiDPI) != (b.isHiDPI == o.isHiDPI) { return a.isHiDPI == o.isHiDPI }
        let da = abs(a.refresh - o.refresh), db = abs(b.refresh - o.refresh)
        if abs(da - db) > refreshTolerance { return da < db }
        return a.pixelWidth > b.pixelWidth
    }

    /// The panel's device points per Mac point with the whole of a `width`×`height`-point desktop
    /// fitted into it.
    static func fit(_ panel: CGSize, width: Int, height: Int) -> Double {
        min(Double(panel.width) / Double(width), Double(panel.height) / Double(height))
    }

    /// The text on the device in `mode`, relative to the original mode's: the rule's ratio. Without
    /// a usable panel (zero, negative, not finite) the point widths' ratio, which is the same for
    /// the same shape.
    static func textScale(of mode: Mode, original: Mode, panel: CGSize) -> Double {
        let usable = panel.width > 0 && panel.height > 0 && panel.width.isFinite && panel.height.isFinite
        guard usable else { return Double(original.width) / Double(mode.width) }
        return fit(panel, width: mode.width, height: mode.height) / fit(panel, width: original.width, height: original.height)
    }

    /// The mode for a device's `scale` (the rule above). Nil, not finite, 0 or less, or within
    /// `unchangedBand` of 1: the original, unchanged.
    static func mode(for scale: Double?, panel: CGSize, modes: [Mode], original: Mode) -> Mode {
        guard let scale, scale.isFinite, scale > 0, abs(scale - 1) >= unchangedBand else { return original }
        var chosen = original
        var distance = Double.infinity
        for m in candidates(modes, original: original) {
            let d = abs(log(textScale(of: m, original: original, panel: panel) / scale))
            if d < distance - 1e-9 || (abs(d - distance) <= 1e-9 && m.width > chosen.width) {
                chosen = m; distance = d
            }
        }
        return chosen
    }

    // MARK: Who asks

    /// What a device asked for the Desktop: its scale and its panel (device points).
    struct Request: Equatable {
        var scale: Double?
        var panel: CGSize
    }

    /// Each connected device's latest viewport that said `desktop` true, in arrival order: the newest
    /// is followed (the latest device's viewport). A viewport without `desktop` true takes that
    /// device's request back (an older device never has one), and a device that leaves takes its
    /// own with it, which hands the Desktop back to the device that asked before it, if any.
    struct Requests<Device: Hashable> {
        private var order: [(device: Device, request: Request)] = []

        init() {}

        mutating func viewport(from device: Device, desktop: Bool?, scale: Double?, panel: CGSize) {
            order.removeAll { $0.device == device }
            if desktop == true { order.append((device, Request(scale: scale, panel: panel))) }
        }

        mutating func left(_ device: Device) { order.removeAll { $0.device == device } }

        /// The newest device's request; nil when no connected device asked.
        var current: Request? { order.last?.request }
        var isEmpty: Bool { order.isEmpty }
    }

    // MARK: When

    /// The mode the display should be in: the requested one only while the Desktop streams (or is
    /// about to) and the host is not stopping, and some device asks; otherwise the original. So the
    /// display goes back to its own mode when the source leaves the Desktop, when the last device
    /// that asked takes its request back or leaves (the last device leaving stops the stream too),
    /// and when the host stops.
    static func target(desktopStreams: Bool, stopping: Bool, request: Request?, modes: [Mode], original: Mode) -> Mode {
        guard desktopStreams, !stopping, let request else { return original }
        return mode(for: request.scale, panel: request.panel, modes: modes, original: original)
    }

    /// The display's own mode, the one every scale is relative to and the one a restore goes back to.
    /// `stored`: the original kept before Sill's first change, `applied`: the mode Sill set last.
    /// While the display is still in the mode Sill set, the stored original; once someone else changed
    /// it (System Settings, another app), or before Sill changed anything, the mode it is in now: a
    /// choice made on the Mac is never undone, and becomes the original.
    static func original(stored: Mode?, applied: Mode?, current: Mode) -> Mode {
        if let stored, let applied, applied == current { return stored }
        return current
    }

    /// At launch, from what an earlier run kept (DisplayResolution's crash note): the mode to put the
    /// display back to, or nil to leave it. Only when the display is still in the mode that run set
    /// and the original is among its modes now; anything else (the window server already put it back,
    /// someone chose another mode, the display changed) is left as it is.
    static func recovery(stored: Mode, applied: Mode, current: Mode, modes: [Mode]) -> Mode? {
        guard current == applied, stored != current, modes.contains(stored) else { return nil }
        return stored
    }

    // MARK: TEST ONLY

    /// SILL_TEST_DESKTOP_MODES (a test host's stand-in display): comma-separated `WxH[@S][*]`, the
    /// points, the backing scale S (pixels per point, 1…3, default 2) and `*` on the mode the display
    /// is in (default the first). Every mode at 60 Hz, ids 1, 2, 3… in order. Nil for anything else:
    /// an empty list, a malformed entry, more than one `*`.
    static func testModes(_ spec: String) -> (modes: [Mode], current: Mode)? {
        var modes: [Mode] = []
        var current: Mode?
        for (i, raw) in spec.split(separator: ",", omittingEmptySubsequences: false).enumerated() {
            var entry = raw.trimmingCharacters(in: .whitespaces)
            let marked = entry.hasSuffix("*")
            if marked { entry.removeLast() }
            let parts = entry.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 1 || parts.count == 2 else { return nil }
            let backing = parts.count == 2 ? Int(parts[1]) : 2
            let size = parts[0].split(separator: "x", omittingEmptySubsequences: false).map { Int($0) }
            guard let backing, (1...3).contains(backing), size.count == 2, let w = size[0], let h = size[1],
                  w > 0, h > 0, w <= 16384, h <= 16384 else { return nil }
            let m = Mode(id: Int32(i + 1), width: w, height: h, pixelWidth: w * backing, pixelHeight: h * backing, refresh: 60)
            if marked {
                guard current == nil else { return nil }
                current = m
            }
            modes.append(m)
        }
        guard let first = modes.first else { return nil }
        return (modes, current ?? first)
    }
}
