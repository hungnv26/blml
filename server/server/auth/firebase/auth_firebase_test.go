package firebase

import (
	"context"
	"errors"
	"testing"

	fbauth "firebase.google.com/go/auth"

	"github.com/tinode/chat/server/store/types"
)

// fakeVerifier returns a fixed identity or error, recording the token it saw.
type fakeVerifier struct {
	id   *identity
	err  error
	seen string
}

func (f *fakeVerifier) Verify(ctx context.Context, idToken string) (*identity, error) {
	f.seen = idToken
	return f.id, f.err
}

func newTestAuth(t *testing.T, v verifier, emailTags bool) *authenticator {
	t.Helper()
	a := &authenticator{}
	if err := a.init("firebase", v, configType{Providers: []string{"google.com", "apple.com"}, EmailTags: emailTags}); err != nil {
		t.Fatal(err)
	}
	return a
}

func TestVerifyRejects(t *testing.T) {
	cases := []struct {
		name   string
		secret string
		v      *fakeVerifier
		want   error
	}{
		{"empty token", "   ", &fakeVerifier{}, types.ErrMalformed},
		{"bad signature", "tok", &fakeVerifier{err: errors.New("signature invalid")}, types.ErrFailed},
		{"no identity", "tok", &fakeVerifier{}, types.ErrFailed},
		{"no uid", "tok", &fakeVerifier{id: &identity{Provider: "google.com"}}, types.ErrFailed},
		{"provider not enabled", "tok", &fakeVerifier{id: &identity{UID: "u1", Provider: "password"}}, types.ErrFailed},
		{"anonymous firebase user", "tok", &fakeVerifier{id: &identity{UID: "u1", Provider: "anonymous"}}, types.ErrFailed},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			a := newTestAuth(t, tc.v, true)
			if _, err := a.verify([]byte(tc.secret)); err != tc.want {
				t.Fatalf("verify() error = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestVerifyAcceptsEnabledProviders(t *testing.T) {
	for _, provider := range []string{"google.com", "apple.com"} {
		v := &fakeVerifier{id: &identity{UID: "u1", Provider: provider}}
		a := newTestAuth(t, v, true)
		id, err := a.verify([]byte("  the-token \n"))
		if err != nil {
			t.Fatalf("%s: verify() error = %v", provider, err)
		}
		if id.UID != "u1" {
			t.Fatalf("%s: uid = %q", provider, id.UID)
		}
		if v.seen != "the-token" {
			t.Fatalf("%s: token passed to verifier = %q, want it trimmed", provider, v.seen)
		}
	}
}

func TestEmailTag(t *testing.T) {
	cases := []struct {
		name      string
		emailTags bool
		id        identity
		want      string
	}{
		{"verified google email", true, identity{Email: "ann@gmail.com", EmailVerified: true}, "email:ann@gmail.com"},
		{"unverified email", true, identity{Email: "ann@gmail.com"}, ""},
		{"tags disabled", false, identity{Email: "ann@gmail.com", EmailVerified: true}, ""},
		{"no email", true, identity{EmailVerified: true}, ""},
		{"not an address", true, identity{Email: "ann", EmailVerified: true}, ""},
		{"apple private relay", true, identity{Email: "x1y2@privaterelay.appleid.com", EmailVerified: true}, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			a := newTestAuth(t, &fakeVerifier{}, tc.emailTags)
			if got := a.emailTag(&tc.id); got != tc.want {
				t.Fatalf("emailTag() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestIdentityFromToken(t *testing.T) {
	token := &fbauth.Token{
		UID:      "fb-uid",
		Firebase: fbauth.FirebaseInfo{SignInProvider: "google.com"},
		Claims: map[string]interface{}{
			"email":          "  Ann@Gmail.COM ",
			"email_verified": true,
			"name":           " Ann Nguyen ",
		},
	}
	id := identityFromToken(token)
	if id.UID != "fb-uid" || id.Provider != "google.com" {
		t.Fatalf("uid/provider = %q/%q", id.UID, id.Provider)
	}
	if id.Email != "ann@gmail.com" || !id.EmailVerified {
		t.Fatalf("email = %q verified=%v; want lower-cased, trimmed, verified", id.Email, id.EmailVerified)
	}
	if id.Name != "Ann Nguyen" {
		t.Fatalf("name = %q", id.Name)
	}

	// Claims of the wrong type must be ignored, not panic.
	id = identityFromToken(&fbauth.Token{UID: "x", Claims: map[string]interface{}{"email": 42, "email_verified": "yes"}})
	if id.Email != "" || id.EmailVerified {
		t.Fatalf("malformed claims produced email=%q verified=%v", id.Email, id.EmailVerified)
	}
}

func TestInitRejectsBadConfig(t *testing.T) {
	for name, conf := range map[string]string{
		"not json":         `{`,
		"no credentials":   `{"providers":["google.com"]}`,
		"no providers":     `{"credentials_file":"/nonexistent.json"}`,
		"unreadable creds": `{"credentials_file":"/nonexistent.json","providers":["google.com"]}`,
	} {
		t.Run(name, func(t *testing.T) {
			if err := (&authenticator{}).Init([]byte(conf), "firebase"); err == nil {
				t.Fatal("Init() accepted a bad config")
			}
		})
	}
}
