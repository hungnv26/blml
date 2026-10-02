package co.tinode.tindroid;

import org.junit.Test;

import com.google.i18n.phonenumbers.PhoneNumberUtil;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;

public class PhoneNumbersTest {
    @Test
    public void international_withSeparators() {
        assertEquals("+61491570104", PhoneNumbers.toE164("+61 491 570 104", "US"));
        assertEquals("+61491570104", PhoneNumbers.toE164("+61 (491) 570-104", "US"));
        assertEquals("+61491570104", PhoneNumbers.toE164("+61.491.570.104"));
        assertEquals("+61491570104", PhoneNumbers.toE164("tel:+61491570104"));
        assertEquals("+84912345678", PhoneNumbers.toE164("+84 91 234 56 78", "AU"));
    }

    @Test
    public void localFormat_usesRegion() {
        assertEquals("+61491570104", PhoneNumbers.toE164("0491 570 104", "AU"));
        assertEquals("+84912345678", PhoneNumbers.toE164("091 234 5678", "VN"));
        assertEquals("+12015550123", PhoneNumbers.toE164("(201) 555-0123", "US"));
    }

    @Test
    public void localFormat_validRegionWinsOverPossible() {
        // Device region US, own number AU: an AU mobile in local format is not a valid US number.
        assertEquals("+61491570105", PhoneNumbers.toE164("0491 570 105", "US", "AU"));
    }

    @Test
    public void internationalPrefix00() {
        assertEquals("+61491570104", PhoneNumbers.toE164("0061 491 570 104", "VN"));
    }

    @Test
    public void countryCodeWithoutPlus() {
        assertEquals("+61491570104", PhoneNumbers.toE164("61 491 570 104", "VN"));
    }

    @Test
    public void possibleButNotValid_isAccepted() throws Exception {
        // Right length, but not in libphonenumber's list of allocated ranges: possible, not
        // valid. Still a phone number someone may own (new ranges, MVNOs, stale metadata).
        PhoneNumberUtil util = PhoneNumberUtil.getInstance();
        assertFalse(util.isValidNumber(util.parse("+1 201 155 0123", "ZZ")));
        assertEquals("+12011550123", PhoneNumbers.toE164("+1 (201) 155-0123", "AU"));
        assertFalse(util.isValidNumber(util.parse("+84 199 999 999", "ZZ")));
        assertEquals("+84199999999", PhoneNumbers.toE164("0199 999 999", "VN"));
    }

    @Test
    public void serverContractExamples() {
        // qa/runs/2026-10-02/contract-friend-requests.md section 4.1.
        assertEquals("+61495570111", PhoneNumbers.toE164("+61 495 570 111"));
        assertEquals("+61491570111", PhoneNumbers.toE164("+61 (0)491 570 111"));
        assertEquals("+61491570111", PhoneNumbers.toE164("+61 491\u2013570\u2013111"));
        assertEquals("+61491570111", PhoneNumbers.toE164("(0491) 570.111", "AU"));
        assertNull(PhoneNumbers.toE164("+61 491 57"));
        // Service-code length: "possible" in AU, but not a subscriber number.
        assertNull(PhoneNumbers.toE164("+61 12345"));
    }

    @Test
    public void notAPhone() {
        assertNull(PhoneNumbers.toE164(null, "AU"));
        assertNull(PhoneNumbers.toE164("", "AU"));
        assertNull(PhoneNumbers.toE164("hello", "AU"));
        assertNull(PhoneNumbers.toE164("1-800-FLOWERS", "US"));
        assertNull(PhoneNumbers.toE164("123", "AU"));
        assertNull(PhoneNumbers.toE164("+1234567890123456789", "AU"));
        assertNull(PhoneNumbers.toE164("alice@example.com", "AU"));
    }

    @Test
    public void localNumberWithoutRegion_isRejected() {
        assertNull(PhoneNumbers.toE164("0491 570 104"));
    }
}
