"""Tests for the ECHO backend. Run: python3 -m unittest server/test_companion_server.py"""
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import companion_server as cs  # noqa: E402

VALID = {
    "run_id": 1042, "state_version": 3, "event_id": "help#4", "room_id": "cargo",
    "objective_id": "open_compartment", "time_band": "ok", "inventory": [],
    "recent_event": "help", "boots_use_count": 2,
    "canonical_hint": "Wait for a DOWN surge to slide it onto the pressure plate.",
}


class ValidationTests(unittest.TestCase):
    def test_valid_snapshot(self):
        snap, reason = cs.validate_snapshot(dict(VALID))
        self.assertIsNotNone(snap, reason)

    def test_float_ids_from_godot_json_are_accepted(self):
        snap, _ = cs.validate_snapshot({**VALID, "run_id": 1042.0})
        self.assertIsNotNone(snap)

    def test_rejects_missing_field(self):
        bad = dict(VALID)
        del bad["canonical_hint"]
        self.assertIsNone(cs.validate_snapshot(bad)[0])

    def test_rejects_wrong_types(self):
        for key, value in [("run_id", "x"), ("run_id", 1.5), ("run_id", True),
                           ("inventory", "core"), ("inventory", [1]), ("event_id", 3)]:
            self.assertIsNone(cs.validate_snapshot({**VALID, key: value})[0], key)

    def test_rejects_non_object(self):
        self.assertIsNone(cs.validate_snapshot([1, 2])[0])

    def test_clean_line_strips_markup_and_quotes(self):
        self.assertEqual(cs.clean_line('  "**Hello**  [b]there[/b] <i>you</i>"  '), "Hello there you")

    def test_clean_line_caps_length_on_word_boundary(self):
        line = cs.clean_line("word " * 100)
        self.assertLessEqual(len(line), cs.MAX_LINE)
        self.assertTrue(line.endswith("…"))


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), cs.Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def post(self, body: bytes):
        req = urllib.request.Request(self.base + "/companion", data=body,
                                     headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_mock_reply_echoes_ids(self):
        cs.MOCK = True
        code, data = self.post(json.dumps(VALID).encode())
        self.assertEqual(code, 200)
        self.assertEqual((data["run_id"], data["state_version"], data["event_id"]), (1042, 3, "help#4"))
        self.assertEqual(data["source"], "mock")
        self.assertTrue(0 < len(data["line"]) <= 180)

    def test_bad_json_is_400(self):
        code, _ = self.post(b"{not json")
        self.assertEqual(code, 400)

    def test_missing_field_is_400(self):
        code, data = self.post(json.dumps({"run_id": 1}).encode())
        self.assertEqual(code, 400)
        self.assertIn("missing", data["error"])

    def test_model_failure_is_502_not_a_fake_line(self):
        cs.MOCK = False
        old_url, old_timeout = cs.API_URL, cs.MODEL_TIMEOUT
        cs.API_URL, cs.MODEL_TIMEOUT = "http://127.0.0.1:9/v1/messages", 0.5  # nothing listens on port 9
        try:
            code, data = self.post(json.dumps(VALID).encode())
        finally:
            cs.API_URL, cs.MODEL_TIMEOUT, cs.MOCK = old_url, old_timeout, True
        self.assertEqual(code, 502)
        self.assertNotIn("line", data)

    def test_health(self):
        with urllib.request.urlopen(self.base + "/health", timeout=5) as r:
            self.assertTrue(json.loads(r.read())["ok"])


if __name__ == "__main__":
    unittest.main()
