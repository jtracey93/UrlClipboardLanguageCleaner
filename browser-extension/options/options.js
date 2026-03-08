/**
 * Options page script for URL Clipboard Language Cleaner.
 * Loads, validates, and saves extension settings to chrome.storage.sync.
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

// ─── DOM refs ────────────────────────────────────────────────────────────────
const enabledToggle = document.getElementById('enabled-toggle');
const localePatternInput = document.getElementById('locale-pattern');
const excludedCodesInput = document.getElementById('excluded-codes');
const patternError = document.getElementById('pattern-error');
const codesError = document.getElementById('codes-error');
const saveBtn = document.getElementById('save-btn');
const resetBtn = document.getElementById('reset-btn');
const saveStatus = document.getElementById('save-status');

// ─── Validation ──────────────────────────────────────────────────────────────

/**
 * Validate the regex pattern string. Returns an error message or empty string.
 * @param {string} value
 * @returns {string}
 */
function validatePattern(value) {
  const trimmed = value.trim();
  if (!trimmed) return 'Pattern cannot be empty.';
  try {
    new RegExp(trimmed, 'i'); // eslint-disable-line no-new
    return '';
  } catch (e) {
    return `Invalid regular expression: ${e.message}`;
  }
}

/**
 * Validate the excluded codes textarea. Returns an error message or empty string.
 * @param {string} value
 * @returns {string}
 */
function validateCodes(value) {
  const codes = value
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  const invalid = codes.filter((c) => !/^[a-z]{2}$/.test(c));
  if (invalid.length > 0) {
    return `Invalid entries (must be lowercase 2-letter codes): ${invalid.join(', ')}`;
  }
  return '';
}

// ─── Populate form ───────────────────────────────────────────────────────────

function populateForm(settings) {
  enabledToggle.checked = settings.enabled;
  localePatternInput.value = settings.localePattern;
  excludedCodesInput.value = settings.excludedCodes.join('\n');
  clearErrors();
  clearStatus();
}

function clearErrors() {
  patternError.hidden = true;
  patternError.textContent = '';
  codesError.hidden = true;
  codesError.textContent = '';
  localePatternInput.classList.remove('invalid');
  excludedCodesInput.classList.remove('invalid');
}

function clearStatus() {
  saveStatus.textContent = '';
  saveStatus.className = 'save-status';
}

// ─── Load settings ───────────────────────────────────────────────────────────

chrome.storage.sync.get(
  ['enabled', 'excludedCodes', 'localePattern'],
  (result) => {
    const settings = {
      enabled:
        result.enabled !== undefined ? result.enabled : DEFAULT_SETTINGS.enabled,
      excludedCodes: result.excludedCodes || DEFAULT_SETTINGS.excludedCodes,
      localePattern: result.localePattern || DEFAULT_SETTINGS.localePattern
    };
    populateForm(settings);
  }
);

// ─── Save ────────────────────────────────────────────────────────────────────

saveBtn.addEventListener('click', () => {
  clearErrors();
  clearStatus();

  const patternValue = localePatternInput.value.trim();
  const codesValue = excludedCodesInput.value.trim();

  const patternErr = validatePattern(patternValue);
  const codesErr = validateCodes(codesValue);

  let hasError = false;

  if (patternErr) {
    patternError.textContent = patternErr;
    patternError.hidden = false;
    localePatternInput.classList.add('invalid');
    hasError = true;
  }

  if (codesErr) {
    codesError.textContent = codesErr;
    codesError.hidden = false;
    excludedCodesInput.classList.add('invalid');
    hasError = true;
  }

  if (hasError) return;

  const excludedCodes = codesValue
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  const settings = {
    enabled: enabledToggle.checked,
    localePattern: patternValue,
    excludedCodes
  };

  chrome.storage.sync.set(settings, () => {
    saveStatus.textContent = 'Settings saved.';
    saveStatus.className = 'save-status';
    setTimeout(clearStatus, 3000);
  });
});

// ─── Reset ───────────────────────────────────────────────────────────────────

resetBtn.addEventListener('click', () => {
  if (
    !confirm(
      'Restore all settings to their defaults? This will overwrite any custom configuration.'
    )
  ) {
    return;
  }
  chrome.storage.sync.set(DEFAULT_SETTINGS, () => {
    populateForm(DEFAULT_SETTINGS);
    saveStatus.textContent = 'Settings restored to defaults.';
    saveStatus.className = 'save-status';
    setTimeout(clearStatus, 3000);
  });
});

// ─── Live validation (clear errors as user types) ────────────────────────────

localePatternInput.addEventListener('input', () => {
  patternError.hidden = true;
  localePatternInput.classList.remove('invalid');
});

excludedCodesInput.addEventListener('input', () => {
  codesError.hidden = true;
  excludedCodesInput.classList.remove('invalid');
});
