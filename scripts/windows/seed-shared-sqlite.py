"""Seed a new shared SQLite store with existing UI state and paginated history."""
import argparse
import contextlib
from pathlib import Path
import sqlite3
import tomllib
import re

parser = argparse.ArgumentParser()
parser.add_argument('--ui-home', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
parser.add_argument('--normalize-rollout-paths', action='store_true')
parser.add_argument('--refresh-inventory', action='store_true')
args = parser.parse_args()
config = args.ui_home / 'config.toml'
settings = tomllib.loads(config.read_text(encoding='utf-8-sig')) if config.exists() else {}
source_home = Path(settings.get('sqlite_home') or args.ui_home)
if not source_home.is_absolute():
    source_home = args.ui_home / source_home
args.destination.mkdir(parents=True, exist_ok=True)
for name in ('state_5.sqlite', 'thread_history_1.sqlite'):
    source = source_home / name
    destination = args.destination / name
    if not source.exists() or destination.exists() or source.resolve() == destination.resolve():
        continue
    temporary = destination.with_suffix('.seed-tmp')
    try:
        with contextlib.closing(sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True)) as src:
            with contextlib.closing(sqlite3.connect(temporary)) as dst:
                src.backup(dst)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    print('Preserved existing ' + name)

if args.refresh_inventory:
    # A UI database may have completed its scan before old CLI files are merged.
    # Let Codex's native backfill discover those IDs before native migration.
    with contextlib.closing(sqlite3.connect(args.destination / 'state_5.sqlite')) as state:
        state.execute('DELETE FROM backfill_state')
        state.commit()

if args.normalize_rollout_paths:
    # Initializer junctions live in the backup folder. Persist physical shared
    # paths so removing a setup backup cannot make conversations disappear.
    paths = {}
    shared_home = args.destination.parent
    for folder in ('sessions', 'archived_sessions'):
        for rollout in (shared_home / folder).rglob('*.jsonl'):
            match = re.search(r'([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\.jsonl$', rollout.name, re.I)
            if match:
                paths[(match[1], int(folder == 'archived_sessions'))] = str(rollout.resolve())
    with contextlib.closing(sqlite3.connect(args.destination / 'state_5.sqlite')) as state:
        for tid, archived in state.execute('SELECT id,archived FROM threads').fetchall():
            path = paths.get((tid, archived))
            if path:
                state.execute('UPDATE threads SET rollout_path=? WHERE id=?', (path, tid))
        state.commit()
