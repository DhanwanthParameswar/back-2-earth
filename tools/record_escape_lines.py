#!/usr/bin/env python3
"""Pre-record every scripted escape line with ElevenLabs (docs/Game Design.md section 9).

Reads data/escape_lines.json and writes assets/voice/escape/<id>.mp3 for the crew's
lines and assets/voice/escape/marvis_<id>.mp3 for M.A.R.V.I.S.'s sentences. The game
plays a file when it exists and shows text alone when it doesn't, so this is optional.

Needs ELEVENLABS_API_KEY (on the team server it's in /etc/back2earth/companion.env):
    set -a; . /etc/back2earth/companion.env; set +a
    python3 tools/record_escape_lines.py            # only lines without a file yet
    python3 tools/record_escape_lines.py --force    # re-record everything
    python3 tools/record_escape_lines.py --only count_one count_two count_three

Voices: AARON_VOICE_ID / DHAN_VOICE_ID (same defaults as the server), MARVIS_VOICE_ID
(defaults to Dhan's voice; pick a flatter one in the ElevenLabs library). After
recording, open the project in Godot once so it imports the new files.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
OUT = ROOT / "assets/voice/escape"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--force", action="store_true", help="re-record lines that already have a file")
    parser.add_argument("--only", nargs="*", help="record just these ids")
    parser.add_argument("--dry-run", action="store_true", help="list what would be recorded")
    args = parser.parse_args()
    import companion_server as server  # noqa: E402  (reads the API key from the environment)
    if not server.ELEVEN_API_KEY and not args.dry_run:
        raise SystemExit("ELEVENLABS_API_KEY is not set.")
    voices = {"aaron": server.AARON_VOICE_ID, "dhan": server.DHAN_VOICE_ID,
              "marvis": os.environ.get("MARVIS_VOICE_ID", server.DHAN_VOICE_ID)}
    data = json.loads((ROOT / "data/escape_lines.json").read_text())
    jobs = [(lid, voices[entry["who"]], entry["text"]) for lid, entry in data["lines"].items()]
    jobs += [("marvis_" + lid.replace(" ", "_").lower(), voices["marvis"], text) for lid, text in data["marvis"].items()]
    OUT.mkdir(parents=True, exist_ok=True)
    done = 0
    for name, voice, text in jobs:
        if args.only and name not in args.only and name.removeprefix("marvis_") not in args.only:
            continue
        path = OUT / f"{name}.mp3"
        if path.exists() and not args.force:
            continue
        print(f"{name}: {text}")
        if args.dry_run:
            continue
        path.write_bytes(server.synthesize(text, voice))
        done += 1
    print(f"recorded {done} line(s) into {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
