# Mac Toolkit 🖱️↔️🖲️ · 🗂️ · 📊

A small menu bar utility for macOS (formerly **ConvinientScroll**) with four modules, each of which can be turned on or off in Settings:

- **Scrolling** — automatically switches “Natural scrolling” depending on what’s connected: a **mouse** or a **trackpad**.
- **File Shelf** — drag files to the notch (or the top centre of any display), switch to another Space, and drag them out again.
- **Memory** — shows the share of RAM in use in the menu bar, counted as in Activity Monitor.
- **Temperature** — shows the CPU temperature in the menu bar and warns when macOS throttles the Mac to cool it.

All modules share **one menu bar item** and one menu: the scrolling or shelf icon, then the memory and temperature readings when those modules are on. Hold ⌘ and drag the item to move the whole group along the menu bar.

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

### Memory

Off by default; turn it on in **Settings → Memory**.

- The Mac Toolkit menu bar item gains the share of RAM in use, for example **57%**, counted the same way as **Memory Used** in Activity Monitor: app memory, wired and compressed, without file cache.
- The number changes only when usage moves by a whole point, so it does not flicker between two values.
- The number turns **yellow** when macOS reports memory pressure and **red** when it becomes critical.
- Click the item to see the amount in GB and the pressure level, or to open Activity Monitor.

### Temperature

Off by default; turn it on in **Settings → Temperature**.

- The Mac Toolkit menu bar item gains the temperature of the hottest CPU core, for example **58°**, in °C. The item keeps the same width as the digits change.
- The number turns **yellow** when macOS reports Heavy thermal pressure (the Mac is throttled) and **red** at Critical.
- Click the item to see the temperature, the fan speed and the pressure level, and how long the Mac has been throttled since the module was turned on, for example **Throttled 1m of 13m**.
- A notification arrives when the Mac starts throttling: Heavy at most once every 10 minutes, Critical every time. It can be turned off in the same settings section.
- Works on Apple silicon (M1 and later). On Intel Macs the item shows **—°** and the pressure level only.

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

**Memory**

- macOS has no notification for memory usage, so the module reads `host_statistics64` every 2 seconds with a 20% leeway, letting the system batch the wake-ups. Used memory is `internal − purgeable + wired + compressor` pages out of the installed RAM.
- The menu bar item is redrawn only when the whole percentage or the pressure level changes. Pressure comes from a `DispatchSource` memory pressure event, not from polling.
- The timer runs only while the module is on, and stops while the Mac sleeps, the display is off or another user is active.

**Temperature**

- The thermal pressure level comes from the `com.apple.system.thermalpressurelevel` Darwin notification, so colours and notifications need no polling.
- The temperature is read every 2 seconds with a 20% leeway from the SMC sensors of the CPU cores (`Tp*` and `Te*` keys), found by listing the SMC keys once rather than from a per-model table. On a Mac without them the module falls back to the HID sensors of the chip (`tdie`, `pACC`/`eACC MTR`, `SOC MTR`), which read cooler than the cores. Readings outside 10–130 °C are ignored. Which sensor is which on M5 was found experimentally: [docs/thermal-sensors-m5.md](docs/thermal-sensors-m5.md). The fan speed comes from SMC (`F0Ac` against `F0Mx`).
- To keep the cost down, each sample reads only the four hottest sensors and re-checks all of them every 30 seconds. The number in the menu bar is the median of the last three samples and changes only when it moves by at least 1.5 °C, so it does not flicker with sensor noise. The fan is read only while the menu is open.
- Sensors are read on a background queue. The HID client and the SMC connection are opened once when the module is turned on and closed when it is turned off.
- The timer runs only while the module is on, and stops while the Mac sleeps, the display is off or another user is active. The level statistics live in memory only.

Apart from the Memory and Temperature modules, the app runs no periodic timers when idle: everything is driven by system notifications.

---

## 🚀 Install / Run

### From a disk image

1. Download `MacToolkit-<version>.dmg` and open it
2. If Mac Toolkit (or the older ConvinientScroll) is already running, quit it from the menu bar first
3. Drag **Mac Toolkit** onto **Applications**; if an older version is there, choose **Replace**
4. Eject the disk image and open Mac Toolkit from **Applications**

Versions that have **Check for Updates…** in the menu bar install updates themselves. The manual steps above are needed only for the first installation and for versions without that menu item.

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
- **The menu bar item is missing**
  - On a crowded menu bar it can be hidden behind the notch; ⌘-drag it closer to the clock
- **The memory or temperature reading is missing**
  - Check that **Memory** or **Temperature** is on in Settings
- **The temperature shows —°**
  - The Mac exposes no CPU temperature sensor the module recognises (for example an Intel Mac). The log lists which sensors were found: `log show --last 1h --info --predicate 'subsystem == "com.alehbarushka.convinientscroll" AND category == "thermal"'`

---

## 🙏 Credits

- Apple `IOKit` / HID — device information access
- macOS preferences (`CFPreferences`) — system preference synchronization
- Quick Look Thumbnailing — shelf card previews
- Mach host statistics (`host_statistics64`) — memory usage
- SMC, HID temperature sensors and the thermal pressure notification — CPU temperature, fan speed and throttling

---

## 📄 License

Mac Toolkit is free for personal and other noncommercial use: you may use, copy and modify it and share your changes. Commercial use is not permitted.

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE.md) since version 2.0.0. Versions up to and including 1.1.3 were released under the MIT License, and those releases keep it.

Required Notice: Copyright (c) 2026 Aleh Barushka
