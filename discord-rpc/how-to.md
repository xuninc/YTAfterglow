# Afterglow Discord RPC Integration

Show what you're watching on YouTube in your Discord status. In real time

## Requirements

- iPhone with YouTube Afterglow installed
- Discord running on your desktop
- iPhone and desktop on the **same Wi-Fi network**

---

## Installation

### macOS

1. Download the Afterglow RPC macOS companion from the project release bundle, when available.
2. Open the `.dmg` and drag the app to your Applications folder
3. Launch **Afterglow RPC** from Applications

> First launch may show a warning — go to **System Settings → Privacy & Security** and click **Open Anyway**

### Windows

1. Download the Afterglow RPC Windows companion from the project release bundle, when available.
2. Run the installer and follow the steps
3. Launch **Afterglow RPC** from the desktop shortcut

> Windows may show a SmartScreen warning — click **More info → Run anyway**

---

## Setup

1. Make sure **Discord is running**
2. Launch **Afterglow RPC** — it will appear in your system tray
3. Click the tray icon and note the server address (e.g. `http://192.168.1.5:5001`)
4. On your iPhone, open **YouTube → Settings → Afterglow → Discord RPC**
5. Paste the server address and enable Discord RPC

---

## Usage

- Keep **Afterglow RPC** and **Discord** open while watching
- Your iPhone and desktop must be on the **same Wi-Fi network**
- You can toggle visibility in Discord from the tray menu via **Display in profile**

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "Discord disconnected" in tray | Make sure Discord is running, the app will reconnect automatically |
| No activity showing in Discord | Check that both devices are on the same Wi-Fi network |
| "Please enable local network permission" on iPhone | Go to **iOS Settings → YouTube → Local Network** and enable it |
| "Please start the server" on iPhone | Make sure Afterglow RPC is running on your desktop |
| RPC not working even on the same Wi-Fi | On Windows, disable any virtual network adapters (VMware, VPN adapters, TAP adapters, and similar). These can interfere with local network discovery and prevent your iPhone from reaching the desktop server |
| "app is damaged" on macOS | Run `xattr -cr "/Applications/Afterglow RPC.app"` in Terminal |
