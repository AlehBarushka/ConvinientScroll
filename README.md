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

For now, the project is distributed as source.

1. Open `ConvinientScroll.xcodeproj` in Xcode
2. Select the `ConvinientScroll` target
3. Run (⌘R)

After launch, the app shows up in the menu bar.

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

