import { asE164Phone, phoneRegion, regionsFromLanguages } from './phone';

test('regionsFromLanguages', () => {
  expect(regionsFromLanguages(['en-AU', 'vi', 'en-US', 'en_AU'])).toEqual(['AU', 'US']);
  expect(regionsFromLanguages(['zh-Hant-TW'])).toEqual(['TW']);
  expect(regionsFromLanguages(['vi'])).toEqual([]);
  expect(regionsFromLanguages(undefined)).toEqual([]);
});

test('asE164Phone', () => {
  // Local format, interpreted with the browser's region(s).
  expect(asE164Phone('0491 570 104', ['AU'])).toBe('+61491570104');
  expect(asE164Phone('0491570104', ['US', 'AU'])).toBe('+61491570104');
  expect(asE164Phone('0912 345 678', ['VN'])).toBe('+84912345678');
  // International format needs no region.
  expect(asE164Phone('+61 491 570 104', [])).toBe('+61491570104');
  expect(asE164Phone('+61 (491) 570-104')).toBe('+61491570104');
  // Not phones, or not valid in any of the regions.
  expect(asE164Phone('0491 570 104', [])).toBeNull();
  expect(asE164Phone('alice', ['AU'])).toBeNull();
  expect(asE164Phone('12345', ['AU'])).toBeNull();
  expect(asE164Phone('', ['AU'])).toBeNull();
});

test('phoneRegion', () => {
  expect(phoneRegion('+61491570104')).toBe('AU');
  expect(phoneRegion('+84912345678')).toBe('VN');
  expect(phoneRegion('')).toBeNull();
  expect(phoneRegion(undefined)).toBeNull();
});
