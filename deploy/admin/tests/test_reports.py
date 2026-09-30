"""Report parsing: which messages on the `sys` topic count as abuse reports.

Both apps send the same shape from Block and report: a Drafty document with
one EX entity whose JSON value is {"action": "report", "target": <topic>}.
"""
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# db reads its connection settings at import; parse_report needs no database.
os.environ.setdefault("PGPASSWORD", "unused-in-tests")

from app.db import parse_report  # noqa: E402


def drafty(val):
    return {"txt": " ", "fmt": [{"at": -1, "len": 1, "key": 0}],
            "ent": [{"tp": "EX", "data": {"mime": "application/json", "val": val}}]}


class ParseReportTest(unittest.TestCase):
    def test_group_report(self):
        self.assertEqual(parse_report(drafty({"action": "report", "target": "grpAbc123"})),
                         {"action": "report", "target": "grpAbc123"})

    def test_person_report(self):
        self.assertEqual(parse_report(drafty({"action": "report", "target": "usrXyz"}))["target"], "usrXyz")

    def test_not_a_report(self):
        self.assertIsNone(parse_report(drafty({"action": "hello", "target": "grpA"})))

    def test_report_without_target(self):
        self.assertIsNone(parse_report(drafty({"action": "report"})))

    def test_plain_text_message(self):
        self.assertIsNone(parse_report({"txt": "hi"}))
        self.assertIsNone(parse_report("just a string"))
        self.assertIsNone(parse_report(None))

    def test_malformed_entities_do_not_raise(self):
        self.assertIsNone(parse_report({"ent": [None, {"tp": "EX"}, {"data": {"val": "x"}}]}))


if __name__ == "__main__":
    unittest.main()
