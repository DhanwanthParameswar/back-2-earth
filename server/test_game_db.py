"""Tests for accounts, runs, and the leaderboard, against an in-memory fake database.
Run: python3 -m unittest server/test_game_db.py"""
import copy
import json
import secrets
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import companion_server as cs  # noqa: E402
import game_db  # noqa: E402


class FakeStore:
    """Same interface as game_db.Store, in memory. `clock` is the server time in seconds."""

    def __init__(self):
        self.clock = 1000.0
        self.accounts = {}   # id -> {"username", "hash"}
        self.sessions = {}   # token -> account id
        self.runs = {}       # run_token -> dict
        self.events = []
        self.saves = {}

    def create_account(self, username, password_hash):
        if any(a["username"].lower() == username.lower() for a in self.accounts.values()):
            return None
        new_id = max(self.accounts, default=0) + 1
        self.accounts[new_id] = {"username": username, "hash": password_hash}
        return new_id

    def account_by_name(self, username):
        for i, a in self.accounts.items():
            if a["username"].lower() == username.lower():
                return (i, a["username"], a["hash"])
        return None

    def create_session(self, account_id):
        token = secrets.token_urlsafe(32)
        self.sessions[token] = account_id
        return token

    def account_by_token(self, token):
        i = self.sessions.get(token)
        return (i, self.accounts[i]["username"]) if i else None

    def delete_session(self, token):
        self.sessions.pop(token, None)

    def delete_account(self, account_id):
        owned = {token for token, run in self.runs.items() if run['account_id'] == account_id}
        self.events = [event for event in self.events if event[0] not in owned]
        self.runs = {token: run for token, run in self.runs.items() if token not in owned}
        self.memory = [row for row in getattr(self, 'memory', []) if row[0] != game_db.player_key(account_id, None)]
        self.saves.pop(account_id, None)
        self.sessions = {token: owner for token, owner in self.sessions.items() if owner != account_id}
        self.accounts.pop(account_id, None)

    def load_save(self, account_id):
        return copy.deepcopy(self.saves.get(account_id, {"snapshot": None, "revision": 0, "updated_at": None}))

    def write_save(self, account_id, snapshot, revision):
        current = self.saves.get(account_id, {"revision": 0})
        if current["revision"] != revision:
            return None
        self.saves[account_id] = {"snapshot": copy.deepcopy(snapshot), "revision": revision + 1, "updated_at": self.clock}
        return {"revision": revision + 1, "updated_at": self.clock}

    def start_run(self, run_token, account_id, guest_id, suit, client):
        self.runs[run_token] = {"account_id": account_id, "guest_id": guest_id, "start": self.clock, "end": None,
                                "outcome": None, "duration": None, "suit": suit}

    def run_info(self, run_token):
        r = self.runs.get(run_token)
        return (self.clock - r["start"], r["end"] is not None, r["account_id"], r["guest_id"]) if r else None

    def finish_run(self, run, duration):
        r = self.runs[run["run_token"]]
        if r["end"] is not None:
            return False
        r.update(end=self.clock, outcome=run["outcome"], duration=duration)
        return True

    def add_events(self, run_token, events):
        self.events.extend((run_token,) + tuple(e) for e in events)

    def claim_run(self, run_token, account_id):
        r = self.runs.get(run_token)
        if not r or r["account_id"] is not None or r["end"] is None or self.clock - r["end"] > 3600:
            return False
        r["account_id"] = account_id
        return True

    def _board(self):
        best = {}  # player_key -> (duration, display name)
        for r in self.runs.values():
            key = game_db.player_key(r["account_id"], r["guest_id"])
            if r["outcome"] == "won" and key:
                name = self.accounts[r["account_id"]]["username"] if r["account_id"] else game_db.guest_name(r["guest_id"])
                if key not in best or r["duration"] < best[key][0]:
                    best[key] = (r["duration"], name)
        ordered = sorted(best.items(), key=lambda kv: kv[1][0])
        return [{"rank": n + 1, "key": k, "player": name, "seconds": round(d, 1)}
                for n, (k, (d, name)) in enumerate(ordered)]

    def npc_memory(self, player_key, npc_id, turns=8, notes=12):
        rows = [r for r in getattr(self, "memory", []) if r[0] == player_key and r[1] == npc_id]
        t = [{"role": r[3], "text": r[4]} for r in rows if r[2] == "turn"][-turns:]
        n = [r[4] for r in rows if r[2] == "note"][-notes:]
        return {"turns": t, "notes": n}

    def npc_remember(self, player_key, npc_id, rows):
        self.memory = getattr(self, "memory", []) + [(player_key, npc_id, k, role, text) for k, role, text in rows]

    def leaderboard(self, limit):
        return [{k: e[k] for k in ("rank", "player", "seconds")} for e in self._board()[:limit]]

    def best_for(self, key):
        for e in self._board():
            if e["key"] == key:
                return {"rank": e["rank"], "seconds": e["seconds"], "player": e["player"]}
        return None


