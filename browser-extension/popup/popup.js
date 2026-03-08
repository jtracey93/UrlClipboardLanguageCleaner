/**
 * Popup script for URL Clipboard Language Cleaner.
 * Handles the enable/disable toggle, clipboard preview, and navigation to options.
 */

const DEFAULT_EXCLUDED_CODES = [
  'to', 'do', 'go', 'me', 'us', 'my', 'no', 'or', 'so', 'up',
  'if', 'in', 'on', 'at', 'by', 'of', 'as', 'is', 'it', 'an'
];

/** Build a RegExp from the stored pattern string.
 *  The pattern is raw RegExp source – NOT a JS regex literal /pattern/flags.
 *  The leading '/' in the default pattern is intentional: it matches the URL
 *  path separator before the language code so the whole '/en-gb' segment is
 *  removed in one operation (no double-slash artefact). */
function buildPattern(patternStr) {
  try {
    return new RegExp(patternStr, 'i');
  } catch (_) {
    // Fallback to default; leading '/' is a literal path-separator character
    return new RegExp('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)', 'i');
  }
}

/**
 * Remove the first locale/language path segment from a URL string.
 * @param {string} text
 * @param {string[]} excludedCodes
 * @param {string} localePattern
 * @returns {string|null}
 */
function removeUrlLocale(text, excludedCodes, localePattern) {
  const trimmed = text.trim();
  if (trimmed.length > 2048) return null;

  let url;
  try {
    url = new URL(trimmed);
  } catch (_) {
    return null;
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;

  const pattern = buildPattern(localePattern);
  const match = url.pathname.match(pattern);
  if (!match) return null;

  const matchedCode = match[0].replace(/^\//, '').toLowerCase();
  if (matchedCode.length === 2 && excludedCodes.includes(matchedCode)) return null;

  const cleanedPath =
    url.pathname.slice(0, match.index) +
    url.pathname.slice(match.index + match[0].length);

  if (cleanedPath === url.pathname) return null;

  url.pathname = cleanedPath;
  return url.toString();
}

// ─── DOM refs ────────────────────────────────────────────────────────────────
const toggle = document.getElementById('enabled-toggle');
const statusText = document.getElementById('status-text');
const previewEl = document.getElementById('clipboard-preview');
const cleanBtn = document.getElementById('clean-btn');
const optionsBtn = document.getElementById('options-btn');

let currentCleaned = null;

// ─── Helpers ─────────────────────────────────────────────────────────────────

function setStatusLabel(enabled) {
  statusText.textContent = enabled ? 'Enabled' : 'Disabled';
  statusText.classList.toggle('off', !enabled);
}

function showPreview(original, cleaned) {
  if (cleaned) {
    previewEl.innerHTML =
      `<span class="original" title="Original">${escapeHtml(original)}</span>` +
      `<span class="cleaned" title="Cleaned">${escapeHtml(cleaned)}</span>`;
    currentCleaned = cleaned;
    cleanBtn.disabled = false;
  } else if (original) {
    previewEl.innerHTML = `<span class="no-change">${escapeHtml(original)}</span>`;
    currentCleaned = null;
    cleanBtn.disabled = true;
  } else {
    previewEl.innerHTML = '<span class="placeholder">No URL detected in clipboard&hellip;</span>';
    currentCleaned = null;
    cleanBtn.disabled = true;
  }
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ─── Clipboard check ─────────────────────────────────────────────────────────

async function checkClipboard(excludedCodes, localePattern) {
  try {
    const text = await navigator.clipboard.readText();
    if (!text) {
      showPreview(null, null);
      return;
    }
    const cleaned = removeUrlLocale(text, excludedCodes, localePattern);
    showPreview(text, cleaned);
  } catch (_) {
    // Clipboard access denied or unavailable
    previewEl.innerHTML =
      '<span class="placeholder">Clipboard access unavailable.</span>';
    cleanBtn.disabled = true;
  }
}

// ─── Initialise ──────────────────────────────────────────────────────────────

chrome.storage.sync.get(['enabled', 'excludedCodes', 'localePattern'], async (result) => {
  const enabled = result.enabled !== undefined ? result.enabled : true;
  const excludedCodes = result.excludedCodes || DEFAULT_EXCLUDED_CODES;
  const localePattern = result.localePattern || '/[a-z]{2}(?:-[a-z]{2,4})?(?=/)';

  toggle.checked = enabled;
  setStatusLabel(enabled);

  await checkClipboard(excludedCodes, localePattern);
});

// ─── Toggle handler ──────────────────────────────────────────────────────────

toggle.addEventListener('change', () => {
  const enabled = toggle.checked;
  chrome.storage.sync.set({ enabled }, () => {
    setStatusLabel(enabled);
  });
});

// ─── Clean button ────────────────────────────────────────────────────────────

cleanBtn.addEventListener('click', async () => {
  if (!currentCleaned) return;
  try {
    await navigator.clipboard.writeText(currentCleaned);
    cleanBtn.textContent = 'Copied!';
    cleanBtn.classList.add('copied');
    setTimeout(() => {
      cleanBtn.textContent = 'Copy cleaned URL';
      cleanBtn.classList.remove('copied');
    }, 1500);
  } catch (_) {
    cleanBtn.textContent = 'Failed to copy';
    setTimeout(() => {
      cleanBtn.textContent = 'Copy cleaned URL';
    }, 1500);
  }
});

// ─── Options button ──────────────────────────────────────────────────────────

optionsBtn.addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});
