import { asE164Phone, localRegions, phoneRegion, regionsFromLanguages } from './phone';

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
  // Not phones, or no region to interpret a local number with.
  expect(asE164Phone('0491 570 104', [])).toBeNull();
  expect(asE164Phone('alice', ['AU'])).toBeNull();
  expect(asE164Phone('12345', ['AU'])).toBeNull();
  expect(asE164Phone('', ['AU'])).toBeNull();
  expect(asE164Phone(undefined, ['AU'])).toBeNull();
  expect(asE164Phone('+61 491 570 104 ext', [])).toBeNull();
  expect(asE164Phone('call 0491 570 104', ['AU'])).toBeNull();
  expect(asE164Phone('1234567890123456789', ['AU'])).toBeNull();
  // A valid number in a later region wins over a merely possible one in an earlier region.
  expect(asE164Phone('0491 570 104', ['US', 'AU'])).toBe('+61491570104');
});

test('asE164Phone accepts possible numbers, not only valid mobiles', () => {
  // Landlines (the mobile-only metadata doesn't call them valid, but they are possible).
  expect(asE164Phone('(02) 9876-5432', ['AU'])).toBe('+61298765432');
  expect(asE164Phone('028 3823 4567', ['VN'])).toBe('+842838234567');
  expect(asE164Phone('+84 28 3823 4567', [])).toBe('+842838234567');
  // Right length, unassigned range.
  expect(asE164Phone('+1 555 555 5555', [])).toBe('+15555555555');
  expect(asE164Phone('(415) 555-0100', ['US'])).toBe('+14155550100');
  // Wrong length for the region: not a phone number.
  expect(asE164Phone('555-0100', ['US'])).toBeNull();
  // The '00' international prefix, and other separators.
  expect(asE164Phone('00 61 491 570 104', ['VN'])).toBe('+61491570104');
  expect(asE164Phone('0061 491 570 104', [])).toBe('+61491570104');
  expect(asE164Phone('0491.570.104', ['AU'])).toBe('+61491570104');
  expect(asE164Phone('  0912-345-678 ', ['VN'])).toBe('+84912345678');
  // A trunk '0' after the country code.
  expect(asE164Phone('+84 0912 345 678', [])).toBe('+84912345678');
});

test('localRegions', () => {
  expect(localRegions(['en-US'], ['+61491570104'])).toEqual(['US', 'AU']);
  expect(localRegions(['vi'], ['+84912345678', '+61491570104'])).toEqual(['VN', 'AU']);
  expect(localRegions(['en-AU'], ['+61491570104'])).toEqual(['AU']);
  expect(localRegions(undefined, undefined)).toEqual([]);
});

test('phoneRegion', () => {
  expect(phoneRegion('+61491570104')).toBe('AU');
  expect(phoneRegion('+84912345678')).toBe('VN');
  expect(phoneRegion('')).toBeNull();
  expect(phoneRegion(undefined)).toBeNull();
});
