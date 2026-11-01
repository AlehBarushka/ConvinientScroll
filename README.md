# ConvinientScroll 🖱️↔️🖲️

A macOS utility that **automatically switches “Natural scrolling”** depending on what’s currently connected: a **mouse** or a **trackpad**.

If you (like me) prefer:

- 🖱️ **with a mouse** — *Natural Scroll OFF* (classic “wheel down = content down”)
- 🖲️ **with a trackpad** — *Natural Scroll ON* (native gesture feel “like on a phone”)

…then `ConvinientScroll` removes the need to open System Settings and flip the option manually every time.

---

## ✨ Features

- **Auto-switch** Natural Scroll when a mouse/trackpad connects or disconnects
- **Manual toggle** inside the app (for quick override)
- **Menu bar icon** that reflects what’s detected
- **Notifications** when the state changes (best effort)

---

## 🧠 How it works

In short:

- The app periodically enumerates HID devices via `IOKit` and detects the presence of:
  - a **mouse** (usage/page + `product` heuristics)
  - a **trackpad** (including `product` containing “trackpad”)
- It then computes a target value:
  - if **trackpad present** and **no mouse** → Natural Scroll **ON**
  - if **mouse present** → Natural Scroll **OFF** (mouse wins)
  - if **nothing is detected** → do nothing (avoid fighting an unknown state)
- The setting is changed via the global preference key:
  - `com.apple.swipescrolldirection` (global domain; equivalent to `defaults write -g ...`)

---

## 🚀 Install / Run

### From a disk image

1. Download `ConvinientScroll-<version>.dmg` and open it
2. If ConvinientScroll is already running, quit it from the menu bar first
3. Drag **ConvinientScroll** onto **Applications**; if an older version is there, choose **Replace**
4. Eject the disk image and open ConvinientScroll from **Applications**

Don't run the app from the disk image or from the Downloads folder. macOS may run a quarantined app
from a temporary copy that is removed later (for example after sleep), and the app then crashes.

The app is signed with a development certificate and is not notarized, so macOS may refuse to open it
the first time. Right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/ConvinientScroll.app
```

### From source

1. Open `ConvinientScroll.xcodeproj` in Xcode
2. Select the `ConvinientScroll` target
3. Run (⌘R)

After launch, the app shows up in the menu bar.

### Building the disk image

```sh
brew install create-dmg
./scripts/make-dmg.sh   # writes dist/ConvinientScroll-<version>.dmg
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

## 🧩 Usage

- **Auto mode** starts immediately on launch (no extra steps)
- The **Natural Scroll** toggle in the app changes the setting directly
- The **Mouse / Trackpad** rows show what’s currently detected

---

## 🛠️ Troubleshooting

- **The setting doesn’t change**
  - Make sure the build is **not** running in App Sandbox
  - Sometimes macOS may not apply it instantly; try logging out/in
- **Mouse/trackpad isn’t detected**
  - Detection is based on HID properties and the device `product` string, so some devices may require additional heuristics

---

## 🙏 Credits

- Apple `IOKit` / HID — device information access
- macOS preferences (`CFPreferences`) — system preference synchronization

