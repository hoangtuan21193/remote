import SwiftUI
import UIKit

/// The Mac keys bar over the software keyboard (docs/keyboard-auto-plan.md, D6): the keys a Mac needs
/// that the keyboard does not offer, one row that scrolls sideways as Jump Desktop's does: esc and
/// tab, the four modifiers, the arrows, F1 to F12, then home, end, page up and down and forward
/// delete; the button that puts the keyboard away stays at the right edge. The stream's input view
/// (InputOverlayView) is its owner: it shows the bar only for the person's own keyboard, never for a
/// hardware keyboard's hold, and does what its keys ask.
///
/// The modifiers latch as the key row's do (ModifierLatch, D7): a tap holds one for the next key, two
/// lock it (lit and underlined), and a tap on a held or locked one lets it go. An arrow or forward
/// delete held down repeats, as a keyboard's key does.
final class KeyboardAccessoryBar: UIView {
    /// A key: down and up, with whatever is held (the owner spends the latch).
    var press: (UInt16) -> Void = { _ in }
    /// A tap on a modifier's key.
    var tapModifier: (KeyModifiers) -> Void = { _ in }
    /// The keyboard goes away.
    var hide: () -> Void = {}

    static let height: CGFloat = 44

    private enum Key {
        case press(String, UInt16, String)
        case arrow(String, UInt16, String)
        case modifier(String, KeyModifiers, String)
        case gap
    }

    private static let keys: [Key] = {
        var keys: [Key] = [
            .press("esc", HIDKey.escape, "Escape"), .press("tab", HIDKey.tab, "Tab"), .gap,
            .modifier("ctrl", .control, "Control"), .modifier("opt", .option, "Option"),
            .modifier("cmd", .command, "Command"), .modifier("shift", .shift, "Shift"), .gap,
            .arrow("chevron.left", HIDKey.leftArrow, "Left arrow"), .arrow("chevron.up", HIDKey.upArrow, "Up arrow"),
            .arrow("chevron.down", HIDKey.downArrow, "Down arrow"), .arrow("chevron.right", HIDKey.rightArrow, "Right arrow"), .gap,
        ]
        keys += (0..<12).map { .press("F\($0 + 1)", HIDKey.f1 + UInt16($0), "F\($0 + 1)") }
        keys += [.gap, .press("home", HIDKey.home, "Home"), .press("end", HIDKey.end, "End"),
                 .press("pg up", HIDKey.pageUp, "Page Up"), .press("pg dn", HIDKey.pageDown, "Page Down"),
                 .arrow("delete.right", HIDKey.deleteForward, "Forward Delete")]
        return keys
    }()

