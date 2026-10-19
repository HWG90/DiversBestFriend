"""Build a local fixture from pinned CSC/HD2Runtime releases, then run ASS tests.
No third-party source is distributed in the ASS candidate.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CSC_SHA = 'd897fe63e1b8a7bc949c5dbb1281ed4e5f3fb571282208efe0bacfef47c30865'
RUNTIME_SHA = '3357d8b2b832dad23dd96af90e21d4fcdea60367a097a172d7e749ddbc1ff0ab'

def checked(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Unverified release archive: ' + str(path))
    return zipfile.ZipFile(path)

def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--compendium-zip', type=Path, required=True)
    parser.add_argument('--runtime-zip', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    with checked(args.compendium_zip, CSC_SHA) as csc:
        definitions = json.loads(csc.read('custom_stratagems.json'))['stratagems']
    with checked(args.runtime_zip, RUNTIME_SHA) as runtime:
        archive = runtime.read('runtime/9ba626afa44a3aa3.patch_0')
    spec = importlib.util.spec_from_file_location('ass_packager', ROOT / 'build.py')
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    target = packager.resource_hash('hd2runtime/runtime/calldown_codes')
    magic, types, count = struct.unpack_from('<III', archive)
    assert magic == 0xF0000011 and 0 < types <= 1024 and 0 < count <= 100000
    start = 72 + types * 32
    assert start + count * 80 <= len(archive)
    matches = []
    for index in range(count):
        record = start + index * 80
        name, _, offset = struct.unpack_from('<3Q', archive, record)
        size = struct.unpack_from('<I', archive, record + 56)[0]
        if name == target:
            assert start + count * 80 <= offset and offset + size <= len(archive)
            blob = archive[offset:offset + size]
            assert struct.unpack_from('<II', blob) == (size - 8, 2)
            matches.append(blob[8:])
    assert len(matches) == 1
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    owner = output / 'hd2runtime-calldown-0.40.0.lua'
    owner.write_bytes(matches[0])
    cases = []
    for item in definitions:
        values = [['up', 'right', 'down', 'left'].index(d) + 1 for d in item['code']]
        assert 1 <= len(values) <= 9
        cases.append('{id=' + json.dumps(item['id']) + ',values={' + ','.join(map(str, values)) + '}}')
    fixture = output / 'compendium-code-fixture.lua'
    fixture.write_text('return {owner_source=' + json.dumps(owner.as_posix()) + ',cases={' + ','.join(cases) + '}}\n')
    env = dict(os.environ, ASS_CUSTOM_CODES_FIXTURE=str(fixture))
    subprocess.run([sys.executable, 'scripts/test.py'], cwd=ROOT, env=env, check=True)
    report = {'compendium_version': '0.4.1', 'compendium_sha256': CSC_SHA,
              'hd2runtime_version': '0.40.0', 'hd2runtime_sha256': RUNTIME_SHA,
              'owner_source_sha256': hashlib.sha256(matches[0]).hexdigest(),
              'shipped_codes_tested': len(cases), 'full_ass_suite': 'passed',
              'in_game_verified': False, 'deployed': False}
    (output / 'custom-stratagem-validation.json').write_text(json.dumps(report, indent=2) + '\n')

if __name__ == '__main__':
    main()
