"""Loopback dashboard using Codex app-server account and usage reads."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from queue import Empty, Queue
import socket
import subprocess
import threading
import time
from urllib.error import URLError
from urllib.request import urlopen
import webbrowser

DASHBOARD_PORT = 47631


class LoginRequired(ValueError):
    pass

def read_limits(runtime, profile):
    if not profile.is_dir():
        raise ValueError('Profile folder missing')
    messages = Queue()
    env = dict(os.environ, CODEX_HOME=str(profile))
    # Do not use a shell or read credentials ourselves. Codex handles its own login.
    with subprocess.Popen([runtime, 'app-server'], cwd=profile, env=env,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, encoding='utf-8', errors='replace',
                          creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as child:
        def receive():
            try:
                for line in child.stdout:
                    try:
                        messages.put(json.loads(line))
                    except ValueError:
                        pass
            finally:
                messages.put(None)

        threading.Thread(target=receive, daemon=True).start()
        deadline = time.monotonic() + 20

        def send(method, request_id=None, params=None):
            request = {'method': method}
            if request_id is not None:
                request['id'] = request_id
            if params is not None:
                request['params'] = params
            child.stdin.write(json.dumps(request) + '\n')
            child.stdin.flush()

        def reply(request_id):
            while True:
                try:
                    result = messages.get(timeout=max(0, deadline - time.monotonic()))
                except Empty:
                    raise ValueError('Codex did not respond in time') from None
                if result is None:
                    raise ValueError('Codex stopped before returning limits')
                if isinstance(result, dict) and result.get('id') == request_id:
                    if 'error' in result:
                        error = result['error']
                        message = str(error.get('message', '')).lower()
                        if any(s in message for s in ('auth', 'login', 'sign in', '401', '403')):
                            raise LoginRequired('Check this profile’s ChatGPT login')
                        if error.get('code') == -32601:
                            raise ValueError('This Codex version does not support reading limits')
                        raise ValueError('Codex could not retrieve limits; try again')
                    return result['result']

        try:
            send('initialize', 1, {'clientInfo': {'name': 'limits_dashboard', 'version': '1.0'}})
            reply(1)
            send('initialized')
            identity = {}
            try:
                send('account/read', 2, {'refreshToken': False})
                account_info = reply(2)
                account = account_info.get('account') or {}
                email = account.get('email') if account.get('type') == 'chatgpt' else None
                identity = {'email': email if isinstance(email, str) and email.strip() else None,
                            'accountPlan': account.get('planType'),
                            'loginRequired': not account and account_info.get('requiresOpenaiAuth') is True}
            except ValueError:
                pass  # Older engines can still provide limits without account metadata.
            try:
                send('account/rateLimits/read', 3)
                return dict(identity, **summarize(reply(3)))
            except ValueError as exc:
                if isinstance(exc, LoginRequired):
                    identity['loginRequired'] = True
                return dict(identity, error=str(exc))
        finally:
            child.terminate()


def summarize(result):
    primary = result.get('rateLimits') or {}
    groups = dict(result.get('rateLimitsByLimitId') or {})
    if primary:
        groups.setdefault(primary.get('limitId') or 'codex', primary)
    output = []
    for key, group in sorted(groups.items(), key=lambda pair: (pair[0] != 'codex', pair[0])):
        windows = []
        for field in ('primary', 'secondary'):
            window = group.get(field) or {}
            if type(window.get('usedPercent')) in (int, float):
                windows.append({'remaining': max(0, min(100, 100 - window['usedPercent'])),
                                'minutes': window.get('windowDurationMins'),
                                'reset': window.get('resetsAt')})
        if windows:
            output.append({'label': group.get('limitName') or key, 'windows': windows})
    summary = result.get('rateLimitResetCredits') or {}
    count = summary.get('availableCount')
    data = {'plan': primary.get('planType'), 'groups': output,
            'usageAllowed': result.get('ordinaryUsageAllowed') if type(result.get('ordinaryUsageAllowed')) is bool else None,
            'resetCredits': count if type(count) is int and count >= 0 else None}
    if not output:
        data['error'] = 'No usage windows were returned for this account'
    return data


class Monitor:
    def __init__(self, runtime, home, count, reader=read_limits):
        self.runtime, self.home, self.reader = runtime, home, reader
        self.rows = {n: {'number': n} for n in range(1, count + 1)}
        self.lock = threading.Lock()
        self.wake = threading.Event()
        self.stop = threading.Event()
        self.running = False
        self.pending = set()
        self.active = set()
        self.confirmed = {}
        self.next = time.time()

    def request(self, number=None):
        with self.lock:
            targets = set(self.rows) if number is None else {number}
            queued = targets - self.active - self.pending
            self.pending.update(queued)
            if not queued:
                return False
            self.wake.set()
            return True

    def snapshot(self):
        with self.lock:
            return {'running': self.running or bool(self.pending), 'next': self.next,
                    'busyAccounts': sorted(self.active | self.pending),
                    'accounts': [dict(row) for row in self.rows.values()]}

    def update(self, number):
        try:
            result = self.reader(self.runtime, self.home / f'.codex-plus-{number}')
            changes = dict(result) if result.get('error') else dict(result, updated=time.time(), error=None)
        except ValueError as exc:
            changes = {'error': str(exc)}
        except Exception:
            changes = {'error': 'Could not read this profile; check Codex and try again'}
        with self.lock:
            row = self.rows[number]
            if 'email' in changes and row.get('email') != changes['email']:
                self.confirmed.pop(number, None)
                for key in ('groups', 'updated', 'plan', 'resetCredits', 'recoveredAt'):
                    row.pop(key, None)
            changes.setdefault('usageAllowed', None)
            if not changes.get('error'):
                changes.setdefault('loginRequired', False)
            if type(changes['usageAllowed']) is bool:
                if changes['usageAllowed'] and self.confirmed.get(number) is False:
                    changes['recoveredAt'] = time.time()
                self.confirmed[number] = changes['usageAllowed']
            changes['resetCreditsStale'] = 'resetCredits' not in changes and row.get('resetCredits') is not None
            row.update(changes)

    def run(self):
        with ThreadPoolExecutor(max_workers=min(6, len(self.rows))) as pool:
            while not self.stop.is_set():
                with self.lock:
                    started = time.time()
                    automatic = started >= self.next
                    targets = set(self.rows) if automatic else set(self.pending)
                    self.pending.difference_update(targets)
                    self.active = targets
                    self.wake.clear()
                    self.running = bool(targets)
                if not targets:
                    self.wake.wait(max(0, self.next - time.time()))
                    continue
                list(pool.map(self.update, sorted(targets)))
                with self.lock:
                    self.running = False
                    self.active.clear()
                    if automatic or len(targets) == len(self.rows):
                        self.next = max(time.time() + 1, started + 60)


ASSETS = {'/': ('index.html', 'text/html'), '/dashboard.css': ('dashboard.css', 'text/css'),
          '/dashboard.js': ('dashboard.js', 'text/javascript'),
          '/Vazirmatn.woff2': ('Vazirmatn.woff2', 'font/woff2')}


class DashboardServer(ThreadingHTTPServer):
    allow_reuse_address = os.name != 'nt'

    def server_bind(self):
        if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def serve(runtime, home, count, open_browser=True, port=DASHBOARD_PORT):
    monitor = Monitor(runtime, home, count)
    assets = Path(__file__).with_name('limits-dashboard')

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def respond(self, status, data=b'', mime='application/json'):
            self.send_response(status)
            self.send_header('Content-Type', mime if mime.startswith('font/') else mime + '; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.headers.get('Host') != host:
                return self.respond(403)
            if self.path == '/api/limits':
                return self.respond(200, json.dumps(monitor.snapshot()).encode())
            if self.path == '/api/health':
                return self.respond(200, b'{"service":"codex-limits-dashboard"}')
            if self.path in ASSETS:
                name, mime = ASSETS[self.path]
                return self.respond(200, (assets / name).read_bytes(), mime)
            self.respond(404)

        def do_POST(self):
            if (self.headers.get('Host') != host or self.headers.get('Origin') != origin
                    or self.headers.get('X-Limits-Refresh') != '1'):
                return self.respond(403)
            number = None
            if self.path != '/api/refresh':
                prefix = '/api/refresh/'
                suffix = self.path[len(prefix):]
                if not self.path.startswith(prefix) or not suffix.isascii() or not suffix.isdigit() or len(suffix) > 2:
                    return self.respond(404)
                number = int(suffix)
                if number not in monitor.rows:
                    return self.respond(404)
            self.respond(202, json.dumps({'queued': monitor.request(number)}).encode())

    # A single fixed loopback listener acts as the instance lock. Only reopen
    # a service that identifies itself as this dashboard.
    try:
        server = DashboardServer(('127.0.0.1', port), Handler)
    except OSError:
        existing = f'http://127.0.0.1:{port}/'
        for _ in range(8):
            try:
                with urlopen(existing + 'api/health', timeout=.4) as response:
                    if json.loads(response.read(256)).get('service') == 'codex-limits-dashboard':
                        print(f'Codex limits dashboard already running: {existing}')
                        if open_browser:
                            webbrowser.open(existing)
                        return
            except (OSError, URLError, ValueError, AttributeError):
                pass
            time.sleep(.15)
        raise SystemExit(f'Cannot start dashboard: localhost port {port} is unavailable.')
    with server:
        host = f'127.0.0.1:{server.server_port}'
        origin = f'http://{host}'
        worker = threading.Thread(target=monitor.run, daemon=True)
        worker.start()
        print(f'Codex limits dashboard: {origin}/\nPress Ctrl+C to stop monitoring.')
        if open_browser:
            threading.Thread(target=webbrowser.open, args=(origin + '/',), daemon=True).start()
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            monitor.stop.set()
            monitor.wake.set()
            worker.join()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--home', type=Path, required=True)
    parser.add_argument('--count', type=int, choices=range(1, 100), required=True)
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--port', type=int, default=DASHBOARD_PORT, help='Loopback port (0 for an isolated test)')
    args = parser.parse_args()
    serve(args.runtime, args.home, args.count, not args.no_browser, args.port)
