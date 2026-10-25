// Sources/SillHost/DesktopScalePolicy.swift on its own: the Desktop's text size. Which of the Mac
// display's own modes a device's scale picks (realistic lists: a 14-inch MacBook Pro's built-in
// display, a 27-inch 4K display at "looks like 1920×1080", a 3:2 display in a low-resolution mode),
// what counts as a candidate (shape, HiDPI, usable, refresh), the nearest-in-ratio rule and its
// ties, whose request the Desktop follows, when the display goes back to its own mode, the crash
// note's recovery and the TEST ONLY stand-in's format. Then a sweep of every scale from 0.5 to 1.5 on
// each list against the invariants.
//   swiftc -O Sources/SillHost/DesktopScalePolicy.swift Tests/checks/desktop-scale/main.swift -o .build/checks/desktop-scale/check && .build/checks/desktop-scale/check
import CoreGraphics
import Foundation

typealias P = DesktopScalePolicy
typealias Mode = P.Mode
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }
func near(_ a: Double, _ b: Double, _ e: Double = 0.0005) -> Bool { abs(a - b) <= e }
var nextID: Int32 = 0
/// A mode of `w`×`h` points at `s` pixels per point and `hz`.
func M(_ w: Int, _ h: Int, _ s: Int = 2, _ hz: Double = 120, usable: Bool = true) -> Mode {
    nextID += 1
    return Mode(id: nextID, width: w, height: h, pixelWidth: w * s, pixelHeight: h * s, refresh: hz, usable: usable)
}
func pick(_ scale: Double?, _ modes: [Mode], _ original: Mode, panel: CGSize = CGSize(width: 1366, height: 1024)) -> Mode {
    P.mode(for: scale, panel: panel, modes: modes, original: original)
}
func size(_ m: Mode) -> String { "\(m.width)x\(m.height)" }
let iPhone = CGSize(width: 852, height: 393)      // an iPhone 16 Pro on its side: the Desktop is height-bound
let upright = CGSize(width: 393, height: 852)     // held upright: width-bound
let iPad = CGSize(width: 1366, height: 1024)

// MARK: - A 14-inch MacBook Pro's built-in display (3024×1964, 120 Hz)

