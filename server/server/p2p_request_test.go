package main

// Tests for BLML 1:1 chat requests (p2p_requires_accept) and tolerant phone search.

import (
	"net/http"
	"reflect"
	"testing"

	"github.com/golang/mock/gomock"
	"github.com/tinode/chat/server/auth"
	"github.com/tinode/chat/server/store/types"
)

// withRequestPolicy turns p2p_requires_accept on (and fixes the p2p mode set) for one test.
func withRequestPolicy(t *testing.T, on bool) {
	t.Helper()
	oldOn, oldCP2P := globals.p2pRequiresAccept, globals.typesModeCP2P
	globals.p2pRequiresAccept = on
	globals.typesModeCP2P = types.ModeCP2P
	t.Cleanup(func() {
		globals.p2pRequiresAccept = oldOn
		globals.typesModeCP2P = oldCP2P
	})
}

// setUpRequestP2P makes uids[0] the requester and uids[1] the recipient of an unanswered request,
// with the exact modes initTopicP2P gives a new chat.
func setUpRequestP2P(t *testing.T, helper *TopicTestHelper, attach bool) (requester, recipient types.Uid) {
	t.Helper()
	helper.setUp(t, 2, types.TopicCatP2P, "p2pReq", attach)
	requester, recipient = helper.uids[0], helper.uids[1]
	pa := helper.topic.perUser[requester]
	pa.modeWant, pa.modeGiven = types.ModeCP2P, p2pRequestGiven
	helper.topic.perUser[requester] = pa
	pb := helper.topic.perUser[recipient]
	pb.modeWant, pb.modeGiven = p2pRequestWant, types.ModeCP2P
	helper.topic.perUser[recipient] = pb
	return requester, recipient
}

func TestP2PRequestModes(t *testing.T) {
	if p2pRequestWant.String() != "JA" || p2pRequestGiven.String() != "JRA" {
		t.Fatalf("request modes changed: want=%s given=%s", p2pRequestWant, p2pRequestGiven)
	}
	// The shipped apps show their Accept/Ignore/Block panel when given has J and given&^want has R/W.
	excessive := types.ModeCP2P &^ p2pRequestWant
	if !types.ModeCP2P.IsJoiner() || !excessive.IsReader() || !excessive.IsWriter() {
		t.Errorf("recipient would not see the invitation panel: excessive=%s", excessive)
	}
	// ...and list the chat normally (mode has J), not under blocked contacts.
	if !(p2pRequestWant & types.ModeCP2P).IsJoiner() || !(types.ModeCP2P & p2pRequestGiven).IsJoiner() {
		t.Error("both sides must keep J")
	}
	if !p2pWantUnaccepted(p2pRequestWant) || p2pWantUnaccepted(types.ModeCP2P) {
		t.Error("p2pWantUnaccepted")
	}
	// A block of an accepted chat (-JP) is not a request.
	if p2pWantUnaccepted(types.ModeCP2P &^ (types.ModeJoin | types.ModePres)) {
		t.Error("a blocked accepted chat must not count as a request")
	}
	if p2pWantUnaccepted(types.ModeUnset) || p2pWantUnaccepted(types.ModeInvalid) {
		t.Error("undefined modes are not requests")
	}
}

func TestP2PAcceptedGiven(t *testing.T) {
	old := globals.typesModeCP2P
	defer func() { globals.typesModeCP2P = old }()

	globals.typesModeCP2P = types.ModeCP2PD
	if got := p2pAcceptedGiven(p2pRequestGiven, types.ModeCP2PD); got != types.ModeCP2PD {
		t.Errorf("mirror of the recipient's given: got %s", got)
	}
	globals.typesModeCP2P = types.ModeCP2P
	if got := p2pAcceptedGiven(p2pRequestGiven, types.ModeCP2PD); got != types.ModeCP2P {
		t.Errorf("clamped to the p2p set: got %s", got)
	}
	// Even if the recipient was given little, the requester gets at least JRWP(A).
	if got := p2pAcceptedGiven(p2pRequestGiven, types.ModeUnset); got != types.ModeCP2P {
		t.Errorf("minimum: got %s", got)
	}
}

