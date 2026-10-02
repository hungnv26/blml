// 1:1 chat requests (qa/runs/2026-10-02/contract-friend-requests.md, section 2).
// A new 1:1 chat starts as a request: the requester gets given = 'JRA' (no W), the recipient
// gets want = 'JA' (no R, no W). Nobody can write until the recipient adds W to their want.
// 'acs' is the current user's AccessMode for the P2P topic; only meaningful for P2P topics.

// Request sent by the current user, not accepted yet: own want has W, own given has J but not W.
// A declined request looks the same, by design.
export function isRequestSent(acs) {
  return !!acs && acs.isWriter('want') && acs.isJoiner('given') && !acs.isWriter('given');
}

// Request received by the current user, not accepted yet: own want has J but neither R nor W,
// own given has J.
export function isRequestReceived(acs) {
  return !!acs && acs.isJoiner('want') && !acs.isReader('want') && !acs.isWriter('want') &&
    acs.isJoiner('given');
}

// The peer has accepted the chat: the peer's own want includes W. Tells a pending request apart from
// an accepted chat where the peer later took W away from the current user ("disable messaging").
// 'peer' is the peer's subscription ({acs: AccessMode}), e.g. topic.p2pPeerDesc().
export function isPeerAccepted(peer) {
  return !!(peer && peer.acs && peer.acs.isWriter('want'));
}