// System Settings' five looks (1147×745 … 2056×1329, 1512×982 the default), each HiDPI at 60 and
// 120 Hz (the 60 first, so a candidate's refresh is chosen, not first seen), their low-resolution
// twins (kCGDisplayShowDuplicateLowResolutionModes), the panel's native 3024×1964 at 1×, the
// notch-less 16:10 sizes, and a mode not usable for the desktop.
let mbpOriginal = M(1512, 982)
let mbp: [Mode] = [
    M(1147, 745, 2, 60), M(1147, 745), M(1147, 745, 1),
    M(1352, 878, 2, 60), M(1352, 878), M(1352, 878, 1),
    M(1512, 982, 2, 60), mbpOriginal, M(1512, 982, 1),
    M(1800, 1169, 2, 60), M(1800, 1169), M(1800, 1169, 1),
    M(2056, 1329, 2, 60), M(2056, 1329), M(2056, 1329, 1),
    M(3024, 1964, 1), M(3024, 1964, 1, 60),
    M(1512, 945), M(1147, 717), M(1800, 1125), M(2056, 1285),
    M(756, 491, 2, 120, usable: false),
]
do {
    let c = P.candidates(mbp, original: mbpOriginal)
    check("MBP: the five looks are the candidates, smallest first: \(c.map(size))",
          c.map(size) == ["1147x745", "1352x878", "1512x982", "1800x1169", "2056x1329"])
    check("MBP: every candidate HiDPI at 120 Hz, as the original", c.allSatisfy { $0.isHiDPI && $0.refresh == 120 })
    check("MBP: the original itself is its size's candidate", c.contains(mbpOriginal))
    check("MBP: nil is the display's own mode", pick(nil, mbp, mbpOriginal) == mbpOriginal)
    check("MBP: 1.0 is the display's own mode", pick(1.0, mbp, mbpOriginal) == mbpOriginal)
    check("MBP: 1.004 is 1", pick(1.004, mbp, mbpOriginal) == mbpOriginal)
    for bad in [0, -1, Double.nan, Double.infinity] {
        check("MBP: \(bad) is the display's own mode", pick(bad, mbp, mbpOriginal) == mbpOriginal)
    }
    let want: [(Double, String)] = [(1.5, "1147x745"), (1.4, "1147x745"), (1.3, "1147x745"), (1.2, "1352x878"), (1.1, "1352x878"),
                                    (1.05, "1512x982"), (0.95, "1512x982"), (0.9, "1800x1169"), (0.8, "1800x1169"),
                                    (0.7, "2056x1329"), (0.6, "2056x1329"), (0.5, "2056x1329")]
    for (scale, expected) in want {
        let m = pick(scale, mbp, mbpOriginal, panel: iPhone)
        check("MBP: \(scale)× on an iPhone → \(expected) (got \(size(m)) at \(m.refresh) Hz, \(m.pixelWidth) px)",
              size(m) == expected && m.refresh == 120 && m.isHiDPI)
    }
    // Nearest in ratio, not in difference: 1.215 lies between 1352's 1.118 and 1147's 1.318, nearer the
    // second in ratio (0.0815 against 0.0829) and the first in difference (0.103 against 0.097).
    check("MBP: 1.215 → 1147×745 (nearest in ratio)", size(pick(1.215, mbp, mbpOriginal)) == "1147x745")
    // The text: the Desktop fitted whole into the panel. 2056×1329 is not quite the original's shape
    // (+0.47%), so a height-bound panel and a width-bound one differ.
    let wide = mbp.first { $0.width == 2056 && $0.refresh == 120 && $0.isHiDPI }!
    check("MBP: 2056×1329's text on a wide panel is 982/1329 the original's",
          near(P.textScale(of: wide, original: mbpOriginal, panel: iPhone), 982.0 / 1329))
    check("MBP: and on an upright one 1512/2056", near(P.textScale(of: wide, original: mbpOriginal, panel: upright), 1512.0 / 2056))
    check("MBP: no panel: the widths' ratio", near(P.textScale(of: wide, original: mbpOriginal, panel: .zero), 1512.0 / 2056))
    check("MBP: a panel not finite: the widths' ratio",
          near(P.textScale(of: wide, original: mbpOriginal, panel: CGSize(width: CGFloat.infinity, height: 400)), 1512.0 / 2056))
    check("MBP: fit is the smaller side's", near(P.fit(iPhone, width: 1512, height: 982), 393.0 / 982))
    let small = mbp.first { $0.width == 1147 && $0.refresh == 120 && $0.isHiDPI }!
    check("MBP: 1147×745 shows text 1.318× the original's", near(P.textScale(of: small, original: mbpOriginal, panel: iPad), 1512.0 / 1147, 0.002))
    // The same original at 60 Hz (a ProMotion panel capped): the 60 Hz twins.
    let at60 = mbp.first { $0.width == 1512 && $0.height == 982 && $0.refresh == 60 && $0.isHiDPI }!
    let c60 = P.candidates(mbp, original: at60)
    check("MBP at 60 Hz: the 60 Hz twins", c60.count == 5 && c60.allSatisfy { $0.refresh == 60 && $0.isHiDPI })
    check("MBP at 60 Hz: 1.3× → 1147×745 at 60 Hz", pick(1.3, mbp, at60).refresh == 60)
}

// MARK: - A 27-inch 4K display at "looks like 1920×1080" (3840×2160, 60 Hz)

let k4Original = M(1920, 1080, 2, 60)
let k4: [Mode] = [
    M(1280, 720, 2, 60), M(1504, 846, 2, 60), k4Original, M(2560, 1440, 2, 60), M(3008, 1692, 2, 60),
    M(3840, 2160, 1, 60), M(1920, 1080, 1, 60), M(2560, 1440, 1, 60), M(1280, 720, 1, 60),
    M(1024, 768, 1, 60), M(1600, 1200, 1, 60), M(1920, 1200, 2, 60),
    M(1920, 1080, 2, 50), M(1280, 720, 2, 50), M(1920, 1080, 2, 30),
]
do {
    let c = P.candidates(k4, original: k4Original)
    check("4K: candidates \(c.map(size))", c.map(size) == ["1280x720", "1504x846", "1920x1080", "2560x1440", "3008x1692"])
    check("4K: all HiDPI at 60 Hz", c.allSatisfy { $0.isHiDPI && $0.refresh == 60 })
    check("4K: 1.5× → 1280×720", size(pick(1.5, k4, k4Original)) == "1280x720")
    check("4K: 1.25× → 1504×846", size(pick(1.25, k4, k4Original)) == "1504x846")
    check("4K: 0.75× → 2560×1440", size(pick(0.75, k4, k4Original)) == "2560x1440")
    check("4K: 0.5× → 3008×1692, never the native 3840×2160 at 1×", size(pick(0.5, k4, k4Original)) == "3008x1692")
    check("4K: 1.5× is the 60 Hz 1280×720, not the 50 Hz", pick(1.5, k4, k4Original).refresh == 60)
    check("4K: the original is never swapped for its low-resolution twin", pick(1.0, k4, k4Original).pixelWidth == 3840)
}