def end_body(run_token, outcome="won", **extra):
    return {"run_token": run_token, "outcome": outcome, "time_left_s": 120.5, "debris_hits": 2,
            "boots_uses": 4, "npc_messages": 1, "objectives_done": 6,
            "events": [{"t": 3.5, "event": "debris_hit", "room": "cargo", "objective": "open_compartment"}], **extra}


class HelperTests(unittest.TestCase):
    def test_usernames(self):
        for ok in ("Kien", "kien_vo", "abc", "A" * 16):
            self.assertEqual(game_db.check_username(ok), "", ok)
        for bad in ("ab", "a" * 17, "has space", "émile", "", None, 5, "admin", "Guest", "xXfuckXx"):
            self.assertNotEqual(game_db.check_username(bad), "", bad)

    def test_passwords(self):
        self.assertEqual(game_db.check_password("longenough"), "")
        for bad in ("short", "", None, "x" * 129):
            self.assertNotEqual(game_db.check_password(bad), "")

    def test_hash_roundtrip(self):
        stored = game_db.hash_password("correct horse")
        self.assertTrue(stored.startswith("scrypt$"))
        self.assertNotIn("correct horse", stored)
        self.assertTrue(game_db.verify_password("correct horse", stored))
        self.assertFalse(game_db.verify_password("wrong horse", stored))
        self.assertNotEqual(stored, game_db.hash_password("correct horse"), "salted")
        self.assertFalse(game_db.verify_password("x", "garbage"))

    def test_validate_run_end(self):
        good, reason = game_db.validate_run_end(end_body("t" * 32))
        self.assertIsNotNone(good, reason)
        self.assertEqual(good["events"], [(3.5, "debris_hit", "cargo", "open_compartment")])
        for key, value in [("run_token", "short"), ("outcome", "cheated"), ("debris_hits", -1),
                           ("debris_hits", 1.5), ("time_left_s", 9999), ("events", "x"),
                           ("events", [{"t": 1, "event": "DROP TABLE"}]), ("events", [{"event": "x"}] * 301)]:
            self.assertIsNone(game_db.validate_run_end({**end_body("t" * 32), key: value})[0], key)


