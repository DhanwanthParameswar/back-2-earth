"""Accounts, runs, and the leaderboard for Back2Earth. Owner: C.

Storage is Tiger Cloud (PostgreSQL + TimescaleDB); see server/schema.sql.
`Service` holds the rules and returns (http_code, payload); `Store` is the only
code that talks SQL. Tests swap Store for an in-memory fake.

Rules:
- Playing needs no account. Each device sends a random guest_id, and guest wins
  go on the leaderboard as "Guest" + its first 4 characters. Creating an account
  (or logging in) right after a guest win claims that run under the username.
- Passwords: scrypt hashes only. Login has a per-username lockout.
- Run time is measured by the server clock (start -> end), each run ends once,
  and a win faster than MIN_WIN_SECONDS is refused.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import re
import secrets
import threading
import time

try:
    import psycopg
except ImportError:  # tests and local runs without Postgres
    psycopg = None

USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")
RESERVED = {"admin", "administrator", "guest", "anonymous", "echo", "crewmate", "system",
            "moderator", "root", "back2earth"}
# Shown publicly on the leaderboard, so refuse names containing these.
BLOCKED_PARTS = ("fuck", "shit", "bitch", "cunt", "nigg", "fag", "rape", "nazi", "hitler", "whore",
                 "slut", "porn", "dick", "pussy", "cock", "penis", "vagina", "retard", "kys")
MIN_PASSWORD, MAX_PASSWORD = 8, 128
# A real win crosses four rooms and waits for a DOWN surge; fast players can do it in ~20 s.
MIN_WIN_SECONDS = 12.0
MAX_RUN_SECONDS = 3 * 3600.0
SESSION_DAYS = 30
MAX_EVENTS = 300
LOGIN_MAX_FAILS = 5
LOGIN_LOCK_SECONDS = 300
CLAIM_WINDOW = "1 hour"
OUTCOMES = ("won", "lost", "quit")
_EVENT_RE = re.compile(r"^[a-z0-9_]{1,32}$")
_SHORT_RE = re.compile(r"^[a-z0-9_]{0,32}$")
_RUN_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{20,64}$")
_GUEST_RE = re.compile(r"^[a-z0-9]{8,32}$")
_SCRYPT_N, _SCRYPT_R, _SCRYPT_P = 2 ** 14, 8, 1


class DbError(Exception):
    """The database is unreachable or refused the query."""


# --- Pure helpers ------------------------------------------------------------------------

def check_username(name: object) -> str:
    """"" if allowed, else a message for the player."""
    if not isinstance(name, str) or not USERNAME_RE.match(name):
        return "Username: 3-16 letters, numbers or _"
    low = name.lower()
    if low in RESERVED or any(part in low for part in BLOCKED_PARTS):
        return "That username isn't allowed"
    return ""


def check_password(password: object) -> str:
    if not isinstance(password, str) or not MIN_PASSWORD <= len(password) <= MAX_PASSWORD:
        return f"Password: at least {MIN_PASSWORD} characters"
    return ""


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=32)
    return "scrypt$%d$%d$%d$%s$%s" % (_SCRYPT_N, _SCRYPT_R, _SCRYPT_P,
                                      base64.b64encode(salt).decode(), base64.b64encode(digest).decode())


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, n, r, p, salt_b64, digest_b64 = stored.split("$")
        if algo != "scrypt":
            return False
        expected = base64.b64decode(digest_b64)
        got = hashlib.scrypt(password.encode("utf-8"), salt=base64.b64decode(salt_b64),
                             n=int(n), r=int(r), p=int(p), dklen=len(expected))
        return hmac.compare_digest(got, expected)
    except (ValueError, TypeError):
        return False


# Checked when the username doesn't exist, so a wrong name takes as long as a wrong password.
_DUMMY_HASH = hash_password(secrets.token_hex(8))


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def guest_name(guest_id: str) -> str:
    """Matches the leaderboard view: Guest + first 4 characters, upper case."""
    return "Guest" + guest_id[:4].upper()


def player_key(account_id: int | None, guest_id: str | None) -> str | None:
    """Matches the leaderboard view's player_key."""
    if account_id is not None:
        return f"a{account_id}"
    return f"g{guest_id}" if guest_id else None


def _whole(value: object, low: int, high: int) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value != int(value):
        return None
    value = int(value)
    return value if low <= value <= high else None