    private let scroll = KeyScroll()
    private let row = UIStackView()
    private var modifierButtons: [(button: UIButton, flag: KeyModifiers, label: String, lock: UIView)] = []
    /// The key held down that repeats, and its timer.
    private var repeating: (usage: UInt16, timer: Timer)?
    private var repeated = false

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: Self.height))
        autoresizingMask = .flexibleWidth
        backgroundColor = UIColor(Palette.bar)
        accessibilityLabel = "Mac keys"
        accessibilityTraits = .none
        let line = UIView()
        line.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delaysContentTouches = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)

        let hideButton = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "keyboard.chevron.compact.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        config.baseForegroundColor = UIColor(Palette.barLabel)
        hideButton.configuration = config
        hideButton.backgroundColor = UIColor(Palette.bar)
        hideButton.accessibilityLabel = "Hide the keyboard"
        hideButton.addAction(UIAction { [weak self] _ in self?.hide() }, for: .primaryActionTriggered)
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hideButton)
        // The row fades under the button's left edge, so a key half under it reads as more to scroll.
        let fade = FadeView()
        fade.translatesAutoresizingMaskIntoConstraints = false
        fade.isUserInteractionEnabled = false
        addSubview(fade)

        for key in Self.keys { row.addArrangedSubview(view(for: key)) }

        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor), line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor), line.heightAnchor.constraint(equalToConstant: 1),
            hideButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            hideButton.topAnchor.constraint(equalTo: topAnchor), hideButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            hideButton.widthAnchor.constraint(equalToConstant: 52),
            fade.trailingAnchor.constraint(equalTo: hideButton.leadingAnchor), fade.widthAnchor.constraint(equalToConstant: 16),
            fade.topAnchor.constraint(equalTo: topAnchor, constant: 1), fade.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: hideButton.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 1), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    /// What the latch holds now: the modifiers' keys light, a locked one underlined.
    func show(held: KeyModifiers, locked: KeyModifiers) {
        for item in modifierButtons {
            let on = held.contains(item.flag)
            let isLocked = locked.contains(item.flag)
            var config = item.button.configuration
            config?.background.backgroundColor = UIColor(on ? Palette.controlOpen : Palette.control)
            config?.baseForegroundColor = UIColor(on ? Palette.accent : Palette.text)
            item.button.configuration = config
            item.lock.isHidden = !isLocked
            item.button.accessibilityLabel = isLocked ? "\(item.label), locked. Tap to release."
                : on ? "\(item.label), held. Tap twice to lock, once to release." : "\(item.label), hold for the next key"
        }
    }

    // MARK: Keys

    private func view(for key: Key) -> UIView {
        switch key {
        case .gap:
            let gap = UIView()
            gap.widthAnchor.constraint(equalToConstant: 6).isActive = true
            return gap
        case .press(let title, let usage, let label):
            let button = cap(title: title, symbol: nil, label: label, minWidth: title.count > 3 ? 52 : 40)
            button.addAction(UIAction { [weak self] _ in self?.press(usage) }, for: .primaryActionTriggered)
            return button
        case .arrow(let symbol, let usage, let label):
            let button = cap(title: nil, symbol: symbol, label: label, minWidth: 40)
            button.addAction(UIAction { [weak self] _ in self?.startRepeat(usage) }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in self?.endRepeat(press: true) }, for: .touchUpInside)
            button.addAction(UIAction { [weak self] _ in self?.endRepeat(press: false) }, for: [.touchUpOutside, .touchCancel])
            button.accessibilityTraits.insert(.keyboardKey)
            return button
        case .modifier(let title, let flag, let label):
            let button = cap(title: title, symbol: nil, label: label, minWidth: 48)
            button.addAction(UIAction { [weak self] _ in self?.tapModifier(flag) }, for: .primaryActionTriggered)
            let lock = UIView()
            lock.backgroundColor = UIColor(Palette.accent)
            lock.layer.cornerRadius = 1
            lock.isHidden = true
            lock.isUserInteractionEnabled = false
            lock.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(lock)
            NSLayoutConstraint.activate([
                lock.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
                lock.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
                lock.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
                lock.heightAnchor.constraint(equalToConstant: 2),
            ])
            modifierButtons.append((button, flag, label, lock))
            return button
        }
    }

    private func cap(title: String?, symbol: String?, label: String, minWidth: CGFloat) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.background.backgroundColor = UIColor(Palette.control)
        config.background.cornerRadius = 8
        config.baseForegroundColor = UIColor(Palette.text)
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 9)
        if let title {
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .medium)]))
        }
        if let symbol {
            config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        }
        let button = UIButton(configuration: config)
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 32),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
        ])
        return button
    }

    // MARK: Repeat

    /// An arrow or forward delete down: after 0.4 s it repeats ten times a second until let go.
    private func startRepeat(_ usage: UInt16) {
        repeating?.timer.invalidate()
        repeated = false
        let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeated = true
            self.press(usage)
            let every = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.press(usage) }
            RunLoop.main.add(every, forMode: .common)
            self.repeating = (usage, every)
        }
        RunLoop.main.add(timer, forMode: .common)
        repeating = (usage, timer)
    }

    /// Let go: a key that never repeated goes once now (inside the key), and the repeat stops.
    private func endRepeat(press: Bool) {
        guard let held = repeating else { return }
        held.timer.invalidate()
        repeating = nil
        if press, !repeated { self.press(held.usage) }
        repeated = false
    }

    /// The row's scroll view: a drag that starts on a key still scrolls the row. The keys fill it, and
    /// UIScrollView by default never takes a touch back from a control (`touchesShouldCancel(in:)`
    /// false for a UIControl), so with `delaysContentTouches` off the row never moved under a finger
    /// (found on the iPhone Duo, 2026-10-25: F1 to F12 out of reach). A key's own action waits for its
    /// touch's end, and an arrow's repeat stops on the cancel.
    private final class KeyScroll: UIScrollView {
        override func touchesShouldCancel(in view: UIView) -> Bool { true }
    }

    /// The row's fade under the hide button's left edge.
    private final class FadeView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }
        override init(frame: CGRect) {
            super.init(frame: frame)
            let gradient = layer as! CAGradientLayer
            let bar = UIColor(Palette.bar)
            gradient.colors = [bar.withAlphaComponent(0).cgColor, bar.cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}
