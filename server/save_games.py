"""Bounded, versioned escape checkpoints. Saves never grant leaderboard results."""
import json
import math

FLAGS = set('locker_ready locker_clear assessed isolated fuse_taken fuse_installed fault_found aux_off engineering_power case_requested case_arrived samples_saved battery_out battery_loaded battery_taken battery_connected clamps departed'.split())
TASKS = ('', 'help_locker', 'load_battery', 'fetch_case')


def number(value, high=1000000):
    try:
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and 0 <= value <= high
    except (ValueError, OverflowError):
        return False


def vector(value, signed=False):
    return (isinstance(value, list) and len(value) == 2 and
            all(isinstance(x, (int, float)) and not isinstance(x, bool) and (-1 if signed else 0) <= x <= (1 if signed else 10000) and math.isfinite(x) for x in value))


def valid(snapshot):
    if not isinstance(snapshot, dict) or snapshot.get('schema') != 1 or isinstance(snapshot.get('schema'), bool) or snapshot.get('map') != 'escape-v1':
        return False
    try:
        if len(json.dumps(snapshot, allow_nan=False, ensure_ascii=False).encode()) > 24000:
            return False
    except (ValueError, TypeError, OverflowError, RecursionError):
        return False
    state = snapshot.get('state', {})
    if not isinstance(state, dict) or state.get('route') not in ('', 'engineering', 'battery') or state.get('carrying') not in ('', 'fuse', 'battery cart'):
        return False
    flags = state.get('flags')
    if not isinstance(flags, dict) or any(k not in FLAGS or not isinstance(v, bool) for k, v in flags.items()) or flags.get('departed'):
        return False
    if not number(state.get('version'), 1000000) or int(state['version']) != state['version']:
        return False
    journal = state.get('journal')
    if not isinstance(journal, list) or len(journal) > 40 or any(not isinstance(x, str) or len(x) > 500 for x in journal):
        return False
    if not number(snapshot.get('elapsed'), 31536000) or not isinstance(snapshot.get('flashlight'), bool):
        return False
    player = snapshot.get('player')
    if not isinstance(player, dict) or not vector(player.get('position')):
        return False
    crew = snapshot.get('crew')
    if not isinstance(crew, dict) or set(crew) != {'mara', 'ivo'}:
        return False
    for actor in crew.values():
        if not isinstance(actor, dict) or not vector(actor.get('position')) or not vector(actor.get('facing'), True):
            return False
        if any(not isinstance(actor.get(k), bool) for k in ('following', 'light_on', 'cargo')) or actor.get('task') not in TASKS:
            return False
        path = actor.get('path')
        if not isinstance(path, list) or len(path) > 300 or any(not vector(p) for p in path):
            return False
    history = snapshot.get('history', {})
    if not isinstance(history, dict) or any(k not in crew for k in history):
        return False
    for turns in history.values():
        if not isinstance(turns, list) or len(turns) > 6:
            return False
        if any(not isinstance(t, dict) or t.get('role') not in ('player', 'npc') or not isinstance(t.get('text'), str) or len(t['text']) > 420 for t in turns):
            return False
    return True
