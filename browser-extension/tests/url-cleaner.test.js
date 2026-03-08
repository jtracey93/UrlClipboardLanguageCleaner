/**
 * Unit tests for the browser extension's URL locale-cleaning logic.
 *
 * Uses Node.js built-in test runner (node:test). Run with:
 *   node --test browser-extension/tests/url-cleaner.test.js
 *
 * The pure functions are inlined here (no Chrome API dependencies) and kept
 * in sync with content/content.js and popup/popup.js. This mirrors the
 * approach used in the PowerShell Pester tests.
 */

'use strict';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');

// ─── Functions under test (inlined, no Chrome API deps) ──────────────────────

const DEFAULT_EXCLUDED_CODES = [
  'to', 'do', 'go', 'me', 'us', 'my', 'no', 'or', 'so', 'up',
  'if', 'in', 'on', 'at', 'by', 'of', 'as', 'is', 'it', 'an'
];

// The localePattern is raw RegExp source (NOT a JS regex literal /pattern/flags).
// The leading '/' is intentional – it matches the URL path separator before the
// language code so the whole '/en-gb' segment is removed without leaving a
// double-slash artefact. buildPattern() wraps this string in new RegExp(..., 'i').
const DEFAULT_LOCALE_PATTERN = '/[a-z]{2}(?:-[a-z]{2,4})?(?=/)';

function buildPattern(patternStr) {
  try {
    return new RegExp(patternStr, 'i');
  } catch (_) {
    return new RegExp('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)', 'i');
  }
}

function removeUrlLocale(
  text,
  excludedCodes = DEFAULT_EXCLUDED_CODES,
  localePattern = DEFAULT_LOCALE_PATTERN
) {
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
    url.pathname.slice(0, match.index) + url.pathname.slice(match.index + match[0].length);
  if (cleanedPath === url.pathname) return null;

  url.pathname = cleanedPath;
  return url.toString();
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('removeUrlLocale – xx-xx locale codes', () => {
  test('removes /en-gb/ from Microsoft Learn URL', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/en-gb/azure/virtual-machines/overview'),
      'https://learn.microsoft.com/azure/virtual-machines/overview'
    );
  });

  test('removes /en-us/ from Microsoft support URL', () => {
    assert.equal(
      removeUrlLocale('https://support.microsoft.com/en-us/help/12345'),
      'https://support.microsoft.com/help/12345'
    );
  });

  test('removes /fr-fr/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/fr-fr/docs/guide'),
      'https://example.com/docs/guide'
    );
  });

  test('removes /zh-hans/ (4-letter region subtag)', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/zh-hans/dotnet/overview'),
      'https://learn.microsoft.com/dotnet/overview'
    );
  });

  test('removes /pt-br/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/pt-br/docs/getting-started'),
      'https://example.com/docs/getting-started'
    );
  });

  test('removes /de-de/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/de-de/products/item'),
      'https://example.com/products/item'
    );
  });

  test('removes /ja-jp/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/ja-jp/products'),
      'https://example.com/products'
    );
  });
});

describe('removeUrlLocale – bare xx locale codes', () => {
  test('removes /en/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/en/docs/guide'),
      'https://example.com/docs/guide'
    );
  });

  test('removes /de/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/de/products/item'),
      'https://example.com/products/item'
    );
  });

  test('removes /fr/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/fr/page'),
      'https://example.com/page'
    );
  });

  test('removes /ja/ from URL', () => {
    assert.equal(
      removeUrlLocale('https://example.com/ja/support'),
      'https://example.com/support'
    );
  });
});

describe('removeUrlLocale – excluded bare 2-letter codes', () => {
  const codes = [
    'to', 'do', 'go', 'me', 'us', 'my', 'no', 'or', 'so', 'up',
    'if', 'in', 'on', 'at', 'by', 'of', 'as', 'is', 'it', 'an'
  ];

  for (const code of codes) {
    test(`does NOT remove /${code}/ (excluded common word)`, () => {
      assert.equal(
        removeUrlLocale(`https://example.com/${code}/store/item`),
        null
      );
    });
  }

  test('DOES remove /no-nb/ even though /no/ is excluded', () => {
    assert.equal(
      removeUrlLocale('https://example.com/no-nb/path/guide'),
      'https://example.com/path/guide'
    );
  });

  test('DOES remove /us-en/ even though /us/ is excluded', () => {
    assert.equal(
      removeUrlLocale('https://example.com/us-en/support'),
      'https://example.com/support'
    );
  });
});

