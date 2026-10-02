package main

// BLML: 1:1 chat requests (config "p2p_requires_accept", on unless set to false).
//
// A new p2p topic is created as a request. Tinode's own access modes carry the state, so no
// schema change or migration is needed and the shipped apps' "invitation" panel works:
//
//   - requester: want as usual, given = p2pRequestGiven ("JRA": no W, no P);
//   - recipient: want = p2pRequestWant ("JA": no R, no W, no P), given as usual.
//
// While either side's want lacks both R and W (p2pWantUnaccepted) the chat is a pending request:
// nobody can publish (403, params.what = "not-accepted"), notes are dropped, the topic is never
// hard-deleted (the recipient's deleted subscription is the record of a decline), and only the
// creation of the request sends the recipient a push. The recipient accepts by setting their own
// want to include W; the server then grants the requester W/P itself (p2pAcceptRequest).
//
// Subscriptions created before this policy existed always have R and W in their want, so
// existing chats are never treated as requests.

import (
	"github.com/tinode/chat/server/logs"
	"github.com/tinode/chat/server/store"
	"github.com/tinode/chat/server/store/types"
)

const (
	// Recipient's own want on a new chat request: listed, but nothing accepted ("JA").
	p2pRequestWant = types.ModeJoin | types.ModeApprove
	// Requester's given until the recipient accepts: can attach and read, cannot write,
	// no presence ("JRA").
	p2pRequestGiven = types.ModeJoin | types.ModeRead | types.ModeApprove
)

// p2pWantUnaccepted reports whether a p2p want belongs to someone who has not accepted the chat:
// neither R nor W.
func p2pWantUnaccepted(want types.AccessMode) bool {
	return want.IsDefined() && want&(types.ModeRead|types.ModeWrite) == 0
}

// p2pRequestPending reports whether t is a 1:1 chat request that has not been accepted, declined
// requests included (a deleted subscription still counts).
func (t *Topic) p2pRequestPending() bool {
	if t.cat != types.TopicCatP2P || !globals.p2pRequiresAccept {
		return false
	}
	for _, pud := range t.perUser {
		if p2pWantUnaccepted(pud.modeWant) {
			return true
		}
	}
	return false
}

// p2pSubsPending is p2pRequestPending for subscriptions loaded from the store.
func p2pSubsPending(subs []types.Subscription) bool {
	if !globals.p2pRequiresAccept {
		return false
	}
	for i := range subs {
		if p2pWantUnaccepted(subs[i].ModeWant) {
			return true
		}
	}
	return false
}

// p2pRequestPendingInStore checks a p2p topic that is not loaded in memory.
func p2pRequestPendingInStore(topic string) bool {
	if !globals.p2pRequiresAccept {
		return false
	}
	subs, err := store.Topics.GetSubsAny(topic, nil)
	if err != nil {
		logs.Warn.Println("p2p request: failed to load subscriptions", topic, err)
		// Keeping a topic is the safe side: deleting it would lose the record of a decline.
		return true
	}
	return p2pSubsPending(subs)
}

// p2pAcceptedGiven is the requester's given once the recipient accepts: everything the recipient
// was given by the requester (the two sides mirror each other, as the apps' Accept button does),
// at least J, R, W and P.
func p2pAcceptedGiven(requesterGiven, recipientGiven types.AccessMode) types.AccessMode {
	m := requesterGiven
	if recipientGiven.IsDefined() {
		m |= recipientGiven
	}
	m |= types.ModeJoin | types.ModeRead | types.ModeWrite | types.ModePres
	return m&globals.typesModeCP2P | types.ModeApprove
}

// p2pAcceptRequest is called when uid, the recipient of a chat request, has just set a want with W.
// Grants the requester W and P and starts the presence exchange.
func (t *Topic) p2pAcceptRequest(uid types.Uid) {
	peer := t.p2pOtherUser(uid)
	pud2, ok := t.perUser[peer]
	if !ok || pud2.modeGiven.IsWriter() {
		// Already granted (or the recipient restricted the requester earlier and is only changing
		// their own settings now): nothing to do.
		return
	}
	pud := t.perUser[uid]
	oldGiven := pud2.modeGiven
	pud2.modeGiven = p2pAcceptedGiven(pud2.modeGiven, pud.modeGiven)
	// The requester's subscription may be deleted (they cancelled); update it anyway so it comes
	// back accepted.
	if err := store.Subs.Update(t.name, peer, map[string]any{"ModeGiven": pud2.modeGiven}); err != nil {
		logs.Warn.Println("p2p request: failed to grant the requester", t.name, err)
		return
	}
	t.perUser[peer] = pud2

	if pud2.deleted {
		return
	}
	t.notifySubChange(peer, uid, false, pud2.modeWant, oldGiven, pud2.modeWant, pud2.modeGiven, "")
	// Both sides now have P: exchange online status, as a new subscription does.
	t.presSingleUserOffline(uid, pud.modeWant&pud.modeGiven, "?unkn+en", nilPresParams, "", false)
	t.presSingleUserOffline(peer, pud2.modeWant&pud2.modeGiven, "?unkn+en", nilPresParams, "", false)
}

// p2pAcceptRequestOffline is p2pAcceptRequest for a {set sub} handled while the topic is not loaded
// (replyOfflineTopicSetSub). sub is the recipient's subscription, already updated.
func p2pAcceptRequestOffline(topic string, uid types.Uid, sub *types.Subscription) {
	uid1, uid2, err := types.ParseP2P(topic)
	if err != nil {
		return
	}
	peer := uid1
	if peer == uid {
		peer = uid2
	}
	psub, err := store.Subs.Get(topic, peer, true)
	if err != nil || psub == nil || psub.ModeGiven.IsWriter() {
		return
	}
	newGiven := p2pAcceptedGiven(psub.ModeGiven, sub.ModeGiven)
	if err := store.Subs.Update(topic, peer, map[string]any{"ModeGiven": newGiven}); err != nil {
		logs.Warn.Println("p2p request: failed to grant the requester (offline)", topic, err)
		return
	}
	if psub.DeletedAt != nil {
		return
	}
	presSingleUserOfflineOffline(peer, uid.UserId(), "acs", &presParams{
		dGiven: psub.ModeGiven.Delta(newGiven),
		actor:  uid.UserId(),
		target: peer.UserId(),
	}, "")
}
