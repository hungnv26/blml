package tel

import (
	"errors"
	"testing"

	t "github.com/tinode/chat/server/store/types"
	"github.com/tinode/chat/server/validate"
)

func TestNormalizeAccepts(tt *testing.T) {
	cases := []struct {
		raw, region, want string
	}{
		// E.164 and the ways people write it.
		{"+61491570111", "", "+61491570111"},
		{"+61 491 570 111", "", "+61491570111"},
		{"+61-491-570-111", "", "+61491570111"},
		{"+61.491.570.111", "", "+61491570111"},
		{"+61 (0) 491 570 111", "", "+61491570111"},
		{"+61 0491 570 111", "", "+61491570111"},
		{" +61 491–570–111 ", "", "+61491570111"},
		{"tel:+61491570111", "", "+61491570111"},
		{"TEL:+61 491 570 111", "", "+61491570111"},
		{"＋６１491570111", "", "+61491570111"},
		{"0061 491 570 111", "", "+61491570111"},
		// Region hint for local numbers.
		{"0491 570 111", "AU", "+61491570111"},
		{"(0491) 570-111", "au", "+61491570111"},
		{"0011 61 491 570 111", "AU", "+61491570111"},
		{"0061491570111", "AU", "+61491570111"},
		{"0912 345 678", "VN", "+84912345678"},
		{"+84 0912 345 678", "", "+84912345678"},
		{"(202) 555-0143", "US", "+12025550143"},
		{"011 61 491 570 111", "US", "+61491570111"},
		// Fixed line and other countries.
		{"+61 2 9374 4000", "", "+61293744000"},
		{"+84 99 999 9999", "", "+84999999999"},
		{"+44 7000 000000", "", "+447000000000"},
		// "Possible but not valid": 0495 is not an AU mobile range in libphonenumber's metadata,
		// but the number has the length of an AU mobile.
		{"+61 495 570 111", "", "+61495570111"},
		{"0495 570 111", "AU", "+61495570111"},
		// Region is ignored when the number has a country code.
		{"+61491570111", "US", "+61491570111"},
	}
	for _, c := range cases {
		got, err := Normalize(c.raw, c.region)
		if err != nil || got != c.want {
			tt.Errorf("Normalize(%q, %q) = %q, %v; want %q", c.raw, c.region, got, err, c.want)
		}
	}
}

func TestNormalizeRejects(tt *testing.T) {
	cases := []struct {
		raw, region, reason string
	}{
		{"0491570111", "", ReasonRegionRequired},
		{"12345", "", ReasonRegionRequired},
		{"491 570 111", "", ReasonRegionRequired},
		{"0491570111", "XX", ReasonInvalidRegion},
		{"+6149157", "", ReasonTooShort},
		{"+61 2 9999 9999 9999", "", ReasonTooLong},
		{"+999 123 456 789", "", ReasonInvalidCountryCode},
		{"abc", "", ReasonNotANumber},
		{"<script>", "", ReasonNotANumber},
		{"+61 491 570 111 ext", "", ReasonNotANumber},
		{"1-800-FLOWERS", "US", ReasonNotANumber},
		{"++61491570111", "", ReasonNotANumber},
		{"61+491570111", "", ReasonNotANumber},
		{"", "", ReasonNotANumber},
		{"+", "", ReasonNotANumber},
		{"12345", "AU", ReasonTooShort},
		// "Possible" for AU's numbering plan (service numbers) but shorter/longer than any
		// subscriber number: truncated or mistyped.
		{"+61 4915701", "", ReasonTooShort},
		{"+61 491 570 1111", "", ReasonTooLong},
	}
	for _, c := range cases {
		got, err := Normalize(c.raw, c.region)
		var verr *validate.Error
		if !errors.As(err, &verr) {
			tt.Errorf("Normalize(%q, %q) = %q, %v; want error %s", c.raw, c.region, got, err, c.reason)
			continue
		}
		if verr.Reason != c.reason {
			tt.Errorf("Normalize(%q, %q): reason %s, want %s", c.raw, c.region, verr.Reason, c.reason)
		}
		if !errors.Is(err, t.ErrMalformed) || verr.Text == "" {
			tt.Errorf("Normalize(%q, %q): must wrap ErrMalformed with a message, got %#v", c.raw, c.region, verr)
		}
	}
}

func TestPreCheckRegionParams(tt *testing.T) {
	v := &validator{}
	for _, params := range []map[string]any{
		{"region": "AU"},
		{"region": "au"},
		{"countryCode": "AU"},
		{"region": "", "countryCode": "AU"},
	} {
		got, err := v.PreCheck("0491 570 111", params)
		if err != nil || got != "tel:+61491570111" {
			tt.Errorf("PreCheck with %v = %q, %v", params, got, err)
		}
	}
	if _, err := v.PreCheck("0491 570 111", nil); err == nil {
		tt.Error("local number without region must be refused")
	}
	// Same number, different notations: same credential (one account per number).
	a, _ := v.PreCheck("+61 491-570-111", nil)
	b, _ := v.PreCheck("(0491) 570 111", map[string]any{"region": "AU"})
	if a != b || a != "tel:+61491570111" {
		tt.Errorf("notations differ: %q vs %q", a, b)
	}
}
