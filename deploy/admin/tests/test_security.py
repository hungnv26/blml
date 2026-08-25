"""Tests for the admin console's auth primitives.

Runs on a bare Python with no dependencies:  python3 -m unittest discover tests

The TOTP cases are the published vectors from RFC 6238 Appendix B, not
values this implementation produced. A self-generated fixture would pass just
as happily against a subtly wrong implementation.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.security import (  # noqa: E402
    RateLimiter, hash_password, hash_session_token, new_session_token,
    provisioning_uri, totp_at, verify_password, verify_totp,
)

# RFC 6238 uses the ASCII secret "12345678901234567890" with SHA-1.
RFC_SECRET_B32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"


class PasswordTests(unittest.TestCase):
    # Keep the tests fast; the rounds are a stored parameter, not a constant.
    ROUNDS = 1000

    def test_roundtrip(self):
        enc = hash_password("correct horse battery staple", rounds=self.ROUNDS)
        self.assertTrue(verify_password("correct horse battery staple", enc))

    def test_wrong_password_rejected(self):
        enc = hash_password("hunter2", rounds=self.ROUNDS)
        self.assertFalse(verify_password("hunter3", enc))

    def test_salt_is_random(self):
        a = hash_password("same", rounds=self.ROUNDS)
        b = hash_password("same", rounds=self.ROUNDS)
        self.assertNotEqual(a, b, "identical hashes mean the salt is not random")

    def test_rounds_are_carried_in_the_record(self):
        enc = hash_password("x", rounds=1234)
        self.assertIn("$1234$", enc)
        self.assertTrue(verify_password("x", enc))

    def test_malformed_records_fail_closed(self):
        for bad in ("", "nonsense", "pbkdf2_sha256$notanumber$a$b",
                    "bcrypt$10$salt$hash", "pbkdf2_sha256$1000$!!!$!!!"):
            with self.subTest(bad=bad):
                self.assertFalse(verify_password("x", bad))


class TotpTests(unittest.TestCase):
    def test_rfc6238_vectors(self):
        # (unix time, expected 8-digit code) from RFC 6238 Appendix B, SHA-1.
        for ts, expected in [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
            (20000000000, "65353130"),
        ]:
            with self.subTest(ts=ts):
                self.assertEqual(totp_at(RFC_SECRET_B32, ts, digits=8), expected)

    def test_verify_accepts_current_step(self):
        now = 1111111111
        code = totp_at(RFC_SECRET_B32, now)
        self.assertTrue(verify_totp(RFC_SECRET_B32, code, now=now))

    def test_verify_absorbs_one_step_of_drift(self):
        now = 1111111111
        for offset in (-30, 30):
            with self.subTest(offset=offset):
                code = totp_at(RFC_SECRET_B32, now + offset)
                self.assertTrue(verify_totp(RFC_SECRET_B32, code, now=now))

    def test_verify_rejects_beyond_the_window(self):
        now = 1111111111
        code = totp_at(RFC_SECRET_B32, now + 120)
        self.assertFalse(verify_totp(RFC_SECRET_B32, code, now=now))

    def test_verify_rejects_junk(self):
        now = 1111111111
        for bad in ("", "abcdef", "12345", None):
            with self.subTest(bad=bad):
                self.assertFalse(verify_totp(RFC_SECRET_B32, bad, now=now))

    def test_unpadded_secret_is_accepted(self):
        # Authenticator apps show secrets without base32 padding.
        unpadded = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ".rstrip("=")
        self.assertEqual(totp_at(unpadded, 59, digits=8), "94287082")

    def test_provisioning_uri_shape(self):
        uri = provisioning_uri("ABC234", "operator", "BLML admin")
        self.assertTrue(uri.startswith("otpauth://totp/"))
        self.assertIn("secret=ABC234", uri)
        self.assertIn("BLML%20admin", uri)


class SessionTests(unittest.TestCase):
    def test_tokens_are_unique_and_long(self):
        tokens = {new_session_token() for _ in range(100)}
        self.assertEqual(len(tokens), 100)
        self.assertGreaterEqual(len(tokens.pop()), 40)

    def test_hash_is_stable_and_not_the_token(self):
        token = new_session_token()
        self.assertEqual(hash_session_token(token), hash_session_token(token))
        self.assertNotEqual(hash_session_token(token), token)


class RateLimiterTests(unittest.TestCase):
    def test_allows_up_to_the_threshold(self):
        rl = RateLimiter(threshold=3)
        for _ in range(3):
            self.assertEqual(rl.retry_after("ip", now=1000.0), 0.0)
            rl.record_failure("ip", now=1000.0)
        self.assertGreater(rl.retry_after("ip", now=1000.0), 0.0)

    def test_backoff_grows(self):
        rl = RateLimiter(threshold=1, base_delay=2.0)
        rl.record_failure("ip", now=0.0)
        first = rl.retry_after("ip", now=0.0)
        rl.record_failure("ip", now=0.0)
        second = rl.retry_after("ip", now=0.0)
        self.assertGreater(second, first)

    def test_backoff_is_capped(self):
        rl = RateLimiter(threshold=1, base_delay=2.0, max_delay=10.0)
        for _ in range(20):
            rl.record_failure("ip", now=0.0)
        self.assertLessEqual(rl.retry_after("ip", now=0.0), 10.0)

    def test_waiting_it_out_clears_the_block(self):
        rl = RateLimiter(threshold=1, base_delay=2.0)
        rl.record_failure("ip", now=0.0)
        self.assertGreater(rl.retry_after("ip", now=0.0), 0.0)
        self.assertEqual(rl.retry_after("ip", now=1000.0), 0.0)

    def test_success_resets(self):
        rl = RateLimiter(threshold=1)
        rl.record_failure("ip", now=0.0)
        rl.reset("ip")
        self.assertEqual(rl.retry_after("ip", now=0.0), 0.0)



class SparklineTests(unittest.TestCase):
    """The dashboard chart. Pure enough to test, and wrong enough to matter:
    an inverted y-axis or an off-by-one step looks plausible in code."""

    def setUp(self):
        from app.charts import sparkline
        self.sparkline = sparkline

    def _points(self, svg):
        import re
        raw = re.search(r'points="([^"]+)"', svg).group(1)
        return [tuple(float(n) for n in p.split(",")) for p in raw.split()]

    def test_empty_series_renders_nothing(self):
        self.assertEqual(self.sparkline([]), "")

    def test_point_count_matches_series(self):
        self.assertEqual(len(self._points(self.sparkline([1, 2, 3, 4]))), 4)

    def test_peak_sits_at_the_top(self):
        # SVG y grows downwards, so the largest value must have the smallest y.
        pts = self._points(self.sparkline([1, 9, 3], height=48))
        ys = [y for _, y in pts]
        self.assertEqual(min(ys), ys[1], "the peak is not the highest point")

    def test_spans_the_full_width(self):
        pts = self._points(self.sparkline([1, 2, 3], width=100))
        self.assertAlmostEqual(pts[0][0], 0.0)
        self.assertAlmostEqual(pts[-1][0], 100.0, places=1)

    def test_flat_series_does_not_divide_by_zero(self):
        self.assertIn("polyline", self.sparkline([0, 0, 0]))

    def test_single_point_is_safe(self):
        self.assertEqual(len(self._points(self.sparkline([5]))), 1)

if __name__ == "__main__":
    unittest.main()
