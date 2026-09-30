package main

import (
	"errors"
	"strings"
	"testing"

	"github.com/golang/mock/gomock"

	"github.com/tinode/chat/server/store"
	"github.com/tinode/chat/server/store/mock_store"
	"github.com/tinode/chat/server/store/types"
)

// fakeTelValidator normalises like the real tel validator's PreCheck: returns
// "tel:<E.164>" or ErrMalformed. Only PreCheck is exercised by autoConfirmCred.
type fakeTelValidator struct{}

func (fakeTelValidator) Init(string) error   { return nil }
func (fakeTelValidator) IsInitialized() bool { return true }
func (fakeTelValidator) PreCheck(cred string, _ map[string]any) (string, error) {
	digits := strings.NewReplacer(" ", "", "-", "").Replace(cred)
	if !strings.HasPrefix(digits, "+") || len(digits) < 8 {
		return "", types.ErrMalformed
	}
	return "tel:" + digits, nil
}
func (fakeTelValidator) Request(types.Uid, string, string, string, []byte) (bool, error) {
	return false, errors.New("Request must not be called when auto-confirming")
}
func (fakeTelValidator) ResetSecret(string, string, string, []byte, map[string]any) error { return nil }
func (fakeTelValidator) Check(types.Uid, string) (string, error)                          { return "", nil }
func (fakeTelValidator) Remove(types.Uid, string) error                                   { return nil }
func (fakeTelValidator) Delete(types.Uid) error                                           { return nil }
func (fakeTelValidator) TempAuthScheme() (string, error)                                  { return "", nil }

func withMockUsers(t *testing.T) *mock_store.MockUsersPersistenceInterface {
	t.Helper()
	ctrl := gomock.NewController(t)
	uu := mock_store.NewMockUsersPersistenceInterface(ctrl)
	saved := store.Users
	store.Users = uu
	t.Cleanup(func() {
		store.Users = saved
		ctrl.Finish()
	})
	return uu
}

func TestAutoConfirmNewNumber(t *testing.T) {
	uu := withMockUsers(t)
	uid := types.Uid(7)
	uu.EXPECT().UpsertCred(&types.Credential{User: uid.String(), Method: "tel", Value: "+84912345678"}).Return(true, nil)
	uu.EXPECT().ConfirmCred(uid, "tel").Return(nil)

	value, err := autoConfirmCred(uid, fakeTelValidator{}, &MsgCredClient{Method: "tel", Value: "+84 912 345 678"})
	if err != nil {
		t.Fatalf("autoConfirmCred() error = %v", err)
	}
	if value != "+84912345678" {
		t.Fatalf("value = %q, want the normalised number", value)
	}
}

func TestAutoConfirmNumberTakenByAnotherAccount(t *testing.T) {
	uu := withMockUsers(t)
	uid := types.Uid(7)
	uu.EXPECT().UpsertCred(gomock.Any()).Return(false, types.ErrDuplicate)
	// This user's confirmed numbers do not include it: someone else owns it.
	uu.EXPECT().GetAllCreds(uid, "tel", true).Return([]types.Credential{{Value: "+61400000000"}}, nil)
	// Must not be confirmed.
	uu.EXPECT().ConfirmCred(gomock.Any(), gomock.Any()).Times(0)

	_, err := autoConfirmCred(uid, fakeTelValidator{}, &MsgCredClient{Method: "tel", Value: "+84912345678"})
	if err != types.ErrDuplicate {
		t.Fatalf("autoConfirmCred() error = %v, want ErrDuplicate", err)
	}
}

func TestAutoConfirmOwnNumberAgainIsNoop(t *testing.T) {
	uu := withMockUsers(t)
	uid := types.Uid(7)
	uu.EXPECT().UpsertCred(gomock.Any()).Return(false, types.ErrDuplicate)
	uu.EXPECT().GetAllCreds(uid, "tel", true).Return([]types.Credential{{Value: "+84912345678"}}, nil)
	uu.EXPECT().ConfirmCred(gomock.Any(), gomock.Any()).Times(0)

	value, err := autoConfirmCred(uid, fakeTelValidator{}, &MsgCredClient{Method: "tel", Value: "+84912345678"})
	if err != nil || value != "+84912345678" {
		t.Fatalf("autoConfirmCred() = %q, %v; want the number and no error", value, err)
	}
}

func TestAutoConfirmRejectsMalformedNumber(t *testing.T) {
	uu := withMockUsers(t)
	// Nothing may be written for an invalid number.
	uu.EXPECT().UpsertCred(gomock.Any()).Times(0)
	uu.EXPECT().ConfirmCred(gomock.Any(), gomock.Any()).Times(0)

	if _, err := autoConfirmCred(types.Uid(7), fakeTelValidator{}, &MsgCredClient{Method: "tel", Value: "12"}); err != types.ErrMalformed {
		t.Fatalf("autoConfirmCred() error = %v, want ErrMalformed", err)
	}
}
