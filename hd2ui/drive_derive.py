# drive: write a command to derive_in.txt, wait for it to be consumed, then
# wait for an expected log marker.  usage: python drive_derive.py <timeout_s> <cmd> [marker]
import os, sys, time, pathlib

appdata = os.environ['APPDATA']
IN = pathlib.Path(appdata) / 'Arrowhead/Helldivers2/derive_in.txt'
OUT = pathlib.Path(appdata) / 'Arrowhead/Helldivers2/derive_out.log'

timeout = float(sys.argv[1]); cmd = sys.argv[2]
marker = sys.argv[3] if len(sys.argv) > 3 else None

if marker:                       # snapshot log size so we only match NEW output
    base = OUT.stat().st_size if OUT.exists() else 0
else:
    base = 0

IN.write_text(cmd + '\n')
t0 = time.time()
consumed = False
while time.time() - t0 < timeout:
    if not IN.exists() or IN.read_text().strip() == '':
        consumed = True
        break
    time.sleep(0.3)
print(f'CMD {cmd!r} consumed={consumed} after {time.time()-t0:.1f}s')

if marker:
    t0 = time.time()
    while time.time() - t0 < timeout:
        size = OUT.stat().st_size if OUT.exists() else 0
        if size > base:
            with open(OUT, 'r', errors='replace') as f:
                f.seek(base)
                new = f.read()
            if marker in new:
                print(new.strip())
                sys.exit(0)
        time.sleep(0.5)
    print(f'TIMEOUT waiting for {marker!r}')
    sys.exit(1)
