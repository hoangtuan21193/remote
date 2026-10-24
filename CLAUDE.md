# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad (designed for
iPhone Duo first), with a free Mac companion. Tip jar, no subscription, no servers. Read
`docs/BRIEF.md` before product-level work. Formerly winstream; the folder still has the old name.

This repository is a fork of Saffsanity/sill (Apache-2.0). Keep `LICENSE` and the upstream
copyright lines; mark files changed here. `docs/HISTORY.md` and the plans record upstream's own
decisions and tests; read "Noah" there as the upstream author. Decisions for this fork are the
repository owner's: ask the user.

Where things are written down:
- `docs/HISTORY.md`: every feature's log, newest first (what changed, decisions, what was verified,
  and the **"Untested"** device tests left open upstream). Read the top entries before touching
  a recent feature.
- `docs/*-plan.md`: one per feature (rule, open questions with defaults taken, results, review).
- `docs/CODEMAP.md`: the full file-by-file map and every test hook (`SILL_TEST_*` variables,
  `-Sill…` launch arguments, harness cases). Look a hook up there before inventing one.
- `docs/DEVELOPMENT.md`: building, running, permissions, troubleshooting, releasing.
- `docs/release-checklist.md`, `docs/app-store-metadata.md`: releases and the App Store record.
- **Design canvases** (`design/canvas/README.md`): every screen, one canvas per device — iPhone
  https://claude.ai/artifact/BfwySRCcdAt1Fq77ysBEty, iPad
  https://claude.ai/artifact/7SquPwJcDScq13HnTUVar1, iPhone Duo
  https://claude.ai/artifact/GNodnPMzhbmAaVxg39jB2x, Mac
  https://claude.ai/artifact/CuHyhiTKiGhsFPcQa4h3Lq. The artboards' source is in
  `design/canvas/<device>/project/`. A screen changed in code changes its artboard in the same
  change, and the other way round.

When a feature lands, add its entry at the top of `docs/HISTORY.md`, not here.

## Architecture

Three halves sharing one wire format:
- **`Sources/StreamProtocol`** (iOS + macOS): 14-byte header + payload framing, message kinds
  0–28, 32 and 33 both ways (`StreamMessage.swift`), and the JSON payloads, one file per feature
  (`Switcher`, `HostSettings`, `Remote`, `Pairing`, `Compatibility`, `Pointer`, `MacMenu`,
  `Gesture`, `Clipboard`, `TextFocus`, …). Change the wire in one place; see the Compatibility floor below.
- **Mac host, `Sources/SillHost`** (library target `SillHostCore`, no product, reached with
  `package` access) behind two executables: the CLI `SillHost` (`Sources/SillHostCLI`) and
  Sill.app's `SillMenuBar` (`Sources/SillMenuBar`, an LSUIElement AppKit app with SwiftUI panes).
  Pipeline: ScreenCaptureKit (`WindowCapture`) → VideoToolbox HEVC (`HEVCEncoder`, one frame
  inside at a time behind a one-slot `EncoderMailbox`, hang watchdog, software fallback and
  re-check) → `StreamServer` (Network.framework, Bonjour `_sill._tcp`, per-client pacing,
  keepalive ticks, eviction). `StreamCoordinator` (main actor) owns it: source switches,
  viewports, live settings (`setTarget`), input (`InputInjector`, `KeyStrokes`), menus
  (`MenuMirror`), gestures, clipboard, virtual display (`VirtualStage`), window restore.
  Admission: the home door is TLS 1.3 with pairing (`Door`, `DoorPolicy`), the remote door
  `RemoteServer`, identity and trust in the keychain (`RemoteAccess`, `HostIdentity`).
- **iOS client, `iOSClient/Sill.xcodeproj`** (Swift 5 mode): `StreamClient` (discovery,
  connection, reconnect, moves between cable/Wi-Fi/Direct/remote; extensions `+Remote`, `+Home`,
  `+Clipboard`, `+Viewport`) over `SessionLink` and `MessageReader`; `StreamScreen` /
  `PortraitStreamScreen` / `PhonePortraitLayout` / `DuoPosture` for layouts; `InputOverlay` and
  `TrackpadView` for input; `HEVCDisplayView` draws video and the one pointer sprite.

Pattern throughout: the rules live in **pure types** (`…Policy`, `…Layout`, `…Copy`, ledgers;
Foundation/CoreGraphics only) checked by `Tests/checks`, and the framework glue around them stays
thin. New logic goes in a pure type with a check.

## Commands

