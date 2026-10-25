# Design canvases

Every screen of the app, drawn as a Design canvas: one canvas per device. Each folder is the
canvas's own files (`project/canvas.json`, the index, and one `.dc.html` per artboard), the same
files the live canvas serves. Code and design move together: change a screen in code, change its
artboard in the same change, and the other way round.

| Device | Live canvas | Folder |
|---|---|---|
| iPhone (402×874, 17 Pro) | https://claude.ai/artifact/BfwySRCcdAt1Fq77ysBEty | `iphone/` |
| iPad (744×1133, mini) | https://claude.ai/artifact/7SquPwJcDScq13HnTUVar1 | `ipad/` |
| iPhone Duo (inner 951×669, cover 466×678) | https://claude.ai/artifact/GNodnPMzhbmAaVxg39jB2x | `iphone-duo/` |
| Mac (Sill.app, light) | https://claude.ai/artifact/CuHyhiTKiGhsFPcQa4h3Lq | `mac/` |

The canvases are private to their owner until shared from the page's Share menu.

## Editing

- To change a canvas, edit its `.dc.html` here and publish the changed files to its link with the
  Artifact tool (`root` = the device's folder, `file_path` = the changed file). Send
  `project/canvas.json` only when artboards are added, moved or removed.
- Someone may have edited the live canvas by hand: read the artboard from the canvas first
  (`read` with its `path`), then copy it back here, so the folder and the canvas stay the same.
- Palette (iOS, `iOSClient/StreamScreen.swift`, `Palette`): bar #16181C, control #23262C,
  controlOpen #2C3550, accent #9BB7FF, text #EEF0F3, barLabel #C4C9D1, muted #A4ABB5,
  panel #1F2126, trackpad #101215. The Mac uses system colors.

## Where each artboard lives in code

iOS (`iOSClient/`):
- Connect, Add a Mac, pairing at home: `ContentView.swift` (ConnectScreen), `AddMacCard.swift`,
  `CodeScanner.swift`, `DiscoveryPolicy.swift` (row words, HomeCopy).
- Stream screen and bar: `StreamScreen.swift` (TopBar, WindowStrip, WindowThumbnail,
  WindowLightsMenu, TextScaleControl, AppDrawer, LinkLineView).
- Upright: `PortraitStreamScreen.swift` (halves, KeyRow), `PhonePortraitLayout.swift` (phone rects,
  Larger Picture), `TrackpadView.swift`.
- Settings panel: `HostSettingsPanel.swift`, `AwayCopy.swift`. Menus: `MacMenuButton.swift` (upright); the menu bar strip, the one bar sideways, `MacMenuStrip.swift` (`MenuStripLayout.swift`). App switcher: `AppSwitcher.swift` (`AppSwitcherPolicy.swift`).
- Pair This iPad…: `PairingOverlay.swift`. Clipboard chip: `ClipboardChip.swift`.
- Tour: `TourPolicy.swift` (copy), `TourOverlay.swift`. Duo poses: `DuoPosture.swift`.

Mac (`Sources/SillMenuBar/`): status menu `StatusItemController.swift`, `StatusText.swift`,
`StatusCard.swift`; Settings `SettingsWindow.swift`, `SettingsPanes.swift`, `DevicesPane.swift`,
`RemoteAccessPane.swift`; pairing and cable notice `PairDeviceWindow.swift`; log `LogWindow.swift`.

Not drawn yet: every error and edge state (each failure line, the Mac's attention menu items, the
update notice), VoiceOver variants, dark mode on the Mac, accessibility text sizes.
