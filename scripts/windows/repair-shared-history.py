"""Recover rollout ordering and missing saved history after all writers close.

Uses only Python's standard library. Never touches authentication. Original
rollouts and consistent SQLite snapshots are retained in the backup directory.
"""
import argparse
import contextlib
import json
import msvcrt
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import time

ORDINAL = re.compile(rb'("ordinal"\s*:\s*)(\d+)')
TABLES = ('thread_items', 'thread_turns', 'thread_history_projection_state', 'thread_realtime_items')

class WritersBusy(Exception):
    pass


def snapshot(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with contextlib.closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as src:
        with contextlib.closing(sqlite3.connect(target)) as dst:
            src.backup(dst)


@contextlib.contextmanager
def writer_locks(homes):
    handles = []
    seen = set()
    try:
        for home in homes:
            directory = home / 'thread-writer-locks'
            directory.mkdir(exist_ok=True)
            directory = directory.resolve()
            if directory in seen:
                continue
            seen.add(directory)
            # Coordination first, then per-thread locks, matching Codex's order.
            paths = [directory / '.coordination.lock']
            paths += sorted(p for p in directory.glob('*.lock') if p.name != '.coordination.lock')
            for path in paths:
                handle = path.open('a+b')
                handles.append(handle)
                handle.seek(0)
                try:
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                except OSError as error:
                    raise WritersBusy(str(path)) from error
        yield
    finally:
        for handle in reversed(handles):
            try:
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
            handle.close()


def ordering_damage(path):
    previous = -1
    damaged = 0
    with path.open('rb') as handle:
        for line in handle:
            # Ordinal is a top-level field before the potentially huge payload.
            header = line.split(b'"payload"', 1)[0]
            match = ORDINAL.search(header)
            if not match:
                continue  # Legacy rollouts have no explicit ordinals.
            value = int(match[2])
            if value <= previous:
                damaged += 1
            previous = max(previous, value)
    return damaged


def repair_order(path, backup):
    shutil.copy2(path, backup)
    temporary = path.with_suffix('.repair-tmp')
    try:
        with path.open('rb') as src, temporary.open('wb') as dst:
            for number, line in enumerate(src):
                if number == 0:
                    metadata = json.loads(line)
                    metadata['payload']['history_mode'] = 'legacy'
                    line = (json.dumps(metadata, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')
                line, count = ORDINAL.subn(lambda m: m[1] + str(number).encode('ascii'), line, count=1)
                if count != 1:
                    raise RuntimeError(f'Missing ordinal in {path.name} at line {number}')
                dst.write(line)
            dst.flush()
            os.fsync(dst.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def recover(root, runtime, backup):
    shared = root / '.codex-shared-history'
    db_home = shared / 'sqlite'
    state_path = db_home / 'state_5.sqlite'
    history_path = db_home / 'thread_history_1.sqlite'
    damaged = []
    for directory in [shared / 'sessions', shared / 'archived_sessions']:
        for path in directory.rglob('*.jsonl'):
            count = ordering_damage(path)
            if count:
                damaged.append(path)
                print(f'Ordering damage: {path.name}: {count} regressed/duplicate records', flush=True)

    backup.mkdir(parents=True, exist_ok=True)
    for path in [state_path, history_path]:
        if path.exists():
            snapshot(path, backup / path.name)

    # Previous setup rebuilt the inventory but omitted existing paginated DBs.
    # Recover missing records without overwriting newer shared records.
    imported = 0
    with contextlib.closing(sqlite3.connect(history_path)) as history:
        for source in [root / '.codex', *sorted(root.glob('.codex-plus-*'))]:
            path = source / 'thread_history_1.sqlite'
            if not path.exists() or path.resolve() == history_path.resolve():
                continue
            saved = backup / source.name / path.name
            snapshot(path, saved)
            history.execute('ATTACH DATABASE ? AS prior', (str(saved),))
            for table in TABLES:
                columns = [row[1] for row in history.execute(f'PRAGMA table_info({table})')]
                old_columns = {row[1] for row in history.execute(f'PRAGMA prior.table_info({table})')}
                if not columns or not set(columns) <= old_columns:
                    continue
                names = ','.join('"' + name + '"' for name in columns)
                before = history.total_changes
                history.execute(f'INSERT OR IGNORE INTO main.{table} ({names}) SELECT {names} FROM prior.{table}')
                imported += history.total_changes - before
            history.commit()
            history.execute('DETACH DATABASE prior')
        history.commit()
    print(f'Restored {imported} missing cached history records', flush=True)

    for path in damaged:
        with path.open('rb') as metadata:
            tid = json.loads(metadata.readline())['payload']['id']
        relative = path.relative_to(shared)
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        stage = backup / 'staging' / tid
        staged_rollout = stage / 'sessions' / path.name
        staged_rollout.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, staged_rollout)
        repair_order(staged_rollout, saved)
        stage_history = stage / history_path.name
        stage_state = stage / state_path.name
        snapshot(history_path, stage_history)
        snapshot(state_path, stage_state)
        with contextlib.closing(sqlite3.connect(stage_history)) as history:
            for table in TABLES:
                history.execute(f'DELETE FROM {table} WHERE thread_id=?', (tid,))
            history.commit()
        with contextlib.closing(sqlite3.connect(stage_state)) as state:
            state.execute("UPDATE threads SET history_mode='legacy',rollout_path=? WHERE id=?", (str(staged_rollout), tid))
            state.commit()
        (stage / 'config.toml').write_text('sqlite_home = ' + json.dumps(str(stage)) + '\n', encoding='utf-8')
        env = dict(os.environ, CODEX_HOME=str(stage))
        result = subprocess.run([str(runtime), 'migrate-rollouts', '--apply', '--thread', tid, '--json'],
                                env=env, capture_output=True, text=True, encoding='utf-8', timeout=300)
        report = json.loads(result.stdout) if result.returncode == 0 else {}
        statuses = [item['status'] for item in report.get('outcomes', []) if item['thread_id'] == tid]
        if statuses != ['migrated']:
            raise RuntimeError(f'Migration failed for {tid}: {result.stdout[-1500:]} {result.stderr[-1500:]}')
        if ordering_damage(staged_rollout):
            raise RuntimeError('Native migration did not repair rollout ordering')
        # Publish only this thread's rebuilt projection while holding the real
        # clients' writer locks. The migration uses its own isolated lock home.
        with contextlib.closing(sqlite3.connect(history_path)) as history:
            history.execute('ATTACH DATABASE ? AS repaired', (str(stage_history),))
            try:
                for table in TABLES:
                    columns = [row[1] for row in history.execute(f'PRAGMA table_info({table})')]
                    names = ','.join('"' + name + '"' for name in columns)
                    history.execute(f'DELETE FROM {table} WHERE thread_id=?', (tid,))
                    history.execute(f'INSERT INTO main.{table} ({names}) SELECT {names} FROM repaired.{table} WHERE thread_id=?', (tid,))
                os.replace(staged_rollout, path)
                history.commit()
            except Exception:
                history.rollback()
                shutil.copy2(saved, path)
                raise
        print(f'Recovered {tid}', flush=True)
    print('Recovery complete. Backup: ' + str(backup), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path.home())
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--wait', action='store_true')
    parser.add_argument('--backup', type=Path, required=True)
    args = parser.parse_args()
    homes = [args.root / '.codex', *sorted(args.root.glob('.codex-plus-*'))]
    waiting = False
    while True:
        try:
            with writer_locks(homes):
                recover(args.root, args.runtime, args.backup)
            break
        except WritersBusy:
            if not args.wait:
                raise
            if not waiting:
                print('Waiting for Codex UI/CLI writers to close before recovery.', flush=True)
                waiting = True
            time.sleep(2)


if __name__ == '__main__':
    main()
