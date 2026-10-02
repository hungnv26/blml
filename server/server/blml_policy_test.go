package main

// Tests for BLML's server-side policies: p2p blocking, invite-only groups,
// delete-for-everyone rules and redaction of logged client frames.

import (
	"net/http"
	"strings"
	"sync"
	"testing"

	"github.com/golang/mock/gomock"
	"github.com/tinode/chat/server/auth"
	"github.com/tinode/chat/server/auth/mock_auth"
	"github.com/tinode/chat/server/store"
	"github.com/tinode/chat/server/store/mock_store"
	"github.com/tinode/chat/server/store/types"
)

// The mode a BLML client leaves on its own subscription after "Block" (-JP).
const blockedWant = types.ModeCP2P & ^(types.ModeJoin | types.ModePres)

// setUpBlockedP2P makes a p2p topic between uids[0] and uids[1] where uids[1] has blocked uids[0].
func setUpBlockedP2P(t *testing.T, helper *TopicTestHelper, attach bool) {
	t.Helper()
	helper.setUp(t, 2, types.TopicCatP2P, "p2pBlocked", attach)
	for i, uid := range helper.uids {
		pud := helper.topic.perUser[uid]
		pud.modeGiven = types.ModeCP2P
		pud.modeWant = types.ModeCP2P
		if i == 1 {
			pud.modeWant = blockedWant
		}
		helper.topic.perUser[uid] = pud
	}
}

func TestPubP2PBlockedRefusedBothWays(t *testing.T) {
	helper := TopicTestHelper{}
	setUpBlockedP2P(t, &helper, true)
	defer helper.tearDown()
	// No Messages.Save expected: gomock fails the test if anything is stored.

	for i, uid := range helper.uids {
		helper.topic.handleClientMsg(&ClientComMessage{
			AsUser:   uid.UserId(),
			Original: helper.uids[i^1].UserId(),
			Pub:      &MsgClientPub{Id: "pub1", Topic: "p2p", Content: "hi"},
			sess:     helper.sessions[i],
		})
	}
	helper.finish()

	for i, r := range helper.results {
		// Each sender gets exactly a 403; nothing reaches the other side.
		registerSessionVerifyOutputs(t, r, []int{http.StatusForbidden})
		if len(helper.hubMessages[helper.uids[i].UserId()]) != 0 {
			t.Errorf("user %d: no presence expected for a refused message", i)
		}
	}
}

func TestPubP2PUnblockedDelivered(t *testing.T) {
	helper := TopicTestHelper{}
	setUpBlockedP2P(t, &helper, true)
	defer helper.tearDown()
	// Unblock: the blocker restores J and P.
	pud := helper.topic.perUser[helper.uids[1]]
	pud.modeWant = types.ModeCP2P
	helper.topic.perUser[helper.uids[1]] = pud
	helper.mm.EXPECT().Save(gomock.Any(), gomock.Any(), gomock.Any()).Return(nil, true)

	helper.topic.handleClientMsg(&ClientComMessage{
		Id:       "pub1",
		AsUser:   helper.uids[0].UserId(),
		Original: helper.uids[1].UserId(),
		Pub:      &MsgClientPub{Id: "pub1", Topic: "p2p", Content: "hi", NoEcho: true},
		sess:     helper.sessions[0],
	})
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[0], []int{http.StatusAccepted})
	if n := len(helper.results[1].messages); n != 1 {
		t.Fatalf("peer: expected the message, got %d frames", n)
	}
}

func TestNoteP2PBlockedNotDelivered(t *testing.T) {
	helper := TopicTestHelper{}
	setUpBlockedP2P(t, &helper, true)
	defer helper.tearDown()

	helper.topic.handleClientMsg(&ClientComMessage{
		AsUser:   helper.uids[0].UserId(),
		Original: helper.uids[1].UserId(),
		Note:     &MsgClientNote{Topic: "p2p", What: "kp"},
		sess:     helper.sessions[0],
	})
	helper.finish()

	for i, r := range helper.results {
		if len(r.messages) != 0 {
			t.Errorf("session %d: typing notification must not be delivered, got %d frames", i, len(r.messages))
		}
	}
	if len(helper.hubMessages) != 0 {
		t.Errorf("no offline notifications expected, got %d", len(helper.hubMessages))
	}
}

