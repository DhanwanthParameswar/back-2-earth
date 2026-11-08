"""Ephemeral localhost account/save API for client integration tests.

No live database or model calls. Run with Python 3.12+; all test data disappears
when stopped. Use B2E_BACKEND=http://127.0.0.1:8788 in the native Godot process.
"""
import argparse
from http.server import ThreadingHTTPServer
import companion_server
import game_db
from test_game_db import FakeStore


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8788)
    args = parser.parse_args()
    companion_server.MOCK = True
    companion_server.GAME = game_db.Service(FakeStore())
    companion_server.LIMITS.BUCKETS = {key: (1000, .001) for key in companion_server.LIMITS.BUCKETS}
    print(f'In-memory test API: http://127.0.0.1:{args.port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), companion_server.Handler).serve_forever()


if __name__ == '__main__':
    main()
