# URL Clipboard Language Cleaner

A cross-platform PowerShell script that automatically removes language/locale segments from URLs when you copy them to the clipboard.

When you copy a URL like `https://learn.microsoft.com/en-gb/azure/virtual-machines/overview`, the script instantly cleans it to `https://learn.microsoft.com/azure/virtual-machines/overview` — so when you share the link, recipients are redirected to their own preferred language by the server.

## How It Works

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
