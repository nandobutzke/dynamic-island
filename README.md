# Dynamic Island for Mac

A notch-native Dynamic Island for MacBook that keeps **Cursor usage** in your peripheral vision while you code — with Spotify controls as a secondary convenience.

[Português (Brasil)](README.pt-BR.md)

---

## Motivation

As a developer, I live inside the editor. Cursor’s included usage (and how fast it burns) matters every day — but the dashboard lives in another tab, another context switch, another break in flow.

I wanted that signal where my eyes already go: the **MacBook notch**. A glanceable pill that answers “how much of my plan have I used?” without opening Settings or the billing page.

That’s the core of this project: **developer day-to-day awareness**. Spotify landed later as an extra module — useful when music is already playing, but not the reason the island exists.

This repo is **open source**. Use it, fork it, improve it.

---

## What it does

### Cursor (primary)

- Shows included usage for **Cursor Models** and **Other Models** (same two-pool idea as the Cursor dashboard)
- Compact mode: a single percentage (the higher of the two pools), with color as you approach the limit
- Expanded mode: progress bars and short footers in the style of the web UI
- Sign in through an embedded WebView; session stored in the Keychain
- Soft pulse when usage crosses 90% / 100%

### Spotify (secondary)

- Now playing (artwork, title, artist) when the Spotify desktop app is running
- Play / pause / previous / next via AppleScript
- Compact mode switches to the track when music is playing

---

## Features

- SwiftUI island glued to the **built-in** notch display (external monitors ignored)
- Compact ↔ expanded morph with spring animation
- Module switch (Cursor / Spotify) in the expanded view
- Menu bar app (no Dock icon): sign in/out, refresh, launch at login, quit
- Launch at Login via `SMAppService`

---

## Requirements

- macOS 14+
- MacBook with a notch (positioning targets the built-in display)
- Cursor account (for usage)
- Spotify desktop app (only if you want music controls)
- Automation permission for Spotify when prompted

---

## Build & run

```bash
./Scripts/package-app.sh
open build/DynamicIsland.app
```

Alternatively:

- Open `DynamicIsland.xcodeproj` in Xcode and run, or
- `swift build -c release` and package with the script above

On first use: **Sign in to Cursor** from the island or the menu bar item. For Spotify, grant **Automation** when macOS asks.

---

## Permissions & privacy

| Permission | Why |
|---|---|
| Keychain | Stores the Cursor session cookie |
| Automation | Controls Spotify playback / metadata |
| Network | Calls Cursor’s dashboard usage API |

**Caveats:** Cursor usage is read from an undocumented dashboard endpoint (`/api/usage-summary`) using your session cookie. Cursor may change or break this at any time. Treat this as a personal / experimental tool — use at your own risk. No telemetry is sent by this app beyond what Cursor’s own APIs receive when you fetch usage.

---

## Project layout

```
Sources/DynamicIsland/
  App/           # App entry, menu bar, bootstrap
  Island/        # Notch panel, morph, views
  Features/      # Cursor usage + Spotify
  Auth/          # WebView login
  Support/       # Geometry, Keychain, motion, logos
Scripts/         # package-app.sh
Resources/       # Info.plist
```

---

## Contributing

Issues and pull requests are welcome — especially around Cursor API resilience, notch geometry on more machines, and polish.

---

## License

[MIT](LICENSE)
