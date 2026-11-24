# MMTVL

A full-screen TV launcher for the Mac, styled after tvOS. Put a Mac on your TV and drive it with a Siri Remote, a keyboard, a game controller or your phone: open your apps, watch YouTube and live TV, and control the receiver and TV from one place.

![Home screen with Plex Continue Watching](docs/images/home-plex.jpg)

| | |
|---|---|
| ![Live TV guide](docs/images/guide.jpg) | ![Multiview](docs/images/multiview.jpg) |
| ![Settings → Live TV](docs/images/settings-live-tv.jpg) | ![PIN entry](docs/images/pin.jpg) |

- **Home screen** of app tiles with a top shelf (Plex Continue Watching, Live TV previews)
- **YouTube** in its TV interface, with casting from phones
- **Live TV** from your own IPTV playlist and guides, or an HDHomeRun antenna: guide, search, timeshift, Multiview (up to 5 channels) and My Teams
- **Remotes:** Siri Remote (buttons and touch surface), phone remote with a trackpad, keyboard, controllers
- **Receiver and TV control** over serial, network or HDMI-CEC, with a power menu
- **Kiosk mode** that keeps other apps out, with an optional PIN

The Siri Remote's touch surface is read through a private macOS framework, so it may break with a macOS update.

## Requirements

- macOS 26 or later, on a Mac connected to a TV
- **Accessibility** permission (global Home, controlling other apps)
- **Local Network** permission (Plex, casting, HDHomeRun)

## Install

Download the MMTVL zip from the [latest release](https://github.com/dwolcot1/mmtvl/releases/latest), unzip it, move `MMTVL.app` to Applications and open it.

## Updates

From 1.4.0, MMTVL updates itself from this repository's releases. When a new version is out, the home screen says **Update Available** under the clock; **Settings → System → Software Update** shows the installed and available versions, checks on demand and installs (MMTVL quits and opens again in about half a minute). **Automatic Updates** can install on its own: *When Idle* (after Power has turned the TV off, or during the screen saver) or *At Night* (about 4 a.m. when nothing is playing); it's *Off* by default. Turn **Check for Updates** off to stop the daily check. Every update is checked twice before it's installed: its EdDSA signature (Sparkle) and the new app's Developer ID signature. Settings are kept.

**From 1.3.x:** those versions have no updater, so install 1.4.0 once by hand: quit MMTVL, then replace the app the same way as above.

## First run

- MMTVL starts full screen in **kiosk mode**. Leave with the **Exit to Desktop** tile, or ⌘Q (both ask for the PIN if one is set).
- To try it in a normal window: `open /Applications/MMTVL.app --args -windowed YES`
- Settings live in `~/Library/Application Support/MMTVL`. Secrets (playlist and guide URLs, PIN, Plex tokens, paired phones) are in the login Keychain under `dev.mmtvl.launcher`; remove one with `security delete-generic-password -s dev.mmtvl.launcher -a <account>`.

## Network

| Port | What | Turn off |
|---|---|---|
| TCP 8765, 8766 | Phone remote (page, WebSocket) | Settings → Remote & Input → Phone Remote |
| TCP 8770, UDP 1900 | YouTube casting (DIAL, SSDP) | Settings → Casting → Cast from the YouTube App |

Live TV's stream relay listens on localhost only.

Open the phone remote by the address Settings shows (the QR code does). A name works only when it's the Mac's own name (`<name>.local`, or your router's `<name>.lan` or `<name>.home.arpa`). After a phone pairs, Pair a Phone shows a new QR code and code for the next one.

The phone remote is plain HTTP and WebSocket on your local network, not encrypted: anyone who can watch that network's traffic can see a paired phone's token and use it to control the Mac. Use the phone remote only on a network you trust (not a shared or guest network), or turn it off.

## Unofficial

MMTVL isn't affiliated with any of the services it works with. YouTube runs YouTube's TV web app and may break when YouTube changes it; follow YouTube's terms. MMTVL provides no channels: Live TV plays playlists and guides you supply, and you're responsible for using sources you're entitled to. YouTube, Plex, Prime Video, AirPlay, HDHomeRun, Reflector and other names belong to their owners.

## Building from source

Xcode 27, macOS 26 SDK. The first build downloads about 350 MB of Swift packages.

```sh
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
```

Set your own team in the project's signing settings, or sign ad hoc with `CODE_SIGN_IDENTITY=-` (then Accessibility has to be granted again after each build).

The `roku/` folder holds a separate, sideloaded Roku app for Live TV; see [roku/README.md](roku/README.md).

## License

MMTVL is MIT licensed ([LICENSE](LICENSE)). It includes mpv, FFmpeg and other libraries under their own licenses, some LGPL: see [THIRD_PARTY_NOTICES.md](MMTVL/Licenses/THIRD_PARTY_NOTICES.md), which also explains how to rebuild MMTVL with a modified library. The same list is in Settings → Licenses.
