"""Read-only session selection regression checks, with synthetic data only."""
from pathlib import Path
from contextlib import closing
import runpy
import sqlite3
import tempfile
import uuid

choose = runpy.run_path(str(Path(__file__).resolve().parents[2] /
    'scripts/windows/select-status-session.py'))['choose']
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    database = root / 'state.sqlite'
    rollout = root / 'rollout.jsonl'
    rollout.write_text('synthetic', encoding='utf-8')
    valid, archived, missing = (str(uuid.uuid4()) for _ in range(3))
    with closing(sqlite3.connect(database)) as connection, connection:
        connection.execute('CREATE TABLE threads(id TEXT, rollout_path TEXT, archived INTEGER)')
        connection.executemany('INSERT INTO threads VALUES (?,?,?)', [
            (valid, str(rollout), 0), (archived, str(rollout), 1),
            (missing, str(root/'missing.jsonl'), 0), ('not-an-id', str(rollout), 0)])
    before = database.read_bytes()
    assert {choose(database) for _ in range(10)} == {valid}
    assert database.read_bytes() == before
    with closing(sqlite3.connect(database)) as connection, connection:
        connection.execute('DELETE FROM threads')
    assert choose(database) is None
print('PASS: active valid local chats only; read-only selection; empty-store fallback')
