#!/usr/bin/env python3
"""derive_walk.py — batch driver for the in-game derive probe.

Runs a list of derive commands sequentially through the file-RPC
(derive_in.txt -> derive_out.log), returns each command's fresh output
lines. Used for live pointer-chain walks without redeploying anything.

Usage (as a module):
    from derive_walk import dcmd
    v = dcmd('read 7FF96A080000+3326468 ptr')   # NOT supported: use daddr
"""
import os, sys, time

APPDATA = os.path.join(os.environ['APPDATA'], 'Arrowhead', 'Helldivers2')
IN = os.path.join(APPDATA, 'derive_in.txt')
OUT = os.path.join(APPDATA, 'derive_out.log')

def _size(p):
    try: return os.path.getsize(OUT)
    except OSError: return 0

def dcmd(cmd, timeout=12.0):
    """send one derive command, wait for the log to grow, return new lines."""
    before = _size(OUT)
    with open(IN, 'w', encoding='ascii') as f:
        f.write(cmd.strip() + '\n')
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(0.35)
        now = _size(OUT)
        if now > before:
            time.sleep(0.15)          # let multi-line writes finish
            with open(OUT, 'rb') as f:
                f.seek(before)
                return f.read().decode('utf-8', 'replace').strip().splitlines()
    return ['<TIMEOUT waiting for: %s>' % cmd]

def readval(cmd_expr):
    """convenience: issue 'read <expr> <type>' and parse the = value."""
    lines = dcmd('read ' + cmd_expr)
    for l in lines:
        if ' = ' in l: return l.split(' = ', 1)[1].strip()
    raise RuntimeError('no value: %r' % lines)

if __name__ == '__main__':
    for c in sys.argv[1:]:
        for l in dcmd(c): print(l)
        print('---')
