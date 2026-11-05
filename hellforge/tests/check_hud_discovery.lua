-- Offline integration check. Feed HF-LLL's real scanner the patch from the release zip.
local loader, patch_name, expected_name = ...
LLL_DISCOVERY_HASH = dofile(loader .. "/src/discovery_hash.lua")
local discover = dofile(loader .. "/src/discovery.lua")
local patch = assert(io.read("*a"))
local function scan(name, bytes)
    local full_path = "data/" .. name
    local closed = false
    local platform = {
        data = "data",
        files = function(folder, glob)
            assert(folder == "data" and glob == "9ba626afa44a3aa3.patch_*")
            return {name}
        end,
        archive = function(path)
            assert(path == full_path)
            return {
                size = #bytes,
                read = function(at, size)
                    assert(at >= 0 and at + size <= #bytes)
                    return bytes:sub(at + 1, at + size)
                end,
                close = function() closed = true end,
            }
        end,
    }
    local names, warnings, diagnostics, _, details = discover(platform)
    assert(#warnings == 0, table.concat(warnings, "\n"))
    return names, details, closed, diagnostics
end

local names, details, closed, diagnostics = scan(patch_name, patch)
assert(closed and #names == 1, diagnostics)
assert(not expected_name or names[1] == expected_name, names[1])
local entry = assert(details[names[1]])
assert(entry.kind == "addon" and entry.archive == patch_name)
local body = patch:sub(entry.offset + 9, entry.offset + entry.length)
assert(loadstring(body, "@" .. names[1])) -- compile only, no game globals or native calls

-- Mutate just the declared name, keeping the table key and envelope length intact.
local marker = "-- HD2-Addon: "
assert(body:sub(1, #marker) == marker)
local at = entry.offset + 9 + #marker + #names[1] - 1
local replacement = patch:sub(at, at) == "z" and "x" or "z"
local mismatched = patch:sub(1, at - 1) .. replacement .. patch:sub(at + 1)
assert(#scan(patch_name, mismatched) == 0, "wrong name/hash pair was discovered")
assert(#scan(patch_name .. ".stream", patch) == 0, "sidecar was discovered as a patch")
print("HF-LLL discovered and LuaJIT compiled " .. names[1] .. " from " .. patch_name)
