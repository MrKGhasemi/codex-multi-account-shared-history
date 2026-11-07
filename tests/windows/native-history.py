"""Regression test using Codex's real storage engine; no model turns are sent."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import queue
import runpy
import sqlite3
import subprocess
import threading
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
args = parser.parse_args()
workspace = Path(__file__).resolve().parents[2]
fixture = workspace / '.diagnostics' / ('native-tests-' + uuid.uuid4().hex)
ui, cli, shared = (fixture / x for x in ('.codex', '.codex-plus-1', '.codex-shared-history'))
for path in (ui, cli, shared / 'sessions', shared / 'archived_sessions', shared / 'sqlite', ui / 'thread-writer-locks'):
    path.mkdir(parents=True, exist_ok=True)
for home in (ui, cli):
    (home / 'config.toml').write_text('sqlite_home = ' + json.dumps(str(shared / 'sqlite')) + '\n', encoding='utf-8')

def junction(path, target):
    quote = lambda value: "'" + str(value).replace("'", "''") + "'"
    subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                    'New-Item -ItemType Junction -Path ' + quote(path) + ' -Target ' + quote(target) + ' | Out-Null'], check=True)

for home in (ui, cli):
    for child in ('sessions', 'archived_sessions'):
        junction(home / child, shared / child)
junction(cli / 'thread-writer-locks', ui / 'thread-writer-locks')
tid = str(uuid.uuid4())
rollout = shared / 'sessions' / ('rollout-2026-10-12T00-00-00-' + tid + '.jsonl')

def event(kind, payload, ordinal):
    return dict(timestamp='2026-10-12T00:00:00Z', ordinal=ordinal, type=kind, payload=payload)

records = [event('session_meta', dict(id=tid, session_id=tid, timestamp='2026-10-12T00:00:00Z',
             cwd=str(fixture), source='cli', originator='codex_cli_rs', cli_version='0.162.0-alpha.17.2',
             model_provider='openai', history_mode='legacy'), 0)]

def turn(text, start):
    turn_id, item_id = str(uuid.uuid4()), str(uuid.uuid4())
    return [event('event_msg', dict(type='task_started', turn_id=turn_id, root_turn_id=turn_id,
                started_at=1791763200 + start, model_context_window=258400), start),
            event('event_msg', dict(type='item_completed', thread_id=tid, turn_id=turn_id,
                item=dict(type='UserMessage', id=item_id, content=[dict(type='text', text=text, text_elements=[])]),
                started_at_ms=(1791763200 + start)*1000, completed_at_ms=(1791763200 + start)*1000), start+1),
            event('event_msg', dict(type='task_complete', turn_id=turn_id, root_turn_id=turn_id,
                started_at=1791763200 + start, completed_at=1791763201 + start, duration_ms=1000,
                last_agent_message=None), start+2)]

records += turn('older saved message', 1) + turn('message saved before restart', 4)
rollout.write_text(''.join(json.dumps(v, separators=(',', ':'))+'\n' for v in records), encoding='utf-8')
env = dict(os.environ, CODEX_HOME=str(ui))
migration = subprocess.run([str(args.runtime), 'migrate-rollouts', '--apply', '--json'],
                           env=env, capture_output=True, text=True, encoding='utf-8', timeout=60)
assert migration.returncode == 0, migration.stderr
assert json.loads(migration.stdout)['outcomes'][0]['status'] == 'migrated'

class Client:
    def __init__(self, home):
        self.process = subprocess.Popen([str(args.runtime), 'app-server'],
            env=dict(os.environ, CODEX_HOME=str(home)), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
        self.queue = queue.Queue()
        self.counter = 0
        threading.Thread(target=self._read, daemon=True).start()
        self.call('initialize', {'clientInfo':{'name':'shared_history_regression', 'version':'1.0'},
                                'capabilities':{'experimentalApi':True}})
        self.process.stdin.write('{"method":"initialized"}\n'); self.process.stdin.flush()

    def _read(self):
        for line in self.process.stdout:
            try: self.queue.put(json.loads(line))
            except ValueError: pass

    def call(self, method, params, allow_error=False):
        self.counter += 1
        self.process.stdin.write(json.dumps(dict(id=self.counter, method=method, params=params))+'\n')
        self.process.stdin.flush()
        while True:
            result = self.queue.get(timeout=30)
            if result.get('id') == self.counter:
                if 'error' in result and not allow_error: raise RuntimeError(result['error'])
                return result if allow_error else result['result']

    def messages(self):
        turns = self.call('thread/turns/list', {'threadId':tid, 'limit':50, 'itemsView':'full'})['data']
        return {content['text'] for turn_data in turns for item in turn_data['items']
                if item['type']=='userMessage' for content in item['content'] if content['type']=='text'}

    def close(self):
        self.process.terminate(); self.process.wait(timeout=10)
        self.process.stdin.close(); self.process.stdout.close()

for home in (ui, cli):
    with contextlib.closing(Client(home)) as client:
        assert 'message saved before restart' in client.messages()
print('PASS: two fresh clients read the same saved messages')

# Reproduce regressed ordinals while retaining the complete user message.
with rollout.open('a', encoding='utf-8') as output:
    for record in turn('font installation message that must survive restart', 1):
        output.write(json.dumps(record, separators=(',', ':'))+'\n')
module = runpy.run_path(str(workspace / 'scripts/windows/repair-shared-history.py'))
assert module['ordering_damage'](rollout) > 0
with module['writer_locks']([ui, cli]):
    module['recover'](fixture, args.runtime, fixture/'backup')
for home in (ui, cli):
    with contextlib.closing(Client(home)) as client:
        assert 'font installation message that must survive restart' in client.messages()
print('PASS: recovered font message survives two independent client restarts')

first = Client(ui)
second = Client(cli)
try:
    first.call('thread/resume', {'threadId':tid})
    rejected = second.call('thread/resume', {'threadId':tid}, allow_error=True)
    assert 'error' in rejected and ('lock' in rejected['error']['message'].lower() or
                                   'active writer' in rejected['error']['message'].lower()), rejected
    print('PASS: native engine refuses a second writer to the same chat')
    first.close(); first = None
    second.call('thread/resume', {'threadId':tid})
    assert 'font installation message that must survive restart' in second.messages()
    print('PASS: another profile resumes after the first writer closes, with history intact')
finally:
    if first: first.close()
    second.close()

# Existing SQLite history must be seeded, not recreated from rollout listings.
destination = fixture / 'seeded-sqlite'
seed = subprocess.run([os.sys.executable, str(workspace/'scripts/windows/seed-shared-sqlite.py'),
    '--ui-home', str(ui), '--destination', str(destination)], capture_output=True, text=True, timeout=30)
assert seed.returncode == 0, seed.stderr
with sqlite3.connect(destination/'thread_history_1.sqlite') as database:
    assert database.execute("select count(*) from thread_items where thread_id=? and item_json like '%font installation%'", (tid,)).fetchone()[0] > 0
print('PASS: first setup preserves paginated SQLite history')

# Run the complete setup against a separate user-home fixture: existing GUI
# databases plus an older CLI rollout, then check every resulting saved path.
fresh = fixture / 'first-setup'
fresh_ui, fresh_cli = fresh/'.codex', fresh/'.codex-plus-1'
for home in (fresh_ui, fresh_cli):
    (home/'sessions').mkdir(parents=True)
    (home/'archived_sessions').mkdir()
import shutil
shutil.copy2(rollout, fresh_ui/'sessions'/rollout.name)
for name in ('state_5.sqlite','thread_history_1.sqlite'):
    module['snapshot'](shared/'sqlite'/name, fresh_ui/name)
with sqlite3.connect(fresh_ui/'state_5.sqlite') as state:
    state.execute('UPDATE threads SET rollout_path=? WHERE id=?', (str(fresh_ui/'sessions'/rollout.name), tid))
extra_tid = str(uuid.uuid4())
extra_name = 'rollout-2026-10-12T00-00-00-' + extra_tid + '.jsonl'
(fresh_cli/'sessions'/extra_name).write_text(''.join(json.dumps(record,separators=(',',':')).replace(tid,extra_tid)+'\n' for record in records),encoding='utf-8')
setup_env = {key:value for key,value in os.environ.items() if key.upper() not in ('USERPROFILE','PATH')}
setup_env['USERPROFILE'] = str(fresh)
setup_env['Path'] = str(Path(os.sys.executable).parent) + os.pathsep + os.environ.get('PATH','')
setup_command = ['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',
    str(workspace/'scripts/windows/use-live-shared-history.ps1'),'-AccountCount','1','-Force']
with contextlib.closing(Client(fresh_ui)) as active_writer:
    active_writer.call('thread/resume', {'threadId':tid})
    before = (fresh_ui/'sessions'/rollout.name).read_bytes()
    refused = subprocess.run(setup_command,env=setup_env,capture_output=True,text=True,encoding='utf-8',timeout=30)
    assert refused.returncode != 0 and 'cannot bypass writer safety' in refused.stderr, refused.stdout+'\n'+refused.stderr
    assert (fresh_ui/'sessions'/rollout.name).read_bytes() == before
print('PASS: even Force setup refuses to migrate a store with an active native writer')
setup = subprocess.run(setup_command,env=setup_env,capture_output=True,text=True,encoding='utf-8',timeout=60)
assert setup.returncode == 0, setup.stdout+'\n'+setup.stderr
with sqlite3.connect(fresh/'.codex-shared-history/sqlite/state_5.sqlite') as state:
    paths = state.execute('SELECT id,rollout_path FROM threads').fetchall()
    assert {tid,extra_tid} <= {row[0] for row in paths}
    assert all(Path(path).is_relative_to(fresh/'.codex-shared-history') and Path(path).exists() for _,path in paths), paths
with sqlite3.connect(fresh/'.codex-shared-history/sqlite/thread_history_1.sqlite') as history:
    assert history.execute("select count(*) from thread_items where thread_id=? and item_json like '%font installation%'", (tid,)).fetchone()[0] > 0
print('PASS: full first setup preserves UI history and old CLI chats without depending on backup paths')
