-- Inputs: hud_pack.render() output, then the exact 25480438 RVA-layout dump.
-- Only the bridge comparison is simulated; run the assembled admission closure.
local host = assert(loadfile(arg[1]))()
host.on_enable()
local function upvalue(fn, key)
    for i=1,100 do
        local name, value = debug.getupvalue(fn, i)
        if name == key then return value end
        if not name then break end
    end
    error('missing upvalue '..key)
end
local scope = upvalue(host.on_enable, 'scope')
local dump = assert(io.open(arg[2], 'rb'))
assert(dump:seek('end') == 0x4744000)
local by_rva = {}
for _, g in ipairs(scope.native_guards) do by_rva[g.rva] = g.name end
local bad, total = 0, 0
-- First enumerate without early exit, then exercise strict admission group results.
local function verify(strict)
    local group, calls, mismatches
    local admit = scope.wheel_admission({dbf_hud_guard=function(rva, bytes, n)
        calls = calls+1
        assert(dump:seek('set', rva))
        local actual = dump:read(n)
        if n>0 and n<=256 and actual==bytes then return 1 end
        mismatches = mismatches+1
        if strict then return 0 end
        local at=1
        while at<=n and actual:byte(at)==bytes:byte(at) do at=at+1 end
        print(('%s %s RVA 0x%x len %d first difference +0x%x'):format(group,by_rva[rva],rva,n,at-1))
        return 1
    end})
    local groups = upvalue(admit, 'groups')
    local names = {}
    for name in pairs(groups) do names[#names+1] = name end
    table.sort(names)
    for _,name in ipairs(names) do
        group,calls,mismatches = name,0,0
        local ok, reason = admit(name, 0)
        if strict then
            print(name, ok and 'admitted' or ('refused at '..reason))
            assert(ok or bad>0, reason)
        else
            assert(ok,reason)
            bad,total = bad+mismatches,total+calls
        end
    end
end
verify(false)
verify(true)
dump:close()
assert(total==#scope.native_guards, 'some witnesses were not exercised')
print(('compared %d witnesses, %d mismatches'):format(total,bad))
assert(bad==0, 'see mismatches above')
