package main

import (
	"reflect"
	"testing"
	"time"
)

func TestMissingSince(t *testing.T) {
	cutoff := time.Date(2026, 10, 7, 0, 0, 0, 0, time.UTC)
	since := map[string]time.Time{"email": cutoff}
	before := cutoff.Add(-time.Hour)
	after := cutoff.Add(time.Hour)

	cases := []struct {
		name      string
		missing   []string
		createdAt time.Time
		want      []string
	}{
		{"old account is exempt from email", []string{"email"}, before, nil},
		{"new account still needs email", []string{"email"}, after, []string{"email"}},
		{"created exactly at the cutoff needs email", []string{"email"}, cutoff, []string{"email"}},
		{"other validators are never exempt", []string{"email", "tel"}, before, []string{"tel"}},
		{"nothing missing stays nothing", nil, before, nil},
	}
	for _, c := range cases {
		if got := missingSince(c.missing, c.createdAt, since); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
	if got := missingSince([]string{"email"}, before, nil); !reflect.DeepEqual(got, []string{"email"}) {
		t.Errorf("no required_since configured: got %v, want [email]", got)
	}
}
