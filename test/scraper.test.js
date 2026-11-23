const test = require('node:test');
const assert = require('node:assert/strict');
const {
  extractMapDate
} = require('../scraper');

test('extracts dates from short Civil Protection filenames', () => {
  assert.equal(extractMapDate('/261123.jpg'), '2026-11-23');
  assert.equal(
    extractMapDate('https://example.test/261123_0.jpg?download=1'),
    '2026-11-23'
  );
});

test('extracts dates from long filenames', () => {
  assert.equal(
    extractMapDate('/20261123.png'),
    '2026-11-23'
  );
});

test('extracts dates from visible date text', () => {
  assert.equal(extractMapDate('23/11/2026'), '2026-11-23');
});