func TestP2PRequestPending(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	setUpRequestP2P(t, &helper, false)
	defer helper.tearDown()
	defer helper.finish()

	if !helper.topic.p2pRequestPending() {
		t.Error("new request must be pending")
	}
	// Declined: the recipient's subscription is deleted but still counts.
	pb := helper.topic.perUser[helper.uids[1]]
	pb.deleted = true
	helper.topic.perUser[helper.uids[1]] = pb
	if !helper.topic.p2pRequestPending() {
		t.Error("declined request must stay pending")
	}
	globals.p2pRequiresAccept = false
	if helper.topic.p2pRequestPending() {
		t.Error("policy off: never pending")
	}
}

func TestP2PRequestExistingChatNotPending(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	helper.setUp(t, 2, types.TopicCatP2P, "p2pOld", true)
	defer helper.tearDown()
	for _, uid := range helper.uids {
		pud := helper.topic.perUser[uid]
		pud.modeWant, pud.modeGiven = types.ModeCP2P, types.ModeCP2P
		helper.topic.perUser[uid] = pud
	}
	helper.mm.EXPECT().Save(gomock.Any(), gomock.Any(), gomock.Any()).Return(nil, true)

	if helper.topic.p2pRequestPending() {
		t.Fatal("a chat with W on both sides is not a request")
	}
	helper.topic.handleClientMsg(&ClientComMessage{
		Id: "pub1", AsUser: helper.uids[0].UserId(), Original: helper.uids[1].UserId(),
		Pub:  &MsgClientPub{Id: "pub1", Topic: "p2p", Content: "hi", NoEcho: true},
		sess: helper.sessions[0],
	})
	helper.finish()
	registerSessionVerifyOutputs(t, helper.results[0], []int{http.StatusAccepted})
	if n := len(helper.results[1].messages); n != 1 {
		t.Errorf("existing chat: peer should get the message, got %d frames", n)
	}
}

func TestP2PRequestPubRefusedBothSides(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	setUpRequestP2P(t, &helper, true)
	defer helper.tearDown()
	// No Messages.Save expected: gomock fails the test if anything is stored.

	for i, uid := range helper.uids {
		helper.topic.handleClientMsg(&ClientComMessage{
			AsUser: uid.UserId(), Original: helper.uids[i^1].UserId(),
			Pub:  &MsgClientPub{Id: "pub1", Topic: "p2p", Content: "hi"},
			sess: helper.sessions[i],
		})
	}
	helper.finish()

	for i, r := range helper.results {
		registerSessionVerifyOutputs(t, r, []int{http.StatusForbidden})
		if len(r.messages) == 1 {
			ctrl := r.messages[0].(*ServerComMessage).Ctrl
			if ctrl.Params == nil || ctrl.Params.(map[string]any)["what"] != "not-accepted" {
				t.Errorf("user %d: want params.what=not-accepted, got %v", i, ctrl.Params)
			}
		}
	}
	if len(helper.hubMessages) != 0 {
		t.Errorf("no notifications or pushes expected, got %v", helper.hubMessages)
	}
}

func TestP2PRequestNotesDropped(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	requester, _ := setUpRequestP2P(t, &helper, true)
	defer helper.tearDown()

	for _, what := range []string{"kp", "read", "recv"} {
		helper.topic.handleClientMsg(&ClientComMessage{
			AsUser: requester.UserId(), Original: helper.uids[1].UserId(),
			Note: &MsgClientNote{Topic: "p2p", What: what, SeqId: 0},
			sess: helper.sessions[0],
		})
	}
	helper.finish()
	for i, r := range helper.results {
		if len(r.messages) != 0 {
			t.Errorf("session %d: nothing must be delivered, got %d frames", i, len(r.messages))
		}
	}
	if len(helper.hubMessages) != 0 {
		t.Errorf("no offline notifications expected, got %d", len(helper.hubMessages))
	}
}

