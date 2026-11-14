#!/usr/bin/env python3
"""Conservative folded-Stow migration. Run --dry-run before --apply."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import signal
import stat
import subprocess
import sys
import tarfile

ROOTS = {
    '.config/sway': 'sway/.config/sway',
    '.config/waybar': 'sway/.config/waybar',
    '.config/swaylock': 'sway/.config/swaylock',
    '.config/foot': 'foot/.config/foot',
    '.config/fuzzel': 'fuzzel/.config/fuzzel',
    '.config/swaync': 'swaync/.config/swaync',
    '.config/fish': 'fish/.config/fish',
    '.config/Thunar': 'thunar/.config/Thunar',
    '.config/xfce4': 'xfce/.config/xfce4',
    '.config/xsettingsd': 'xsettingsd/.config/xsettingsd',
    '.local/share/xfce4': 'xfce/.local/share/xfce4',
}
FILES = {'.local/bin/sway-satellite.sh': 'sway/.local/bin/sway-satellite.sh'}
MUTABLE = {
    '.config/sway': {'theme', 'border', 'smart-borders', 'gaps', 'bar-mode', 'bar-style', 'bar-position', 'cursor', 'cursor-size', 'look', 'wallpaper', 'monitors.conf', 'workspaces', 'outputs'},
    '.config/waybar': {'config.jsonc', 'theme.css', 'style-variant.css', 'state.css'},
    '.config/foot': {'theme.ini'}, '.config/fuzzel': {'fuzzel.ini'},
    '.config/swaync': {'theme.css'}, '.config/swaylock': {'theme-colors'},
    '.config/fish': {'fish_variables', 'fish_history'},
}
EXTERNAL_SINKS = ('.config/gtk-3.0/settings.ini', '.config/gtk-4.0/settings.ini', '.icons/default/index.theme')

def fail(message):
    raise RuntimeError(message)

def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()

def lexists(path):
    return os.path.lexists(path)

def no_symlink_parents(path, stop):
    path, stop = Path(os.path.abspath(path)), Path(os.path.abspath(stop))
    try:
        rel = path.relative_to(stop)
    except ValueError:
        fail(f'{path} is outside {stop}')
    p = stop
    if p.is_symlink():
        fail(f'symlink parent: {p}')
    for part in rel.parts:
        p = p / part
        if p.is_symlink():
            fail(f'symlink parent: {p}')

def check_external_sinks(home):
    # Legacy look.sh writes here as well, outside the Stow packages.
    for rel in EXTERNAL_SINKS:
        check_external_sink(home, rel)

def check_external_sink(home, rel):
    path = home / rel
    no_symlink_parents(path, home)
    parent = home
    for part in Path(rel).parts[:-1]:
        parent = parent / part
        if lexists(parent) and not parent.is_dir():
            fail(f'generated output parent is not a directory: {parent}')
    if lexists(path) and not path.is_file():
        fail(f'generated output is not an ordinary file: {path}')
    if path.is_file() and path.stat().st_nlink != 1:
        fail(f'generated output has hard links and needs review: {path}')

def walk_error(error):
    raise error

def identity(st):
    return {'device': st.st_dev, 'inode': st.st_ino, 'ctime_ns': st.st_ctime_ns,
            'uid': st.st_uid, 'gid': st.st_gid}

def equivalent(a, b):
    return all(a.get(k) == b.get(k) for k in ('type', 'mode', 'sha256'))

def load_approvals(path):
    if path is None:
        return {}, None
    no_symlink_parents(path, Path('/'))
    raw = path.read_bytes()
    data = json.loads(raw)
    if not isinstance(data, dict) or set(data) != {'version', 'updates'} or data['version'] != 1 or not isinstance(data['updates'], list):
        fail('invalid approval manifest format')
    updates = {}
    fields = {'path', 'type', 'old_sha256', 'new_sha256', 'old_mode', 'new_mode', 'reason'}
    for entry in data['updates']:
        if not isinstance(entry, dict) or set(entry) != fields:
            fail('invalid approval entry fields')
        name = entry['path']
        if not isinstance(name, str) or not name or name.startswith('/') or any(p in ('', '.', '..') for p in name.split('/')) or name in updates:
            fail('invalid or duplicate approval path')
        if (entry['type'] != 'file' or not isinstance(entry['reason'], str) or not entry['reason'].strip()
                or any(not isinstance(entry[k], str) or not re.fullmatch(r'[0-9a-f]{64}', entry[k]) for k in ('old_sha256', 'new_sha256'))
                or any(type(entry[k]) is not int or not 0 <= entry[k] <= 0o7777 for k in ('old_mode', 'new_mode'))):
            fail(f'invalid approval: {name}')
        updates[name] = entry
    return updates, hashlib.sha256(raw).hexdigest()

def approved(approvals, name, old_info, new_info):
    a = approvals.get(name)
    return bool(a and old_info['type'] == new_info['type'] == a['type']
                and old_info['sha256'] == a['old_sha256'] and new_info['sha256'] == a['new_sha256']
                and old_info['mode'] == a['old_mode'] and new_info['mode'] == a['new_mode'])

def inventory(home, old, new, approval_path):
    """Read-only complete package comparison, including links and directory modes."""
    approvals, _ = load_approvals(approval_path)
    packages = sorted({p.split('/')[0] for p in (*ROOTS.values(), *FILES.values())})
    blockers = []
    targets = []
    for rel, src in {**ROOTS, **FILES}.items():
        target, expected = home / rel, old / src
        try:
            no_symlink_parents(target.parent, home)
            if not lexists(target):
                status = 'missing-not-migrated'
            elif not target.is_symlink() or not target.exists():
                status = 'blocked-not-owned-or-broken'
            elif not expected.exists() or target.resolve() != expected.resolve():
                status = 'blocked-unexpected-target'
            else:
                status = 'folded-stow'
            targets.append({'path': rel, 'status': status})
            if status.startswith('blocked-'):
                blockers.append(f'{rel}: {status}')
        except (OSError, RuntimeError) as e:
            blockers.append(f'{rel}: {e}')
            targets.append({'path': rel, 'status': 'blocked', 'error': str(e)})
    for rel in EXTERNAL_SINKS:
        try:
            check_external_sink(home, rel)
        except (OSError, RuntimeError) as e:
            blockers.append(f'{rel}: {e}')
    def scan(base):
        entries = {}
        for package in packages:
            root = base / package
            if not root.is_dir() or root.is_symlink():
                fail(f'package is missing or a symlink: {root}')
            for current, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
                for name in sorted(dirs + files):
                    p = Path(current) / name
                    st = p.lstat()
                    rel = p.relative_to(base).as_posix()
                    info = {'mode': stat.S_IMODE(st.st_mode)}
                    if stat.S_ISLNK(st.st_mode):
                        info.update(type='symlink', target=os.readlink(p))
                    elif stat.S_ISREG(st.st_mode):
                        info.update(type='file', sha256=digest(p))
                    elif stat.S_ISDIR(st.st_mode):
                        info.update(type='dir')
                    else:
                        info.update(type='special')
                    entries[rel] = info
        return entries
    a, b = scan(old), scan(new)
    result = []
    for name in sorted(a.keys() | b.keys()):
        before, after = a.get(name), b.get(name)
        if before == after and before and before['type'] not in ('symlink', 'special'):
            continue
        disposition = 'review'
        if (before and before['type'] in ('symlink', 'special')) or (after and after['type'] in ('symlink', 'special')):
            disposition = 'blocked-internal-link-or-special'
            blockers.append(f'{name}: {disposition}')
        if before and after and before['type'] == after['type'] == 'file' and approved(approvals, name, before, after):
            disposition = 'approved-update'
        for dest, src in ROOTS.items():
            if name.startswith(src + '/'):
                sub = name[len(src) + 1:]
                if disposition != 'blocked-internal-link-or-special' and (sub in MUTABLE.get(dest, set()) or (dest == '.config/sway' and (sub.startswith('monitor') or sub.startswith('workspace')))):
                    disposition = 'preserve-local'
                break
        if disposition != 'blocked-internal-link-or-special' and before is not None and after is None:
            disposition = 'preserve-old-review'
        elif disposition != 'blocked-internal-link-or-special' and after is not None and before is None:
            disposition = 'new-source-review'
        result.append({'path': name, 'old': before, 'new': after, 'disposition': disposition})
    print(json.dumps({'packages': packages, 'objects': len(a.keys() | b.keys()), 'targets': targets,
                      'blockers': blockers, 'differences': result}, indent=2, ensure_ascii=False))

def tree(path):
    """Snapshot without following internal symlinks; reject non-regular entries."""
    result = {}
    for root, dirs, files in os.walk(path, followlinks=False, onerror=walk_error):
        dirs.sort(); files.sort()
        for name in dirs + files:
            p = Path(root) / name
            rel = p.relative_to(path).as_posix()
            st = p.lstat()
            if stat.S_ISLNK(st.st_mode):
                fail(f'internal symlink requires manual review: {p}')
            if stat.S_ISDIR(st.st_mode):
                result[rel] = {'type': 'dir', 'mode': stat.S_IMODE(st.st_mode), **identity(st)}
            elif stat.S_ISREG(st.st_mode):
                result[rel] = {'type': 'file', 'mode': stat.S_IMODE(st.st_mode), 'sha256': digest(p), **identity(st)}
            else:
                fail(f'unsupported filesystem object: {p}')
    return result

def plan(home, old, new, approval_path=None):
    if not home.is_dir() or home.is_symlink():
        fail('HOME must be an existing ordinary directory')
    if old == new or not old.is_dir() or not new.is_dir():
        fail('old and new must be different existing directories')
    if any(source == home or source in home.parents for source in (old, new)):
        fail('HOME may not be inside either source project')
    check_external_sinks(home)
    approvals, approval_hash = load_approvals(approval_path)
    records, conflicts, used = [], [], set()
    for rel, source in {**ROOTS, **FILES}.items():
        target, a, b = home / rel, old / source, new / source
        no_symlink_parents(target.parent, home)
        no_symlink_parents(a, old)
        no_symlink_parents(b, new)
        if not lexists(target):
            # Missing packages remain missing. This is not a clean installer.
            continue
        if not target.is_symlink() or not target.exists():
            fail(f'expected a non-broken folded Stow symlink: {target}')
        if not a.exists() or not b.exists() or target.resolve() != a.resolve():
            fail(f'unexpected Stow ownership or missing source: {target}')
        record = {'path': rel, 'source': source, 'original_link': os.readlink(target), 'link_identity': identity(target.lstat()), 'kind': 'dir' if rel in ROOTS else 'file'}
        if rel in ROOTS:
            if not a.is_dir() or not b.is_dir():
                fail(f'expected source directories for {target}')
            oldtree, newtree = tree(a), tree(b)
            record['old_root_identity'] = identity(a.stat())
            record['new_root_identity'] = identity(b.stat())
            record['old_root_mode'] = stat.S_IMODE(a.stat().st_mode)
            record['new_root_mode'] = stat.S_IMODE(b.stat().st_mode)
            record['old_tree'], record['new_tree'], record['actions'] = oldtree, newtree, {}
            for name, info in oldtree.items():
                if name in newtree and newtree[name]['type'] != info['type']:
                    conflicts.append(f'conflicting file/directory types: {target / name}')
                    continue
                if info['type'] != 'file':
                    continue
                newer = newtree.get(name)
                mutable = name in MUTABLE.get(rel, set()) or (rel == '.config/sway' and (name.startswith('monitor') or name.startswith('workspace')))
                if mutable or newer is None:
                    action = 'copy-user' if newer is None else 'copy-mutable'
                elif not equivalent(newer, info):
                    full = source + '/' + name
                    if approved(approvals, full, info, newer):
                        action = 'update-link'
                        used.add(full)
                    else:
                        conflicts.append(f'conflicting changed source file: {target / name} old={info["sha256"]} new={newer["sha256"]}')
                        continue
                else:
                    action = 'link'
                record['actions'][name] = action
            for name, info in newtree.items():
                if info['type'] == 'file' and name not in oldtree:
                    mutable = name in MUTABLE.get(rel, set()) or (rel == '.config/sway' and (name.startswith('monitor') or name.startswith('workspace')))
                    if not mutable:
                        record['actions'][name] = 'new-link'
        else:
            if not a.is_file() or not b.is_file():
                conflicts.append(f'conflicting file source: {target}')
                continue
            ai = {'type': 'file', 'mode': stat.S_IMODE(a.stat().st_mode), 'sha256': digest(a), **identity(a.stat())}
            bi = {'type': 'file', 'mode': stat.S_IMODE(b.stat().st_mode), 'sha256': digest(b), **identity(b.stat())}
            if not equivalent(ai, bi):
                if approved(approvals, source, ai, bi):
                    used.add(source)
                else:
                    conflicts.append(f'conflicting file source: {target} old={ai["sha256"]} new={bi["sha256"]}')
                    continue
            record['sha256'], record['old_file'], record['new_file'] = ai['sha256'], ai, bi
        records.append(record)
    for unused in sorted(set(approvals) - used):
        conflicts.append(f'unused or stale approval: {unused}')
    if conflicts:
        fail('preflight conflicts:\n  ' + '\n  '.join(conflicts))
    if not records:
        fail('no expected folded Stow links found')
    payload = {'version': 1, 'home': str(home), 'old': str(old), 'new': str(new), 'records': records,
               'approval_path': str(approval_path) if approval_path else None, 'approval_sha256': approval_hash,
               'approved_updates': {k: approvals[k] for k in sorted(used)}}
    token = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return payload, token

def write_json(path, obj):
    tmp = path.with_name(path.name + '.tmp')
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)

def describe(data, token):
    for r in data['records']:
        print(f"UNFOLD {r['path']}: {r['original_link']}")
        for name, action in r.get('actions', {}).items():
            print(f'  {action.upper()} {name}')
    for name, approval in data['approved_updates'].items():
        print(f'APPROVED {name}: {approval["old_sha256"]} -> {approval["new_sha256"]} ({approval["reason"]})')
    print(f'PLAN-SHA256 {token}')
    print('BACKUP: original links, metadata and full source contents for listed directories')

def backup(tx, data):
    archive = tx / 'before.tar.gz'
    with tarfile.open(archive, 'w:gz', dereference=False) as t:
        for i, r in enumerate(data['records']):
            t.add(Path(data['home']) / r['path'], arcname=f'links/{i}', recursive=False)
            t.add(Path(data['old']) / r['source'], arcname=f'contents/{i}', recursive=True)
    # Read all members and contents before any HOME target is changed.
    with tarfile.open(archive, 'r:gz') as t:
        for member in t:
            if member.isfile():
                f = t.extractfile(member)
                while f.read(1024 * 1024):
                    pass
    with tarfile.open(archive, 'r:gz') as t:
        for i, r in enumerate(data['records']):
            link = t.getmember(f'links/{i}')
            if not link.issym() or link.linkname != r['original_link']:
                fail('backup link does not match preflight')
            files = r.get('old_tree', {})
            if r['kind'] == 'file':
                files = {'': {'type': 'file', 'sha256': r['sha256']}}
            for name, info in files.items():
                if info['type'] != 'file':
                    continue
                member = t.getmember(f'contents/{i}' + ('/' + name if name else ''))
                f = t.extractfile(member)
                h = hashlib.sha256()
                for chunk in iter(lambda: f.read(1024 * 1024), b''):
                    h.update(chunk)
                if h.hexdigest() != info['sha256']:
                    fail(f'backup contents differ from preflight: {r["path"]}/{name}')
    data['archive_sha256'] = digest(archive)
    write_json(tx / 'manifest.json', data)

def injected(point):
    if os.environ.get('SWAY_MIGRATION_TEST_FAIL') == 'kill-' + point:
        if os.environ.get('SWAY_MIGRATION_TESTING') != '1':
            fail('test failure injection requires SWAY_MIGRATION_TESTING=1')
        os.kill(os.getpid(), signal.SIGKILL)
    if os.environ.get('SWAY_MIGRATION_TEST_FAIL') == point:
        if os.environ.get('SWAY_MIGRATION_TESTING') != '1':
            fail('test failure injection requires SWAY_MIGRATION_TESTING=1')
        fail(f'injected failure: {point}')

def apply(home, old, new, backup_dir, txid, expected, approval_path):
    tx = backup_dir / txid
    if tx.exists():
        data = json.loads((tx / 'manifest.json').read_text())
        if data.get('status') == 'complete':
            verify(tx, home)
            print('Already migrated and verified; no changes.')
            return
        fail(f'transaction already exists; use --restore --id {txid}')
    data, token = plan(home, old, new, approval_path)
    if not expected or expected != token:
        fail('plan changed or --expect is missing; rerun --dry-run')
    no_symlink_parents(backup_dir, home)
    for prohibited in (home / '.config', old, new):
        if backup_dir == prohibited or prohibited in backup_dir.parents:
            fail(f'backup may not be inside {prohibited}')
    backup_dir.mkdir(parents=True, exist_ok=True)
    for r in data['records']:
        if backup_dir.stat().st_dev != (home / r['path']).parent.stat().st_dev:
            fail('backup must be on the same filesystem as every target directory')
    tx.mkdir(mode=0o700)
    (tx / 'original-links').mkdir(); (tx / 'saved-trees').mkdir()
    data.update(status='preparing', token=token, id=txid)
    backup(tx, data)
    injected('after-backup')
    for i, r in enumerate(data['records']):
        target = home / r['path']
        stage = target.parent / ('.sway-migration-' + txid + '-' + str(i))
        if lexists(stage):
            fail(f'staging collision: {stage}')
        r['stage'] = str(stage)
        write_json(tx / 'manifest.json', data)
        if r['kind'] == 'dir':
            stage.mkdir(mode=(old / r['source']).stat().st_mode & 0o777)
            oldbase, newbase = old / r['source'], new / r['source']
            for name, info in r['old_tree'].items():
                if info['type'] == 'dir':
                    (stage / name).mkdir(parents=True, exist_ok=True)
                    os.chmod(stage / name, info['mode'])
            for j, (name, action) in enumerate(r['actions'].items()):
                dest = stage / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                if action in ('link', 'new-link', 'update-link'):
                    os.symlink(os.path.relpath(newbase / name, dest.parent), dest)
                else:
                    shutil.copy2(oldbase / name, dest)
                if i == 0 and j == 0:
                    injected('after-partial-links')
            r['result'] = inspect(stage)
        else:
            os.symlink(os.path.relpath(new / r['source'], stage.parent), stage)
            r['result'] = {'link': os.readlink(stage)}
        write_json(tx / 'manifest.json', data)
        if i == 0:
            injected('after-prepare')
    # Recheck the entire input snapshot immediately before replacing any link.
    _, now = plan(home, old, new, approval_path)
    if now != token:
        fail('input changed while preparing; restore this transaction')
    for r in data['records']:
        stage = Path(r['stage'])
        if r['kind'] == 'dir':
            if stage.is_symlink() or inspect(stage) != r['result']:
                fail(f'stage changed while preparing: {stage}')
        elif not stage.is_symlink() or os.readlink(stage) != r['result']['link']:
            fail(f'stage changed while preparing: {stage}')
    data['status'] = 'switching'; write_json(tx / 'manifest.json', data)
    for i, r in enumerate(data['records']):
        target = home / r['path']
        os.rename(target, tx / 'original-links' / str(i))
        if i == 0:
            injected('after-one-link')
        os.rename(r['stage'], target)
        write_json(tx / 'manifest.json', data)
    injected('before-complete')
    data['status'] = 'complete'; write_json(tx / 'manifest.json', data)
    verify(tx, home)
    print(f'Migration complete. ID: {txid}')

def inspect(path):
    result = {}
    for root, dirs, files in os.walk(path, followlinks=False, onerror=walk_error):
        dirs.sort(); files.sort()
        for name in dirs + files:
            p = Path(root) / name; rel = p.relative_to(path).as_posix(); st = p.lstat()
            if stat.S_ISLNK(st.st_mode):
                result[rel] = {'type': 'link', 'target': os.readlink(p)}
            elif stat.S_ISDIR(st.st_mode):
                result[rel] = {'type': 'dir', 'mode': stat.S_IMODE(st.st_mode)}
            elif stat.S_ISREG(st.st_mode):
                result[rel] = {'type': 'file', 'mode': stat.S_IMODE(st.st_mode), 'sha256': digest(p)}
            else:
                fail(f'unsupported object: {p}')
    return result

def stow_command(data):
    mutable = set().union(*MUTABLE.values())
    pattern = '(^|/)(' + '|'.join(re.escape(x) for x in sorted(mutable)) + '|monitor.*|workspace.*)$'
    packages = sorted({r['source'].split('/')[0] for r in data['records']})
    return ['stow', '--simulate', '--no-folding', '--verbose=1', '--ignore=' + pattern,
            '-d', data['new'], '-t', data['home'], *packages]

def load(tx, expected_home):
    data = json.loads((tx / 'manifest.json').read_text())
    if data.get('home') != str(expected_home) or data.get('id') != tx.name:
        fail('backup HOME or migration ID does not match the requested target')
    allowed = {**ROOTS, **FILES}
    seen = set()
    for i, r in enumerate(data['records']):
        rel = r.get('path')
        if rel not in allowed or rel in seen or r.get('source') != allowed[rel]:
            fail('invalid or duplicate path in manifest')
        seen.add(rel)
        if r.get('stage'):
            expected = expected_home / rel
            expected = expected.parent / ('.sway-migration-' + tx.name + '-' + str(i))
            if r['stage'] != str(expected):
                fail('invalid stage path in manifest')
    if digest(tx / 'before.tar.gz') != data['archive_sha256']:
        fail('backup archive checksum mismatch')
    return data

def verify(tx, expected_home):
    data = load(tx, expected_home); home = Path(data['home'])
    check_external_sinks(home)
    if data['status'] != 'complete':
        fail('transaction not complete')
    for r in data['records']:
        target = home / r['path']
        no_symlink_parents(target.parent, home)
        if r['kind'] == 'dir':
            if target.is_symlink() or not target.is_dir() or inspect(target) != r['result']:
                fail(f'migrated directory differs or contains new data: {target}')
            if not os.access(target, os.W_OK):
                fail(f'configuration directory is not writable: {target}')
            for name, item in r['result'].items():
                mutable = name in MUTABLE.get(r['path'], set()) or (r['path'] == '.config/sway' and (name.startswith('monitor') or name.startswith('workspace')))
                if mutable and item['type'] == 'link':
                    fail(f'mutable file is a symlink: {target / name}')
                if mutable and item['type'] == 'file' and not os.access(target / name, os.W_OK):
                    fail(f'mutable file is not writable: {target / name}')
                if item['type'] == 'link' and not (target / name).is_file():
                    fail(f'broken link: {target / name}')
        elif not target.is_symlink() or os.readlink(target) != r['result']['link']:
            fail(f'migrated link differs: {target}')
    # Stow is invoked in simulation mode with writable files explicitly excluded.
    # Without these exclusions Stow would replace local/generated files by links.
    cmd = stow_command(data)
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode or re.search(r'(?m)^(LINK|UNLINK|MKDIR|RMDIR):', result.stderr + result.stdout):
        fail('Stow simulation reports conflicts or pending changes: ' + (result.stderr + result.stdout).strip())
    print('Verified filesystem and repeated Stow simulation with explicit mutable-file exclusions.')
    print('STOW-DRY-RUN:', shlex.join(cmd))

def restore(tx, expected_home):
    data = load(tx, expected_home); home = Path(data['home'])
    old = Path(data['old'])
    for r in data['records']:
        source = old / r['source']
        if r['kind'] == 'dir':
            if not source.is_dir() or tree(source) != r['old_tree']:
                fail(f'original source changed; restore would expose different data: {source}')
        elif not source.is_file() or digest(source) != r['sha256']:
            fail(f'original source changed; restore would expose different data: {source}')
    # Preflight every root first: refuse to overwrite new/changed user data.
    for i, r in enumerate(data['records']):
        target = home / r['path']; orig = tx / 'original-links' / str(i)
        no_symlink_parents(target.parent, home)
        if lexists(orig):
            if not orig.is_symlink() or os.readlink(orig) != r['original_link']:
                fail(f'original link changed: {orig}')
            if lexists(target):
                if lexists(tx / 'saved-trees' / str(i)):
                    fail(f'backup destination already exists for {target}')
                if r['kind'] == 'dir':
                    if target.is_symlink() or not target.is_dir() or inspect(target) != r.get('result'):
                        fail(f'new or changed data; restore blocked: {target}')
                elif not target.is_symlink() or os.readlink(target) != r['result']['link']:
                    fail(f'new or changed link; restore blocked: {target}')
        elif not target.is_symlink() or os.readlink(target) != r['original_link']:
            fail(f'cannot identify original link safely: {target}')
        stage = Path(r['stage']) if r.get('stage') else None
        if stage and lexists(stage):
            if lexists(tx / 'saved-trees' / ('stage-' + str(i))):
                fail(f'backup stage destination already exists: {stage}')
            if 'result' not in r:
                # Incomplete staging is moved intact to the backup, never deleted.
                continue
            if r['kind'] == 'dir' and (stage.is_symlink() or inspect(stage) != r.get('result')):
                fail(f'stage changed; restore blocked: {stage}')
            if r['kind'] == 'file' and (not stage.is_symlink() or os.readlink(stage) != r['result']['link']):
                fail(f'stage changed; restore blocked: {stage}')
    for i, r in enumerate(data['records']):
        target = home / r['path']; orig = tx / 'original-links' / str(i)
        if lexists(orig):
            if lexists(target):
                os.rename(target, tx / 'saved-trees' / str(i))
            os.rename(orig, target)
        stage = Path(r['stage']) if r.get('stage') else None
        if stage and lexists(stage):
            os.rename(stage, tx / 'saved-trees' / ('stage-' + str(i)))
    data['status'] = 'restored'; write_json(tx / 'manifest.json', data)
    print('Original links restored; migrated trees retained in backup.')

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    modes = ap.add_mutually_exclusive_group()
    for mode in ('dry-run', 'apply', 'verify', 'restore', 'inventory'):
        modes.add_argument('--' + mode, action='store_true')
    ap.add_argument('--home', default=str(Path.home()))
    ap.add_argument('--old', default=str(Path.home() / 'dotfiles-sway-ubuntu-minimal'))
    ap.add_argument('--new', default=str(Path.home() / 'dotfiles-sway-ubuntu-minimal-next-20261112'))
    ap.add_argument('--backup', help='backup root (must be inside target HOME)')
    ap.add_argument('--id', default='migration')
    ap.add_argument('--expect', help='PLAN-SHA256 from --dry-run, required by --apply')
    ap.add_argument('--allow', help='explicit hash-pinned JSON approval manifest')
    a = ap.parse_args()
    if not a.id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in a.id):
        fail('invalid migration ID')
    home, old, new = (Path(os.path.abspath(p)) for p in (a.home, a.old, a.new))
    no_symlink_parents(home, Path('/'))
    no_symlink_parents(old, Path('/'))
    no_symlink_parents(new, Path('/'))
    backup_dir = Path(os.path.abspath(a.backup or home / '.local/state/sway-minimal/migrations'))
    approval_path = Path(os.path.abspath(a.allow)) if a.allow else None
    no_symlink_parents(backup_dir, home)
    tx = backup_dir / a.id
    no_symlink_parents(tx, home)
    no_symlink_parents(home / '.config', home)
    # Lock an existing directory, not a newly-created lockfile: dry-run is read-only.
    lock = os.open(home / '.config', os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(lock, fcntl.LOCK_SH if not (a.apply or a.restore) else fcntl.LOCK_EX)
        if a.inventory:
            inventory(home, old, new, approval_path)
        elif a.verify:
            verify(tx, home)
        elif a.restore:
            restore(tx, home)
        elif a.apply:
            apply(home, old, new, backup_dir, a.id, a.expect, approval_path)
        else:
            describe(*plan(home, old, new, approval_path))
    finally:
        os.close(lock)

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, tarfile.TarError) as e:
        print(f'ERROR: {e}', file=sys.stderr)
        sys.exit(1)
