package co.tinode.tinodesdk;

import org.junit.Test;

import co.tinode.tinodesdk.model.Acs;
import co.tinode.tinodesdk.model.Description;
import co.tinode.tinodesdk.model.PrivateType;
import co.tinode.tinodesdk.model.TheCard;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * Topic-level chat request state (qa/runs/2026-10-02/contract-friend-requests.md). A pending
 * request never has messages, so a chat with messages is never shown as a request, whatever a
 * stale cached access mode says.
 */
public class TopicChatRequestTest {
    private static ComTopic<TheCard> p2p(String given, String want, int seq) {
        Description<TheCard, PrivateType> desc = new Description<>();
        desc.acs = new Acs(given, want);
        desc.seq = seq;
        // No Tinode instance: the topic isn't tracked, which is all a predicate test needs.
        return new ComTopic<>(null, "usrPeerQA1234", desc);
    }

    @Test
    public void incomingRequestWithoutMessages() {
        assertTrue(p2p("JRWPAD", "JA", 0).isChatRequestIncoming());
    }

    @Test
    public void outgoingRequestWithoutMessages() {
        assertTrue(p2p("JRA", "JRWPAD", 0).isChatRequestOutgoing());
    }

    @Test
    public void staleRequestModeOnChatWithMessages() {
        // The 2026-10-02 glitch: an accepted chat with messages whose cached want looked like a
        // request until the chat was opened.
        ComTopic<TheCard> t = p2p("JRWPAD", "JA", 12);
        assertFalse(t.isChatRequestIncoming());
        assertFalse(t.isChatRequestOutgoing());
        assertFalse(p2p("JRA", "JRWPAD", 3).isChatRequestOutgoing());
    }

    @Test
    public void groupIsNeverARequest() {
        Description<TheCard, PrivateType> desc = new Description<>();
        desc.acs = new Acs("JRWPAD", "JA");
        assertFalse(new ComTopic<>(null, "grpQAgroup123", desc).isChatRequestIncoming());
    }
}
