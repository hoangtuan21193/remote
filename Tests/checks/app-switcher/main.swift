// iOSClient/AppSwitcherPolicy.swift on its own: the app switcher of a three-finger swipe (D3, D7 of
// .planboard/strip-gestures). Pinned cases (the tiles' order, opening from a window, from the Desktop,
// from nothing, stepping round the ends, the pause, taps, what a choice streams), then random sessions
// against a model: the lit tile always one of the row's, a choice only after the pause, never twice.
//   swiftc -O iOSClient/AppSwitcherPolicy.swift Tests/checks/app-switcher/main.swift -o .build/checks/app-switcher/check && .build/checks/app-switcher/check
import Foundation

typealias P = AppSwitcherPolicy
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }

let pages = "com.apple.iWork.Pages", safari = "com.apple.Safari", notes = "com.apple.Notes"
let windows: [P.Window] = [.init(id: 1, bundleID: pages), .init(id: 2, bundleID: safari),
                           .init(id: 3, bundleID: safari), .init(id: 4, bundleID: notes)]

// MARK: - The tiles

var recents = P.Recents()
check("tiles: Desktop first, then the window list's order while nothing was used",
      P.tiles(windows: windows, recents: recents) == [.desktop, .app(pages), .app(safari), .app(notes)])
recents.note(window: 4, bundleID: notes)
recents.note(window: 3, bundleID: safari)
check("tiles: the app used last first, then the one before, then the rest",
      P.tiles(windows: windows, recents: recents) == [.desktop, .app(safari), .app(notes), .app(pages)])
check("tiles: an app used here whose windows have gone has no tile",
      P.tiles(windows: windows.filter { $0.bundleID != notes }, recents: recents) == [.desktop, .app(safari), .app(pages)])
check("tiles: none but the Desktop with no windows", P.tiles(windows: [], recents: recents) == [.desktop])
check("recents: a window again moves its app first and remembers it",
      { var r = recents; r.note(window: 1, bundleID: pages); return r.order == [pages, safari, notes] && r.lastWindow[pages] == 1 }())

// MARK: - Opening and stepping

do {
    var s = P()
    check("closed at first", !s.isOpen && s.due(now: 100) == nil)
    s.swipe(forward: true, windows: windows, showing: .window(3), recents: recents, now: 10)
    check("left from Safari lights the app used before it (Notes)", s.lit == 2 && s.tiles[2] == .app(notes))
    check("the pause runs from the swipe", s.chooseAt == 10 + P.pause)
    check("nothing chosen before the pause", s.due(now: 10.5) == nil && s.isOpen)
    s.swipe(forward: true, windows: windows, showing: .window(3), recents: recents, now: 10.5)
    check("another left steps on (Pages) and restarts the pause", s.lit == 3 && s.chooseAt == 10.5 + P.pause)
    s.swipe(forward: true, windows: windows, showing: .window(3), recents: recents, now: 10.7)
    check("left from the last tile goes round to the Desktop", s.lit == 0)
    s.swipe(forward: false, windows: windows, showing: .window(3), recents: recents, now: 10.8)
    check("right steps back round the end", s.lit == 3)
    check("chosen at the pause's end, and the row closes", s.due(now: 10.8 + P.pause) == .app(pages) && !s.isOpen)
    check("nothing chosen twice", s.due(now: 20) == nil)
}
do {
    var s = P()
    s.swipe(forward: false, windows: windows, showing: .window(3), recents: recents, now: 0)
    check("right from the first app lights the Desktop", s.lit == 0 && s.tiles[0] == .desktop)
    var d = P()
    d.swipe(forward: true, windows: windows, showing: .desktop, recents: recents, now: 0)
    check("left from the Desktop lights the app used last", d.lit == 1 && d.tiles[1] == .app(safari))
    var n = P()
    n.swipe(forward: true, windows: windows, showing: .nothing, recents: recents, now: 0)
    check("left with nothing streaming lights the Desktop", n.lit == 0)
    var nb = P()
    nb.swipe(forward: false, windows: windows, showing: .nothing, recents: recents, now: 0)
    check("right with nothing streaming lights the last tile", nb.lit == 3)
    var u = P()
    u.swipe(forward: true, windows: windows, showing: .window(99), recents: recents, now: 0)
    check("a window not in the list counts as nothing streaming", u.lit == 0)
    var e = P()
    e.swipe(forward: true, windows: [], showing: .desktop, recents: P.Recents(), now: 0)
    check("only the Desktop: it stays lit", e.lit == 0 && e.tiles == [.desktop])
}
do {
    var s = P()
    s.swipe(forward: true, windows: windows, showing: .window(3), recents: recents, now: 0)
    check("a tap chooses that tile at once and closes", s.tap(1) == .app(safari) && !s.isOpen && s.due(now: 5) == nil)
    var t = P()
    check("a tap with no row chooses nothing", t.tap(0) == nil)
    t.swipe(forward: true, windows: windows, showing: .window(3), recents: recents, now: 0)
    check("a tap outside the tiles chooses nothing", t.tap(9) == nil && t.isOpen)
    t.close()
    check("closed: nothing lit, nothing due", !t.isOpen && t.due(now: 9) == nil)
    var f = P()
    f.swipe(forward: true, windows: windows, showing: .window(3), recents: recents, now: 0)
    let fixed = f.tiles
    var later = recents; later.note(window: 1, bundleID: pages)
    f.swipe(forward: true, windows: windows, showing: .window(1), recents: later, now: 0.1)
    check("the row's tiles stay as they opened while it shows", f.tiles == fixed)
}

