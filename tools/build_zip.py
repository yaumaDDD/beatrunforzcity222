#!/usr/bin/env python3
"""Build beatrun_zcity_<version>.zip from the repository tree.

The archive layout is exactly the one Garry's Mod expects after unpacking into
garrysmod/addons/:

    beatrun_zcity/
        addon.json
        lua/
        models/
        sound/
        resource/

The sound files are not stored loose in the repository (see sound.zip), so they are
merged back in here. The version is taken from lua/autorun/beatrun_zcity_loader.lua,
which keeps the archive and the "[Beatrun Z-City] version ..." console line in sync.

Usage:  python3 tools/build_zip.py
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOADER = os.path.join(ROOT, 'lua', 'autorun', 'beatrun_zcity_loader.lua')
SOUNDS = os.path.join(ROOT, 'sound.zip')
DIRS = ['lua', 'models', 'resource']


def addon_version():
    text = open(LOADER, encoding='utf-8').read()
    m = re.search(r'local\s+THIS_VERSION\s*=\s*"([^"]+)"', text)
    if not m:
        sys.exit('no THIS_VERSION in ' + LOADER)
    return m.group(1)


def collect():
    files = ['addon.json']
    for d in DIRS:
        for root, _dirs, names in os.walk(os.path.join(ROOT, d)):
            for name in names:
                full = os.path.join(root, name)
                files.append(os.path.relpath(full, ROOT).replace('\\', '/'))
    return sorted(files)


def main():
    version = addon_version()
    out_path = os.path.join(ROOT, 'beatrun_zcity_%s.zip' % version)

    with zipfile.ZipFile(SOUNDS) as snd:
        sound_names = [n for n in snd.namelist() if not n.endswith('/')]
    files = collect() + sound_names

    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        # directory placeholders, like the shipped archives had
        written_dirs = set()
        for rel in files:
            parts = rel.split('/')
            for i in range(1, len(parts)):
                d = '/'.join(parts[:i])
                if d not in written_dirs:
                    out.writestr('beatrun_zcity/' + d + '/', '')
                    written_dirs.add(d)
        for rel in files:
            arc = 'beatrun_zcity/' + rel
            if rel.startswith('sound/'):
                with zipfile.ZipFile(SOUNDS) as snd:
                    data = snd.read(rel)
                out.writestr(arc, data)
            else:
                out.write(os.path.join(ROOT, rel), arc)

    with zipfile.ZipFile(out_path) as z:
        inner = z.read('beatrun_zcity/lua/autorun/beatrun_zcity_loader.lua').decode('utf-8')
        if ('"%s"' % version) not in inner:
            sys.exit('version mismatch inside the archive')
        print('built %s  (%d files, %.1f MB, version %s)'
              % (os.path.basename(out_path), len(z.namelist()),
                 os.path.getsize(out_path) / 1048576.0, version))


if __name__ == '__main__':
    main()