func TestRegisterSessionP2PBlockedPlainSubKeepsBlock(t *testing.T) {
	helper := TopicTestHelper{}
	setUpBlockedP2P(t, &helper, false)
	defer helper.tearDown()

	blocker := helper.uids[1]
	s := helper.sessions[1]
	// What the apps send when the chat is opened: no mode.
	helper.topic.registerSession(&ClientComMessage{
		Original: helper.uids[0].UserId(),
		Sub:      &MsgClientSub{Id: "sub1", Topic: helper.uids[0].UserId()},
		AsUser:   blocker.UserId(),
		AuthLvl:  int(auth.LevelAuth),
		sess:     s,
	})
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
	if len(s.subs) != 1 {
		t.Errorf("blocker should be attached to read the chat, subs=%d", len(s.subs))
	}
	if want := helper.topic.perUser[blocker].modeWant; want != blockedWant {
		t.Errorf("plain sub must not unblock: want=%s", want)
	}
	if !helper.topic.p2pBlocked() {
		t.Error("topic must still be blocked")
	}
}

func TestRegisterSessionP2PExplicitUnblock(t *testing.T) {
	old := globals.typesModeCP2P
	globals.typesModeCP2P = types.ModeCP2P
	defer func() { globals.typesModeCP2P = old }()

	helper := TopicTestHelper{}
	setUpBlockedP2P(t, &helper, false)
	defer helper.tearDown()
	helper.ss.EXPECT().Update("p2pBlocked", helper.uids[1], gomock.Any()).Return(nil)

	blocker := helper.uids[1]
	helper.topic.registerSession(&ClientComMessage{
		Original: helper.uids[0].UserId(),
		Sub: &MsgClientSub{Id: "sub1", Topic: helper.uids[0].UserId(),
			Set: &MsgSetQuery{Sub: &MsgSetSub{Mode: "JRWPA"}}},
		AsUser:  blocker.UserId(),
		AuthLvl: int(auth.LevelAuth),
		sess:    helper.sessions[1],
	})
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
	if !helper.topic.perUser[blocker].modeWant.IsJoiner() {
		t.Error("explicit mode with J must unblock")
	}
	if helper.topic.p2pBlocked() {
		t.Error("topic must no longer be blocked")
	}
}

func TestRegisterSessionGroupInviteOnly(t *testing.T) {
	old := globals.groupInviteOnly
	globals.groupInviteOnly = true
	defer func() { globals.groupInviteOnly = old }()

	helper := TopicTestHelper{}
	helper.setUp(t, 1, types.TopicCatGrp, "grpInviteOnly", false)
	defer helper.tearDown()

	// A stranger (or a removed member: no live subscription) tries to join by id.
	// No store access is expected: refused before the old subscription is looked up.
	stranger := types.Uid(1001)
	s, r := helper.newSession("stranger", stranger)
	helper.sessions = append(helper.sessions, s)
	helper.results = append(helper.results, r)
	helper.topic.registerSession(&ClientComMessage{
		Original: "grpInviteOnly",
		Sub:      &MsgClientSub{Id: "sub1", Topic: "grpInviteOnly"},
		AsUser:   stranger.UserId(),
		AuthLvl:  int(auth.LevelAuth),
		sess:     s,
	})

	// An existing member (invited earlier) attaches as usual.
	member := helper.uids[0]
	helper.topic.registerSession(&ClientComMessage{
		Original: "grpInviteOnly",
		Sub:      &MsgClientSub{Id: "sub2", Topic: "grpInviteOnly"},
		AsUser:   member.UserId(),
		AuthLvl:  int(auth.LevelAuth),
		sess:     helper.sessions[0],
	})
	helper.finish()

	registerSessionVerifyOutputs(t, r, []int{http.StatusForbidden})
	if resp := r.messages[0].(*ServerComMessage); resp.Ctrl.Params == nil ||
		resp.Ctrl.Params.(map[string]any)["what"] != "invite-only" {
		t.Errorf("refusal should say why: %+v", resp.Ctrl.Params)
	}
	if _, found := helper.topic.perUser[stranger]; found {
		t.Error("stranger must not be added to the group")
	}
	registerSessionVerifyOutputs(t, helper.results[0], []int{http.StatusOK})
}

// delMsg builds a {del what:"msg" hard:true} for seq IDs [low, hi).
func delMsg(helper *TopicTestHelper, i, low, hi int) *ClientComMessage {
	return &ClientComMessage{
		Del:    &MsgClientDel{Id: "del1", What: "msg", DelSeq: []MsgRange{{LowId: low, HiId: hi}}, Hard: true},
		AsUser: helper.uids[i].UserId(),
		sess:   helper.sessions[i],
	}
}

