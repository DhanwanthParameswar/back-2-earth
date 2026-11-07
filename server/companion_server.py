#!/usr/bin/env python3
"""ECHO companion backend for Back2Earth. Owner: C.

Standard library only — no pip install needed.

    # Mock mode (no key, no cost): answers with canned lines labeled "mock".
    python3 server/companion_server.py

    # Live mode: the key stays in this process's environment, never in Godot.
    export ANTHROPIC_API_KEY=sk-...          # set a spending limit first!
    python3 server/companion_server.py

POST /companion   body = game state snapshot (see README "Companion contract")
                  200 -> {"run_id", "state_version", "event_id", "line", "source"}
                  400 -> malformed snapshot, 502 -> model failed (game shows fallback)
GET  /health      -> {"ok": true, "mode": "live"|"mock"}

The server only ever returns a short line of flavor text. It cannot change
game state; the game validates the shape and the ids before showing anything.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("COMPANION_HOST", "127.0.0.1")
PORT = int(os.environ.get("COMPANION_PORT", "8787"))
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
MODEL = os.environ.get("COMPANION_MODEL", "claude-haiku-5-5")
API_URL = os.environ.get("COMPANION_API_URL", "https://api.anthropic.com/v1/messages")
API_VERSION = os.environ.get("ANTHROPIC_VERSION", "2026-10-21")
MOCK = os.environ.get("COMPANION_MOCK", "") == "1" or not API_KEY
# The game gives up after 3 s, so the model gets a little less than that.
MODEL_TIMEOUT = float(os.environ.get("COMPANION_MODEL_TIMEOUT", "2.5"))
MAX_LINE = 180
MAX_BODY = 4096

SNAPSHOT_FIELDS = {
    "run_id": int,
    "state_version": int,
    "event_id": str,
    "room_id": str,
    "objective_id": str,
    "time_band": str,
    "inventory": list,
    "recent_event": str,
    "boots_use_count": int,
    "canonical_hint": str,
}

ECHO_SYSTEM_PROMPT = """You are ECHO, the damaged onboard AI of a spaceship tumbling toward a black hole.
The player is the last crew member trying to reach the escape pod.
Personality: dry, deadpan humor; glitchy; increasingly protective of the player.

You receive a JSON snapshot of the game. Reply with ONE short spoken line reacting to
recent_event, in character.

Hard rules:
- Maximum 25 words and 160 characters. Plain text only: no markdown, quotes, emojis, or stage directions.
- Never invent objectives, items, doors, codes, timers, or places. Never promise anything happens.
- If you give direction, only paraphrase canonical_hint. If unsure, give no direction.
- Do not mention JSON, snapshots, games, or players. Speak to "you".
- time_band is how much evacuation time is left: plenty, ok, low, critical, or not_started."""

MOCK_LINES = {
    "run_start": "Mock ECHO here. The real one is saving tokens. Terminal first.",
    "help": "Mock hint: read the objective at the top. It is always right. I am sometimes.",
    "debris_hit_repeat": "Mock ECHO notes repeated impacts. Boots. Space bar. Please.",
}
MOCK_DEFAULT = "Mock ECHO acknowledges the event. The live model would be funnier."

_MARKUP = re.compile(r"\[[^\]]*\]|<[^>]*>|[*`#]")
_SPACES = re.compile(r"\s+")


def validate_snapshot(data: object) -> tuple[dict | None, str]:
    """Return (snapshot, "") if valid, else (None, reason)."""
    if not isinstance(data, dict):
        return None, "body must be a JSON object"
    for key, kind in SNAPSHOT_FIELDS.items():
        if key not in data:
            return None, f"missing field: {key}"
        value = data[key]
        if kind is int:
            # JSON numbers may arrive as 3.0 from some clients.
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value != int(value):
                return None, f"{key} must be an integer"
        elif not isinstance(value, kind):
            return None, f"{key} must be {kind.__name__}"
    if not all(isinstance(i, str) for i in data["inventory"]):
        return None, "inventory must be a list of strings"
    return data, ""


def clean_line(text: str) -> str:
    """Strip markup and quotes, collapse whitespace, cap at MAX_LINE on a word boundary."""
    line = _SPACES.sub(" ", _MARKUP.sub("", text)).strip().strip("\"'“”").strip()
    if len(line) > MAX_LINE:
        cut = line[: MAX_LINE - 1].rsplit(" ", 1)[0].rstrip(",;:")
        line = cut + "…"
    return line


def call_model(snapshot: dict) -> str:
    """Ask the model for one line. Raises on any failure."""
    body = {
        "model": MODEL,
        "max_tokens": 80,
        "system": ECHO_SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": json.dumps(snapshot, sort_keys=True)}],
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "x-api-key": API_KEY,
            "anthropic-version": API_VERSION,
            "content-type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=MODEL_TIMEOUT) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    parts = [b.get("text", "") for b in payload.get("content", []) if b.get("type") == "text"]
    line = clean_line(" ".join(parts))
    if not line:
        raise ValueError("model returned no text")
    return line


def make_reply(snapshot: dict) -> tuple[int, dict]:
    ids = {k: snapshot[k] for k in ("run_id", "state_version", "event_id")}
    ids["run_id"] = int(ids["run_id"])
    ids["state_version"] = int(ids["state_version"])
    if MOCK:
        line = MOCK_LINES.get(snapshot["recent_event"], MOCK_DEFAULT)
        return 200, {**ids, "line": clean_line(line), "source": "mock"}
    try:
        return 200, {**ids, "line": call_model(snapshot), "source": "model"}
    except (urllib.error.URLError, TimeoutError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"[companion] model call failed: {exc!r}", file=sys.stderr)
        return 502, {"error": "model_unavailable"}


class Handler(BaseHTTPRequestHandler):
    server_version = "EchoCompanion/1.0"

    def _send(self, code: int, payload: dict) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        # CORS so a browser (web export) build can call us.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self) -> None:  # noqa: N802 (http.server naming)
        self._send(204, {})

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._send(200, {"ok": True, "mode": "mock" if MOCK else "live", "model": None if MOCK else MODEL})
        else:
            self._send(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/companion":
            self._send(404, {"error": "not_found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            self._send(400, {"error": "bad_length"})
            return
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send(400, {"error": "invalid_json"})
            return
        snapshot, reason = validate_snapshot(data)
        if snapshot is None:
            self._send(400, {"error": reason})
            return
        code, payload = make_reply(snapshot)
        self._send(code, payload)

    def log_message(self, fmt: str, *args) -> None:
        print(f"[companion] {self.address_string()} {fmt % args}", file=sys.stderr)


def main() -> None:
    mode = "MOCK (canned lines)" if MOCK else f"LIVE (model {MODEL})"
    print(f"ECHO companion on http://{HOST}:{PORT}/companion — {mode}")
    if MOCK and not API_KEY:
        print("  No ANTHROPIC_API_KEY set; running in mock mode.")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
