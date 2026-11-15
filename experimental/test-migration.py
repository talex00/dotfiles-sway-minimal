#!/usr/bin/env python3
"""Isolated migration tests; no use of the user's HOME."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('migration', here / 'migration.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
PACKAGES = ['sway', 'foot', 'fuzzel', 'swaync', 'fish', 'thunar', 'xfce', 'xsettingsd']

def run(*args, env=None, ok=True):
    result = subprocess.run(['python3', str(here / 'migration.py'), *map(str, args)], text=True, capture_output=True, env=env)
    if (result.returncode == 0) != ok:
        raise AssertionError(f'Unexpected exit {result.returncode}: {args}\n{result.stdout}\n{result.stderr}')
    return result.stdout

def fingerprint(root):
    h = hashlib.sha256()
    for p in sorted(root.rglob('*')):
        h.update(str(p.relative_to(root)).encode())
        if p.is_symlink(): h.update(b'L' + os.readlink(p).encode())
        elif p.is_file(): h.update(b'F' + p.read_bytes())
        elif p.is_dir(): h.update(b'D')
    return h.hexdigest()

def fixture(base):
    home = base / 'home with spaces'; old = base / 'old source'; new = base / 'new source'
    for p in [home / '.config', home / '.local/bin', home / '.local/share', old, new]: p.mkdir(parents=True)
    for rel, source in m.ROOTS.items():
        d = old / source; d.mkdir(parents=True)
        (d / ('config.jsonc' if rel == '.config/waybar' else 'fuzzel.ini' if rel == '.config/fuzzel' else 'base.conf')).write_text(f'base for {rel}\n')
    for source in m.FILES.values():
        (old / source).parent.mkdir(parents=True, exist_ok=True)
        (old / source).write_text('#!/bin/sh\n')
    shutil.copytree(old, new, dirs_exist_ok=True)
    # Untracked state lives inside the old folded directory, as on the real system.
    (old / m.ROOTS['.config/sway'] / 'monitors.conf').write_text('output custom\n')
    (old / m.ROOTS['.config/sway'] / 'workspaces').write_text('workspace 1 output custom\n')
    (old / m.ROOTS['.config/sway'] / 'personal.txt').write_text('personal data\n')
    (home / '.local/state').mkdir(parents=True)
    (home / '.local/state/preserved').write_text('state data')
    subprocess.run(['stow', '-d', str(old), '-t', str(home), *PACKAGES], check=True, capture_output=True)
    return home, old, new

def opts(home, old, new): return ['--home', home, '--old', old, '--new', new, '--id', 'test']
def token(output): return next(x.split()[1] for x in output.splitlines() if x.startswith('PLAN-SHA256 '))

with tempfile.TemporaryDirectory(prefix='sway-migration-tests ') as td:
    base = Path(td); home, old, new = fixture(base / 'main')
    args = opts(home, old, new)
    before_home, before_old, before_new = fingerprint(home), fingerprint(old), fingerprint(new)
    plan = run('--dry-run', *args); plan_token = token(plan)
    assert fingerprint(home) == before_home and fingerprint(old) == before_old and fingerprint(new) == before_new
    print('PASS T03 dry-run leaves filesystem unchanged')
    run('--apply', *args, '--expect', plan_token)
    run('--verify', *args)
    assert not (home / '.config/sway').is_symlink()
    assert (home / '.config/sway/base.conf').is_symlink()
    assert (home / '.config/waybar/config.jsonc').is_file() and not (home / '.config/waybar/config.jsonc').is_symlink()
    assert (home / '.config/sway/personal.txt').read_text() == 'personal data\n'
    assert (home / '.config/sway/monitors.conf').read_text() == 'output custom\n'
    assert (home / '.config/sway/workspaces').read_text() == 'workspace 1 output custom\n'
    assert (home / '.local/state/preserved').read_text() == 'state data'
    assert fingerprint(old) == before_old and fingerprint(new) == before_new
    print('PASS T01 T04 T05 T06 T09 T15 T17 T18 migration and preserved files')
    for rel in ['.config/fuzzel/fuzzel.ini', '.config/waybar/config.jsonc']:
        target = home / rel; original = target.read_bytes()
        target.write_bytes(original + b'\n# local generated change\n')
        assert fingerprint(old) == before_old and fingerprint(new) == before_new
        target.write_bytes(original)
    generated = home / '.config/sway/theme'
    generated.write_text('ice\n')
    assert fingerprint(old) == before_old and fingerprint(new) == before_new
    generated.unlink()
    print('PASS T17 writes to mutable outputs do not change sources')
    run('--apply', *args, '--expect', plan_token)
    print('PASS T02 repeated migration')
    stow = subprocess.run(['stow', '--simulate', '--no-folding', '--ignore=fuzzel.ini|config.jsonc', '-d', str(new), '-t', str(home), *PACKAGES], text=True, capture_output=True)
    if stow.returncode: raise AssertionError('Stow simulation: ' + stow.stderr)
    before_stow = m.inspect(home / '.config/sway')
    subprocess.run(['stow', '--no-folding', '--ignore=fuzzel.ini|config.jsonc', '-d', str(new), '-t', str(home), *PACKAGES], check=True, capture_output=True)
    assert m.inspect(home / '.config/sway') == before_stow
    print('PASS T16 repeated Stow with explicit mutable-file ignores')
    (home / '.config/sway/new-after.txt').write_text('new user data')
    run('--restore', *args, ok=False)
    assert (home / '.config/sway/new-after.txt').read_text() == 'new user data'
    print('PASS T14 restore blocks on new user file')
    (home / '.config/sway/new-after.txt').unlink()
    run('--restore', *args)
    assert (home / '.config/sway').is_symlink() and (home / '.config/sway/personal.txt').read_text() == 'personal data\n'
    print('PASS T12 restore after successful migration')
    for i, point in enumerate(['after-backup', 'after-prepare', 'after-partial-links', 'after-one-link', 'before-complete', 'kill-after-one-link']):
        h, o, n = fixture(base / f'failure-{i}'); a = opts(h, o, n); t = token(run('--dry-run', *a))
        source_before = fingerprint(o), fingerprint(n)
        env = os.environ.copy(); env.update(SWAY_MIGRATION_TESTING='1', SWAY_MIGRATION_TEST_FAIL=point)
        if point.startswith('kill-'):
            proc = subprocess.run(['python3', str(here / 'migration.py'), '--apply', *map(str, a), '--expect', t], capture_output=True, env=env)
            assert proc.returncode == -9, f'expected SIGKILL, got {proc.returncode}'
        else:
            run('--apply', *a, '--expect', t, env=env, ok=False)
        run('--restore', *a)
        assert (h / '.config/sway').is_symlink() and (h / '.config/sway/monitors.conf').read_text() == 'output custom\n'
        assert (fingerprint(o), fingerprint(n)) == source_before
    print('PASS T11 T13 injected failures, SIGKILL and partial restore')
    h, o, n = fixture(base / 'permission-error'); a = opts(h, o, n); t = token(run('--dry-run', *a))
    (h / '.config').chmod(0o500)
    try:
        run('--apply', *a, '--expect', t, ok=False)
    finally:
        (h / '.config').chmod(0o700)
    run('--restore', *a)
    assert (h / '.config/sway').is_symlink()
    print('PASS T10 filesystem write failure and recovery')
    h, o, n = fixture(base / 'changed-plan'); a = opts(h, o, n); t = token(run('--dry-run', *a))
    (o / m.ROOTS['.config/sway'] / 'new-file').write_text('changed')
    run('--apply', *a, '--expect', t, ok=False)
    assert (h / '.config/sway').is_symlink()
    print('PASS changed source since dry-run blocks apply')
    for i, broken in enumerate([False, True]):
        h, o, n = fixture(base / f'conflict-{i}'); link = h / '.config/sway'
        link.unlink(); link.symlink_to((base / 'missing') if broken else (o / m.ROOTS['.config/waybar']))
        run('--dry-run', *opts(h, o, n), ok=False)
    print('PASS T07 T08 unexpected and broken symlinks blocked')
    h, o, n = fixture(base / 'internal-link'); a = opts(h, o, n)
    (o / m.ROOTS['.config/sway'] / 'custom-link').symlink_to('/etc')
    run('--dry-run', *a, ok=False)
    print('PASS unexpected internal symlink requires manual review')
    h, o, n = fixture(base / 'external-write-symlink'); a = opts(h, o, n)
    (h / '.config/gtk-3.0').symlink_to(o / m.ROOTS['.config/sway'], target_is_directory=True)
    run('--dry-run', *a, ok=False)
    print('PASS external GTK write path symlink blocked')
    h, o, n = fixture(base / 'unreadable-source'); a = opts(h, o, n)
    hidden = o / m.ROOTS['.config/sway'] / 'private-directory'
    hidden.mkdir(); (hidden / 'private').write_text('do not omit')
    hidden.chmod(0)
    try:
        run('--dry-run', *a, ok=False)
    finally:
        hidden.chmod(0o700)
    assert (h / '.config/sway').is_symlink()
    print('PASS unreadable source directory blocks migration')
    h, o, n = fixture(base / 'damaged-backup'); a = opts(h, o, n); t = token(run('--dry-run', *a))
    run('--apply', *a, '--expect', t)
    archive = h / '.local/state/sway-minimal/migrations/test/before.tar.gz'
    with archive.open('ab') as f: f.write(b'damage')
    run('--restore', *a, ok=False)
    assert not (h / '.config/sway').is_symlink()
    print('PASS damaged backup blocks restore')
    h, o, n = fixture(base / 'changed-old-source'); a = opts(h, o, n); t = token(run('--dry-run', *a))
    run('--apply', *a, '--expect', t)
    (o / m.ROOTS['.config/sway'] / 'personal.txt').write_text('changed externally')
    run('--restore', *a, ok=False)
    assert not (h / '.config/sway').is_symlink()
    assert (h / '.config/sway/personal.txt').read_text() == 'personal data\n'
    print('PASS changed old source blocks restore without losing new data')

    # Hash-pinned reconciliation; old and new contain intentionally different look.sh.
    h, o, n = fixture(base / 'reconciliation'); a = opts(h, o, n)
    rel = 'sway/.config/sway/scripts/look.sh'
    for root, text in [(o, 'old look\n'), (n, 'new look\n')]:
        path = root / rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text); path.chmod(0o755)
    policy = base / 'approval.json'
    entry = {'path': rel, 'type': 'file', 'old_sha256': m.digest(o / rel), 'new_sha256': m.digest(n / rel),
             'old_mode': 0o755, 'new_mode': 0o755, 'reason': 'test intentional update'}
    policy.write_text(json.dumps({'version': 1, 'updates': [entry]}))
    run('--dry-run', *a, ok=False)
    allowed = [*a, '--allow', policy]
    out = run('--dry-run', *allowed); t = token(out)
    assert 'UPDATE-LINK scripts/look.sh' in out
    old_before, new_before = fingerprint(o), fingerprint(n)
    run('--apply', *allowed, '--expect', t)
    assert (h / '.config/sway/scripts/look.sh').read_text() == 'new look\n'
    run('--verify', *a)
    print('PASS R01 intentional update uses exact hash-pinned approval')
    run('--apply', *allowed, '--expect', t)
    assert (h / '.config/sway/scripts/look.sh').read_text() == 'new look\n'
    print('PASS R08 repeated migration unchanged')
    run('--restore', *a)
    assert (h / '.config/sway/scripts/look.sh').read_text() == 'old look\n'
    assert (fingerprint(o), fingerprint(n)) == (old_before, new_before)
    print('PASS R06 R07 restore old version and preserve both sources')

    h, o, n = fixture(base / 'stale-approval'); a = opts(h, o, n)
    for root, text in [(o, 'old look\n'), (n, 'new look\n')]:
        path = root / rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text); path.chmod(0o755)
    allowed = [*a, '--allow', policy]
    t = token(run('--dry-run', *allowed))
    (o / rel).write_text('user changed active file\n')
    run('--apply', *allowed, '--expect', t, ok=False)
    run('--dry-run', *allowed, ok=False)
    assert (h / '.config/sway').is_symlink()
    print('PASS R02 R09 changed active version and stale approval rejected')
    (o / rel).write_text('old look\n'); (o / rel).chmod(0o755)
    t = token(run('--dry-run', *allowed))
    (n / rel).write_text('changed destination\n')
    run('--apply', *allowed, '--expect', t, ok=False)
    print('PASS R04 changed destination rejected')
    (n / rel).write_text('new look\n'); (n / rel).chmod(0o755)
    (n / m.ROOTS['.config/foot'] / 'base.conf').write_text('unexpected change\n')
    run('--dry-run', *allowed, ok=False)
    print('PASS R03 unexpected unapproved difference rejected')
    (n / m.ROOTS['.config/fish'] / 'base.conf').write_text('another change\n')
    proc = subprocess.run(['python3', str(here / 'migration.py'), '--dry-run', *map(str, allowed)], text=True, capture_output=True)
    assert proc.returncode != 0 and '.config/foot/base.conf' in proc.stderr and '.config/fish/base.conf' in proc.stderr
    inv = json.loads(run('--inventory', *allowed))
    assert any(x['path'] == rel and x['disposition'] == 'approved-update' for x in inv['differences'])
    assert sum(x['disposition'] == 'review' for x in inv['differences']) >= 2
    print('PASS R10 preflight and inventory list multiple conflicts')
    h, o, n = fixture(base / 'inventory-blockers'); a = opts(h, o, n)
    for rel_target in ['.config/foot', '.config/fish']:
        link = h / rel_target
        link.unlink(); link.symlink_to(base / 'absent-target', target_is_directory=True)
    (o / m.ROOTS['.config/sway'] / 'unexpected-link').symlink_to('/etc')
    inv = json.loads(run('--inventory', *a))
    assert any('.config/foot' in x for x in inv['blockers'])
    assert any('.config/fish' in x for x in inv['blockers'])
    assert any('unexpected-link' in x for x in inv['blockers'])
    print('PASS inventory reports multiple ownership and source-link blockers')

    # Policy changes invalidate an otherwise identical plan.
    h, o, n = fixture(base / 'changed-policy'); a = opts(h, o, n)
    for root, text in [(o, 'old look\n'), (n, 'new look\n')]:
        path = root / rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text); path.chmod(0o755)
    allowed = [*a, '--allow', policy]
    t = token(run('--dry-run', *allowed)); original_policy = policy.read_text()
    edited = json.loads(original_policy); edited['updates'][0]['reason'] = 'different explanation'
    policy.write_text(json.dumps(edited))
    run('--apply', *allowed, '--expect', t, ok=False)
    assert (h / '.config/sway').is_symlink()
    policy.write_text(original_policy)
    print('PASS policy content change invalidates plan')

    # Replacement with identical bytes still changes identity and invalidates the plan.
    h, o, n = fixture(base / 'same-bytes-replacement'); a = opts(h, o, n)
    t = token(run('--dry-run', *a))
    victim = n / m.ROOTS['.config/sway'] / 'base.conf'
    replacement = victim.with_name('replacement.tmp')
    replacement.write_bytes(victim.read_bytes()); replacement.chmod(victim.stat().st_mode & 0o777)
    replacement.replace(victim)
    run('--apply', *a, '--expect', t, ok=False)
    assert (h / '.config/sway').is_symlink()
    print('PASS inode replacement with identical content invalidates plan')

    h, o, n = fixture(base / 'link-swap'); a = opts(h, o, n)
    t = token(run('--dry-run', *a))
    link = h / '.config/sway'; same_target = link.resolve()
    link.unlink(); link.symlink_to(same_target, target_is_directory=True)
    run('--apply', *a, '--expect', t, ok=False)
    assert link.is_symlink() and link.resolve() == same_target
    print('PASS changed link identity/target spelling invalidates plan')

    # Unstow and reinstall in an isolated migrated HOME; keep mutable files.
    h, o, n = fixture(base / 'unstow-reinstall'); a = opts(h, o, n)
    t = token(run('--dry-run', *a)); run('--apply', *a, '--expect', t)
    tx = h / '.local/state/sway-minimal/migrations/test'
    data = json.loads((tx / 'manifest.json').read_text())
    cmd = m.stow_command(data)
    delete_cmd = [('--delete' if x == '--simulate' else x) for x in cmd]
    subprocess.run(delete_cmd, check=True, capture_output=True)
    assert (h / '.config/sway/monitors.conf').read_text() == 'output custom\n'
    assert not (h / '.config/waybar/config.jsonc').is_symlink()
    assert not (h / '.config/sway/base.conf').exists()
    install_cmd = [x for x in cmd if x != '--simulate']
    subprocess.run(install_cmd, check=True, capture_output=True)
    assert (h / '.config/sway/base.conf').is_symlink()
    run('--verify', *a)
    print('PASS Stow no-folding remove and reinstall preserve mutable files')

    # Real working-copy script's read-only CLI and cancelled menu, in a fake HOME.
    sandbox = base / 'look-cli-home'; scripts = sandbox / '.config/sway/scripts/helpers'
    scripts.mkdir(parents=True)
    (sandbox / '.config/sway/themes').symlink_to(here.parent / 'sway/.config/sway/themes', target_is_directory=True)
    (sandbox / '.config/waybar').mkdir(parents=True)
    (sandbox / '.config/waybar/styles').symlink_to(here.parent / 'sway/.config/waybar/styles', target_is_directory=True)
    (scripts / 'doctor.sh').write_text('#!/bin/sh\nprintf "doctor-ok\\n"\n')
    (scripts / 'fuzzel-menu.sh').write_text('#!/bin/sh\nexit 0\n'); (scripts / 'fuzzel-menu.sh').chmod(0o755)
    look = here.parent / 'sway/.config/sway/scripts/look.sh'
    env = os.environ.copy(); env['HOME'] = str(sandbox); env['SWAY_MINIMAL_RENDER_ONLY'] = '1'
    for args, expected in [(['--help'], 'Usage:'), (['status'], 'theme='), (['themes'], 'ice'), (['styles'], 'pragmatic'), (['doctor'], 'doctor-ok')]:
        proc = subprocess.run(['sh', str(look), *args], text=True, capture_output=True, env=env)
        assert proc.returncode == 0 and expected in proc.stdout, (args, proc.stderr)
    subprocess.run(['sh', str(look)], check=True, env=env, capture_output=True)
    subprocess.run(['sh', '-n', str(look)], check=True)
    print('PASS R05 help, status, themes, styles, doctor and cancelled menu')
print('ALL TESTS PASSED')