def _number(value: object, low: float, high: float) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if low <= value <= high else None


def _short(value: object, default: str = "") -> str | None:
    if value is None:
        return default
    if not isinstance(value, str) or not _SHORT_RE.match(value):
        return None
    return value


def validate_run_end(data: object) -> tuple[dict | None, str]:
    """Return (cleaned, "") or (None, reason) for a /runs/end body."""
    if not isinstance(data, dict):
        return None, "body must be a JSON object"
    run_token = data.get("run_token")
    if not isinstance(run_token, str) or not _RUN_TOKEN_RE.match(run_token):
        return None, "bad run_token"
    outcome = data.get("outcome")
    if outcome not in OUTCOMES:
        return None, "outcome must be won, lost or quit"
    out = {"run_token": run_token, "outcome": outcome}
    for key in ("debris_hits", "boots_uses", "npc_messages", "objectives_done"):
        value = _whole(data.get(key, 0), 0, 100000)
        if value is None:
            return None, f"{key} must be a whole number"
        out[key] = value
    time_left = _number(data.get("time_left_s", 0), 0, 3600)
    if time_left is None:
        return None, "time_left_s out of range"
    out["time_left_s"] = time_left
    events = data.get("events", [])
    if not isinstance(events, list) or len(events) > MAX_EVENTS:
        return None, f"events must be a list of at most {MAX_EVENTS}"
    clean = []
    for e in events:
        if not isinstance(e, dict):
            return None, "bad event"
        t = _number(e.get("t"), 0, MAX_RUN_SECONDS)
        name = e.get("event")
        room, objective = _short(e.get("room")), _short(e.get("objective"))
        if t is None or not isinstance(name, str) or not _EVENT_RE.match(name) or room is None or objective is None:
            return None, "bad event"
        clean.append((t, name, room or None, objective or None))
    out["events"] = clean
    return out, ""


# --- Postgres ----------------------------------------------------------------------------

