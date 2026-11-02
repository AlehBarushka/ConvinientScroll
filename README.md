# Mac Toolkit 🖱️↔️🖲️ · 🗂️

A small menu bar utility for macOS (formerly **ConvinientScroll**) with two modules, each of which can be turned off in Settings:

- **Scrolling** — automatically switches “Natural scrolling” depending on what’s connected: a **mouse** or a **trackpad**.
- **File Shelf** — drag files to the notch (or the top centre of any display), switch to another Space, and drag them out again.

---

## ✨ Features

### Scrolling

If you (like me) prefer:

- 🖱️ **with a mouse** — *Natural Scroll OFF* (classic “wheel down = content down”)
- 🖲️ **with a trackpad** — *Natural Scroll ON* (native gesture feel “like on a phone”)

…then Mac Toolkit removes the need to open System Settings and flip the option manually every time.

- **Auto-switch** Natural Scroll when a mouse/trackpad connects or disconnects
- **Manual toggle** in Settings (for quick override)
- **Menu bar icon** that reflects what’s detected
- **Notifications** when the state changes (best effort)

### File Shelf

Dragging a file into an app on another Space doesn’t work: the drag is lost when you switch. The shelf holds it for you.

- Drag files or folders to the **notch**, or to the **top centre** of a display without one. The shelf grows out of the notch as the file gets close.
- Later, on any Space or over a full-screen app, **hover** there: the shelf opens and you drag the files out — one at a time or all at once.
- Files are **cloned** into the shelf, so the original can move or disappear. On the same disk a clone takes no extra space; files over 1 GB from another disk are kept as a **link** to the original.
- Files are removed after **1 hour, 24 hours or 7 days** (Settings), or with **Clear**. Double-click a card to open the file, hover it and click ✕ to remove it.
- **Show Shelf** in the menu bar menu opens it without hovering.

---

## 🧠 How it works

**Scrolling**

- The app asks `IOKit` to notify it when HID devices appear or disappear (no polling) and then looks for:
  - a **mouse** (usage/page + `product` heuristics)
  - a **trackpad** (including `product` containing “trackpad”)
- It then computes a target value:
  - if **trackpad present** and **no mouse** → Natural Scroll **ON**
  - if **mouse present** → Natural Scroll **OFF** (mouse wins)
  - if **nothing is detected** → do nothing (avoid fighting an unknown state)
- The setting is changed via the global preference key:
  - `com.apple.swipescrolldirection` (global domain; equivalent to `defaults write -g ...`)

**File Shelf**

- One borderless, non-activating panel per display sits above the menu bar on every Space. It never steals focus.
- While a drag is in progress, a mouse monitor watches how close a file gets to the zone (it does nothing otherwise and needs no permission).
- Files live in `~/Library/Application Support/com.alehbarushka.convinientscroll/Shelf`. A one-shot timer removes them when they expire.

When idle, the app runs no periodic timers: everything is driven by system notifications.

---

## 🚀 Install / Run

### From a disk image

1. Download `MacToolkit-<version>.dmg` and open it
2. If Mac Toolkit (or the older ConvinientScroll) is already running, quit it from the menu bar first
3. Drag **Mac Toolkit** onto **Applications**; if an older version is there, choose **Replace**
4. Eject the disk image and open Mac Toolkit from **Applications**

Updating from ConvinientScroll: delete `ConvinientScroll.app` from Applications and turn **Launch at Login** on again in Settings (the login item is tied to the app’s location). Other settings are kept.

Don't run the app from the disk image or from the Downloads folder. macOS may run a quarantined app
from a temporary copy that is removed later (for example after sleep), and the app then crashes.

The app is signed with a development certificate and is not notarized, so macOS may refuse to open it
the first time. Right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/MacToolkit.app
```

### From source

1. Open `ConvinientScroll.xcodeproj` in Xcode
2. Select the `ConvinientScroll` scheme
3. Run (⌘R); run the tests with ⌘U

After launch, the app shows up in the menu bar only (no Dock icon). Open **Settings…** from its menu.

### Building the disk image

```sh
brew install create-dmg
./scripts/make-dmg.sh   # writes dist/MacToolkit-<version>.dmg
```

The script lays the window out through Finder, so run it from a desktop session and allow Finder
control if macOS asks. The window background lives in `dmg/`; regenerate it with
`swift scripts/render-dmg-background.swift`.

---

## 🔐 App Sandbox note

To change the system setting `com.apple.swipescrolldirection`, the app must be **non-sandboxed**.

- In this project, **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO`)
- If you build/distribute a sandboxed build (e.g. Mac App Store), macOS will **block writing** this preference

---

## 🛠️ Troubleshooting

- **The setting doesn’t change**
  - Make sure the build is **not** running in App Sandbox
  - Sometimes macOS may not apply it instantly; try logging out/in
- **Mouse/trackpad isn’t detected**
  - Detection is based on HID properties and the device `product` string, so some devices may require additional heuristics
- **The shelf doesn’t appear**
  - Check that **File Shelf** is on in Settings; an empty shelf is invisible until a file is dragged close

---

## 🙏 Credits

- Apple `IOKit` / HID — device information access
- macOS preferences (`CFPreferences`) — system preference synchronization
- Quick Look Thumbnailing — shelf card previews

---

## 📄 License

Mac Toolkit is free for personal and other noncommercial use: you may use, copy and modify it and share your changes. Commercial use is not permitted.

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE.md) since version 2.0.0. Versions up to and including 1.1.3 were released under the MIT License, and those releases keep it.

Required Notice: Copyright (c) 2026 Aleh Barushka
