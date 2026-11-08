"""Bounded, versioned escape checkpoints. Saves never grant leaderboard results."""
import json
import math

FLAGS = set('locker_ready locker_clear assessed isolated fuse_taken fuse_installed fault_found aux_off engineering_power case_requested case_arrived samples_saved battery_out battery_loaded battery_taken battery_connected clamps departed'.split())
TASKS = ('', 'help_locker', 'load_battery', 'fetch_case')


def valid_notes(notes):
    """Facts remembered by one crewmate during this saved mission."""
    return (isinstance(notes, list) and len(notes) <= 12 and
            all(isinstance(note, str) and 0 < len(note) <= 120 for note in notes))


def number(value, high=1000000):
    try:
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and 0 <= value <= high
    except (ValueError, OverflowError):
        return False


def vector(value, signed=False):
    return (isinstance(value, list) and len(value) == 2 and
            all(isinstance(x, (int, float)) and not isinstance(x, bool) and (-1 if signed else 0) <= x <= (1 if signed else 10000) and math.isfinite(x) for x in value))


# Schema 2: the story in docs/Game Design.md. Mirrors SaveGame.compatible() in
# scripts/core/save_game.gd and the lists in scripts/prototype/escape_state.gd.
FLAGS_V2 = set('''dhan_free locker_clear isolated code_read fuse_installed fault_found aux_off
engineering_power freezer_off battery_out battery_loaded battery_taken battery_connected case_requested
case_arrived samples_saved samples_wrong splint_taken dhan_treated dhan_dead dhan_aboard clamps aaron_aboard
departed'''.split())
CARRY_V2 = ('', 'fuse_A', 'fuse_B', 'fuse_C', 'splint', 'battery cart')
TASKS_V2 = ('', 'lift_locker', 'stay_with_dhan', 'fetch_fuse', 'fetch_case', 'lift_battery', 'carry_dhan', 'release_clamps')
POSES = ('stand', 'pinned', 'straining', 'sit', 'carried', 'dead')
FAILS = ('F1', 'F2', 'F3', 'F4', 'F5')
QUESTIONS = ('stage3_dhan_question', 'freezer_question')


def strings(value, longest, most):
    return isinstance(value, list) and len(value) <= most and all(isinstance(x, str) and 0 < len(x) <= longest for x in value)


def whole(value, options):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value in options and int(value) == value


def valid_puzzle(p):
    if not isinstance(p, dict) or set(p) != {'code', 'fuse_for', 'aux', 'toggle_for', 'selector'}:
        return False
    if not whole(p['code'], (3, 6, 9)) or not whole(p['aux'], (1, 2, 3)) or not whole(p['selector'], (0, 1, 2)):
        return False
    fuse, toggle = p['fuse_for'], p['toggle_for']
    if not isinstance(fuse, dict) or set(fuse) != {'3', '6', '9'} or sorted(fuse.values()) != ['A', 'B', 'C']:
        return False
    return (isinstance(toggle, dict) and set(toggle) == {'1', '2', '3'} and all(whole(v, (0, 1, 2)) for v in toggle.values())
            and sorted(int(v) for v in toggle.values()) == [0, 1, 2])


def valid(snapshot):
    if isinstance(snapshot, dict) and snapshot.get('schema') == 2 and not isinstance(snapshot.get('schema'), bool):
        return valid_v2(snapshot)
    return valid_v1(snapshot)


def _common(snapshot, crew_ok):
    try:
        if len(json.dumps(snapshot, allow_nan=False, ensure_ascii=False).encode()) > 24000:
            return False
    except (ValueError, TypeError, OverflowError, RecursionError):
        return False
    state = snapshot.get('state', {})
    if not isinstance(state, dict) or not number(state.get('version'), 1000000) or int(state['version']) != state['version']:
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
        if any(not isinstance(actor.get(k), bool) for k in ('following', 'light_on', 'cargo')) or not crew_ok(actor):
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
    notes = snapshot.get('memory_notes', {})
    return isinstance(notes, dict) and all(k in crew and valid_notes(v) for k, v in notes.items())


def valid_v2(snapshot):
    if snapshot.get('map') != 'escape-v2':
        return False
    state = snapshot.get('state')
    if not isinstance(state, dict):
        return False
    flags = state.get('flags')
    if not isinstance(flags, dict) or any(k not in FLAGS_V2 or not isinstance(v, bool) for k, v in flags.items()) or flags.get('departed'):
        return False
    if state.get('carrying') not in CARRY_V2 or state.get('fuse_at_cabinet') not in ('', 'A', 'B', 'C') or state.get('fuse_task') not in ('', 'A', 'B', 'C'):
        return False
    if not strings(state.get('learned'), 80, 40) or not strings(state.get('fails'), 5, 4) or any(f not in FAILS for f in state['fails']):
        return False
    if not number(state.get('vitality'), 100) or not whole(state.get('selector'), (0, 1, 2)) or not valid_puzzle(state.get('puzzle')):
        return False
    promises = state.get('promises')
    if not isinstance(promises, dict) or any(k not in QUESTIONS or not isinstance(v, str) or len(v) > 100 for k, v in promises.items()):
        return False
    if not strings(snapshot.get('said'), 120, 60):
        return False
    return _common(snapshot, lambda a: a.get('task') in TASKS_V2 and a.get('pose') in POSES and isinstance(a.get('visible'), bool))


def valid_v1(snapshot):
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
    notes = snapshot.get('memory_notes', {})
    if not isinstance(notes, dict) or any(k not in crew or not valid_notes(v) for k, v in notes.items()):
        return False
    return True
