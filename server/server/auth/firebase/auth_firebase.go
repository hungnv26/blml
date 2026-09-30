// Package firebase implements an authenticator which accepts Firebase ID tokens,
// so users can sign in with Google or Apple (via Firebase Authentication on the
// client) instead of a login and password.
//
// The client signs in with the provider, obtains a Firebase ID token and sends it
// as the secret of `{login scheme:"firebase"}`. The server verifies the token's
// signature, audience and expiry with the Firebase Admin SDK, then looks up the
// account bound to the token's Firebase uid. If there is none, it answers 404 and
// the client creates one with `{acc user:"new" scheme:"firebase"}` carrying the
// same token.
//
// Configuration (auth_config.firebase):
//
//	"firebase": {
//		// Service-account JSON, the same file the FCM push adapter uses.
//		"credentials_file": "/etc/blml/fcm-service-account.json",
//		// Sign-in providers accepted, as Firebase names them.
//		"providers": ["google.com", "apple.com"],
//		// Add "email:<address>" to new accounts when the provider vouches for
//		// the address, so address-book discovery can find the user.
//		"email_tags": true
//	}
package firebase

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"time"

	fbase "firebase.google.com/go"
	fbauth "firebase.google.com/go/auth"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/option"

	"github.com/tinode/chat/server/auth"
	"github.com/tinode/chat/server/store"
	"github.com/tinode/chat/server/store/types"
)

const (
	realName = "firebase"
	// Verifying a token may fetch Google's public keys; never let a slow
	// network hold a login open indefinitely.
	verifyTimeout = 10 * time.Second
)

// identity is what the authenticator needs from a verified token.
type identity struct {
	// Firebase uid: stable for a given person and provider, the unique key.
	UID string
	// Sign-in provider as Firebase names it: "google.com", "apple.com", ...
	Provider string
	// Email address and whether the provider has verified it.
	Email         string
	EmailVerified bool
	// Display name offered by the provider, if any.
	Name string
}

// verifier checks a raw ID token. It is an interface so tests can run without
// network access or a Firebase project.
type verifier interface {
	Verify(ctx context.Context, idToken string) (*identity, error)
}

type firebaseVerifier struct {
	client *fbauth.Client
}

func (v *firebaseVerifier) Verify(ctx context.Context, idToken string) (*identity, error) {
	token, err := v.client.VerifyIDToken(ctx, idToken)
	if err != nil {
		return nil, err
	}
	return identityFromToken(token), nil
}

// identityFromToken extracts the fields the authenticator uses from a verified token.
func identityFromToken(token *fbauth.Token) *identity {
	id := &identity{UID: token.UID, Provider: token.Firebase.SignInProvider}
	if email, ok := token.Claims["email"].(string); ok {
		id.Email = strings.ToLower(strings.TrimSpace(email))
	}
	if verified, ok := token.Claims["email_verified"].(bool); ok {
		id.EmailVerified = verified
	}
	if name, ok := token.Claims["name"].(string); ok {
		id.Name = strings.TrimSpace(name)
	}
	return id
}

type authenticator struct {
	name      string
	verifier  verifier
	providers map[string]bool
	emailTags bool
}

type configType struct {
	CredentialsFile string   `json:"credentials_file"`
	Providers       []string `json:"providers"`
	EmailTags       bool     `json:"email_tags"`
}

// Init initializes the handler.
func (a *authenticator) Init(jsonconf json.RawMessage, name string) error {
	if a.name != "" {
		return errors.New("auth_firebase: already initialized as " + a.name + "; " + name)
	}

	var config configType
	if err := json.Unmarshal(jsonconf, &config); err != nil {
		return errors.New("auth_firebase: failed to parse config: " + err.Error() + "(" + string(jsonconf) + ")")
	}
	if config.CredentialsFile == "" {
		return errors.New("auth_firebase: credentials_file is required")
	}
	if len(config.Providers) == 0 {
		return errors.New("auth_firebase: at least one provider is required")
	}

	raw, err := os.ReadFile(config.CredentialsFile)
	if err != nil {
		return errors.New("auth_firebase: " + err.Error())
	}
	ctx := context.Background()
	credentials, err := google.CredentialsFromJSON(ctx, raw)
	if err != nil {
		return errors.New("auth_firebase: " + err.Error())
	}
	if credentials.ProjectID == "" {
		return errors.New("auth_firebase: credentials have no project ID")
	}
	app, err := fbase.NewApp(ctx, &fbase.Config{ProjectID: credentials.ProjectID}, option.WithCredentials(credentials))
	if err != nil {
		return errors.New("auth_firebase: " + err.Error())
	}
	client, err := app.Auth(ctx)
	if err != nil {
		return errors.New("auth_firebase: " + err.Error())
	}

	return a.init(name, &firebaseVerifier{client: client}, config)
}

