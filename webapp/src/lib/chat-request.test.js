import { AccessMode } from 'tinode-sdk';

import { isPeerAccepted, isRequestReceived, isRequestSent } from './chat-request';

const acs = (want, given) => new AccessMode({want: want, given: given});

// Modes as observed on the QA server (contract-friend-requests.md, sections 2-3).
test('requester side', () => {
  // Pending: own want has W, server gives exactly JRA.
  expect(isRequestSent(acs('JRWPAD', 'JRA'))).toBe(true);
  // The web asks for JRWPS when starting a chat.
  expect(isRequestSent(acs('JRWPS', 'JRA'))).toBe(true);
  // Accepted: the server copied the recipient's given onto ours.
  expect(isRequestSent(acs('JRWPAD', 'JRWPAD'))).toBe(false);
  // Blocked by me (want lacks J): not a request; given lacking J (blocked by the peer's server rules).
  expect(isRequestSent(acs('A', 'JRA'))).toBe(false);
  expect(isRequestSent(acs('JRWPAD', 'A'))).toBe(false);
  expect(isRequestReceived(acs('JRWPAD', 'JRA'))).toBe(false);
  expect(isRequestSent(null)).toBe(false);
});

test('recipient side', () => {
  // Pending incoming: server sets want JA.
  expect(isRequestReceived(acs('JA', 'JRWPAD'))).toBe(true);
  // Unblocked from Blocked contacts with +JP: back to pending incoming.
  expect(isRequestReceived(acs('JPA', 'JRWPAD'))).toBe(true);
  // Accepted.
  expect(isRequestReceived(acs('JRWPAD', 'JRWPAD'))).toBe(false);
  // Blocked from the request (want - JP = A).
  expect(isRequestReceived(acs('A', 'JRWPAD'))).toBe(false);
  expect(isRequestSent(acs('JA', 'JRWPAD'))).toBe(false);
  expect(isRequestReceived(undefined)).toBe(false);
});

test('isPeerAccepted', () => {
  // The requester sees the recipient with want JA while pending.
  expect(isPeerAccepted({acs: acs('JA', 'JRWPAD')})).toBe(false);
  expect(isPeerAccepted({acs: acs('JRWPAD', 'JRWPAD')})).toBe(true);
  expect(isPeerAccepted({})).toBe(false);
  expect(isPeerAccepted(null)).toBe(false);
});
