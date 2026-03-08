/**
 * Content script for URL Clipboard Language Cleaner.
 * Intercepts copy events on every page and strips language/locale
 * path segments from URLs before they reach the clipboard.
 *
 * Matching logic mirrors the PowerShell module exactly:
 *   Pattern : /[a-z]{2}(?:-[a-z]{2,4})?(?=/)  (case-insensitive)
 *   Excluded : bare 2-letter codes in the exclusion list are NOT removed
 *              e.g. /us/ or /in/ are kept; /en-us/ or /no-nb/ are removed
 */

const DEFAULT_EXCLUDED_CODES = [
  'to', 'do', 'go', 'me', 'us', 'my', 'no', 'or', 'so', 'up',
  'if', 'in', 'on', 'at', 'by', 'of', 'as', 'is', 'it', 'an'
];

// Cached settings – updated whenever storage changes
let cachedSettings = {
  enabled: true,
  excludedCodes: DEFAULT_EXCLUDED_CODES,
  // The localePattern is raw RegExp source (NOT a JS regex literal /pattern/flags).
  // The leading '/' IS intentional – it matches the URL path separator that precedes
  // the language code so the entire '/en-gb' segment (including its leading slash)
  // is removed in one pass, leaving no double-slash artefact.
  localePattern: '/[a-z]{2}(?:-[a-z]{2,4})?(?=/)'
};

/**
 * Build a RegExp from the stored pattern string.
 * The pattern is treated as raw regex source (not JS regex literal syntax).
 * Falls back to the default pattern if the stored value is invalid.
 * @param {string} patternStr
 * @returns {RegExp}
 */
function buildPattern(patternStr) {
  try {
    return new RegExp(patternStr, 'i');
  } catch (_) {
    return new RegExp('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)', 'i');
  }
}

/**
 * Remove the first locale/language path segment from a URL string.
 * Returns the cleaned URL string, or null if nothing was changed.
 * @param {string} text
 * @returns {string|null}
 */
function removeUrlLocale(text) {
  const trimmed = text.trim();
  if (trimmed.length > 2048) return null;

  let url;
  try {
    url = new URL(trimmed);
  } catch (_) {
    return null;
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;

  const pattern = buildPattern(cachedSettings.localePattern);
  const match = url.pathname.match(pattern);
  if (!match) return null;

  // Extract just the language code portion (strip leading /)
  const matchedCode = match[0].replace(/^\//, '').toLowerCase();

  // Only exclude bare 2-letter codes that are in the exclusion list
  if (matchedCode.length === 2 && cachedSettings.excludedCodes.includes(matchedCode)) {
    return null;
  }

  const cleanedPath = url.pathname.slice(0, match.index) +
    url.pathname.slice(match.index + match[0].length);

  if (cleanedPath === url.pathname) return null;

  url.pathname = cleanedPath;
  return url.toString();
}

/**
 * Display a brief in-page toast when a URL locale is removed.
 * Uses a closed shadow DOM for complete style isolation from the host page.
 * @param {string} cleanedUrl
 */
function showToast(cleanedUrl) {
  // Maximum z-index (2^31 − 1) ensures the toast sits above all page content
  const MAX_Z_INDEX = 2147483647;
  // Truncation constants: keep the displayed URL readable at a glance
  const MAX_DISPLAY_LENGTH = 55;
  const TRUNCATE_LENGTH = 52;

  const TOAST_ID = '__urlcleaner-toast-host__';
  const existing = document.getElementById(TOAST_ID);
  if (existing) existing.remove();

  const host = document.createElement('div');
  host.id = TOAST_ID;
  Object.assign(host.style, {
    position: 'fixed',
    bottom: '20px',
    right: '20px',
    zIndex: String(MAX_Z_INDEX),
    pointerEvents: 'none'
  });

  const shadow = host.attachShadow({ mode: 'closed' });
  const displayUrl =
    cleanedUrl.length > MAX_DISPLAY_LENGTH
      ? cleanedUrl.slice(0, TRUNCATE_LENGTH) + '\u2026'
      : cleanedUrl;
  const safeUrl = displayUrl
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  const titleAttr = cleanedUrl.replace(/"/g, '&quot;');

  shadow.innerHTML = `
    <style>
      .toast {
        background: #0f4c81;
        color: #fff;
        border-radius: 10px;
        padding: 10px 14px 10px 12px;
        font: 500 13px/1.45 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        max-width: 320px;
        box-shadow: 0 6px 24px rgba(0,0,0,.28);
        display: flex;
        align-items: flex-start;
        gap: 10px;
        animation: uc-in .2s cubic-bezier(.2,.8,.4,1), uc-out .3s ease 2.7s forwards;
      }
      .icon {
        width: 22px; height: 22px;
        background: rgba(255,255,255,.18);
        border-radius: 50%;
        display: flex; align-items: center; justify-content: center;
        font-size: 12px; flex-shrink: 0; margin-top: 1px;
      }
      .body { min-width: 0; }
      .title {
        font-size: 11px; font-weight: 700; letter-spacing: .06em;
        text-transform: uppercase; opacity: .75; margin-bottom: 3px;
      }
      .url {
        font: 12px/1.35 'Cascadia Code', Consolas, 'Courier New', monospace;
        white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
        max-width: 268px; opacity: .95;
      }
      @keyframes uc-in  { from { transform: translateY(10px); opacity: 0; } to { transform: none; opacity: 1; } }
      @keyframes uc-out { to   { opacity: 0; transform: translateY(4px); } }
    </style>
    <div class="toast">
      <div class="icon">&#10003;</div>
      <div class="body">
        <div class="title">Locale removed</div>
        <div class="url" title="${titleAttr}">${safeUrl}</div>
      </div>
    </div>`;

  document.documentElement.appendChild(host);
  setTimeout(() => host.remove(), 3000);
}

/**
 * Copy-event handler – rewrites the clipboard text if a locale is detected.
 * @param {ClipboardEvent} event
 */
function onCopy(event) {
  if (!cachedSettings.enabled) return;

  const text = event.clipboardData && event.clipboardData.getData('text/plain');
  if (!text) return;

  const cleaned = removeUrlLocale(text);
  if (!cleaned) return;

  event.clipboardData.setData('text/plain', cleaned);
  event.preventDefault();
  showToast(cleaned);
}

// Listen at the capture phase so we run before any page handlers
document.addEventListener('copy', onCopy, true);

// Load settings from storage
function loadSettings() {
  chrome.storage.sync.get(['enabled', 'excludedCodes', 'localePattern'], (result) => {
    if (result.enabled !== undefined) cachedSettings.enabled = result.enabled;
    if (result.excludedCodes !== undefined) cachedSettings.excludedCodes = result.excludedCodes;
    if (result.localePattern !== undefined) cachedSettings.localePattern = result.localePattern;
  });
}

// Keep settings in sync when they change (popup toggle, options save)
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'sync') return;
  if (changes.enabled !== undefined) cachedSettings.enabled = changes.enabled.newValue;
  if (changes.excludedCodes !== undefined) cachedSettings.excludedCodes = changes.excludedCodes.newValue;
  if (changes.localePattern !== undefined) cachedSettings.localePattern = changes.localePattern.newValue;
});

loadSettings();