class Store:
    """All SQL lives here. One shared connection, serialized by a lock, reconnects once."""

    def __init__(self, url: str) -> None:
        self.url = url
        self._lock = threading.Lock()
        self._conn = None

    def _query(self, sql: str, params: tuple = (), fetch: str = "", many: list | None = None):
        if psycopg is None:
            raise DbError("psycopg is not installed")
        with self._lock:
            for attempt in (1, 2):
                try:
                    if self._conn is None or self._conn.closed:
                        self._conn = psycopg.connect(self.url, autocommit=True, connect_timeout=5)
                    with self._conn.cursor() as cur:
                        if many is not None:
                            cur.executemany(sql, many)
                            return None
                        cur.execute(sql, params)
                        if fetch == "one":
                            return cur.fetchone()
                        if fetch == "all":
                            return cur.fetchall()
                        return cur.rowcount
                except psycopg.errors.UniqueViolation:
                    raise
                except psycopg.OperationalError as exc:
                    self._conn = None
                    if attempt == 2:
                        raise DbError(str(exc)) from exc
                except psycopg.Error as exc:
                    raise DbError(str(exc)) from exc
        return None

    def create_account(self, username: str, password_hash: str) -> int | None:
        """New account id, or None if the username is taken."""
        try:
            row = self._query("INSERT INTO accounts (username, password_hash) VALUES (%s, %s) RETURNING id",
                              (username, password_hash), "one")
        except psycopg.errors.UniqueViolation:
            return None
        return row[0]

    def account_by_name(self, username: str):
        """(id, username, password_hash) or None. Case-insensitive."""
        return self._query("SELECT id, username, password_hash FROM accounts WHERE lower(username) = lower(%s)",
                           (username,), "one")

    def create_session(self, account_id: int) -> str:
        token = secrets.token_urlsafe(32)
        self._query("INSERT INTO sessions (token_hash, account_id, expires_at) "
                    "VALUES (%s, %s, now() + make_interval(days => %s))",
                    (token_hash(token), account_id, SESSION_DAYS))
        return token

    def account_by_token(self, token: str):
        """(id, username) for a live session, or None."""
        return self._query("SELECT a.id, a.username FROM sessions s JOIN accounts a ON a.id = s.account_id "
                           "WHERE s.token_hash = %s AND s.expires_at > now()", (token_hash(token),), "one")

    def delete_session(self, token: str) -> None:
        self._query("DELETE FROM sessions WHERE token_hash = %s", (token_hash(token),))

    def start_run(self, run_token: str, account_id: int | None, guest_id: str | None, suit: str, client: str) -> None:
        self._query("INSERT INTO runs (run_token, account_id, guest_id, suit, client) VALUES (%s, %s, %s, %s, %s)",
                    (run_token, account_id, guest_id, suit or None, client or None))

    def run_info(self, run_token: str):
        """(seconds since start by the server clock, already ended, account_id, guest_id) or None."""
        return self._query("SELECT extract(epoch FROM now() - started_at)::float8, ended_at IS NOT NULL, "
                           "account_id, guest_id FROM runs WHERE run_token = %s", (run_token,), "one")

    def finish_run(self, run: dict, duration: float) -> bool:
        """True if this call ended the run (each run ends once)."""
        count = self._query(
            "UPDATE runs SET ended_at = now(), outcome = %s, duration_s = %s, time_left_s = %s, debris_hits = %s, "
            "boots_uses = %s, npc_messages = %s, objectives_done = %s WHERE run_token = %s AND ended_at IS NULL",
            (run["outcome"], duration, run["time_left_s"], run["debris_hits"], run["boots_uses"],
             run["npc_messages"], run["objectives_done"], run["run_token"]))
        return count == 1

    def add_events(self, run_token: str, events: list) -> None:
        if not events:
            return
        self._query("INSERT INTO events (time, run_token, event, room, objective) "
                    "SELECT r.started_at + make_interval(secs => %s), %s, %s, %s, %s FROM runs r WHERE r.run_token = %s",
                    many=[(t, run_token, name, room, objective, run_token) for t, name, room, objective in events])

    def claim_run(self, run_token: str, account_id: int) -> bool:
        count = self._query(
            "UPDATE runs SET account_id = %s WHERE run_token = %s AND account_id IS NULL "
            f"AND ended_at IS NOT NULL AND ended_at > now() - interval '{CLAIM_WINDOW}'",
            (account_id, run_token))
        return count == 1

    def leaderboard(self, limit: int) -> list:
        rows = self._query("SELECT rank, player, seconds FROM leaderboard ORDER BY rank LIMIT %s", (limit,), "all")
        return [{"rank": int(r[0]), "player": r[1], "seconds": float(r[2])} for r in rows]

    def best_for(self, key: str | None):
        """{"rank", "seconds", "player"} for a player_key, or None if not in the top 100."""
        if not key:
            return None
        row = self._query("SELECT rank, seconds, player FROM leaderboard WHERE player_key = %s", (key,), "one")
        return {"rank": int(row[0]), "seconds": float(row[1]), "player": row[2]} if row else None


# --- Rules -------------------------------------------------------------------------------

