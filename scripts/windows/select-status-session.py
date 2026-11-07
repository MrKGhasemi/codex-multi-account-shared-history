"""Choose a random active local chat, without modifying SQLite or reading auth."""
import argparse
from contextlib import closing
import json
from pathlib import Path
import random
import sqlite3
import uuid


def choose(database):
    with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)) as connection:
        rows = connection.execute(
            'SELECT id, rollout_path FROM threads WHERE archived=0'
        ).fetchall()
    candidates = []
    for tid, rollout in rows:
        try:
            uuid.UUID(tid)
        except (ValueError, TypeError, AttributeError):
            continue
        if rollout and Path(rollout).is_file():
            candidates.append(tid)
    return random.SystemRandom().choice(candidates) if candidates else None


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--database', type=Path, required=True)
    args = parser.parse_args()
    session = choose(args.database)
    directory = None
    if session:
        with closing(sqlite3.connect(args.database.resolve().as_uri() + '?mode=ro', uri=True)) as connection:
            row = connection.execute('SELECT cwd FROM threads WHERE id=?', (session,)).fetchone()
        if row and row[0] and Path(row[0]).is_dir():
            directory = row[0]
    print(json.dumps({'sessionId': session, 'directory': directory}))
