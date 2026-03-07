/**
 * Background service worker for URL Clipboard Language Cleaner.
 * Responsible for setting default options on first install and
 * keeping the extension icon badge in sync with the enabled state.
 */

const DEFAULT_SETTINGS = {
  enabled: true,
  excludedCodes: [
    'to', 'do', 'go', 'me', 'us', 'my', 'no', 'or', 'so', 'up',
    'if', 'in', 'on', 'at', 'by', 'of', 'as', 'is', 'it', 'an'
  ],
  // The localePattern is raw RegExp source (NOT a JS regex literal /pattern/flags).
  // The leading '/' IS intentional – it matches the URL path separator that precedes
  // the language code so the entire '/en-gb' segment (including its leading slash)
  // is removed in one pass, leaving no double-slash artefact.
  localePattern: '/[a-z]{2}(?:-[a-z]{2,4})?(?=/)' // raw regex source; leading / is literal
};

/**
 * Set the extension icon badge to reflect the enabled/disabled state.
 * @param {boolean} enabled
 */
function updateBadge(enabled) {
  if (enabled) {
    chrome.action.setBadgeText({ text: '' });
  } else {
    chrome.action.setBadgeText({ text: 'OFF' });
    chrome.action.setBadgeBackgroundColor({ color: '#888888' });
  }
}

// Set default settings on first install
chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    chrome.storage.sync.set(DEFAULT_SETTINGS, () => {
      updateBadge(DEFAULT_SETTINGS.enabled);
    });
  } else {
    // On update, merge in any new defaults without overwriting existing user settings
    chrome.storage.sync.get(Object.keys(DEFAULT_SETTINGS), (stored) => {
      const toSet = {};
      for (const [key, value] of Object.entries(DEFAULT_SETTINGS)) {
        if (stored[key] === undefined) {
          toSet[key] = value;
        }
      }
      if (Object.keys(toSet).length > 0) {
        chrome.storage.sync.set(toSet);
      }
      const enabled = stored.enabled !== undefined ? stored.enabled : DEFAULT_SETTINGS.enabled;
      updateBadge(enabled);
    });
  }
});

// Keep badge in sync when storage changes (e.g. popup toggle)
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'sync' && changes.enabled !== undefined) {
    updateBadge(changes.enabled.newValue);
  }
});

// Initialise badge on service worker start (browser restart / update)
chrome.storage.sync.get('enabled', (result) => {
  const enabled = result.enabled !== undefined ? result.enabled : DEFAULT_SETTINGS.enabled;
  updateBadge(enabled);
});
