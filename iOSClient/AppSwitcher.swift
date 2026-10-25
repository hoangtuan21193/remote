import SwiftUI

/// The app switcher on screen (AppSwitcherPolicy; .planboard/strip-gestures D3, D7): a row of tiles
/// across the middle of the stream, as the Mac's ⌘Tab draws it, the Desktop first, then the apps,
/// the lit one in the accent. A three-finger swipe opens it and steps it; when the fingers have been
/// still a moment the lit tile is chosen. A tap on a tile chooses it, a tap anywhere else closes the
/// row with nothing chosen and never reaches the Mac. A row wider than the screen scrolls to keep
/// the lit tile in view.
struct AppSwitcher: View {
    @ObservedObject var client: StreamClient
    let state: AppSwitcherPolicy
    let tap: (Int) -> Void
    let dismiss: () -> Void

    static let tile: CGFloat = 64
    static let tileWidth: CGFloat = 92

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(state.tiles.enumerated()), id: \.offset) { index, tile in
                            Button { tap(index) } label: { tileView(tile, lit: state.lit == index) }
                                .buttonStyle(.plain)
                                .id(index)
                                .accessibilityLabel(name(of: tile))
                                .accessibilityAddTraits(state.lit == index ? .isSelected : [])
                        }
                    }
                    .padding(12)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: 760)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.bar.opacity(0.92)))
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 6)
                .environment(\.colorScheme, .dark)
                .padding(.horizontal, 16)
                .onChange(of: state.lit, initial: true) { _, lit in
                    if let lit { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(lit, anchor: .center) } }
                }
            }
        }
        .transition(.opacity)
    }

    private func tileView(_ tile: AppSwitcherPolicy.Tile, lit: Bool) -> some View {
        VStack(spacing: 6) {
            switch tile {
            case .desktop:
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .frame(width: Self.tile, height: Self.tile)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.iconFallback))
            case .app(let bundleID):
                AppIcon(image: client.icons[bundleID], name: name(of: tile), size: Self.tile, radius: 14, fontSize: 22)
            }
            Text(name(of: tile))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(lit ? Palette.text : Palette.barLabel)
                .lineLimit(1)
        }
        .frame(width: Self.tileWidth)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(lit ? Palette.controlOpen : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(lit ? Palette.accent : Color.clear, lineWidth: 2))
    }

    private func name(of tile: AppSwitcherPolicy.Tile) -> String {
        switch tile {
        case .desktop: return "Desktop"
        case .app(let bundleID): return client.windows.first { $0.bundleID == bundleID }?.appName ?? bundleID
        }
    }
}
