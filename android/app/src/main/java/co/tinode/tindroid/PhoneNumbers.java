package co.tinode.tindroid;

import android.content.Context;
import android.telephony.TelephonyManager;

import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.Phonenumber;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import co.tinode.tinodesdk.MeTopic;
import co.tinode.tinodesdk.Tinode;
import co.tinode.tinodesdk.model.Credential;

/**
 * Lenient phone number reading: accepts what people actually type and returns E.164.
 *
 * <ul>
 *   <li>International ("+61 491 570 104", "0061 491 570 104") or local ("0491 570 104")
 *   format, with spaces, dashes, dots, slashes or brackets.</li>
 *   <li>A local number is read in the device's region first, then in the region of the user's
 *   own number. A region where the number is valid wins over one where it is only possible,
 *   so "0491 570 104" on a US phone of an Australian user still becomes +61491570104.</li>
 *   <li>Numbers libphonenumber considers <i>possible</i> (right length for the country) are
 *   accepted even when its metadata doesn't know them as <i>valid</i> (new ranges, MVNOs).</li>
 * </ul>
 * Anything with letters, or too short/long for any country, is rejected (null).
 */
public final class PhoneNumbers {
    // Digits with an optional leading '+' and the usual separators. Letters are never a phone.
    private static final Pattern sPhoneChars = Pattern.compile("^\\+?[0-9 ()./\\-\\u00A0\\u2010-\\u2015\\u2212]+$");
    private static final Pattern sSeparators = Pattern.compile("[ ()./\\-\\u00A0\\u2010-\\u2015\\u2212]");

    private PhoneNumbers() {}

    /**
     * Convert a typed phone number to E.164.
     *
     * @param raw     what the user typed.
     * @param regions ISO-3166 regions to read a local-format number in, most preferred first.
     *                Null and empty entries are skipped.
     * @return the number as E.164 or null if it is not a phone number.
     */
    @Nullable
    public static String toE164(@Nullable String raw, String... regions) {
        if (raw == null) {
            return null;
        }
        String text = raw.trim();
        if (text.startsWith("tel:")) {
            text = text.substring(4).trim();
        }
        if (!sPhoneChars.matcher(text).matches()) {
            return null;
        }
        String digits = sSeparators.matcher(text).replaceAll("");
        // The shortest real numbers (e.g. Niue, Saint Helena) have 4-5 digits after the country
        // code; anything shorter is a typo or a short code nobody can be found by.
        int count = digits.startsWith("+") ? digits.length() - 1 : digits.length();
        if (count < 5 || count > 17) {
            return null;
        }

        final PhoneNumberUtil util = PhoneNumberUtil.getInstance();
        List<String> tryRegions = new ArrayList<>();
        if (regions != null) {
            for (String r : regions) {
                if (r != null && !r.isEmpty() && !"ZZ".equalsIgnoreCase(r)) {
                    String upper = r.toUpperCase(Locale.ROOT);
                    if (!tryRegions.contains(upper)) {
                        tryRegions.add(upper);
                    }
                }
            }
        }
        if (tryRegions.isEmpty()) {
            // An international number parses without a region.
            tryRegions.add("ZZ");
        }

        // Pass 1: a region where the number is valid. Pass 2: one where it is possible.
        Phonenumber.PhoneNumber possible = null;
        for (String region : tryRegions) {
            Phonenumber.PhoneNumber number = parse(util, digits, region);
            if (number == null) {
                continue;
            }
            if (util.isValidNumber(number)) {
                return format(util, number);
            }
            // Same rule as the server (server/validate/tel/normalize.go plausible()): possible,
            // and as long as the country's ordinary subscriber numbers. Refuses short codes and
            // truncated numbers that a bare "possible" check lets through.
            if (possible == null && isPlausible(util, number)) {
                possible = number;
            }
        }

        // A country code typed without the '+' ("61 491 570 104"): accept only if valid,
        // so a local number is never misread as an international one.
        if (!digits.startsWith("+") && !digits.startsWith("0")) {
            Phonenumber.PhoneNumber number = parse(util, "+" + digits, "ZZ");
            if (number != null && util.isValidNumber(number) && possible == null) {
                return format(util, number);
            }
        }

        return possible != null ? format(util, possible) : null;
    }

