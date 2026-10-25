// iOSClient/MenuStripLayout.swift on its own: the Mac's menu titles in the strip along the top of the
// stream. Pinned cases (an iPad's, the Duo's book pose with Pages, the stashed tab, an overflow), then
// a grid of widths, folds and title sets against the invariants: inside the strip and clear of the
// trailing room, never across the fold, in the Mac's order without gaps between neighbours on one
// page, every title either shown or in the overflow (each once), the » only with an overflow, and
// no title left out that would have fit.
//   swiftc -O iOSClient/MenuStripLayout.swift Tests/checks/menu-strip/main.swift -o .build/checks/menu-strip/check && .build/checks/menu-strip/check
import CoreGraphics
import Foundation

typealias L = MenuStripLayout
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 0.01 }

// MARK: - Pinned

// Xcode's eight menus on an iPad held sideways (1133 pt), as the strip's font measures them.
let xcode: [CGFloat] = [36, 24, 26, 30, 30, 51, 42, 50, 32]   // Xcode File Edit View Find Navigate Editor Product Debug…
do {
    let l = L(width: 1133, titleWidths: xcode)
    check("iPad: every title shows", l.slots.map(\.index) == Array(0..<xcode.count))
    check("iPad: no » button", l.more == nil && l.overflow.isEmpty)
    check("iPad: the first title 8 pt from the edge", near(l.slots[0].frame.minX, 8))
    check("iPad: a title is its words and 10 pt either side", near(l.slots[0].frame.width, 56))
    check("iPad: titles end to end", near(l.slots[1].frame.minX, 64))
    check("iPad: the strip's height", l.slots.allSatisfy { near($0.frame.minY, 0) && near($0.frame.height, 32) })
}

// The Duo's book pose: 951 pt, the fold's band 455–495, Pages's ten menus.
let pages: [CGFloat] = [40, 24, 26, 36, 46, 48, 30, 38, 52, 30]   // Pages File Edit Insert Format Arrange View Share Window Help
do {
    let l = L(width: 951, titleWidths: pages, fold: 455...495)
    check("book: every title shows", l.slots.count == pages.count && l.more == nil)
    check("book: nothing on the fold", l.slots.allSatisfy { $0.frame.maxX <= 455 || $0.frame.minX >= 495 })
    let after = l.slots.first { $0.frame.minX >= 495 }
    check("book: the first title past the fold starts at its edge", after.map { near($0.frame.minX, 495) } ?? false)
    // With the bar hidden its tab takes the trailing 52 pt.
    let s = L(width: 951, titleWidths: pages, fold: 455...495, trailingRoom: 52)
    check("book, tab: clear of the tab", s.slots.allSatisfy { $0.frame.maxX <= 951 - 8 - 52 } && (s.more.map { $0.maxX <= 951 - 8 - 52 } ?? true))
}

// The Duo's cover on its side (678 pt): too narrow for Xcode's nine with a tab.
do {
    let wide: [CGFloat] = xcode + [44, 60, 38, 30]
    let l = L(width: 678, titleWidths: wide, trailingRoom: 52)
    check("cover: some titles in the overflow", !l.overflow.isEmpty)
    check("cover: the » at the strip's end, before the tab", l.more.map { near($0.maxX, 678 - 8 - 52) && near($0.width, 40) } ?? false)
    check("cover: the overflow is the rest, in order", l.overflow == Array(l.slots.count..<wide.count))
    check("cover: the titles shown end before the »", l.slots.allSatisfy { $0.frame.maxX <= l.more!.minX + 0.01 })
}

// Nothing to show.
do {
    let l = L(width: 600, titleWidths: [])
    check("none: no titles, no »", l.slots.isEmpty && l.more == nil && l.overflow.isEmpty)
}

// One title wider than the strip.
do {
    let l = L(width: 200, titleWidths: [400, 20])
    check("too wide: nothing shows, both in the overflow", l.slots.isEmpty && l.overflow == [0, 1] && l.more != nil)
}

// MARK: - The grid

var rng = SystemRandomNumberGenerator()
var cases = 0
for width in stride(from: 120 as CGFloat, through: 1400, by: 7) {
    for foldKind in 0..<3 {
        let fold: ClosedRange<CGFloat>? = foldKind == 0 ? nil : {
            let mid = (width / 2).rounded()
            return foldKind == 1 ? (mid - 20)...(mid + 20) : (mid - 2)...(mid + 2)
        }()
        for room in [0 as CGFloat, 52] {
            for _ in 0..<12 {
                let count = Int.random(in: 0...16, using: &rng)
                let widths = (0..<count).map { _ in CGFloat(Int.random(in: 10...120, using: &rng)) }
                let l = L(width: width, titleWidths: widths, fold: fold, trailingRoom: room)
                cases += 1
                let end = width - 8 - room
                var bad: [String] = []
                if l.slots.map(\.index) != Array(0..<l.slots.count) { bad.append("not the first titles in order") }
                if l.overflow != Array(l.slots.count..<count) { bad.append("overflow not the rest") }
                if (l.more != nil) != !l.overflow.isEmpty, l.more != nil || end - 40 >= 8 { bad.append("» without overflow or overflow without »") }
                for s in l.slots {
                    if s.frame.minX < 8 - 0.01 || s.frame.maxX > end + 0.01 { bad.append("title \(s.index) outside") }
                    if !near(s.frame.width, widths[s.index] + 20) { bad.append("title \(s.index) width") }
                    if let fold, s.frame.maxX > fold.lowerBound + 0.01, s.frame.minX < fold.upperBound - 0.01 { bad.append("title \(s.index) on the fold") }
                    if let more = l.more, s.frame.maxX > more.minX + 0.01 { bad.append("title \(s.index) under »") }
                }
                for (a, b) in zip(l.slots, l.slots.dropFirst()) {
                    let jumped = fold.map { near(b.frame.minX, $0.upperBound) && a.frame.maxX <= $0.lowerBound + 0.01 } ?? false
                    if !near(a.frame.maxX, b.frame.minX) && !jumped { bad.append("gap between \(a.index) and \(b.index)") }
                }
                // No title left out that would have fit after the last shown (or after the fold).
                if let next = l.overflow.first {
                    let limit = l.more?.minX ?? end
                    var x = l.slots.last?.frame.maxX ?? 8
                    let w = widths[next] + 20
                    if let fold, x < fold.upperBound, x + w > fold.lowerBound { x = fold.upperBound }
                    if x + w <= limit - 0.01 { bad.append("title \(next) would have fit") }
                }
                if l.overflow.isEmpty, l.more != nil { bad.append("» with nothing in it") }
                if !bad.isEmpty { check("grid width \(width) fold \(foldKind) room \(room) \(widths): \(bad.joined(separator: "; "))", false) }
            }
        }
    }
}
check("grid: \(cases) strips", cases > 0)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