func TestReplyDelMsgHardOthersMessageRefusedP2P(t *testing.T) {
	helper := TopicTestHelper{}
	helper.setUp(t, 2, types.TopicCatP2P, "p2pDel", true)
	defer helper.tearDown()
	helper.topic.lastID = 10
	// p2p_delete_enabled: both sides have D. Message 8 is the peer's.
	helper.mm.EXPECT().GetAll("p2pDel", types.ZeroUid, gomock.Any()).Return([]types.Message{
		{SeqId: 8, From: helper.uids[1].String()}, {SeqId: 7, From: helper.uids[0].String()}}, nil)
	// No DeleteList expected.

	if err := helper.topic.replyDelMsg(helper.sessions[0], helper.uids[0], false, delMsg(&helper, 0, 7, 9)); err == nil {
		t.Error("expected an error")
	}
	helper.finish()
	registerSessionVerifyOutputs(t, helper.results[0], []int{http.StatusForbidden})
}

func TestReplyDelMsgHardOwnMessageGroupMember(t *testing.T) {
	helper := TopicTestHelper{}
	helper.setUp(t, 2, types.TopicCatGrp, "grpDel", true)
	defer helper.tearDown()
	helper.topic.lastID = 10
	// Plain member: default group access, no D.
	member := helper.uids[1]
	pud := helper.topic.perUser[member]
	pud.modeGiven, pud.modeWant = types.ModeCPublic, types.ModeCPublic
	helper.topic.perUser[member] = pud

	// First page: the member's own message; the clipped range is then empty.
	helper.mm.EXPECT().GetAll("grpDel", types.ZeroUid, gomock.Any()).Return([]types.Message{
		{SeqId: 5, From: member.String()}}, nil)
	helper.mm.EXPECT().DeleteList("grpDel", 1, types.ZeroUid, gomock.Any(), []types.Range{{Low: 5}}).Return(nil)

	if err := helper.topic.replyDelMsg(helper.sessions[1], member, false, delMsg(&helper, 1, 5, 6)); err != nil {
		t.Fatal(err)
	}
	helper.finish()
	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
}

func TestReplyDelMsgHardGroupMemberOthersRefused(t *testing.T) {
	helper := TopicTestHelper{}
	helper.setUp(t, 2, types.TopicCatGrp, "grpDel", true)
	defer helper.tearDown()
	helper.topic.lastID = 10
	member := helper.uids[1]
	pud := helper.topic.perUser[member]
	pud.modeGiven, pud.modeWant = types.ModeCPublic, types.ModeCPublic
	helper.topic.perUser[member] = pud

	helper.mm.EXPECT().GetAll("grpDel", types.ZeroUid, gomock.Any()).Return([]types.Message{
		{SeqId: 5, From: helper.uids[0].String()}}, nil)

	helper.topic.replyDelMsg(helper.sessions[1], member, false, delMsg(&helper, 1, 5, 6))
	helper.finish()
	// Refused, not silently turned into delete-for-me.
	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusForbidden})
}

func TestReplyDelMsgHardGroupOwnerAnyMessage(t *testing.T) {
	helper := TopicTestHelper{}
	helper.setUp(t, 2, types.TopicCatGrp, "grpDel", true)
	defer helper.tearDown()
	helper.topic.lastID = 10
	// The owner has D (ModeCFull): no authorship check, so no GetAll.
	helper.mm.EXPECT().DeleteList("grpDel", 1, types.ZeroUid, gomock.Any(), []types.Range{{Low: 5}}).Return(nil)

	if err := helper.topic.replyDelMsg(helper.sessions[0], helper.uids[0], false, delMsg(&helper, 0, 5, 6)); err != nil {
		t.Fatal(err)
	}
	helper.finish()
	registerSessionVerifyOutputs(t, helper.results[0], []int{http.StatusOK})
}