class SaveValidationTests(unittest.TestCase):
    def test_checkpoint_memory_bounds_and_legacy_compatibility(self):
        import save_games
        checkpoint = json.loads((Path(__file__).parent / "fixtures/checkpoint.json").read_text())
        self.assertTrue(save_games.valid(checkpoint))
        checkpoint['memory_notes'] = {'mara': ['Johnny wants to save the samples'], 'ivo': []}
        self.assertTrue(save_games.valid(checkpoint))
        for bad in ([], {'mara': 'fact'}, {'mara': ['x'] * 13}, {'mara': ['x' * 121]}, {'mara': [None]}, {'pirate': []}):
            self.assertFalse(save_games.valid({**checkpoint, 'memory_notes': bad}), bad)

    def test_corrupt_and_oversized_snapshots_are_rejected(self):
        import save_games
        checkpoint = json.loads((Path(__file__).parent / "fixtures/checkpoint.json").read_text())
        self.assertTrue(save_games.valid(checkpoint))
        for field, value in (("elapsed", float("nan")), ("elapsed", float("inf")), ("crew", []), ("schema", 999), ("player", {"position": [-1, 3]}), ("state", {}), ("history", {"mara": [{"role": "system", "text": "inject"}]})):
            with self.subTest(field=field):
                self.assertFalse(save_games.valid({**checkpoint, field: value}))
        unicode_save = copy.deepcopy(checkpoint)
        unicode_save["history"]["mara"] = [{"role": "npc", "text": "🚀" * 420}] * 6
        self.assertTrue(save_games.valid(unicode_save), "Bound real UTF-8 data rather than expanded Unicode escapes")
        broken = copy.deepcopy(checkpoint)
        broken["crew"]["mara"]["path"] = [[1, 2]] * 301
        self.assertFalse(save_games.valid(broken))
        broken = copy.deepcopy(checkpoint)
        broken["state"]["flags"]["departed"] = True
        self.assertFalse(save_games.valid(broken))


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.store = FakeStore()
        self.svc = game_db.Service(self.store)

    def register(self, name="Kien", password="password123"):
        return self.svc.register({"username": name, "password": password})

    def test_register_and_login(self):
        code, data = self.register()
        self.assertEqual((code, data["username"]), (200, "Kien"))
        self.assertTrue(data["token"])
        self.assertEqual(self.register("kien")[0], 409, "usernames are case-insensitive unique")
        self.assertEqual(self.register("ok_name", "short")[0], 400)
        code, data = self.svc.login({"username": "KIEN", "password": "password123"})
        self.assertEqual((code, data["username"]), (200, "Kien"))
        self.assertEqual(self.svc.login({"username": "Kien", "password": "nope-nope"})[0], 401)
        self.assertEqual(self.svc.login({"username": "nobody", "password": "password123"})[0], 401)

    def test_login_lockout(self):
        self.register()
        for _ in range(game_db.LOGIN_MAX_FAILS):
            self.assertEqual(self.svc.login({"username": "Kien", "password": "wrong-pass"})[0], 401)
        code, data = self.svc.login({"username": "Kien", "password": "password123"})
        self.assertEqual(code, 429, "locked even with the right password")
        self.assertGreater(data["retry_after"], 0)

    def test_guest_win_then_claim(self):
        start = self.svc.start_run({"suit": "hazard", "client": "web", "guest_id": "a3f9c2d1e0"}, "")[1]
        self.assertEqual(start["player"], "GuestA3F9")
        rt = start["run_token"]
        self.store.clock += 95
        code, data = self.svc.end_run(end_body(rt))
        self.assertEqual(code, 200)
        self.assertEqual((data["duration_s"], data["saved_to_account"], data["player"]), (95.0, False, "GuestA3F9"))
        self.assertEqual(self.svc.leaderboard(10, "")[1]["entries"], [{"rank": 1, "player": "GuestA3F9", "seconds": 95.0}],
                         "guest wins are on the leaderboard as GuestXXXX")
        token = self.register()[1]["token"]
        code, data = self.svc.claim_run({"run_token": rt}, token)
        self.assertEqual((code, data["best"]), (200, {"rank": 1, "seconds": 95.0, "player": "Kien"}))
        self.assertEqual(self.svc.claim_run({"run_token": rt}, token)[0], 409, "claim once")
        board = self.svc.leaderboard(10, token)[1]
        self.assertEqual(board["entries"], [{"rank": 1, "player": "Kien", "seconds": 95.0}], "claimed: moved to the username")
        self.assertEqual(board["me"]["best"]["rank"], 1)

    def test_guest_best_time_per_device(self):
        for secs in (120, 90, 200):
            rt = self.svc.start_run({"guest_id": "beef0001"}, "")[1]["run_token"]
            self.store.clock += secs
            self.svc.end_run(end_body(rt))
        rt = self.svc.start_run({"guest_id": "cafe0002"}, "")[1]["run_token"]
        self.store.clock += 100
        self.svc.end_run(end_body(rt))
        rt = self.svc.start_run({}, "")[1]["run_token"]  # no guest id at all: stats only
        self.store.clock += 50
        self.assertIsNone(self.svc.end_run(end_body(rt))[1]["best"])
        entries = self.svc.leaderboard(10, "")[1]["entries"]
        self.assertEqual([(e["player"], e["seconds"]) for e in entries], [("GuestBEEF", 90.0), ("GuestCAFE", 100.0)])

    def test_bad_guest_id(self):
        self.assertEqual(self.svc.start_run({"guest_id": "BAD ID!"}, "")[0], 400)

    def test_logged_in_runs_and_ranking(self):
        a = self.register("Alice")[1]["token"]
        b = self.register("Bob_2")[1]["token"]
        for token, secs in ((a, 120), (b, 80), (a, 70), (a, 300)):
            rt = self.svc.start_run({}, token)[1]["run_token"]
            self.store.clock += secs
            self.assertEqual(self.svc.end_run(end_body(rt))[0], 200)
        entries = self.svc.leaderboard(10, "")[1]["entries"]
        self.assertEqual([(e["player"], e["seconds"]) for e in entries], [("Alice", 70.0), ("Bob_2", 80.0)],
                         "one best time per player")

    def test_anti_cheat(self):
        rt = self.svc.start_run({}, "")[1]["run_token"]
        self.store.clock += 5
        self.assertEqual(self.svc.end_run(end_body(rt))[1]["error"], "implausible", "a 5 s win is refused")
        self.assertEqual(self.svc.end_run(end_body(rt, outcome="lost"))[0], 200, "losing fast is fine")
        self.assertEqual(self.svc.end_run(end_body(rt))[0], 409, "a run ends once")
        self.assertEqual(self.svc.end_run(end_body("x" * 32))[0], 404, "unknown run")

    def test_fast_real_run_is_accepted(self):
        """The website bug #2: a genuine ~20-25 s speedrun was refused by the old 30 s minimum."""
        rt = self.svc.start_run({"guest_id": "speed001"}, "")[1]["run_token"]
        self.store.clock += 22
        code, data = self.svc.end_run(end_body(rt))
        self.assertEqual((code, data["duration_s"], data["player"]), (200, 22.0, "GuestSPEE"))

    def test_time_comes_from_server_clock(self):
        rt = self.svc.start_run({}, "")[1]["run_token"]
        self.store.clock += 200
        data = self.svc.end_run(end_body(rt, duration_s=1, time_left_s=359))[1]
        self.assertEqual(data["duration_s"], 200.0, "client can't send its own duration")

    def test_claim_needs_login_and_finished_run(self):
        rt = self.svc.start_run({}, "")[1]["run_token"]
        token = self.register()[1]["token"]
        self.assertEqual(self.svc.claim_run({"run_token": rt}, "")[0], 401)
        self.assertEqual(self.svc.claim_run({"run_token": rt}, token)[0], 409, "unfinished runs can't be claimed")

    def test_logout(self):
        token = self.register()[1]["token"]
        self.assertEqual(self.svc.me(token)[0], 200)
        self.svc.logout(token)
        self.assertEqual(self.svc.me(token)[0], 401)


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), cs.Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def setUp(self):
        self.store = FakeStore()
        self.old_game = cs.GAME
        cs.GAME = game_db.Service(self.store)
        cs.LIMITS = cs.Limits()

    def tearDown(self):
        cs.GAME = self.old_game

    def call(self, path, body=None, token=""):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, headers=headers, method="POST" if data else "GET")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_full_flow_over_http(self):
        code, run = self.call("/runs/start", {"suit": "mint", "client": "web"})
        self.assertEqual(code, 200)
        self.store.clock += 61
        self.assertEqual(self.call("/runs/end", end_body(run["run_token"]))[0], 200)
        code, acct = self.call("/auth/register", {"username": "Kien", "password": "password123"})
        self.assertEqual(code, 200)
        self.assertEqual(self.call("/runs/claim", {"run_token": run["run_token"]}, acct["token"])[0], 200)
        code, board = self.call("/leaderboard?limit=5", token=acct["token"])
        self.assertEqual((code, board["entries"][0]["player"], board["me"]["best"]["seconds"]), (200, "Kien", 61.0))
        self.assertEqual(self.call("/auth/me", token=acct["token"])[1]["username"], "Kien")
        self.assertEqual(self.call("/auth/logout", {}, acct["token"])[0], 200)
        self.assertEqual(self.call("/auth/me", token=acct["token"])[0], 401)

    def test_delete_account_requires_password_and_removes_only_owned_data(self):
        checkpoint = json.loads((Path(__file__).parent / 'fixtures/checkpoint.json').read_text())
        alice = self.call('/auth/register', {'username': 'DeleteAlice', 'password': 'password123'})[1]['token']
        bob = self.call('/auth/register', {'username': 'KeepBob', 'password': 'password123'})[1]['token']
        second_session = self.store.create_session(1)
        for token in (alice, bob):
            self.assertEqual(self.call('/save', {'snapshot': checkpoint, 'revision': 0}, token)[0], 200)
            run = cs.GAME.start_run({}, token)[1]['run_token']
            self.store.clock += 90
            self.assertEqual(cs.GAME.end_run(end_body(run))[0], 200)
        self.store.npc_remember('a1', 'mara', [('note', None, 'Alice memory')])
        self.store.npc_remember('a2', 'mara', [('note', None, 'Bob memory')])
        self.store.npc_remember('g0123abcd', 'ivo', [('note', None, 'Guest memory')])
        body = {'password': 'password123', 'confirm': True, 'account_id': 2}
        self.assertEqual(self.call('/auth/delete', body)[0], 401)
        self.assertEqual(self.call('/auth/delete', {'password': 'password123'}, alice)[0], 400)
        self.assertEqual(self.call('/auth/delete', {**body, 'password': 'incorrect'}, alice)[0], 401)
        self.assertEqual(self.call('/save', token=alice)[1]['snapshot'], checkpoint)
        self.assertEqual(self.call('/auth/delete', body, alice), (200, {'ok': True}))
        self.assertEqual(self.call('/save', token=second_session)[0], 401)
        self.assertEqual(self.call('/save', {'snapshot': checkpoint, 'revision': 0}, alice)[0], 401)
        self.assertEqual(cs.GAME.login({'username': 'DeleteAlice', 'password': 'password123'})[0], 401)
        self.assertNotIn(1, self.store.saves)
        self.assertNotIn(1, self.store.accounts)
        self.assertTrue(all(r['account_id'] != 1 for r in self.store.runs.values()))
        self.assertTrue(all(event[0] in self.store.runs for event in self.store.events))
        self.assertEqual(self.call('/save', token=bob)[1]['snapshot'], checkpoint)
        self.assertEqual([entry['player'] for entry in self.store.leaderboard(10)], ['KeepBob'])
        self.assertEqual({row[0] for row in self.store.memory}, {'a2', 'g0123abcd'})

    def test_delete_password_failures_are_rate_limited(self):
        token = cs.GAME.register({'username': 'DeleteLock', 'password': 'password123'})[1]['token']
        for _ in range(game_db.LOGIN_MAX_FAILS):
            self.assertEqual(cs.GAME.delete_account({'password': 'incorrect', 'confirm': True}, token)[0], 401)
        self.assertEqual(cs.GAME.delete_account({'password': 'password123', 'confirm': True}, token)[0], 429)
        self.assertEqual(cs.GAME.me(token)[0], 200)

    def test_checkpoint_auth_isolation_conflicts_and_deletion(self):
        with open(Path(__file__).parent / "fixtures/checkpoint.json") as file:
            checkpoint = json.load(file)
        alice = self.call("/auth/register", {"username": "SaveAlice", "password": "password123"})[1]["token"]
        bob = self.call("/auth/register", {"username": "SaveBob", "password": "password123"})[1]["token"]
        self.assertEqual(self.call("/save")[0], 401)
        self.assertEqual(self.call("/save", {"snapshot": checkpoint, "revision": 0})[0], 401)
        self.assertEqual(self.call("/save", {"snapshot": checkpoint, "revision": 0}, alice)[0], 200)
        saved = self.call("/save", token=alice)[1]
        self.assertEqual(saved["snapshot"], checkpoint)
        self.assertEqual(saved["revision"], 1)
        self.assertIsNone(self.call("/save", token=bob)[1]["snapshot"])
        self.assertEqual(self.call("/save", {"snapshot": checkpoint, "revision": 0}, alice)[0], 409)
        self.assertEqual(self.call("/save/delete", {"revision": 0}, alice)[0], 409)
        self.assertEqual(self.call("/save/delete", {"revision": 1}, alice)[0], 200)
        self.assertIsNone(self.call("/save", token=alice)[1]["snapshot"])
        self.assertEqual(self.call("/save", {"snapshot": checkpoint, "revision": 1}, alice)[0], 409, "stale offline device cannot resurrect a deleted save")
        self.assertEqual(self.call("/save", {"snapshot": checkpoint, "revision": 2}, alice)[0], 200)
        self.assertEqual(self.call("/auth/me", token=alice)[0], 200, "deleting progress keeps the account")

    def test_full_size_run_report(self):
        """The website bug: a real run's report (hundreds of events) was over the old 8 KB limit."""
        code, run = self.call("/runs/start", {"suit": "mint", "client": "web", "guest_id": "0123abcd"})
        self.store.clock += 240
        events = [{"t": i * 0.8, "event": "enter_room", "room": "engineering", "objective": "open_compartment"}
                  for i in range(game_db.MAX_EVENTS)]
        body = end_body(run["run_token"], events=events)
        self.assertGreater(len(json.dumps(body)), 8192)
        code, data = self.call("/runs/end", body)
        self.assertEqual((code, data["player"], data["best"]["rank"]), (200, "Guest0123", 1))
        self.assertEqual(len(self.store.events), game_db.MAX_EVENTS)

    def test_each_crewmate_has_its_own_memory(self):
        """Aaron (mara) and Dhan (ivo) remember each player separately; they don't share."""
        import escape_dialogue
        seen = []

        def fake_generate(system, turns, max_tokens, timeout):
            seen.append(turns)
            said = json.loads(turns[-1][1])["message"]
            note = "Johnny wants to save the samples" if "samples" in said else None
            return json.dumps({"line": "Copy that: " + said, "action": "none", **({"remember": note} if note else {})})

        old = (cs.MOCK, cs.generate_text, cs.ELEVEN_API_KEY)
        cs.MOCK, cs.generate_text, cs.ELEVEN_API_KEY = False, fake_generate, ""
        try:
            def talk(npc, msg, guest="beef0001"):
                body = {"npc_id": npc, "state_version": 1, "message": msg, "objective": "Clear the doorway.",
                        "flags": {}, "history": [], "guest_id": guest,
                        "available_actions": {"none": "Answer.", "light_on": "Turn on your flashlight."}}
                code, data = self.call("/escape/talk", body)
                self.assertEqual(code, 200, data)
                self.assertNotIn("_remember", data, "internal field never reaches the game")
                return data

            talk("mara", "I want to save the samples")
            talk("ivo", "turn your flashlight on")
            talk("mara", "what do you remember?")
            mara_ctx = [t[1] for t in seen[2]]
            self.assertIn("I want to save the samples", " ".join(mara_ctx), "Aaron remembers his own conversation")
            self.assertNotIn("turn your flashlight on", " ".join(mara_ctx), "...but not what Johnny told Dhan")
            self.assertIn("Johnny wants to save the samples", mara_ctx[-1], "Aaron's story notes are in his prompt")
            talk("ivo", "what do you remember?")
            ivo_ctx = " ".join(t[1] for t in seen[3])
            self.assertIn("turn your flashlight on", ivo_ctx)
            self.assertNotIn("samples", ivo_ctx, "Dhan doesn't know Aaron's notes")
            talk("mara", "hello", guest="cafe0002")
            self.assertNotIn("samples", " ".join(t[1] for t in seen[4]), "another player starts with a fresh memory")
        finally:
            cs.MOCK, cs.generate_text, cs.ELEVEN_API_KEY = old

    def test_saved_memory_is_authoritative_and_never_written_separately(self):
        seen = []

        def generate(system, turns, *args):
            seen.append(turns)
            return json.dumps({'line': 'Understood.', 'action': 'none', 'remember': 'Johnny prefers repairs'})

        old = (cs.MOCK, cs.generate_text, cs.ELEVEN_API_KEY)
        cs.MOCK, cs.generate_text, cs.ELEVEN_API_KEY = False, generate, ''
        try:
            # Even an older playthrough under the same identity cannot leak in.
            self.store.npc_remember('gbeef0001', 'mara', [('note', None, 'OLD GAME SECRET')])
            original = copy.deepcopy(self.store.memory)
            body = {'npc_id': 'mara', 'state_version': 1, 'message': 'What do you remember?',
                    'objective': 'Clear the doorway.', 'flags': {}, 'guest_id': 'beef0001',
                    'history': [], 'memory_notes': [], 'available_actions': {'none': 'Answer.'}}
            code, result = self.call('/escape/talk', body)
            self.assertEqual(code, 200)
            self.assertEqual(result['memory_note'], 'Johnny prefers repairs')
            self.assertNotIn('OLD GAME SECRET', str(seen[-1]))
            self.assertEqual(self.store.memory, original, 'Replies cannot recreate memory independently of a save')
            body['memory_notes'] = [result['memory_note']]
            body['history'] = [{'role': 'player', 'text': 'Please repair engineering'}]
            self.assertEqual(self.call('/escape/talk', body)[0], 200)
            self.assertIn('Johnny prefers repairs', str(seen[-1]))
            self.assertIn('Please repair engineering', str(seen[-1]))
            body['memory_notes'], body['history'] = [], []
            self.assertEqual(self.call('/escape/talk', body)[0], 200)
            self.assertNotIn('Johnny prefers repairs', str(seen[-1]), 'A new game has no facts from a previous playthrough')
            body['memory_notes'] = ['x' * 121]
            self.assertEqual(self.call('/escape/talk', body)[0], 400)
            self.assertEqual(self.store.memory, original)
        finally:
            cs.MOCK, cs.generate_text, cs.ELEVEN_API_KEY = old

    def test_offline_database_is_503(self):
        cs.GAME = None
        code, data = self.call("/leaderboard")
        self.assertEqual((code, data["error"]), (503, "db_unavailable"))

    def test_database_error_is_503(self):
        def broken(*a, **k):
            raise game_db.DbError("down")
        self.store.leaderboard = broken
        self.assertEqual(self.call("/leaderboard")[0], 503)

    def test_auth_rate_limited(self):
        codes = [self.call("/auth/login", {"username": "x_y_z", "password": "password123"})[0] for _ in range(8)]
        self.assertIn(429, codes)

    def test_cors_allows_authorization(self):
        req = urllib.request.Request(self.base + "/leaderboard", method="OPTIONS")
        with urllib.request.urlopen(req, timeout=5) as r:
            self.assertIn("Authorization", r.headers["Access-Control-Allow-Headers"])


if __name__ == "__main__":
    unittest.main()