// MARK: - A 3:2 display in a low-resolution mode (3840×2560 panel at 1920×1280, 1×, as this Mac's)

let lowOriginal = M(1920, 1280, 1, 60)
let low: [Mode] = [
    M(800, 533, 2, 60), M(960, 640, 2, 60), M(1024, 683, 2, 60), M(1080, 720, 2, 60), M(1152, 768, 2, 60),
    M(1280, 853, 2, 60), M(1280, 854, 1, 60), M(1500, 1000, 2, 60), M(1504, 1003, 2, 60), M(1600, 1066, 1, 60),
    M(1680, 1120, 2, 60), M(1680, 1120, 2, 30), M(1800, 1200, 2, 60), M(1920, 1280, 2, 60), lowOriginal, M(1920, 1280, 1, 30),
    M(2048, 1365, 2, 60), M(2160, 1440, 1, 60), M(2304, 1536, 2, 60), M(2304, 1536, 1, 60), M(2560, 1706, 1, 60),
    M(3840, 2560, 1, 60), M(1920, 1080, 2, 60), M(1600, 1200, 1, 60),
    M(640, 427, 2, 60, usable: false), M(512, 341, 2, 60, usable: false),
]
do {
    let c = P.candidates(low, original: lowOriginal)
    check("low: a low-resolution original takes HiDPI and low-resolution sizes alike (\(c.count))",
          c.contains { $0.isHiDPI } && c.contains { !$0.isHiDPI })
    check("low: its own size is the original, not the HiDPI twin", c.first { size($0) == "1920x1280" } == lowOriginal)
    check("low: a size in both: the low-resolution one, as the original", c.first { size($0) == "2304x1536" }.map { !$0.isHiDPI } == true)
    check("low: no 16:9 or 4:3, nothing unusable", !c.contains { [16.0 / 9, 4.0 / 3].contains($0.aspect) } && c.allSatisfy(\.usable))
    check("low: 1.1× → 1800×1200 (HiDPI)", size(pick(1.1, low, lowOriginal)) == "1800x1200")
    check("low: 1.04× → 1800×1200 (outside the band around 1)", size(pick(1.04, low, lowOriginal)) == "1800x1200")
    check("low: 0.85× → 2304×1536, the low-resolution one", pick(0.85, low, lowOriginal).pixelWidth == 2304)
    check("low: 1.5× → 1280×853 or 854", ["1280x853", "1280x854"].contains(size(pick(1.5, low, lowOriginal))))
    check("low: 3× → 800×533, never an unusable 640×427", size(pick(3, low, lowOriginal)) == "800x533")
    check("low: 0.5× → 3840×2560", size(pick(0.5, low, lowOriginal)) == "3840x2560")
    check("low: 1.25× → 1504×1003 at 60 Hz", { let m = pick(1.25, low, lowOriginal); return size(m) == "1504x1003" && m.refresh == 60 }())
}

// MARK: - Ties and twins