```
swift build -c release                     # Mac side (needs Xcode 27 as developer dir)
swift run -c release SillHost --synthetic  # host streaming a test pattern; no Screen Recording, no Bonjour
Scripts/make-app.sh                        # .build/Sill.app, signed with the Apple Development identity
Tests/checks/run-all.sh                    # every pure check, as CI runs them (~5 min)
Tests/checks/run-all.sh tour menus         # only the named checks
Tests/checks/<name>/run.sh --mutants       # one check and its mutants (each mutant must fail it)
xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -configuration Debug \
  -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
python3 Scripts/sillclient.py PORT 8 desktop --stats   # wire-level test client (flags: docs/CODEMAP.md)
```
Test hosts on this Mac: add `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`
so they listen on 127.0.0.1 alone and never touch the hardware encoder. The iOS app reaches one with
the launch argument `-SillConnect 127.0.0.1:PORT`. CI (`.github/workflows/ci.yml`, runner
`xcode-27`) runs the release build, `run-all.sh`, the iOS simulator build and two CLI paths.

## Rules learned the hard way

- **One hardware encoder engine, shared.** While a device streams from Sill.app, don't run
  `simctl io recordVideo`, non-synthetic SillHost streams, encoder benchmarks or the Simulator
  panel's recording: each steals frames, the recorder at higher priority. Check Sill.log for a
  connected device first.
- Never `MainActor.assumeIsolated` in core code: under the CLI's `dispatchMain` the main queue
  drains on a worker thread and it traps. Hop with `Task { @MainActor }`.
- Sill.app's modal-loop rule (AppDelegate's doc comment): start `NSMenu.popUp`, `runModal` or a
  terminate only from AppKit target/action, SwiftUI button actions or a run-loop timer; errors
  show inline, never in alerts.
- The CLI's stdout stays byte-identical across changes (masked and sorted): core `print`s go
  through the shadow in `HostLog.swift`. Nothing new prints unless a device asks for the feature.
- Never reconfigure a running `SCStream`; restart the pipeline instead. A bitrate change needs a
  new encoder session.
- New iOS source files need their four pbxproj entries by hand (next free ID pairs: grep the
  project for `A…/F…`).
- A change to a file a check compiles updates that check, and any mutant pattern it moved, in
  the same commit (`Tests/checks/README.md` lists who compiles what).
- TEST ONLY hooks are honoured only by a host that does not advertise (`DoorPolicy.isTestHost`);
  Sill.app ignores them with one line. Keep it that way.

## Compatibility floor