class Service:
    """The account/run/leaderboard endpoints. Each method returns (http_code, payload).
    May raise DbError (the caller answers 503)."""

    def __init__(self, store) -> None:
        self.store = store
        self._lock = threading.Lock()
        self._fails: dict[str, list] = {}  # lower(username) -> [fail count, locked until]

    # Login lockout ----------------------------------------------------------------------
    def _locked_for(self, key: str) -> float:
        with self._lock:
            fails, until = self._fails.get(key, (0, 0.0))
            return max(0.0, until - time.monotonic())

    def _note_fail(self, key: str) -> None:
        with self._lock:
            if len(self._fails) > 10000:
                self._fails.clear()
            fails, until = self._fails.get(key, (0, 0.0))
            fails += 1
            if fails >= LOGIN_MAX_FAILS:
                self._fails[key] = [0, time.monotonic() + LOGIN_LOCK_SECONDS]
            else:
                self._fails[key] = [fails, until]

    def _clear_fails(self, key: str) -> None:
        with self._lock:
            self._fails.pop(key, None)

    def _account(self, token: str):
        return self.store.account_by_token(token) if token else None

    # Endpoints --------------------------------------------------------------------------
    def register(self, data: object) -> tuple[int, dict]:
        if not isinstance(data, dict):
            return 400, {"error": "invalid", "message": "Bad request"}
        username, password = data.get("username"), data.get("password")
        problem = check_username(username) or check_password(password)
        if problem:
            return 400, {"error": "invalid", "message": problem}
        account_id = self.store.create_account(username, hash_password(password))
        if account_id is None:
            return 409, {"error": "taken", "message": "That username is taken"}
        return 200, {"username": username, "token": self.store.create_session(account_id)}

    def login(self, data: object) -> tuple[int, dict]:
        if not isinstance(data, dict) or not isinstance(data.get("username"), str) \
                or not isinstance(data.get("password"), str) or len(data["password"]) > MAX_PASSWORD:
            return 400, {"error": "invalid", "message": "Enter a username and password"}
        username, password = data["username"].strip(), data["password"]
        key = username.lower()
        wait = self._locked_for(key)
        if wait > 0:
            return 429, {"error": "locked", "message": f"Too many tries. Wait {int(wait) + 1} s", "retry_after": int(wait) + 1}
        row = self.store.account_by_name(username) if USERNAME_RE.match(username) else None
        ok = verify_password(password, row[2] if row else _DUMMY_HASH) and row is not None
        if not ok:
            self._note_fail(key)
            return 401, {"error": "wrong", "message": "Wrong username or password"}
        self._clear_fails(key)
        return 200, {"username": row[1], "token": self.store.create_session(row[0])}

    def logout(self, token: str) -> tuple[int, dict]:
        if token:
            self.store.delete_session(token)
        return 200, {"ok": True}

    def me(self, token: str) -> tuple[int, dict]:
        account = self._account(token)
        if account is None:
            return 401, {"error": "not_logged_in"}
        return 200, {"username": account[1], "best": self.store.best_for(player_key(account[0], None))}

    def start_run(self, data: object, token: str) -> tuple[int, dict]:
        data = data if isinstance(data, dict) else {}
        suit, client = _short(data.get("suit")), _short(data.get("client"))
        if suit is None or client is None:
            return 400, {"error": "invalid", "message": "bad suit or client"}
        guest_id = data.get("guest_id")
        if guest_id is not None and (not isinstance(guest_id, str) or not _GUEST_RE.match(guest_id)):
            return 400, {"error": "invalid", "message": "bad guest_id"}
        account = self._account(token)
        run_token = secrets.token_urlsafe(24)
        self.store.start_run(run_token, account[0] if account else None, guest_id, suit, client)
        name = account[1] if account else (guest_name(guest_id) if guest_id else None)
        return 200, {"run_token": run_token, "username": account[1] if account else None, "player": name}

    def end_run(self, data: object) -> tuple[int, dict]:
        run, reason = validate_run_end(data)
        if run is None:
            return 400, {"error": "invalid", "message": reason}
        info = self.store.run_info(run["run_token"])
        if info is None:
            return 404, {"error": "unknown_run"}
        age, ended, account_id, guest_id = info
        if ended:
            return 409, {"error": "already_ended"}
        if age > MAX_RUN_SECONDS:
            return 400, {"error": "too_old"}
        if run["outcome"] == "won" and age < MIN_WIN_SECONDS:
            return 400, {"error": "implausible", "message": "That was faster than possible"}
        if not self.store.finish_run(run, round(age, 2)):
            return 409, {"error": "already_ended"}
        self.store.add_events(run["run_token"], run["events"])
        key = player_key(account_id, guest_id)
        best = self.store.best_for(key) if run["outcome"] == "won" else None
        return 200, {"outcome": run["outcome"], "duration_s": round(age, 1),
                     "saved_to_account": account_id is not None, "best": best,
                     "player": best["player"] if best else None}

    def claim_run(self, data: object, token: str) -> tuple[int, dict]:
        account = self._account(token)
        if account is None:
            return 401, {"error": "not_logged_in"}
        run_token = data.get("run_token") if isinstance(data, dict) else None
        if not isinstance(run_token, str) or not _RUN_TOKEN_RE.match(run_token):
            return 400, {"error": "invalid", "message": "bad run_token"}
        if not self.store.claim_run(run_token, account[0]):
            return 409, {"error": "cannot_claim", "message": "This run can't be saved any more"}
        return 200, {"username": account[1], "best": self.store.best_for(player_key(account[0], None))}

    def leaderboard(self, limit: int, token: str) -> tuple[int, dict]:
        entries = self.store.leaderboard(max(1, min(limit, 20)))
        me = None
        account = self._account(token)
        if account is not None:
            me = {"username": account[1], "best": self.store.best_for(player_key(account[0], None))}
        return 200, {"entries": entries, "me": me}
