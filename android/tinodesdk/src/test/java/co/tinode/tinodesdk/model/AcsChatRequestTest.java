package co.tinode.tinodesdk.model;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/** States from qa/runs/2026-10-02/contract-friend-requests.md, section 2. Acs(given, want). */
public class AcsChatRequestTest {
    @Test
    public void pendingOutgoing() {
        Acs a = new Acs("JRA", "JRWPAD");
        assertTrue(a.isChatRequestOutgoing());
        assertFalse(a.isChatRequestIncoming());
    }

    @Test
    public void pendingIncoming() {
        Acs a = new Acs("JRWPAD", "JA");
        assertTrue(a.isChatRequestIncoming());
        assertFalse(a.isChatRequestOutgoing());
    }

    @Test
    public void accepted() {
        Acs a = new Acs("JRWPAD", "JRWPAD");
        assertFalse(a.isChatRequestIncoming());
        assertFalse(a.isChatRequestOutgoing());
    }

    @Test
    public void blockedFromRequest() {
        // Block sends want - "JP": "JA" becomes "A".
        Acs a = new Acs("JRWPAD", "A");
        assertFalse(a.isChatRequestIncoming());
        assertFalse(a.isChatRequestOutgoing());
    }

    @Test
    public void existingChatWithoutPresence() {
        // An accepted chat the user muted (no P) is not a request.
        Acs a = new Acs("JRWPAD", "JRWAD");
        assertFalse(a.isChatRequestIncoming());
        assertFalse(a.isChatRequestOutgoing());
    }
}
