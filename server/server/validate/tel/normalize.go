package tel

// BLML: tolerant phone number normalisation shared by the "tel" credential and phone search.

import (
	"strings"
	"sync"
	"unicode"

	"github.com/nyaruka/phonenumbers"
	t "github.com/tinode/chat/server/store/types"
	"github.com/tinode/chat/server/validate"
)

// Reasons sent to clients in ctrl.params.reason.
const (
	ReasonRegionRequired     = "region-required"
	ReasonInvalidRegion      = "invalid-region"
	ReasonInvalidCountryCode = "invalid-country-code"
	ReasonTooShort           = "too-short"
	ReasonTooLong            = "too-long"
	ReasonInvalidLength      = "invalid-length"
	ReasonNotANumber         = "not-a-number"
)

var reasonText = map[string]string{
	ReasonRegionRequired:     "phone number needs a country code (+...) or a region",
	ReasonInvalidRegion:      "unknown region",
	ReasonInvalidCountryCode: "unknown country code",
	ReasonTooShort:           "phone number is too short",
	ReasonTooLong:            "phone number is too long",
	ReasonInvalidLength:      "phone number has the wrong number of digits for its country",
	ReasonNotANumber:         "not a phone number",
}

func phoneError(reason string) error {
	return &validate.Error{Err: t.ErrMalformed, Reason: reason, Text: reasonText[reason]}
}

// Longest input worth looking at: E.164 has at most 15 digits, leave room for formatting.
const maxRawLength = 64

// isSeparator reports characters people put between digits: spaces of all kinds, dashes of all
// kinds, dots, slashes, parentheses and brackets.
func isSeparator(r rune) bool {
	switch r {
	case '-', '.', '/', '(', ')', '[', ']', '‐', '‑', '‒', '–', '—', '―', '−',
		'ー', '－':
		return true
	}
	return unicode.IsSpace(r)
}

// NormalizeRegion returns an upper-case ISO 3166 region code, "" for none, or an error if the
// code is not a region libphonenumber knows.
func NormalizeRegion(region string) (string, error) {
	region = strings.ToUpper(strings.TrimSpace(region))
	if region == "" {
		return "", nil
	}
	if phonenumbers.GetCountryCodeForRegion(region) == 0 {
		return "", phoneError(ReasonInvalidRegion)
	}
	return region, nil
}

// Normalize converts a phone number as a person typed it into E.164, e.g. "+61491570111".
//
//	raw    - the number: spaces, dashes, dots, slashes, parentheses and a "tel:" prefix are ignored;
//	         "+CC (0)..." and "+CC 0..." trunk zeros are dropped.
//	region - ISO 3166 code used only for numbers without a country code ("" = none). Without a
//	         region, a leading "00" is read as "+"; anything else without "+" is refused.
//
// A number is accepted when libphonenumber considers it possible (right length for the country),
// which is wider than "valid": number ranges missing from its metadata, fixed lines, VoIP etc. pass.
// Errors are *validate.Error wrapping t.ErrMalformed.
func Normalize(raw, region string) (string, error) {
	region, err := NormalizeRegion(region)
	if err != nil {
		return "", err
	}

	s := strings.TrimSpace(raw)
	if len(s) > maxRawLength {
		return "", phoneError(ReasonTooLong)
	}
	if len(s) >= 4 && strings.EqualFold(s[:4], "tel:") {
		s = s[4:]
	}

	var digits strings.Builder
	plus := false
	for _, r := range s {
		switch {
		case r >= '0' && r <= '9':
			digits.WriteRune(r)
		case unicode.IsDigit(r):
			// Full-width, Arabic-Indic and other decimal digits.
			d := phonenumbers.NormalizeDigitsOnly(string(r))
			if d == "" {
				return "", phoneError(ReasonNotANumber)
			}
			digits.WriteString(d)
		case r == '+' || r == '＋':
			if plus || digits.Len() > 0 {
				return "", phoneError(ReasonNotANumber)
			}
			plus = true
		case isSeparator(r):
			// Formatting.
		default:
			return "", phoneError(ReasonNotANumber)
		}
	}
	num := digits.String()
	if num == "" {
		return "", phoneError(ReasonNotANumber)
	}

	switch {
	case plus:
		return parsePossible("+"+num, "")
	case region != "":
		e164, err := parsePossible(num, region)
		if err != nil && strings.HasPrefix(num, "00") && len(num) > 2 {
			// "00" is the international prefix in most of the world even where the region's
			// own prefix differs (AU 0011, US 011).
			if e164, err2 := parsePossible("+"+num[2:], ""); err2 == nil {
				return e164, nil
			}
		}
		return e164, err
	case strings.HasPrefix(num, "00") && len(num) > 2:
		return parsePossible("+"+num[2:], "")
	default:
		return "", phoneError(ReasonRegionRequired)
	}
}