func TestRangesBelow(t *testing.T) {
	cases := []struct {
		in   []types.Range
		seq  int
		want []types.Range
	}{
		{[]types.Range{{Low: 1, Hi: 11}}, 8, []types.Range{{Low: 1, Hi: 8}}},
		{[]types.Range{{Low: 1, Hi: 11}}, 2, []types.Range{{Low: 1}}},
		{[]types.Range{{Low: 1, Hi: 11}}, 1, nil},
		{[]types.Range{{Low: 3}, {Low: 5, Hi: 9}, {Low: 12}}, 7, []types.Range{{Low: 3}, {Low: 5, Hi: 7}}},
		{[]types.Range{{Low: 3}, {Low: 5, Hi: 9}}, 20, []types.Range{{Low: 3}, {Low: 5, Hi: 9}}},
	}
	for _, tc := range cases {
		got := rangesBelow(tc.in, tc.seq)
		if len(got) != len(tc.want) {
			t.Errorf("rangesBelow(%v, %d) = %v, want %v", tc.in, tc.seq, got, tc.want)
			continue
		}
		for i := range got {
			if got[i] != tc.want[i] {
				t.Errorf("rangesBelow(%v, %d) = %v, want %v", tc.in, tc.seq, got, tc.want)
				break
			}
		}
	}
}

func TestFrameForLog(t *testing.T) {
	const password = "hunter2-correct-horse"
	const code = "INVITE-123"
	frames := []string{
		// base64("alice:hunter2-correct-horse")
		`{"login":{"id":"1","scheme":"basic","secret":"YWxpY2U6aHVudGVyMi1jb3JyZWN0LWhvcnNl","cred":[{"meth":"tel","val":"+61491570110","resp":"123456"}]}}`,
		`{"acc":{"id":"2","user":"new","scheme":"basic","secret":"YWxpY2U6aHVudGVyMi1jb3JyZWN0LWhvcnNl","tags":["code:` + code + `","basic:alice"],"tmpsecret":"` + password + `"}}`,
		`{"set":{"id":"3","topic":"me","cred":{"meth":"tel","val":"+61491570110"}}}`,
		`{"pub":{"id":"4","topic":"usrAbc","head":{"mime":"text/x-drafty","reply":"` + password + `"},"content":"` + password + `"}}`,
	}
	for _, f := range frames {
		got := frameForLog([]byte(f))
		for _, secret := range []string{password, code, "YWxpY2U6aHVudGVyMi1jb3JyZWN0LWhvcnNl", "+61491570110", "123456"} {
			if strings.Contains(got, secret) {
				t.Errorf("frameForLog leaked %q: %s", secret, got)
			}
		}
	}

	// Useful parts survive.
	got := frameForLog([]byte(frames[3]))
	for _, keep := range []string{`"pub"`, `"id":"4"`, `"topic":"usrAbc"`, "mime,reply", "<redacted 23 bytes>"} {
		if !strings.Contains(got, keep) {
			t.Errorf("frameForLog dropped %q: %s", keep, got)
		}
	}
	if got := frameForLog([]byte(frames[1])); !strings.Contains(got, "basic:alice") || !strings.Contains(got, "code:<redacted>") {
		t.Errorf("tags: %s", got)
	}

	// Malformed input is logged by size only.
	if got := frameForLog([]byte(`{"login":{"secret":"` + password)); strings.Contains(got, password) {
		t.Errorf("malformed frame leaked: %s", got)
	}
	// Long frames are truncated.
	long := `{"note":{"topic":"` + strings.Repeat("x", 2000) + `","what":"kp"}}`
	if got := frameForLog([]byte(long)); len(got) > maxLoggedFrameLen+5 {
		t.Errorf("not truncated: %d", len(got))
	}
}

// A scheme whose handler was never configured (e.g. firebase without
// auth_config.firebase) is an unknown scheme: 401, and the handler is not called.
func TestDispatchLoginUnconfiguredScheme(t *testing.T) {
	ctrl := gomock.NewController(t)
	ss := mock_store.NewMockPersistentStorageInterface(ctrl)
	aa := mock_auth.NewMockAuthHandler(ctrl)
	oldStore := store.Store
	store.Store = ss
	defer func() {
		store.Store = oldStore
		ctrl.Finish()
	}()
	ss.EXPECT().GetLogicalAuthHandler("firebase").Return(aa)
	aa.EXPECT().IsInitialized().Return(false)

	s := &Session{send: make(chan any, 10), ver: 16}
	wg := sync.WaitGroup{}
	r := responses{}
	wg.Add(1)
	go s.testWriteLoop(&r, &wg)

	s.dispatch(&ClientComMessage{Login: &MsgClientLogin{Id: "1", Scheme: "firebase", Secret: []byte("token")}})
	close(s.send)
	wg.Wait()

	verifyResponseCodes(&r, []int{http.StatusUnauthorized}, t)
}
