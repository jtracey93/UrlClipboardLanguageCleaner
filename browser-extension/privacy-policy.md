# Privacy Policy — URL Clipboard Language Cleaner

**Effective date:** 2025-01-01

> **Summary:** This extension processes clipboard content _entirely on your device_. No data is ever sent to any server, collected, stored outside your browser, or shared with third parties.

---

## What the extension does

URL Clipboard Language Cleaner is a browser extension that automatically removes language and locale path segments (e.g. `/en-gb/`, `/fr-fr/`) from URLs as you copy them, so you get clean, locale-free links.

## Data collected

The extension does **not** collect, transmit, or store any personal data. Specifically:

- **Clipboard content** – The text you copy is read and, if it contains a locale segment, rewritten in-place. This processing happens entirely in your browser. The content is never sent anywhere.
- **Extension settings** – Your enabled/disabled state, custom regex pattern, and excluded locale codes are saved using `chrome.storage.sync`, which is managed by your browser and optionally synced across your own signed-in devices via your Google or Microsoft account. These settings are not accessible to us.

## Permissions used

| Permission | Why it is needed |
|---|---|
| `clipboardRead` | Allows the popup to read the current clipboard and show a before/after preview of any locale that would be removed. |
| `clipboardWrite` | Allows the popup's **Copy cleaned URL** button to write the cleaned URL back to the clipboard. |
| `storage` | Persists your settings (toggle state, custom regex, excluded codes) across browser sessions. |
| `host_permissions` (`<all_urls>`) | Allows the content script to intercept copy events on any page and silently clean URLs as you copy them. |

## No remote code or external requests

All extension logic is bundled locally. The extension makes no network requests and executes no remotely hosted code.

## Third-party services

None. The extension has no analytics, advertising, or third-party integrations.

## Children's privacy

The extension does not collect any data from anyone, including children under 13.

## Changes to this policy

If this policy changes, the updated version will be committed to the [project repository](https://github.com/jtracey93/UrlClipboardLanguageCleaner) and the effective date above will be updated.

## Contact

Questions or concerns can be raised via the [GitHub Issues page](https://github.com/jtracey93/UrlClipboardLanguageCleaner/issues).

---

_Source available at [github.com/jtracey93/UrlClipboardLanguageCleaner](https://github.com/jtracey93/UrlClipboardLanguageCleaner)_