// parsePossible parses a digit string ("+..." or national with region) and checks it is possible.
func parsePossible(num, region string) (string, error) {
	parsed, err := phonenumbers.Parse(num, region)
	if err != nil {
		switch err {
		case phonenumbers.ErrInvalidCountryCode:
			return "", phoneError(ReasonInvalidCountryCode)
		case phonenumbers.ErrTooShortNSN, phonenumbers.ErrTooShortAfterIDD:
			return "", phoneError(ReasonTooShort)
		case phonenumbers.ErrNumTooLong:
			return "", phoneError(ReasonTooLong)
		default:
			return "", phoneError(ReasonNotANumber)
		}
	}
	switch plausible(parsed) {
	case phonenumbers.IS_POSSIBLE:
	case phonenumbers.INVALID_COUNTRY_CODE:
		return "", phoneError(ReasonInvalidCountryCode)
	case phonenumbers.TOO_SHORT, phonenumbers.IS_POSSIBLE_LOCAL_ONLY:
		return "", phoneError(ReasonTooShort)
	case phonenumbers.TOO_LONG:
		return "", phoneError(ReasonTooLong)
	default:
		return "", phoneError(ReasonInvalidLength)
	}
	e164 := phonenumbers.Format(parsed, phonenumbers.E164)
	// E.164: "+" and at most 15 digits.
	if len(e164) < 2 || len(e164) > 16 {
		return "", phoneError(ReasonInvalidLength)
	}
	return e164, nil
}

// regionParam returns the region hint from credential params: "region", or the older "countryCode".
func regionParam(params map[string]any) string {
	if r, ok := params["region"].(string); ok && strings.TrimSpace(r) != "" {
		return r
	}
	if r, ok := params["countryCode"].(string); ok {
		return r
	}
	return ""
}

// plausible decides whether a parsed number could be a real subscriber number:
//   - valid per libphonenumber's metadata, or
//   - possible (a length the country's numbering plan allows at all) AND within the range of
//     lengths of the country's ordinary numbers (mobile, fixed line, VoIP, personal, UAN; taken
//     from libphonenumber's example numbers).
//
// The second rule accepts numbers in ranges the metadata does not know yet while still refusing
// short codes and truncated numbers, which a bare "possible" check lets through for countries
// with service numbers (in AU a 5-digit number is "possible").
func plausible(parsed *phonenumbers.PhoneNumber) phonenumbers.ValidationResult {
	if phonenumbers.IsValidNumber(parsed) {
		return phonenumbers.IS_POSSIBLE
	}
	if res := phonenumbers.IsPossibleNumberWithReason(parsed); res != phonenumbers.IS_POSSIBLE {
		return res
	}
	region := phonenumbers.GetRegionCodeForCountryCode(int(parsed.GetCountryCode()))
	minLen, maxLen := subscriberLengths(region)
	if minLen == 0 {
		// No examples (non-geographic codes): the general rule is all there is.
		return phonenumbers.IS_POSSIBLE
	}
	n := len(phonenumbers.GetNationalSignificantNumber(parsed))
	if n < minLen {
		return phonenumbers.TOO_SHORT
	}
	if n > maxLen {
		return phonenumbers.TOO_LONG
	}
	return phonenumbers.IS_POSSIBLE
}

type lengthRange struct{ min, max int }

var subscriberLengthCache sync.Map // region -> lengthRange

// subscriberLengths returns the shortest and longest national number among the region's example
// numbers of the ordinary types; 0, 0 if there are none.
func subscriberLengths(region string) (int, int) {
	if v, ok := subscriberLengthCache.Load(region); ok {
		r := v.(lengthRange)
		return r.min, r.max
	}
	var r lengthRange
	for _, typ := range []phonenumbers.PhoneNumberType{phonenumbers.MOBILE, phonenumbers.FIXED_LINE,
		phonenumbers.FIXED_LINE_OR_MOBILE, phonenumbers.VOIP, phonenumbers.PERSONAL_NUMBER, phonenumbers.UAN} {
		ex := phonenumbers.GetExampleNumberForType(region, typ)
		if ex == nil {
			continue
		}
		n := len(phonenumbers.GetNationalSignificantNumber(ex))
		if n == 0 {
			continue
		}
		if r.min == 0 || n < r.min {
			r.min = n
		}
		if n > r.max {
			r.max = n
		}
	}
	subscriberLengthCache.Store(region, r)
	return r.min, r.max
}
