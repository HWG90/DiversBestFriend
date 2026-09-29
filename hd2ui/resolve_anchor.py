# resolve_anchor.py -- one-shot content anchor resolver via the in-game derive
# addon. Scans the 16-byte weapon GUID, validates each hit's magazine/reserve
# fields (kills registry/blob copies), and locks ammo_reader-compatible base.
#
# usage: python hd2ui/resolve_anchor.py <guid_hex32> <mag_off_neg> <res_off_neg>
#                                       <capacity> [expected_mag]
# e.g.:  python hd2ui/resolve_anchor.py 95d2a294b52bd45e6ed282d0e08968b9 24 2C 8 8
import os, sys, time, pathlib

guid_hex = sys.argv[1]
mag_off = -int(sys.argv[2], 16)
res_off = -int(sys.argv[3], 16)
capacity = int(sys.argv[4])
expected = int(sys.argv[5]) if len(sys.argv) > 5 else None

D = pathlib.Path(os.environ['APPDATA']) / 'Arrowhead/Helldivers2'
IN, OUT, TAG = D/'derive_in.txt', D/'derive_out.log', D/'derive_tag.txt'

def run(cmd, marker, timeout):
    base = OUT.stat().st_size
    IN.write_text(cmd + '\n')
    t0 = time.time()
    while time.time() - t0 < timeout:
        size = OUT.stat().st_size
        if size > base:
            new = OUT.read_bytes()[base:].decode(errors='replace')
            if marker in new:
                return new
        time.sleep(0.5)
    return None

out = run('scanb ' + guid_hex, 'SCAN_DONE', 260)
if not out:
    print('SCAN TIMEOUT'); sys.exit(1)
hits = [l.strip() for l in TAG.read_text().splitlines() if l.strip()]
print('raw hits:', hits)

good = []
for h in hits:
    a = int(h, 16)
    r = run('read 0x%X u32' % (a + mag_off), 'READ', 15)
    if not r: continue
    mag = int(r.split('=')[-1].strip())
    r2 = run('read 0x%X u32' % (a + res_off), 'READ', 15)
    res = int(r2.split('=')[-1].strip()) if r2 else -1
    ok = 0 <= mag <= capacity and 0 <= res <= 20000
    print('hit 0x%s: mag=%d res=%d %s' % (h, mag, res, 'PLAUSIBLE' if ok else 'rejected'))
    if ok:
        good.append((a, mag, res))

if len(good) == 1:
    a, mag, res = good[0]
    status = 'LOCKED'
    if expected is not None:
        status += ' (mag matches ammo check: %s)' % (mag == expected)
    print('ANCHOR BASE = 0x%X  mag=%d res=%d -> %s' % (a, mag, res, status))
    (pathlib.Path(os.environ.get('LOCALAPPDATA', '.')) / 'dbf_anchor_locked.txt').write_text(
        '0x%X\n%s\n' % (a, guid_hex))
    sys.exit(0)
else:
    print('AMBIGUOUS or NONE: %d plausible hits' % len(good))
    sys.exit(2)