do {
    // 1320 points wide; at 1.5× 968 (1.364) and 800 (1.65) are each 1.1 away in ratio: the larger wins.
    let o = M(1320, 660)
    let list = [M(800, 400), o, M(968, 484)]
    check("tie: the larger point size (More Space)", size(pick(1.5, list, o)) == "968x484")
    // A twin of the original that differs only in its id, listed first: the original stays itself.
    let twin = Mode(id: 999, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refresh: 120)
    let withTwin = [twin] + mbp
    check("twin: 1.02× keeps the original itself", pick(1.02, withTwin, mbpOriginal) == mbpOriginal)
    check("twin: the candidate for its size is the original", P.candidates(withTwin, original: mbpOriginal).contains(mbpOriginal)
          && !P.candidates(withTwin, original: mbpOriginal).contains(twin))
    // Only the original: every scale keeps it.
    check("alone: nothing else to pick", pick(1.5, [mbpOriginal], mbpOriginal) == mbpOriginal && pick(0.5, [], mbpOriginal) == mbpOriginal)
    // A refresh the original's list lacks for a size: still picked ("when possible").
    let only60 = [M(1147, 745, 2, 60), mbpOriginal]
    check("refresh: 1147×745 only at 60 Hz is still a candidate", size(pick(1.5, only60, mbpOriginal)) == "1147x745")
    // Of two twins at other rates, the nearer one to the original's.
    let rates = [M(1147, 745, 2, 30), M(1147, 745, 2, 100), M(1147, 745, 2, 48), mbpOriginal]
    check("refresh: the nearest rate (100 Hz for a 120 Hz original)", pick(1.5, rates, mbpOriginal).refresh == 100)
    // The original's rate beats more pixels at another (50 Hz is not 60), but 59.94 is 60.
    let pal = [M(1280, 720, 3, 50), M(1280, 720, 2, 60), k4Original]
    check("refresh: 60 Hz over a sharper 50 Hz twin", pick(1.5, pal, k4Original).refresh == 60)
    let ntsc = [M(1280, 720, 2, 60), M(1280, 720, 3, 59.94), k4Original]
    check("refresh: 59.94 Hz counts as 60, so the sharper twin", pick(1.5, ntsc, k4Original).pixelWidth == 1280 * 3)
    // Of two twins at the original's rate, the more pixels.
    let sharp = [M(1147, 745, 2), M(1147, 745, 3), mbpOriginal]
    check("pixels: the sharper twin", pick(1.5, sharp, mbpOriginal).pixelWidth == 1147 * 3)
}

// MARK: - Whose request: the latest device's viewport that says desktop

do {
    var r = P.Requests<Int>()
    check("requests: none at first", r.current == nil && r.isEmpty)
    r.viewport(from: 1, desktop: true, scale: 1.3, panel: iPad)
    check("requests: A asks 1.3", r.current?.scale == 1.3 && r.current?.panel == iPad)
    r.viewport(from: 2, desktop: true, scale: 0.8, panel: iPhone)
    check("requests: B asks 0.8, the latest", r.current?.scale == 0.8 && r.current?.panel == iPhone)
    r.viewport(from: 3, desktop: nil, scale: 1.5, panel: iPad)
    check("requests: an older device's viewport changes nothing", r.current?.scale == 0.8)
    r.viewport(from: 1, desktop: true, scale: 1.1, panel: iPad)
    check("requests: A again, the latest now", r.current?.scale == 1.1)
    r.left(1)
    check("requests: A leaves, back to B's", r.current?.scale == 0.8)
    r.viewport(from: 2, desktop: false, scale: 0.8, panel: iPhone)
    check("requests: B says false, none left", r.current == nil && r.isEmpty)
    r.viewport(from: 2, desktop: true, scale: nil, panel: iPhone)
    check("requests: desktop true without a scale is a request for the display's own", r.current != nil && r.current?.scale == nil)
    r.viewport(from: 2, desktop: nil, scale: 1.2, panel: iPhone)
    check("requests: nil takes it back", r.current == nil)
    r.viewport(from: 4, desktop: true, scale: 1.2, panel: iPad)
    r.left(5)
    check("requests: a device that never asked leaves: nothing changes", r.current?.scale == 1.2)
    r.left(4)
    check("requests: the last that asked leaves", r.current == nil)
}

// MARK: - When: target

do {
    let ask = P.Request(scale: 1.3, panel: iPad)
    check("target: the Desktop streams and a device asks", size(P.target(desktopStreams: true, stopping: false, request: ask, modes: mbp, original: mbpOriginal)) == "1147x745")
    check("target: a window streams: the display's own", P.target(desktopStreams: false, stopping: false, request: ask, modes: mbp, original: mbpOriginal) == mbpOriginal)
    check("target: the host stops: the display's own", P.target(desktopStreams: true, stopping: true, request: ask, modes: mbp, original: mbpOriginal) == mbpOriginal)
    check("target: nobody asks: the display's own", P.target(desktopStreams: true, stopping: false, request: nil, modes: mbp, original: mbpOriginal) == mbpOriginal)
    check("target: a request without a scale: the display's own",
          P.target(desktopStreams: true, stopping: false, request: P.Request(scale: nil, panel: iPad), modes: mbp, original: mbpOriginal) == mbpOriginal)
}

// MARK: - The display's own mode, and the crash note

