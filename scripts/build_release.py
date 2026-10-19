"""Build all R45 variants and checksums; does not deploy or publish."""
from pathlib import Path
import hashlib,runpy,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from release_package import build,OUT

def main():
    runpy.run_path(str(ROOT/'native-selection-poc/build_poc.py'),run_name='__main__')
    targets=[OUT/'DiversBestFriend-R45-BSL.zip',build('MDL'),build('LLL')]
    (OUT/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in targets),encoding='ascii')
    print(OUT/'SHA256SUMS.txt')
if __name__=='__main__':main()