func TestP2PRequestPlainSubDoesNotAccept(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	requester, recipient := setUpRequestP2P(t, &helper, false)
	defer helper.tearDown()
	// No store updates expected.

	helper.topic.registerSession(&ClientComMessage{
		Original: requester.UserId(),
		Sub:      &MsgClientSub{Id: "sub1", Topic: requester.UserId()},
		AsUser:   recipient.UserId(),
		AuthLvl:  int(auth.LevelAuth),
		sess:     helper.sessions[1],
	})
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
	if want := helper.topic.perUser[recipient].modeWant; want != p2pRequestWant {
		t.Errorf("opening the request must not accept it: want=%s", want)
	}
	if given := helper.topic.perUser[requester].modeGiven; given != p2pRequestGiven {
		t.Errorf("requester must stay restricted: given=%s", given)
	}
}

func TestP2PRequestAccept(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	requester, recipient := setUpRequestP2P(t, &helper, false)
	defer helper.tearDown()

	helper.ss.EXPECT().Update("p2pReq", recipient, gomock.Any()).Return(nil)
	var granted map[string]any
	helper.ss.EXPECT().Update("p2pReq", requester, gomock.Any()).DoAndReturn(
		func(_ string, _ types.Uid, upd map[string]any) error {
			granted = upd
			return nil
		})

	// What the apps' Accept button sends first: own want = the given mode.
	helper.topic.registerSession(&ClientComMessage{
		Original: requester.UserId(),
		Sub: &MsgClientSub{Id: "sub1", Topic: requester.UserId(),
			Set: &MsgSetQuery{Sub: &MsgSetSub{Mode: types.ModeCP2P.String()}}},
		AsUser:  recipient.UserId(),
		AuthLvl: int(auth.LevelAuth),
		sess:    helper.sessions[1],
	})
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
	if !reflect.DeepEqual(granted, map[string]any{"ModeGiven": types.ModeCP2P}) {
		t.Errorf("requester's given in the store: %v", granted)
	}
	if given := helper.topic.perUser[requester].modeGiven; given != types.ModeCP2P {
		t.Errorf("requester's given: %s", given)
	}
	if helper.topic.p2pRequestPending() {
		t.Error("accepted chat must not be pending")
	}
	// The requester is told on 'me' that they were given W and P.
	var told bool
	for _, m := range helper.hubMessages[requester.UserId()] {
		if m.Pres != nil && m.Pres.What == "acs" && m.Pres.Acs != nil && m.Pres.Acs.Given != "" {
			told = true
		}
	}
	if !told {
		t.Errorf("requester not notified of the grant: %v", helper.hubMessages[requester.UserId()])
	}
}

func TestP2PRequestBlockedRecipientUnblockReturnsToRequest(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	requester, recipient := setUpRequestP2P(t, &helper, false)
	defer helper.tearDown()
	// Blocked from the request: "JA" - "JP" = "A".
	pb := helper.topic.perUser[recipient]
	pb.modeWant = types.ModeApprove
	helper.topic.perUser[recipient] = pb
	helper.ss.EXPECT().Update("p2pReq", recipient, gomock.Any()).Return(nil)
	// No update of the requester: "+JP" is not an acceptance.

	helper.topic.registerSession(&ClientComMessage{
		Original: requester.UserId(),
		Sub: &MsgClientSub{Id: "sub1", Topic: requester.UserId(),
			Set: &MsgSetQuery{Sub: &MsgSetSub{Mode: "JPA"}}},
		AsUser:  recipient.UserId(),
		AuthLvl: int(auth.LevelAuth),
		sess:    helper.sessions[1],
	})
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
	if !helper.topic.p2pRequestPending() || helper.topic.perUser[requester].modeGiven != p2pRequestGiven {
		t.Error("unblocking with +JP must return to the pending request")
	}
}