The first public builds (Sill for iPhone and iPad from the App Store, Sill.app from GitHub) set it
for good. Sill.app changes only when its user downloads a new version (its update check only points
at one), and a device can stay on an old version (automatic updates off, an iOS the next version
dropped). So every later host keeps serving devices from the first public build on, and every later
device keeps working with Macs from the first public build on, or each says why
(docs/update-notice-plan.md):
- Kept as they are: the home door as Sill.app 1.0 ships it, TLS with pairing at home
  (docs/home-pairing-plan.md, branch `home-pairing`; it ships before 1.0, decided 2026-09-25), not
  the plain-TCP `_sill._tcp` door, which only development builds and the CLI without `--pairing`
  keep; the ALPNs `sill/1` and `sill-pair/1`, which every host offers for good at both doors
  (`RemoteTLS.serverALPNs`: a later generation's `sill/2` only ever goes beside them); the 14-byte
  header; kinds 0–28 and 32 and their payloads (HEVC with ParameterSets; the JSON of Switcher,
  Input, Viewport, HostSettings, Remote, Compatibility, Pointer, MacMenu, Gesture and Clipboard;
  29 to 31 stay free, 29 the audio plan's, 30 and 31 pull request #66's), inside `sill/1` at
  both doors (19 and 20 on their own `sill-pair/1` connection, the next bullet); the ping echo; a
  kind 16 within 2 s of the first window list, one per connection since Sill for Mac 0.5.1 (away
  from home, docs/remote-bundle-plan.md §4): its `settings` the pair that connection's controls
  set (the away quality for a device away), and its optional `away` (AwayQuality, from a host with
  an identity: Sill.app, SillHost --remote or --pairing) and `link` (LinkReport, only while a link
  does not keep up; its `state` a string,
  which a device reads as keeping up when it does not know it); kind 22's `reason`, `message` and
  `reconnect`; the
  Mac's menus as MacMenu.swift has them (docs/menu-bar-plan.md §3):
  a kind 27 without an id is the device's subscription, and only a subscriber is served (another
  connection's fetches and choices are answered "The menus changed…", nothing read or pressed); an
  id is a path of child indexes that names one item for every device within one version, and a
  request of another version is answered with that note and never acted on; a fetch and a choice
  carry the title the device showed, and the host reads or presses only while the item there still
  has it; a device's tokens come back in `answering`; the fields as they are (MacMenu's `version`,
  `app`, `bundleID`, `menus`, `answering`, `menu`, `items`, `more`, `pressed`, `stale`, `note`;
  MacMenuItem's `id`, `title`, `separator`, `enabled`, `mark`, `key`, `submenu`; FetchMenu's and
  PressMenuItem's `version`, `id`, `title`, `token`); a trackpad gesture (kind 28, Gesture.swift)
  goes only to a host whose window list says `gestures` 1 or more, as one of its six names with
  `fingers`, and a later generation of gestures says 2 and goes only to a host that says so; the
  clipboard (kind 32, Clipboard.swift, docs/clipboard-plan.md) goes from a device only to a host
  whose window list says `clipboard` 1 or more (an Int: 1 is text, a later generation with images
  says 2), and from a host only to a connection that sent a kind 32 and no `stop` since: any kind
  32 subscribes, `{"stop":true}` ends it, `text` (at most 256 KB, the JSON at most 1 MiB) becomes
  the receiver's clipboard, `image` is reserved for that later generation; a subscription says what
  the device takes, `{}` being text alone, so a host sends `image` only to a connection whose
  subscription carries a later field saying it takes images (`"accepts":2`, say), never to one that
  sent `{}`.
- Pairing as 1.0 does it (docs/home-pairing-plan.md §3): the Bonjour TXT keys `r` (the recognition
  tag) and `p` ("1" pairing required, "0" open, no `p` a plain door, any other value read as "1");
  a `sill-pair/1` connection is exactly one kind 19, with no hello (the device gate judges sessions
  only), and one kind 20, then the Mac closes it; kind 19's methods `qr`, `code` and, at the home
  door, `ask` and `cancel` (the remote door answers both `closed`), at `v` 1: a host answers any other `v`
  `closed` without counting a try, so a later method or proof format comes with a later `v`, never
  as a new method at 1, which a 1.0 host counts as a wrong code; kind 20's reasons `code`,
  `closed`, `expired`, `stopped`, `busy` and, after an ask, `shown`, `openOnMac` and `locked`, with
  their meanings (`PairResult.knownReasons`: a later reason comes with its `message`, which 1.0
  devices show as it is); an ok without a proof only as `method` "cable", to an ask that claimed
  the cable; and pairing is never refused for the device's age.
- Additive only (HostSettings.swift's rules): new fields optional, never renamed or retyped; kind
  numbers never reused; no new case in an enum an older peer decodes. `StreamSource` keeps its
  three cases (a new source goes in an optional field, with `active` still one of the three). A new
  `InputEvent` case, scroll phase or window command goes only to a host that said it takes it (a
  kind or a field only newer hosts send), and a gesture ends with a scroll phase the first build
  knows.
- A device is refused, never served wrong. A host that can no longer serve older devices raises
  `DeviceGate.minimumDeviceVersion` ("0" today) by the plan's §4.6, and they get kind 22 "update"
  before anything else. A device from 2026-09-25 on that receives it shows the host's message word
  for word, with its App Store link, and does not reconnect; older development builds cannot. At
  the TLS home door only devices from home pairing on receive it (Decided, below). Kind 22 reaches
  a 1.0 device only inside a `sill/1` session, so such a host still completes that device's
  `sill/1` handshake and reads its hello through the gate before refusing it: a host that stopped
  offering `sill/1` would leave it a failed handshake (-9838), "disconnected" and a redial every
  few seconds, for ever.
- Every device says hello first (kind 23: its version, build, protocol and name), and every host's
  window list gives its version and protocol (`hostVersion`, nil from SillHost and from Macs
  before 2026-09-25). A later device facing an older Mac tells what it lacks from these and from
  which kinds and fields arrive, and says "Update Sill on ‹Mac›", as the Settings panel already
  does for a Mac without kind 16.
- `SillProtocol.current` (1) rises only with a change an older peer cannot skip, and the floor
  rises with it.
- Decided (2026-09-25; the plan's open question 14): home pairing ships before 1.0, so the
  floor is the TLS home door with pairing, and no 1.0 device speaks plain TCP to Sill.app.
  Settled at the merge of main into `home-pairing` (2026-09-27, d11aa60; home pairing landed
  second): the hello goes first inside TLS at both doors, and the device gate runs in `Door`, once
  the key is admitted, one place for both TLS doors (`StreamServer.gate`; the CLI's plain door
  without `--pairing` runs it at `.ready`); what changed while it held a session (the key removed,
  Require pairing on, Remote Access or internet access off, the session limit, Direct Wireless
  off) is judged again by `DoorPolicy.afterGate`, with the goodbye and the line that change's own
  close gives. 1.0's TLS home door is `SillProtocol` 1 with ALPN `sill/1`, as the remote door is:
  pairing on the home door is part of protocol 1, no longer an example of what raises it
  (Compatibility.swift, docs/update-notice-plan.md §3.2 and §4.6), and a later generation raises
  both: `sill/2` is offered beside `sill/1` and `sill-pair/1`, never instead of them (the first
  bullet). Builds from before home
  pairing dial plain TCP and say hello in plaintext: at the TLS door they get a failed handshake
  and EOF, never kind 22 "update", and redial. Only development and TestFlight builds are that
  old, so no plaintext path or sniffer answers them.

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading in the spike is by hand: capture queue → VT callback thread →
  network queue. Keep it explicit and commented rather than reaching for actors
  until the design settles.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple
  silicon as far as we know).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking the user)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
  Bonjour only for the spike.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0, LICENSE since PR #15, kept when the repository went
  public on 2026-09-26 (paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization, audio.