do {
    let small = pick(1.5, mbp, mbpOriginal)
    let other = k4Original
    check("original: nothing set yet: the current mode", P.original(stored: nil, applied: nil, current: other) == other)
    check("original: still in the mode Sill set: the stored one", P.original(stored: mbpOriginal, applied: small, current: small) == mbpOriginal)
    check("original: changed on the Mac since: the current one, never undone", P.original(stored: mbpOriginal, applied: small, current: other) == other)
    check("recovery: still in the mode the run set: back", P.recovery(stored: mbpOriginal, applied: small, current: small, modes: mbp) == mbpOriginal)
    check("recovery: the window server put it back already: nothing", P.recovery(stored: mbpOriginal, applied: small, current: mbpOriginal, modes: mbp) == nil)
    check("recovery: someone chose another mode: left", P.recovery(stored: mbpOriginal, applied: small, current: mbp[0], modes: mbp) == nil)
    check("recovery: the original no longer listed (another display): left", P.recovery(stored: mbpOriginal, applied: small, current: small, modes: [small]) == nil)
}

// MARK: - TEST ONLY: SILL_TEST_DESKTOP_MODES

do {
    let t = P.testModes("1512x982*,1147x745,1352x878,1800x1169,2056x1329")
    check("test modes: five", t?.modes.count == 5)
    check("test modes: the starred one is current", t.map { size($0.current) } == "1512x982")
    check("test modes: HiDPI by default, 60 Hz, ids in order",
          t?.modes.allSatisfy { $0.pixelWidth == 2 * $0.width && $0.refresh == 60 } == true && t?.modes.map(\.id) == [1, 2, 3, 4, 5])
    check("test modes: 1.3× picks 1147×745 from them", t.map { size(pick(1.3, $0.modes, $0.current)) } == "1147x745")
    check("test modes: without a star, the first", P.testModes("1147x745,1512x982").map { size($0.current) } == "1147x745")
    check("test modes: @1 and @3", P.testModes("1920x1080@1,1280x720@3*").map { $0.modes[0].pixelWidth == 1920 && $0.current.pixelWidth == 3840 } == true)
    check("test modes: spaces around entries", P.testModes(" 1512x982 , 1147x745* ").map { size($0.current) } == "1147x745")
    for bad in ["", "1512", "1512x", "x982", "axb", "1512x982@4", "1512x982@0", "1512x982@", "1512x982,", "1x1*,2x2*",
                "0x10", "1512x982@2@2", "1512x-982", "99999x10"] {
        check("test modes: \(bad.debugDescription) is refused", P.testModes(bad) == nil)
    }
}

// MARK: - Sweep: every scale 0.5…1.5 on every list and panel

do {
    var bad: [String] = []
    let lists: [(String, [Mode], Mode)] = [("MBP", mbp, mbpOriginal), ("4K", k4, k4Original), ("low", low, lowOriginal)]
    for (name, list, original) in lists {
        let cands = P.candidates(list, original: original)
        for panel in [iPhone, upright, iPad, CGSize(width: 1180, height: 820), CGSize(width: 951, height: 664)] {
            var lastWidth = Int.max
            for step in 0...100 {
                let scale = 0.5 + Double(step) * 0.01
                let m = pick(scale, list, original, panel: panel)
                let tag = "\(name) \(Int(panel.width))×\(Int(panel.height)) \(scale)"
                if !cands.contains(m) { bad.append("\(tag): \(size(m)) not a candidate") }
                if abs(m.aspect / original.aspect - 1) > 0.01 { bad.append("\(tag): \(size(m)) another shape") }
                if original.isHiDPI && !m.isHiDPI { bad.append("\(tag): \(size(m)) low resolution") }
                if !m.usable { bad.append("\(tag): \(size(m)) unusable") }
                if abs(scale - 1) < 0.005 && m != original { bad.append("\(tag): not the original at 1") }
                // Nearest: no candidate closer in ratio.
                let d = abs(log(P.textScale(of: m, original: original, panel: panel) / scale))
                if abs(scale - 1) >= 0.005, let better = cands.first(where: { abs(log(P.textScale(of: $0, original: original, panel: panel) / scale)) < d - 1e-9 }) {
                    bad.append("\(tag): \(size(m)) but \(size(better)) is nearer")
                }
                // A larger text size never picks more space.
                if m.width > lastWidth { bad.append("\(tag): \(size(m)) wider than at a smaller scale") }
                lastWidth = m.width
            }
        }
    }
    check("sweep: 3 lists × 5 panels × 101 scales: a candidate of the original's shape, nearest, monotonic (\(bad.prefix(3)))", bad.isEmpty)
}

print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(fails == 0 ? 0 : 1)
