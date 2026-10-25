import SwiftUI
import UIKit

/// The Mac's menu bar as a thin strip along the top of the stream (2026-10-25; Settings › Mac Menu
/// Bar, `StreamClient.menuStripKey`): the streamed app's menu titles in a row, the app's own in
/// bold, as the Mac draws them; a tap on one opens that menu under it, as on the Mac, and a choice
/// does on the Mac what choosing it there would. Under the landscape bar, and at the screen's top
/// edge while the bar is hidden, so the menus are one tap away either way. Only while the Mac sent
/// menus (with only a note, no Accessibility on the Mac, the Menus button says so instead).
///
/// Where each title goes is `MenuStripLayout`'s (off the Duo's fold, clear of the stashed bar's tab,
/// » for what does not fit). Each title is a UIKit pull-down holding the one deferred element of its
/// menu (MacMenuElements), so a menu is fetched from the Mac when it opens, fresh every time, as the
/// Menus button's and the iPad menu bar's are; a stale top level or a disabled Mac menu draws its
/// title dimmed and opens nothing. While a menu is open its title is drawn open (the accent), and
/// `onOpen` and `onClose` tell the stream screen, as the Menus button's do.
struct MacMenuStrip: View {
    @ObservedObject var client: StreamClient
    /// The fold's band in the strip's own space (the book pose), nil elsewhere.
    var fold: ClosedRange<CGFloat>? = nil
    /// The stashed bar's tab over the strip's trailing end.
    var trailingRoom: CGFloat = 0
    /// At the screen's top edge (the bar hidden), the titles `edgeInset` lower: the top 20 pt or so of
    /// the Duo's screen take no touch (measured on its simulator, as the bar's handle found), and
    /// the titles' middle then sits below it.
    var atEdge = false
    let onOpen: () -> Void
    var onClose: () -> Void = {}

    static let edgeInset: CGFloat = 8
    static func height(atEdge: Bool) -> CGFloat { MenuStripLayout.height + (atEdge ? edgeInset : 0) }

    var body: some View {
        MacMenuStripBar(client: client, fold: fold, trailingRoom: trailingRoom, onOpen: onOpen, onClose: onClose)
            .frame(height: MenuStripLayout.height)
            .padding(.top, atEdge ? Self.edgeInset : 0)
            .frame(maxWidth: .infinity)
            .background(Palette.bar.ignoresSafeArea(edges: .top))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
    }
}

private struct MacMenuStripBar: UIViewRepresentable {
    @ObservedObject var client: StreamClient
    let fold: ClosedRange<CGFloat>?
    let trailingRoom: CGFloat
    let onOpen: () -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> MacMenuStripView {
        let view = MacMenuStripView()
        update(view)
        return view
    }

    func updateUIView(_ view: MacMenuStripView, context: Context) { update(view) }

    private func update(_ view: MacMenuStripView) {
        view.client = client
        view.onOpen = onOpen
        view.onClose = onClose
        view.set(top: client.menus.top, fold: fold, trailingRoom: trailingRoom)
    }
}

/// The strip's titles, one pull-down button each, placed by `MenuStripLayout` at every layout pass.
final class MacMenuStripView: UIView {
    weak var client: StreamClient?
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}

    static let font = UIFont.systemFont(ofSize: 14, weight: .medium)
    static let appFont = UIFont.systemFont(ofSize: 14, weight: .bold)

    private var top: MacMenuState.Top?
    private var fold: ClosedRange<CGFloat>?
    private var trailingRoom: CGFloat = 0
    private var buttons: [MacMenuTriggerButton] = []
    private let more = MacMenuTriggerButton(type: .custom)
    /// The menus open from the strip (a title, or the »): at most one, but a menu's going can come
    /// after the next one's showing.
    private var openCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        configure(more, title: "»", font: Self.appFont)
        more.accessibilityLabel = "More menus"
        addSubview(more)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been used") }

    func set(top: MacMenuState.Top, fold: ClosedRange<CGFloat>?, trailingRoom: CGFloat) {
        let moved = fold != self.fold || trailingRoom != self.trailingRoom
        self.fold = fold
        self.trailingRoom = trailingRoom
        if top != self.top {
            self.top = top
            rebuild()
        } else if moved {
            setNeedsLayout()
        }
    }

    /// A button per Mac menu, its menu that menu's one deferred element; the »'s menu is set at layout,
    /// from what does not fit.
    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        guard let top, let client, let version = top.version else { setNeedsLayout(); return }
        for (i, row) in top.menus.enumerated() {
            let button = MacMenuTriggerButton(type: .custom)
            let isApp = i == 0 && row.title == top.app
            configure(button, title: row.title, font: isApp ? Self.appFont : Self.font)
            if top.stale || !row.enabled || row.id == nil {
                button.isEnabled = false
            } else {
                button.menu = UIMenu(title: "", children: [MacMenuElements.deferred(for: row, topLevelVersion: version, client: client)])
            }
            button.accessibilityLabel = "\(row.title) menu"
            addSubview(button)
            buttons.append(button)
        }
        setNeedsLayout()
    }

    private func configure(_ button: MacMenuTriggerButton, title: String, font: UIFont) {
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.titleLabel?.font = font
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIColor(Palette.text), for: .normal)
        button.setTitleColor(UIColor(Palette.muted).withAlphaComponent(0.6), for: .disabled)
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.onOpenChange = { [weak self, weak button] isOpen in
            DispatchQueue.main.async {
                guard let self, let button else { return }
                button.backgroundColor = isOpen ? UIColor(Palette.controlOpen) : .clear
                button.setTitleColor(UIColor(isOpen ? Palette.accent : Palette.text), for: .normal)
                let was = self.openCount > 0
                self.openCount = max(0, self.openCount + (isOpen ? 1 : -1))
                if !was, self.openCount > 0 { self.onOpen() }
                if was, self.openCount == 0 { self.onClose() }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let widths = buttons.map { ($0.titleLabel?.text ?? "").size(withAttributes: [.font: $0.titleLabel?.font ?? Self.font]).width.rounded(.up) }
        let layout = MenuStripLayout(width: bounds.width, titleWidths: widths, fold: fold, trailingRoom: trailingRoom)
        let shown = Set(layout.slots.map(\.index))
        // Each button 4 pt in from its slot top and bottom: its touch is the whole slot's height
        // anyway (the strip is 32 pt), the highlight sits inside it as the Mac's does.
        for slot in layout.slots {
            buttons[slot.index].frame = slot.frame.insetBy(dx: 0, dy: 3)
        }
        for (i, button) in buttons.enumerated() { button.isHidden = !shown.contains(i) }
        if let rect = layout.more, let top, let client, let version = top.version {
            more.isHidden = false
            more.frame = rect.insetBy(dx: 0, dy: 3)
            let rows = layout.overflow.map { top.menus[$0] }
            let menus: [UIMenuElement] = rows.map { row in
                guard !top.stale, row.enabled, row.id != nil else { return UIAction(title: row.title, attributes: .disabled) { _ in } }
                return UIMenu(title: row.title, children: [MacMenuElements.deferred(for: row, topLevelVersion: version, client: client)])
            }
            more.menu = UIMenu(children: menus)
        } else {
            more.isHidden = true
            more.menu = nil
        }
    }
}
