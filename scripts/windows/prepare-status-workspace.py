"""Trust only an empty, helper-created status workspace, never a chat's project."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tomllib
import uuid


MARKER = '.codex-status-workspace'


def prepare(profile, root, git):
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    pointer = profile / 'status-workspace.txt'
    workspace = None
    if pointer.exists():
        candidate = Path(pointer.read_text(encoding='utf-8').strip()).resolve()
        if (candidate.parent == root and (candidate / MARKER).is_file()
                and (candidate / '.git').is_dir()
                and {p.name for p in candidate.iterdir()} <= {'.git', MARKER}
                and not any((candidate / '.git' / 'hooks').glob('*'))):
            workspace = candidate
    if workspace is None:
        workspace = root / uuid.uuid4().hex
        workspace.mkdir()
        subprocess.run([git, '-c', 'init.templateDir=', 'init', '--quiet', '--', str(workspace)],
                       check=True, capture_output=True)
        (workspace / MARKER).write_text('Empty Codex account status workspace\n', encoding='utf-8')
        pointer.write_text(str(workspace), encoding='utf-8')
    config = profile / 'config.toml'
    content = config.read_text(encoding='utf-8-sig') if config.exists() else ''
    settings = tomllib.loads(content)
    # Windows Codex's canonical Git trust root is lowercased.
    key = str(workspace).lower() if os.name == 'nt' else str(workspace)
    existing = settings.get('projects', {}).get(key)
    if existing is not None and existing.get('trust_level') != 'trusted':
        # A user may have explicitly revoked trust. Do not override that choice.
        raise RuntimeError('The dedicated status workspace was marked untrusted. Remove status-workspace.txt to create a new empty workspace.')
    if existing is None:
        if config.exists():
            backup = config.with_name('config.toml.before-status-' + uuid.uuid4().hex + '.bak')
            backup.write_bytes(config.read_bytes())
        with config.open('a', encoding='utf-8') as output:
            output.write('\n[projects.' + json.dumps(key) + ']\ntrust_level = "trusted"\n')
    return workspace


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile-home', required=True, type=Path)
    parser.add_argument('--workspace-root', required=True, type=Path)
    parser.add_argument('--git', required=True)
    args = parser.parse_args()
    print(json.dumps({'directory': str(prepare(args.profile_home, args.workspace_root, args.git))}))
