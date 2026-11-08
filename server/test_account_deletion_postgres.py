"""Opt-in PostgreSQL deletion checks using only temporary shadow tables.

Set B2E_TEST_DATABASE_URL for a database with the game schema installed. Every
write targets this connection's temporary tables and is rolled back on exit.
"""
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import game_db


@unittest.skipUnless(os.environ.get('B2E_TEST_DATABASE_URL') and game_db.psycopg, 'requires PostgreSQL test URL')
class AccountDeletionPostgresTests(unittest.TestCase):
    def test_atomic_deletion_and_isolation(self):
        with game_db.psycopg.connect(os.environ['B2E_TEST_DATABASE_URL'], connect_timeout=8,
                                    options='-c statement_timeout=10000 -c lock_timeout=5000') as connection:
            try:
                for table in ('accounts', 'sessions', 'runs', 'events', 'npc_memory', 'game_saves'):
                    connection.execute(f'CREATE TEMP TABLE {table} (LIKE public.{table} INCLUDING ALL) ON COMMIT DROP')
                for table in ('sessions', 'game_saves'):
                    connection.execute(f'ALTER TABLE {table} ADD FOREIGN KEY (account_id) REFERENCES pg_temp.accounts(id) ON DELETE CASCADE')
                connection.execute('ALTER TABLE runs ADD FOREIGN KEY (account_id) REFERENCES pg_temp.accounts(id) ON DELETE SET NULL')
                store = game_db.Store('unused: injected temporary connection')
                store._conn = connection
                alice = store.create_account('TxAlice', 'hash')
                bob = store.create_account('TxBob', 'hash')
                for owner, run in ((alice, 'temporary-alice-run'), (bob, 'temporary-bob-run')):
                    store.create_session(owner)
                    store.write_save(owner, {'test': owner}, 0)
                    store.start_run(run, owner, None, 'classic', 'test')
                    connection.execute("INSERT INTO events (run_token, event) VALUES (%s, 'test')", (run,))
                    store.npc_remember(game_db.player_key(owner, None), 'mara', [('note', None, 'Test memory')])
                store.npc_remember('g0123abcd', 'ivo', [('note', None, 'Guest memory')])
                # Fail the final statement, after earlier deletes have run.
                connection.execute("CREATE FUNCTION pg_temp.refuse_account_delete() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test failure'; END $$")
                connection.execute('CREATE TRIGGER refuse_account_delete BEFORE DELETE ON accounts FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse_account_delete()')
                with self.assertRaises(game_db.DbError):
                    store.delete_account(alice)
                for table in ('accounts', 'sessions', 'runs', 'events', 'game_saves'):
                    self.assertEqual(connection.execute(f'SELECT count(*) FROM {table}').fetchone()[0], 2, table)
                self.assertEqual(connection.execute('SELECT count(*) FROM npc_memory').fetchone()[0], 3)
                connection.execute('DROP TRIGGER refuse_account_delete ON accounts')
                store.delete_account(alice)
                for table in ('accounts', 'sessions', 'runs', 'events', 'game_saves'):
                    self.assertEqual(connection.execute(f'SELECT count(*) FROM {table}').fetchone()[0], 1, table)
                self.assertEqual(connection.execute('SELECT id FROM accounts').fetchone()[0], bob)
                self.assertEqual({r[0] for r in connection.execute('SELECT player_key FROM npc_memory').fetchall()},
                                 {game_db.player_key(bob, None), 'g0123abcd'})
                self.assertEqual(store.load_save(bob)['snapshot'], {'test': bob})
            finally:
                connection.rollback()


if __name__ == '__main__':
    unittest.main()