describe('removeUrlLocale – URL validation', () => {
  test('returns null for non-URL string', () => {
    assert.equal(removeUrlLocale('not a url'), null);
  });

  test('returns null for empty string', () => {
    assert.equal(removeUrlLocale(''), null);
  });

  test('returns null for ftp:// URL', () => {
    assert.equal(removeUrlLocale('ftp://example.com/en/path'), null);
  });

  test('returns null for file:// URL', () => {
    assert.equal(removeUrlLocale('file:///home/user/en/file.txt'), null);
  });

  test('returns null when no locale segment found', () => {
    assert.equal(removeUrlLocale('https://example.com/docs/guide'), null);
  });

  test('returns null for URL longer than 2048 chars', () => {
    assert.equal(
      removeUrlLocale('https://example.com/en/' + 'a'.repeat(2100)),
      null
    );
  });

  test('handles URL at exactly the 2048-char limit (processes normally)', () => {
    const base = 'https://example.com/en-us/';
    const padding = 'a'.repeat(2048 - base.length - 1) + '/';
    const url = base + padding;
    assert.equal(url.length <= 2048, true);
    const result = removeUrlLocale(url);
    assert.ok(result !== null);
  });
});

describe('removeUrlLocale – preserves query strings and hashes', () => {
  test('preserves query string after locale removal', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/en-us/azure/overview?pivots=test'),
      'https://learn.microsoft.com/azure/overview?pivots=test'
    );
  });

  test('preserves hash fragment after locale removal', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/en-us/azure/overview#section'),
      'https://learn.microsoft.com/azure/overview#section'
    );
  });

  test('preserves both query string and hash', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/en-us/azure/overview?pivots=a#section1'),
      'https://learn.microsoft.com/azure/overview?pivots=a#section1'
    );
  });
});

describe('removeUrlLocale – case insensitivity', () => {
  test('removes /EN-GB/ (uppercase)', () => {
    assert.equal(
      removeUrlLocale('https://example.com/EN-GB/docs'),
      'https://example.com/docs'
    );
  });

  test('removes /En-Us/ (mixed case)', () => {
    assert.equal(
      removeUrlLocale('https://example.com/En-Us/docs'),
      'https://example.com/docs'
    );
  });
});

describe('removeUrlLocale – real-world URLs', () => {
  test('Microsoft Learn /en-gb/', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/en-gb/azure/virtual-machines/overview'),
      'https://learn.microsoft.com/azure/virtual-machines/overview'
    );
  });

  test('Azure portal docs /en-us/', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/en-us/azure/portal/overview'),
      'https://learn.microsoft.com/azure/portal/overview'
    );
  });

  test('.NET docs /zh-hans/ (Chinese Simplified)', () => {
    assert.equal(
      removeUrlLocale('https://learn.microsoft.com/zh-hans/dotnet/core/overview'),
      'https://learn.microsoft.com/dotnet/core/overview'
    );
  });
});

describe('buildPattern', () => {
  test('returns a RegExp for a valid pattern string', () => {
    const re = buildPattern('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)');
    assert.ok(re instanceof RegExp);
  });

  test('default pattern matches /en-gb/', () => {
    const re = buildPattern('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)');
    assert.ok(re.test('/en-gb/'));
  });

  test('default pattern matches /fr/', () => {
    const re = buildPattern('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)');
    assert.ok(re.test('/fr/'));
  });

  test('default pattern does NOT match bare hostname (no leading slash)', () => {
    const re = buildPattern('/[a-z]{2}(?:-[a-z]{2,4})?(?=/)');
    assert.equal(re.test('en/path'), false);
  });

  test('falls back to default pattern when given invalid regex', () => {
    const re = buildPattern('[invalid(');
    assert.ok(re instanceof RegExp);
    assert.ok(re.test('/en-us/'));
  });

  test('custom pattern is applied correctly', () => {
    // Narrower pattern matching only xx-xx codes (not bare xx)
    const re = buildPattern('/[a-z]{2}-[a-z]{2,4}(?=/)');
    assert.ok(re.test('/en-gb/'));
    assert.equal(re.test('/en/'), false);
  });
});

describe('removeUrlLocale – custom patterns and excluded codes', () => {
  test('custom excluded codes are respected', () => {
    assert.equal(
      removeUrlLocale('https://example.com/fr/page', ['fr'], DEFAULT_LOCALE_PATTERN),
      null
    );
  });

  test('empty excluded codes list removes even common words', () => {
    assert.equal(
      removeUrlLocale('https://example.com/us/store', [], DEFAULT_LOCALE_PATTERN),
      'https://example.com/store'
    );
  });

  test('custom locale pattern restricts what is removed', () => {
    // Only match xx-xx codes (not bare xx)
    const strictPattern = '/[a-z]{2}-[a-z]{2,4}(?=/)';
    assert.equal(
      removeUrlLocale('https://example.com/en/docs', DEFAULT_EXCLUDED_CODES, strictPattern),
      null
    );
    assert.equal(
      removeUrlLocale('https://example.com/en-us/docs', DEFAULT_EXCLUDED_CODES, strictPattern),
      'https://example.com/docs'
    );
  });
});
