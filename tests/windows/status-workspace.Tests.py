"""An isolated status viewer must never trust a user's real working directory."""
from pathlib import Path
import os
import runpy
import shutil
import subprocess
import tempfile
import tomllib

prepare = runpy.run_path(str(Path(__file__).resolve().parents[2] /
    'scripts/windows/prepare-status-workspace.py'))['prepare']
git = shutil.which('git.exe') or shutil.which('git')
assert git, 'Git is required for this test'
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    profile = root/'profile'; profile.mkdir()
    config = profile/'config.toml'
    original = 'sqlite_home = "unchanged"\ncli_auth_credentials_store = "file"\n'
    config.write_text(original, encoding='utf-8')
    auth = profile/'auth.json'; auth.write_bytes(b'dummy test data')
    # Reproduce the screenshot's parent directory being a Git repository.
    subprocess.run([git, '-c', 'init.templateDir=', 'init', '--quiet', str(root)], check=True)
    workspace = prepare(profile, root/'status', git)
    top = subprocess.check_output([git, '-C', str(workspace), 'rev-parse', '--show-toplevel'], text=True).strip()
    assert Path(top).resolve() == workspace.resolve()
    settings = tomllib.loads(config.read_text(encoding='utf-8'))
    key = str(workspace).lower() if os.name == 'nt' else str(workspace)
    assert settings['projects'] == {key: {'trust_level': 'trusted'}}
    assert settings['sqlite_home'] == 'unchanged'
    assert auth.read_bytes() == b'dummy test data'
    first_config = config.read_bytes()
    assert prepare(profile, root/'status', git) == workspace
    assert config.read_bytes() == first_config
    assert list((workspace/'.git'/'hooks').glob('*')) == []
    # If someone adds project content, choose a fresh empty workspace.
    (workspace/'user-project.txt').write_text('must not use this project', encoding='utf-8')
    replacement = prepare(profile, root/'status', git)
    assert replacement != workspace
    assert not (replacement/'user-project.txt').exists()
    assert (workspace/'user-project.txt').read_text() == 'must not use this project'
print('PASS: own Git root; exact scoped trust; empty template; reuse; auth preserved; real project excluded')
