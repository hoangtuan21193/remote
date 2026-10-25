import Foundation

/// The app switcher (2026-10-25; .planboard/strip-gestures, D3 and D7): a row of tiles across the
/// middle of the stream, as the Mac's ⌘Tab shows, that a three-finger swipe left or right opens and
/// steps through. The Desktop is the first tile, then one tile per app with a window, the app last
/// used first (the one on screen), as ⌘Tab orders them; the Mac's window list gives the apps, this
/// device's own use their order (`Recents`).
///
/// A swipe left steps forward (to the app used before), right steps back, round the ends. The tile
/// lit when the fingers have been still for `pause` seconds is chosen; a tap on a tile chooses it at
/// once, a tap outside the row closes it with nothing chosen. Choosing an app streams the window of
/// it last on screen here, or its first while none of its windows was; choosing the tile already
/// streaming changes nothing.
struct AppSwitcherPolicy: Equatable {
    static let pause: Double = 0.6

    enum Tile: Hashable {
        case desktop
        case app(String)    // bundle ID
    }

    /// One window as the Mac lists it: what the switcher needs of it.
    struct Window: Equatable {
        let id: UInt32
        let bundleID: String
    }

    /// What streams now, as the switcher sees it.
    enum Showing: Equatable {
        case nothing
        case desktop
        case window(UInt32)
    }

    /// This device's use of the apps, most recent first, and the window of each last on screen.
    struct Recents: Equatable {
        private(set) var order: [String] = []
        private(set) var lastWindow: [String: UInt32] = [:]

        /// A window came on screen here: its app goes first.
        mutating func note(window id: UInt32, bundleID: String) {
            order.removeAll { $0 == bundleID }
            order.insert(bundleID, at: 0)
            lastWindow[bundleID] = id
        }
    }

    /// The tiles: the Desktop, then the apps with windows, used here most recently first, then those
    /// never used here in the window list's order.
    static func tiles(windows: [Window], recents: Recents) -> [Tile] {
        var apps: [String] = []
        for w in windows where !apps.contains(w.bundleID) { apps.append(w.bundleID) }
        let used = recents.order.filter { apps.contains($0) }
        let rest = apps.filter { !used.contains($0) }
        return [.desktop] + (used + rest).map { .app($0) }
    }

    /// The tile of what streams now; nil while nothing does.
    static func current(_ showing: Showing, windows: [Window], tiles: [Tile]) -> Int? {
        switch showing {
        case .nothing: return nil
        case .desktop: return tiles.firstIndex(of: .desktop)
        case .window(let id):
            guard let app = windows.first(where: { $0.id == id })?.bundleID else { return nil }
            return tiles.firstIndex(of: .app(app))
        }
    }

    /// The row on screen, its tiles fixed while it shows, and the lit one.
    private(set) var tiles: [Tile] = []
    private(set) var lit: Int? = nil
    /// When the lit tile is chosen, unless another swipe comes first (seconds, the device's uptime).
    private(set) var chooseAt: Double? = nil

    var isOpen: Bool { lit != nil }

    /// A swipe: `forward` for left. Opens the row lit one step from what streams (from before the
    /// first tile while nothing does), or steps the lit tile, and restarts the pause.
    mutating func swipe(forward: Bool, windows: [Window], showing: Showing, recents: Recents, now: Double) {
        if lit == nil {
            tiles = Self.tiles(windows: windows, recents: recents)
            let from = Self.current(showing, windows: windows, tiles: tiles) ?? (forward ? -1 : 0)
            lit = Self.step(from, forward: forward, count: tiles.count)
        } else if let at = lit {
            lit = Self.step(at, forward: forward, count: tiles.count)
        }
        chooseAt = now + Self.pause
    }

    /// The row closes without a choice (a tap outside it, the session ending).
    mutating func close() {
        tiles = []
        lit = nil
        chooseAt = nil
    }

    /// The pause ran out: the lit tile, and the row closes; nil before its time or with no row.
    mutating func due(now: Double) -> Tile? {
        guard let at = chooseAt, now >= at, let i = lit, tiles.indices.contains(i) else { return nil }
        let tile = tiles[i]
        close()
        return tile
    }

    /// A tap on a tile: it, and the row closes.
    mutating func tap(_ index: Int) -> Tile? {
        guard isOpen, tiles.indices.contains(index) else { return nil }
        let tile = tiles[index]
        close()
        return tile
    }

    /// What choosing `tile` streams: nil when it changes nothing (the tile already streaming, or an
    /// app whose windows have all gone).
    static func source(for tile: Tile, windows: [Window], showing: Showing, recents: Recents) -> Showing? {
        switch tile {
        case .desktop:
            return showing == .desktop ? nil : .desktop
        case .app(let bundleID):
            let mine = windows.filter { $0.bundleID == bundleID }
            guard let first = mine.first else { return nil }
            if case .window(let id) = showing, mine.contains(where: { $0.id == id }) { return nil }
            if let last = recents.lastWindow[bundleID], mine.contains(where: { $0.id == last }) { return .window(last) }
            return .window(first.id)
        }
    }

    private static func step(_ index: Int, forward: Bool, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let next = index + (forward ? 1 : -1)
        return ((next % count) + count) % count
    }
}