// MARK: - What a choice streams

check("Desktop: the Desktop", P.source(for: .desktop, windows: windows, showing: .window(1), recents: recents) == .desktop)
check("Desktop while it streams: nothing", P.source(for: .desktop, windows: windows, showing: .desktop, recents: recents) == nil)
check("an app: its window last on screen here", P.source(for: .app(safari), windows: windows, showing: .window(1), recents: recents) == .window(3))
check("an app never on screen here: its first window", P.source(for: .app(pages), windows: windows, showing: .desktop, recents: recents) == .window(1))
check("an app whose last window has gone: its first", P.source(for: .app(safari), windows: windows.filter { $0.id != 3 },
                                                                showing: .desktop, recents: recents) == .window(2))
check("the app already streaming: nothing", P.source(for: .app(safari), windows: windows, showing: .window(2), recents: recents) == nil)
check("an app with no windows left: nothing", P.source(for: .app(notes), windows: windows.filter { $0.bundleID != notes },
                                                         showing: .desktop, recents: recents) == nil)

// MARK: - Random sessions against a model

var rng = SystemRandomNumberGenerator()
var sessions = 0
for _ in 0..<5_000 {
    sessions += 1
    let count = Int.random(in: 0...6, using: &rng)
    let ws = (0..<count).map { P.Window(id: UInt32($0 + 1), bundleID: "app\(Int.random(in: 0...3, using: &rng))") }
    var r = P.Recents()
    for w in ws.shuffled(using: &rng).prefix(Int.random(in: 0...count, using: &rng)) { r.note(window: w.id, bundleID: w.bundleID) }
    let showing: P.Showing = [P.Showing.nothing, .desktop, ws.randomElement(using: &rng).map { .window($0.id) } ?? .nothing].randomElement(using: &rng)!
    var s = P()
    var now = 0.0, chosen = 0
    var modelLit: Int? = nil
    var bad: [String] = []
    for _ in 0..<12 {
        switch Int.random(in: 0...3, using: &rng) {
        case 0, 1:
            let fwd = Bool.random(using: &rng)
            let tiles = s.isOpen ? s.tiles : P.tiles(windows: ws, recents: r)
            let from = modelLit ?? P.current(showing, windows: ws, tiles: tiles) ?? (fwd ? -1 : 0)
            let wasOpen = s.isOpen
            s.swipe(forward: fwd, windows: ws, showing: showing, recents: r, now: now)
            let n = tiles.count
            let expect = ((from + (fwd ? 1 : -1)) % n + n) % n
            if s.lit != expect { bad.append("lit \(String(describing: s.lit)) not \(expect) (open before: \(wasOpen))") }
            modelLit = s.lit
        case 2:
            now += Double.random(in: 0...1, using: &rng)
            let before = s.lit, due = s.chooseAt
            if let tile = s.due(now: now) {
                chosen += 1
                if due == nil || now < due! { bad.append("chosen before its time") }
                if before == nil { bad.append("chosen with nothing lit") }
                if case .app(let b) = tile, !ws.contains(where: { $0.bundleID == b }) { bad.append("an app with no windows chosen") }
                modelLit = nil
            } else if let d = due, now >= d { bad.append("not chosen at its time") }
        default:
            s.close(); modelLit = nil
        }
        if let l = s.lit, !s.tiles.indices.contains(l) { bad.append("lit outside the row") }
        if s.isOpen != (s.chooseAt != nil) { bad.append("open without a pause or the reverse") }
    }
    if !bad.isEmpty { check("session \(sessions): \(bad.joined(separator: "; "))", false); break }
}
check("random: \(sessions) sessions", sessions == 5_000)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
