package main

import (
	"time"

	"github.com/tinode/chat/server/logs"
	"github.com/tinode/chat/server/store"
	"github.com/tinode/chat/server/store/types"
)

// missingSince drops from missing every validator whose "required_since" lies
// after the account's creation time: the rule did not exist when the account
// was made, so the account is not held to it.
func missingSince(missing []string, createdAt time.Time, since map[string]time.Time) []string {
	if len(missing) == 0 || len(since) == 0 {
		return missing
	}
	var still []string
	for _, method := range missing {
		if cutoff, ok := since[method]; ok && createdAt.Before(cutoff) {
			continue
		}
		still = append(still, method)
	}
	return still
}

// exemptGrandfathered applies missingSince to a stored account. If the account
// cannot be read the list is returned unchanged: an error must not open a door.
func exemptGrandfathered(uid types.Uid, missing []string) []string {
	if len(missing) == 0 || len(globals.validatorRequiredSince) == 0 {
		return missing
	}
	user, err := store.Users.Get(uid)
	if err != nil || user == nil {
		logs.Warn.Println("required_since: cannot read account", uid, err)
		return missing
	}
	return missingSince(missing, user.CreatedAt, globals.validatorRequiredSince)
}
