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
