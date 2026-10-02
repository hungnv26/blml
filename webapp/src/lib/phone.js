// Phone number helpers. Kept out of utils.js so libphonenumber-js metadata is loaded
// only when needed (it is large), e.g. import('../lib/phone.js').

import { parsePhoneNumberFromString } from 'libphonenumber-js/mobile';

// E.164 allows at most 15 digits. Fewer than 6 digits is not a phone number anywhere we serve.
const MIN_PHONE_DIGITS = 6;
const MAX_PHONE_DIGITS = 15;

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

// Regions to try for a number typed in local format, most likely first: the browser's region(s),
// then the region(s) of the user's own phone number(s) (E.164).
export function localRegions(languages, ownPhones) {
  const regions = regionsFromLanguages(languages);
  (ownPhones || []).forEach(e164 => {
    const region = phoneRegion(e164);
    if (region && !regions.includes(region)) {
      regions.push(region);
    }
  });
  return regions;
}

// Checks if the given string looks like a phone number: digits with the usual separators
// (spaces, dashes, dots, brackets), optionally starting with '+' or the '00' international prefix.
// If so, returns it in E.164 format (+61491570104), otherwise null.
//
// Numbers in international format need no region. A number in local format ('0491 570 104') is tried
// against each region in order: first the region where it is a valid number, otherwise the first
// region where it is a possible one (right length; libphonenumber's 'possible', not only 'valid').
export function asE164Phone(val, regions) {
  val = (val || '').trim();
  if (!/^\+?[\d\s().\-\/]+$/.test(val)) {
    return null;
  }
  const digits = val.replace(/\D/g, '');
  if (digits.length < MIN_PHONE_DIGITS || digits.length > MAX_PHONE_DIGITS + 2) {
    return null;
  }

  const parse = (text, region) => {
    try {
      const number = parsePhoneNumberFromString(text, region);
      if (number && number.number.replace(/\D/g, '').length <= MAX_PHONE_DIGITS) {
        return number;
      }
    } catch (err) {}
    return null;
  };

  const international = text => {
    const number = parse(text);
    return number && (number.isValid() || number.isPossible()) ? number.number : null;
  };

  // International format: '+61 491 570 104'.
  if (val.startsWith('+')) {
    return international('+' + digits);
  }

  const candidates = (regions || []).map(region => parse(val, region)).filter(number => number);
  const valid = candidates.find(number => number.isValid());
  if (valid) {
    return valid.number;
  }
  // '00 61 491 570 104': the international prefix used in most of the world.
  const idd = /^00[1-9]/.test(digits) ? international('+' + digits.substring(2)) : null;
  if (idd) {
    return idd;
  }
  const possible = candidates.find(number => number.isPossible());
  return possible ? possible.number : null;
}
