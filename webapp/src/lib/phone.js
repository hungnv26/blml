// Phone number helpers. Kept out of utils.js so libphonenumber-js metadata is loaded
// only when needed (it is large), e.g. import('../lib/phone.js').

import { parsePhoneNumberFromString } from 'libphonenumber-js/mobile';

// Country codes (ISO 3166 alpha-2, e.g. 'AU') of the given BCP 47 language tags,
// e.g. ['en-AU', 'vi', 'en-US'] -> ['AU', 'US']. Used to interpret phone numbers typed in local format.
export function regionsFromLanguages(languages) {
  const regions = [];
  (languages || []).forEach(lang => {
    const m = /[-_]([a-z]{2})(?:[-_]|$)/i.exec(lang || '');
    const region = m ? m[1].toUpperCase() : null;
    if (region && !regions.includes(region)) {
      regions.push(region);
    }
  });
  return regions;
}

// Country code (e.g. 'AU') of a phone number in E.164 format, or null.
export function phoneRegion(e164) {
  const number = e164 ? parsePhoneNumberFromString(e164) : null;
  return (number && number.country) || null;
}

// Checks if the given string looks like a phone number in international (+61 491 570 104) or
// local (0491 570 104) format. If so, returns it in E.164 format (+61491570104), otherwise null.
// Local numbers are tried against each region in the list until one gives a valid mobile number.
export function asE164Phone(val, regions) {
  val = (val || '').trim();
  // Digits, spaces and the usual separators only, at least 6 digits.
  if (!/^\+?[\d\s().-]+$/.test(val) || val.replace(/\D/g, '').length < 6) {
    return null;
  }
  const candidates = val.startsWith('+') ? [undefined] : (regions || []);
  for (const region of candidates) {
    const number = parsePhoneNumberFromString(val, region);
    if (number && number.isValid()) {
      return number.number;
    }
  }
  return null;
}