    /**
     * Same as {@link #toE164(String, String...)} using the device region, then the region of
     * the user's own phone number.
     */
    @Nullable
    public static String toE164ForUser(@NonNull Context context, @Nullable String raw) {
        return toE164(raw, deviceRegion(context), ownRegion());
    }

    private static final Map<String, int[]> sSubscriberLengths = new ConcurrentHashMap<>();

    /** Possible (IS_POSSIBLE, not local-only) and within the region's ordinary number lengths. */
    static boolean isPlausible(PhoneNumberUtil util, Phonenumber.PhoneNumber number) {
        if (util.isPossibleNumberWithReason(number) != PhoneNumberUtil.ValidationResult.IS_POSSIBLE) {
            return false;
        }
        String region = util.getRegionCodeForCountryCode(number.getCountryCode());
        int[] range = subscriberLengths(util, region);
        if (range[0] == 0) {
            // Non-geographic codes have no examples: "possible" is all there is.
            return true;
        }
        int n = util.getNationalSignificantNumber(number).length();
        return n >= range[0] && n <= range[1];
    }

    // Shortest and longest national number among the region's example numbers of the ordinary
    // types (mobile, fixed line, VoIP, personal, UAN); {0, 0} if there are none.
    private static int[] subscriberLengths(PhoneNumberUtil util, String region) {
        int[] cached = sSubscriberLengths.get(region);
        if (cached != null) {
            return cached;
        }
        int min = 0, max = 0;
        for (PhoneNumberUtil.PhoneNumberType type : new PhoneNumberUtil.PhoneNumberType[]{
                PhoneNumberUtil.PhoneNumberType.MOBILE, PhoneNumberUtil.PhoneNumberType.FIXED_LINE,
                PhoneNumberUtil.PhoneNumberType.FIXED_LINE_OR_MOBILE, PhoneNumberUtil.PhoneNumberType.VOIP,
                PhoneNumberUtil.PhoneNumberType.PERSONAL_NUMBER, PhoneNumberUtil.PhoneNumberType.UAN}) {
            Phonenumber.PhoneNumber ex = util.getExampleNumberForType(region, type);
            if (ex == null) {
                continue;
            }
            int n = util.getNationalSignificantNumber(ex).length();
            if (n == 0) {
                continue;
            }
            if (min == 0 || n < min) {
                min = n;
            }
            if (n > max) {
                max = n;
            }
        }
        int[] range = new int[]{min, max};
        sSubscriberLengths.put(region, range);
        return range;
    }

    @Nullable
    private static Phonenumber.PhoneNumber parse(PhoneNumberUtil util, String text, String region) {
        try {
            return util.parse(text, region);
        } catch (NumberParseException ignored) {
            return null;
        }
    }

    private static String format(PhoneNumberUtil util, Phonenumber.PhoneNumber number) {
        return util.format(number, PhoneNumberUtil.PhoneNumberFormat.E164);
    }

    /** Region of the device: SIM, then network, then locale. Upper case or null. */
    @Nullable
    public static String deviceRegion(@NonNull Context context) {
        String region = null;
        TelephonyManager tm = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        if (tm != null) {
            region = tm.getSimCountryIso();
            if (region == null || region.isEmpty()) {
                region = tm.getNetworkCountryIso();
            }
        }
        if (region == null || region.isEmpty()) {
            region = context.getResources().getConfiguration().getLocales().get(0).getCountry();
        }
        return region != null && !region.isEmpty() ? region.toUpperCase(Locale.ROOT) : null;
    }

    /** Region of the user's own confirmed or pending phone number, or null. */
    @Nullable
    public static String ownRegion() {
        final Tinode tinode = Cache.getTinode();
        final MeTopic<?> me = tinode != null ? tinode.getMeTopic() : null;
        final Credential[] creds = me != null ? me.getCreds() : null;
        if (creds == null) {
            return null;
        }
        final PhoneNumberUtil util = PhoneNumberUtil.getInstance();
        for (Credential cred : creds) {
            if (Credential.METH_PHONE.equals(cred.meth) && cred.val != null) {
                Phonenumber.PhoneNumber number = parse(util, cred.val, "ZZ");
                if (number != null) {
                    String region = util.getRegionCodeForNumber(number);
                    if (region != null && !region.isEmpty() && !"ZZ".equals(region)) {
                        return region;
                    }
                }
            }
        }
        return null;
    }
}