func TestP2PRequestDeclineIsSilentAndKeepsTopic(t *testing.T) {
	withRequestPolicy(t, true)
	helper := TopicTestHelper{}
	requester, recipient := setUpRequestP2P(t, &helper, true)
	defer helper.tearDown()
	helper.hub.unreg = make(chan *topicUnreg, 1)
	// The requester already deleted their side: the decline removes the last live subscription.
	pa := helper.topic.perUser[requester]
	pa.deleted = true
	helper.topic.perUser[requester] = pa
	helper.ss.EXPECT().Delete("p2pReq", recipient).Return(nil)

	err := helper.topic.replyLeaveUnsub(helper.sessions[1], &ClientComMessage{
		Id: "del1", Original: requester.UserId(), AsUser: recipient.UserId(), init: true,
		Del: &MsgClientDel{Id: "del1", Topic: requester.UserId(), What: "topic", Hard: true},
	}, recipient)
	if err != nil {
		t.Fatal(err)
	}
	if n := len(helper.hub.unreg); n != 0 {
		t.Error("declined request must not delete the topic")
	}
	helper.finish()

	registerSessionVerifyOutputs(t, helper.results[1], []int{http.StatusOK})
	if msgs := helper.hubMessages[requester.UserId()]; len(msgs) != 0 {
		t.Errorf("requester must not be told about the decline: %v", msgs)
	}
	if !helper.topic.p2pRequestPending() {
		t.Error("declined request stays pending")
	}
}

func TestP2PSubsPending(t *testing.T) {
	withRequestPolicy(t, true)
	req := []types.Subscription{{ModeWant: types.ModeCP2P, ModeGiven: p2pRequestGiven},
		{ModeWant: p2pRequestWant, ModeGiven: types.ModeCP2P}}
	if !p2pSubsPending(req) {
		t.Error("request subscriptions")
	}
	old := []types.Subscription{{ModeWant: types.ModeCP2P, ModeGiven: types.ModeCP2P},
		{ModeWant: types.ModeCP2P &^ (types.ModeJoin | types.ModePres), ModeGiven: types.ModeCP2P}}
	if p2pSubsPending(old) {
		t.Error("an existing (even blocked) chat is not a request")
	}
}

func TestJoinPhoneTokens(t *testing.T) {
	old := globals.validators
	globals.validators = map[string]credValidator{"tel": {addToTags: true}}
	defer func() { globals.validators = old }()

	cases := []struct {
		in   []string
		want []string
	}{
		{[]string{"+61", "491", "570", "111"}, []string{"+61491570111"}},
		{[]string{"tel:+61", "491", "570", "111"}, []string{"tel:+61491570111"}},
		{[]string{"(04)", "9157", "0111"}, []string{"(04)91570111"}},
		{[]string{"alice", "+61", "491", "570", "111", "bob"}, []string{"alice", "+61491570111", "bob"}},
		// Not a number when joined, or not starting like one: left alone.
		{[]string{"2024", "2025"}, []string{"2024", "2025"}},
		{[]string{"+61", "1"}, []string{"+61", "1"}},
		{[]string{"alice", "bob"}, []string{"alice", "bob"}},
		{[]string{"+61491570111"}, []string{"+61491570111"}},
	}
	for _, c := range cases {
		if got := joinPhoneTokens(c.in, "AU"); !reflect.DeepEqual(got, c.want) {
			t.Errorf("joinPhoneTokens(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestRewriteTagPhone(t *testing.T) {
	old := globals.validators
	globals.validators = map[string]credValidator{"tel": {addToTags: true}}
	defer func() { globals.validators = old }()

	cases := map[string][]string{
		"tel:+61491570111":    {"tel:+61491570111"},
		"tel:+61 491 570 111": {"tel:+61491570111"},
		"tel:0491570111":      {"tel:+61491570111"},
		"+61-491-570-111":     {"+61-491-570-111", "tel:+61491570111"},
		"0491570111":          {"0491570111", "tel:+61491570111"},
		"(04)91570111":        {"(04)91570111", "tel:+61491570111"},
		"tel:junk":            {"tel:junk"},
		"basic:alice":         {"basic:alice"},
	}
	for in, want := range cases {
		if got := rewriteTag(in, "AU"); !reflect.DeepEqual(got, want) {
			t.Errorf("rewriteTag(%q) = %v, want %v", in, got, want)
		}
	}
}
