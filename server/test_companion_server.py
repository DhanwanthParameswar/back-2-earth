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


NPC_VALID = {
    "npc_id": "crewmate", "run_id": 1042, "message": "  do you have any   instructions? ",
    "history": [{"role": "player", "text": "hi"}, {"role": "npc", "text": "Hey. Stay close."}],
    "objective_id": "start_evacuation", "canonical_hint": "Use the cockpit terminal (E).",
    "room_id": "cockpit", "time_band": "not_started",
}


class NpcValidationTests(unittest.TestCase):
    def test_valid_request_is_trimmed(self):
        req, reason = cs.validate_npc_request(dict(NPC_VALID))
        self.assertIsNotNone(req, reason)
        self.assertEqual(req["message"], "do you have any instructions?")

    def test_rejects_bad_requests(self):
        for key, value in [("npc_id", "pirate"), ("run_id", "1"), ("message", ""), ("message", "x" * 201),
                           ("message", 5), ("history", "hi"), ("history", [{"role": "system", "text": "x"}]),
                           ("history", [{"role": "player", "text": "x"}] * 9)]:
            self.assertIsNone(cs.validate_npc_request({**NPC_VALID, key: value})[0], key)

    def test_gemini_request_shape(self):
        sent = {}

        def fake_post(url, body, headers, timeout):
            sent.update(url=url, body=body, headers=headers)
            return {"candidates": [{"content": {"parts": [{"text": "Terminal first, then power."}]}}]}

        old = (cs.PROVIDER, cs.GEMINI_API_KEY, cs._post_json, cs.LIMITS)
        cs.PROVIDER, cs.GEMINI_API_KEY, cs._post_json, cs.LIMITS = "gemini", "test-key", fake_post, cs.Limits()
        try:
            text = cs.generate_text("sys", [("user", "a"), ("user", "b"), ("model", "c"), ("user", "d")], 50, 1)
        finally:
            cs.PROVIDER, cs.GEMINI_API_KEY, cs._post_json, cs.LIMITS = old
        self.assertEqual(text, "Terminal first, then power.")
        self.assertIn(cs.GEMINI_MODEL, sent["url"])
        self.assertEqual(sent["headers"]["x-goog-api-key"], "test-key")
        roles = [c["role"] for c in sent["body"]["contents"]]
        self.assertEqual(roles, ["user", "model", "user"], "same-role turns are merged")
        self.assertEqual(sent["body"]["systemInstruction"]["parts"][0]["text"], "sys")

    def test_daily_caps(self):
        old = (cs.TEXT_CALLS_PER_DAY, cs.TTS_CHARS_PER_DAY)
        cs.TEXT_CALLS_PER_DAY, cs.TTS_CHARS_PER_DAY = 1, 10
        try:
            limits = cs.Limits()
            self.assertTrue(limits.spend_text_call())
            self.assertFalse(limits.spend_text_call())
            self.assertTrue(limits.spend_tts(10))
            self.assertFalse(limits.spend_tts(1))
        finally:
            cs.TEXT_CALLS_PER_DAY, cs.TTS_CHARS_PER_DAY = old

    def test_token_bucket(self):
        limits = cs.Limits()
        burst = cs.Limits.BUCKETS["npc"][0]
        for _ in range(burst):
            self.assertEqual(limits.allow("npc", "1.2.3.4"), 0.0)
        self.assertGreater(limits.allow("npc", "1.2.3.4"), 0.0)
        self.assertEqual(limits.allow("npc", "5.6.7.8"), 0.0, "other clients are separate")

    def test_audio_store_synthesizes_once(self):
        calls = []
        old = cs.synthesize
        cs.synthesize = lambda text, voice_id=None: calls.append(text) or b"ID3" + b"x" * 300
        try:
            store = cs.AudioStore(2)
            key = store.register("voice", "Hello there.")
            self.assertEqual(store.get_mp3(key)[:3], b"ID3")
            store.get_mp3(key)
            self.assertEqual(calls, ["Hello there."], "cached after the first request")
            self.assertIsNone(store.get_mp3("0" * 20), "unknown ids are refused")
            store.register("voice", "b")
            store.register("voice", "c")
            self.assertIsNone(store.get_mp3(key), "oldest line evicted")
        finally:
            cs.synthesize = old


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), cs.Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def setUp(self):
        cs.LIMITS = cs.Limits()  # fresh rate limits per test

    def post(self, body: bytes, path: str = "/companion"):
        req = urllib.request.Request(self.base + path, data=body,
                                     headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_npc_mock_reply(self):
        cs.MOCK = True
        code, data = self.post(json.dumps(NPC_VALID).encode(), "/npc/talk")
        self.assertEqual(code, 200)
        self.assertEqual((data["npc_id"], data["source"], data["audio_url"]), ("crewmate", "mock", None))
        self.assertIn("cockpit terminal", data["line"])
        self.assertLessEqual(len(data["line"]), cs.MAX_NPC_LINE)

    def test_npc_bad_request_is_400(self):
        code, data = self.post(json.dumps({**NPC_VALID, "npc_id": "pirate"}).encode(), "/npc/talk")
        self.assertEqual((code, data["error"]), (400, "unknown npc_id"))

    def test_npc_rate_limited_is_429(self):
        cs.MOCK = True
        codes = [self.post(json.dumps(NPC_VALID).encode(), "/npc/talk")[0] for _ in range(8)]
        self.assertEqual(codes[0], 200)
        self.assertEqual(codes[-1], 429)

    def test_unknown_audio_is_404(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(self.base + "/npc/audio/" + "a" * 20 + ".mp3", timeout=5)
        self.assertEqual(ctx.exception.code, 404)

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
