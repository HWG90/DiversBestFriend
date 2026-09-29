#!/usr/bin/env python3
"""minidump_triage.py -- parse a Windows minidump without external deps.

Extracts: exception record (code/address), faulting module+offset, the
thread stack's return addresses mapped to modules, and module list info.
Module list entry stride is 108 bytes on these dumps (fixed 2026-09-29;
the earlier 104 assumption corrupted every offset read).
"""
import struct, sys

def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]

StreamType = {3: 'ThreadList', 4: 'ModuleList', 6: 'Exception', 7: 'System'}

def main(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'MDMP', 'not a minidump'
    n_streams = u32(b, 8)
    dir_off = u32(b, 12)
    streams = {}
    for i in range(n_streams):
        o = dir_off + i * 12
        st, size, off = u32(b, o), u32(b, o + 4), u32(b, o + 8)
        streams.setdefault(st, (size, off))

    # exception record
    if 6 not in streams:
        print('no exception stream'); return
    size, off = streams[6]
    tid = u32(b, off)
    rec_off = u32(b, off + 4)
    erec = off + rec_off + 8 if False else off + rec_off
    code = u32(b, erec)
    nparams = u32(b, erec + 8) if False else 0
    # MINIDUMP_EXCEPTION: threadid(4) + align(4) + code(4) + flags(4) +
    # record(8) + addr(8) + paramcount(4) + pad(4) + params[15*8]
    base = off + 8
    ecode = u32(b, base)
    eaddr = u64(b, base + 16)   # ExceptionAddress
    nparams = u32(b, base + 24)
    p0 = u64(b, base + 32)      # AV param0: 0=read 1=write 8=exec
    p1 = u64(b, base + 40)      # AV param1: faulting VA
    print('  nparams=%d' % nparams)
    print(f'thread={tid} exception=0x{ecode:08X} @rip=0x{eaddr:X}')
    print(f'  access {"WRITE" if p1 & 0 else ""} param0=0x{p0:X} fault=0x{p1:X}')

    # modules
    if 4 not in streams:
        print('no module list'); return
    msize, moff = streams[4]
    count = u32(b, moff)
    mstride = (msize - 4) // count
    mods = []
    p = moff + 4
    for i in range(count):
        baseaddr, size_m = u64(b, p), u32(b, p + 8)
        name_rva = u32(b, p + 20)   # MINIDUMP_STRING RVA (base8+size4+csum4+ts4)
        # ModuleList entry: 8 base + 4 size + 4 proc + 8 ts + 4 nameRva + ... stride 108
        try:
            slen = u32(b, name_rva)
            raw = b[name_rva + 4: name_rva + 4 + slen]
            name = raw.decode('utf-16-le', 'replace').split('\x00')[0]
        except Exception:
            name = '?'
        mods.append((baseaddr, size_m, name))
        p += mstride
    def owner(addr):
        for ba, sz, nm in mods:
            if ba <= addr < ba + sz:
                return nm, addr - ba
        return None, None
    if eaddr and not any(ba <= eaddr < ba + sz for ba, sz, _ in mods):
        near = sorted(mods, key=lambda m: abs(m[0] - eaddr))[:6]
        print('NEAREST modules to rip:')
        for ba, sz, nm in near:
            print(f'   0x{ba:X} + 0x{sz:X}  {nm.split(chr(92))[-1]}')
    nm, off1 = owner(eaddr)
    print(f'exception rip: {nm}+0x{off1:X}' if nm else 'exception rip: not in any module')
    nm2, off2 = owner(p1)
    print(f'fault addr   : {nm2}+0x{off2:X}' if nm2 else f'fault addr   : 0x{p1:X} (not in any module)')
    # top stacks: scan thread list (stream 4) for the crashing thread's context
    # cheap version: search entire memory for return addrs is too heavy; use stack memory
    if 3 in streams:
        tsize, toff = streams[3]
        tcount = u32(b, toff)
        tstride = (tsize - 4) // tcount if tcount else 56
        tp = toff + 4
        for i in range(min(tcount, 8192)):
            tid_t = u32(b, tp)
            stk_start = u64(b, tp + 32)
            stk_len = u64(b, tp + 40)
            stk_rva = u32(b, tp + 52)   # ThreadContext LocationDescriptor.Rva @+52? stack desc ends @48
            if tid_t == tid:
                mem = b[stk_rva: stk_rva + stk_len]
                hits = []
                for j in range(0, len(mem) - 8, 8):
                    q = u64(mem, j)
                    m2, o2 = owner(q)
                    if m2 and ('helldivers' in m2.lower() or 'lua' in m2.lower() or 'bingus' in m2.lower() or 'kernel' in m2.lower()):
                        hits.append(f'{m2.split(chr(92))[-1]}+0x{o2:X}')
                    if len(hits) > 24: break
                print('crashing thread %d stack bytes=%d candidates:' % (tid_t, stk_len))
                for h in hits[:24]: print('   ', h)
                break
            tp += tstride
    print('total modules:', count)

if __name__ == '__main__':
    main(sys.argv[1])
