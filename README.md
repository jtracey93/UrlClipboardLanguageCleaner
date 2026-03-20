# URL Clipboard Language Cleaner

A cross-platform PowerShell script or Edge/Chrome browser extension that automatically removes language/locale segments from URLs when you copy them to the clipboard.

When you copy a URL like `https://learn.microsoft.com/en-gb/azure/virtual-machines/overview`, the tool instantly cleans it to `https://learn.microsoft.com/azure/virtual-machines/overview` — so when you share the link, recipients are redirected to their own preferred language by the server.
## Browser Extension (Chrome & Edge)

A Manifest V3 browser extension is also available in the [`browser-extension/`](./browser-extension/) directory. It brings the same URL locale-cleaning functionality to Microsoft Edge and Google Chrome.

## Edge/Chrome Extension

### Install from the store

| Browser | Store link |
|---|---|
| **Google Chrome** | [Install from Chrome Web Store](https://chromewebstore.google.com/detail/url-clipboard-language-cl/lelbdplafgjmiccacifgpflfccnmchfj)  |
| **Microsoft Edge** | [Install from Edge Add-ons](https://microsoftedge.microsoft.com/addons/detail/url-clipboard-language-cl/eeahoklgnhdkbmidbhbgehkiedacmnec)  |

### Features

- **Automatic copy interception** — locale segments are stripped as you copy URLs from any web page
- **Easy on/off toggle** — enable or disable from the extension popup without fully disabling the extension
- **Clipboard inspector** — the popup shows your current clipboard URL and its cleaned equivalent, with a one-click "Copy cleaned URL" button
- **Configurable patterns** — edit the locale regex and excluded 2-letter codes in the Settings page (defaults mirror the PowerShell module exactly)
- **Persistent settings** — all preferences sync across browser profiles via `chrome.storage.sync`

### Installing the extension (unpacked / developer mode)

Both Chrome and Edge support loading unpacked extensions directly from the folder:

#### Google Chrome

1. Open `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked**
4. Select the `browser-extension/` folder from this repository

#### Microsoft Edge

1. Open `edge://extensions`
2. Enable **Developer mode** (left sidebar)
3. Click **Load unpacked**
4. Select the `browser-extension/` folder from this repository

### Publishing to stores

To publish to the Chrome Web Store or Edge Add-ons store, zip the contents of the `browser-extension/` folder and follow the submission process for each store:

- **Chrome Web Store**: [developer.chrome.com/docs/webstore/publish](https://developer.chrome.com/docs/webstore/publish)
- **Microsoft Edge Add-ons**: [learn.microsoft.com/en-us/microsoft-edge/extensions/publish/publish-extension](https://learn.microsoft.com/en-us/microsoft-edge/extensions/publish/publish-extension)

### Extension structure

```
browser-extension/
├── manifest.json            # Manifest V3 — compatible with Chrome and Edge
├── background/
│   └── service-worker.js    # Sets defaults on install, keeps badge in sync
├── content/
│   └── content.js           # Intercepts copy events in web pages
├── popup/
│   ├── popup.html           # Extension popup UI
│   ├── popup.js             # Popup logic (toggle, clipboard preview)
│   └── popup.css
├── options/
│   ├── options.html         # Full settings page
│   ├── options.js           # Validation and save logic
│   └── options.css
└── icons/
    ├── icon16.png
    ├── icon48.png
    └── icon128.png
```

### How it works

The content script intercepts the browser's native `copy` event (in the capture phase) before clipboard contents are written. If the copied text is a URL containing a locale segment, it calls `event.clipboardData.setData()` with the cleaned URL and prevents the default write — so the locale-free version lands on your clipboard seamlessly.

The popup additionally reads the clipboard directly (using the `clipboardRead` permission) so you can see and copy a cleaned URL even when the copy originated from outside a web page (e.g. the address bar).

---

## PowerShell Script

### How It Works

The script monitors your clipboard for changes. When it detects a URL containing a locale path segment (e.g. `/en-gb/`, `/en-us/`, `/fr-fr/`, `/de/`), it strips it out and replaces your clipboard with the cleaned URL. Non-URL clipboard content is left untouched.

### Locale Patterns Matched

Any path segment matching a 2-letter language code with an optional region subtag:

| Pattern | Examples |
|---|---|
| `/xx/` | `/en/`, `/fr/`, `/de/`, `/ja/` |
| `/xx-xx/` | `/en-gb/`, `/en-us/`, `/fr-fr/`, `/zh-hans/` |

### Platform-Specific Behaviour

| Platform | Monitoring Method | CPU Usage |
|---|---|---|
| **Windows** | Win32 `AddClipboardFormatListener` (event-driven) | Zero when idle |
| **macOS** | Polling via `pbpaste` / `pbcopy` | Minimal (default every 500ms) |
| **Linux (Wayland)** | Polling via `wl-paste` / `wl-copy` | Minimal (default every 500ms) |
| **Linux (X11)** | Polling via `xclip` or `xsel` | Minimal (default every 500ms) |

## Prerequisites

- **Windows**: PowerShell 5.1+ (built-in) or PowerShell 7+
- **macOS**: [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-macos) (`brew install powershell`)
- **Linux**: [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) and one of: `xclip`, `xsel`, or `wl-clipboard`

## Usage

### Run Interactively

```powershell
./UrlClipboardLanguageCleaner.ps1
```

The script runs in the foreground and logs each cleaned URL to the console. Press `Ctrl+C` to stop.

### Install (Auto-Run at Logon)

```powershell
./UrlClipboardLanguageCleaner.ps1 -Install
```

This registers the script to start automatically when you log in, then immediately begins monitoring. On Windows it runs hidden with no console window.

| Platform | Auto-Start Mechanism |
|---|---|
| **Windows** | Shortcut in `shell:startup` folder |
| **macOS** | LaunchAgent in `~/Library/LaunchAgents/` |
| **Linux** | systemd user service in `~/.config/systemd/user/` |

### Uninstall (Remove Auto-Run)

```powershell
./UrlClipboardLanguageCleaner.ps1 -Uninstall
```

Removes the auto-start registration. The script will no longer run at logon.

### Adjust Polling Interval (macOS/Linux only)

```powershell
./UrlClipboardLanguageCleaner.ps1 -PollingIntervalMs 300
```

Sets the polling interval to 300ms instead of the default 500ms. This has no effect on Windows, which uses event-driven monitoring.

## Examples

| Before (copied URL) | After (clipboard replaced) |
|---|---|
| `https://learn.microsoft.com/en-gb/azure/overview` | `https://learn.microsoft.com/azure/overview` |
| `https://support.microsoft.com/en-us/help/12345` | `https://support.microsoft.com/help/12345` |
| `https://example.com/fr-fr/docs/guide` | `https://example.com/docs/guide` |
| `https://example.com/de/products/item` | `https://example.com/products/item` |
| `https://example.com/docs/guide` | *(no change — no locale found)* |

## Stopping the Script

- **Interactive mode**: Press `Ctrl+C`
- **Windows (background)**: End the `powershell.exe` process from Task Manager
- **macOS**: `launchctl unload ~/Library/LaunchAgents/com.user.UrlClipboardLanguageCleaner.plist`
- **Linux**: `systemctl --user stop UrlClipboardLanguageCleaner`
