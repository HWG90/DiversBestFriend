"""Run isolated Lua fixtures with the installed game's LuaJIT, not the game process."""
import ctypes
import os
from pathlib import Path
import sys

DLL = Path(os.environ.get('HD2_LUA51_DLL', 'C:/Program Files (x86)/Steam/steamapps/common/Helldivers 2/bin/lua51.dll'))

def run(source: bytes, name: str = 'fixture') -> None:
    lua = ctypes.CDLL(str(DLL))
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        raise RuntimeError('Cannot allocate Lua state')
    try:
        lua.luaL_openlibs(state)
        result = lua.luaL_loadbuffer(state, source, len(source), name.encode())
        if result == 0:
            result = lua.lua_pcall(state, 0, 0, 0)
        if result:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode(errors='replace'))
    finally:
        lua.lua_close(state)

if __name__ == '__main__':
    path = Path(sys.argv[1])
    run(path.read_bytes(), str(path))