// init completes initialization with a ready verifier; split out for tests.
func (a *authenticator) init(name string, v verifier, config configType) error {
	a.name = name
	a.verifier = v
	a.providers = make(map[string]bool, len(config.Providers))
	for _, p := range config.Providers {
		a.providers[strings.TrimSpace(p)] = true
	}
	a.emailTags = config.EmailTags
	return nil
}

// IsInitialized returns true if the handler is initialized.
func (a *authenticator) IsInitialized() bool {
	return a.name != ""
}

// verify checks the token and the provider. Any failure is reported as
// ErrFailed: a client must not learn why a token was rejected.
func (a *authenticator) verify(secret []byte) (*identity, error) {
	idToken := strings.TrimSpace(string(secret))
	if idToken == "" {
		return nil, types.ErrMalformed
	}
	ctx, cancel := context.WithTimeout(context.Background(), verifyTimeout)
	defer cancel()
	id, err := a.verifier.Verify(ctx, idToken)
	if err != nil || id == nil || id.UID == "" {
		return nil, types.ErrFailed
	}
	if !a.providers[id.Provider] {
		return nil, types.ErrFailed
	}
	return id, nil
}

// AddRecord binds the Firebase identity in the token to a new account.
func (a *authenticator) AddRecord(rec *auth.Rec, secret []byte, remoteAddr string) (*auth.Rec, error) {
	id, err := a.verify(secret)
	if err != nil {
		return nil, err
	}

	authLevel := rec.AuthLevel
	if authLevel == auth.LevelNone {
		authLevel = auth.LevelAuth
	}
	// No secret is stored: the token itself is proof of identity on every login.
	if err := store.Users.AddAuthRecord(rec.Uid, authLevel, a.name, id.UID, nil, time.Time{}); err != nil {
		return nil, err
	}

	rec.AuthLevel = authLevel
	if tag := a.emailTag(id); tag != "" {
		rec.Tags = append(rec.Tags, tag)
	}
	return rec, nil
}

// emailTag returns the discovery tag for a provider-verified email, or "".
func (a *authenticator) emailTag(id *identity) string {
	if !a.emailTags || !id.EmailVerified || id.Email == "" || !strings.Contains(id.Email, "@") {
		return ""
	}
	// Apple's private relay addresses are real and verified, but no one has
	// them in an address book, so they would only add noise to discovery.
	if strings.HasSuffix(id.Email, "@privaterelay.appleid.com") {
		return ""
	}
	return "email:" + id.Email
}

// UpdateRecord is not supported: a Firebase identity cannot be changed, only
// replaced by deleting and recreating the account.
func (a *authenticator) UpdateRecord(rec *auth.Rec, secret []byte, remoteAddr string) (*auth.Rec, error) {
	return nil, types.ErrUnsupported
}

// Authenticate verifies the token and finds the account bound to it. An unknown
// identity yields ErrNotFound (404) so the client knows to create an account.
func (a *authenticator) Authenticate(secret []byte, remoteAddr string) (*auth.Rec, []byte, error) {
	id, err := a.verify(secret)
	if err != nil {
		return nil, nil, err
	}

	uid, authLvl, _, _, err := store.Users.GetAuthUniqueRecord(a.name, id.UID)
	if err != nil {
		return nil, nil, err
	}
	if uid.IsZero() {
		return nil, nil, types.ErrNotFound
	}

	return &auth.Rec{
		Uid:       uid,
		AuthLevel: authLvl,
		Features:  auth.FeatureValidated,
		State:     types.StateUndefined}, nil, nil
}

// AsTag is not supported: Firebase uids are not searchable.
func (a *authenticator) AsTag(token string) string {
	return ""
}

// IsUnique checks that the identity in the token is not bound to an account yet.
func (a *authenticator) IsUnique(secret []byte, remoteAddr string) (bool, error) {
	id, err := a.verify(secret)
	if err != nil {
		return false, err
	}
	uid, _, _, _, err := store.Users.GetAuthUniqueRecord(a.name, id.UID)
	if err != nil {
		return false, err
	}
	if uid.IsZero() {
		return true, nil
	}
	return false, types.ErrDuplicate
}

// GenSecret is not supported.
func (authenticator) GenSecret(rec *auth.Rec) ([]byte, time.Time, error) {
	return nil, time.Time{}, types.ErrUnsupported
}

// DelRecords deletes the Firebase binding of the given user.
func (a *authenticator) DelRecords(uid types.Uid) error {
	return store.Users.DelAuthRecords(uid, a.name)
}

// RestrictedTags returns no namespaces: the email tags this handler adds belong
// to the email validator's namespace, which that validator already restricts.
func (a *authenticator) RestrictedTags() ([]string, error) {
	return nil, nil
}

// GetResetParams is not supported: there is no password to reset.
func (a *authenticator) GetResetParams(uid types.Uid) (map[string]any, error) {
	return nil, types.ErrUnsupported
}

// GetRealName returns the hardcoded name of the authenticator.
func (authenticator) GetRealName() string {
	return realName
}

func init() {
	store.RegisterAuthScheme(realName, &authenticator{})
}
