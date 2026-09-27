-- Called within the owner's HUD resource scope, only for separately owned icons.
local function configure_stratagem_icon(b,icon,info,cooling)
    local ffi=require('ffi')
    local texture=ffi.cast('void (*)(uintptr_t, uint64_t, uint64_t, uint8_t)',b.base+0x1450230)
    local hash=ffi.new('uint64_t[1]');ffi.copy(hash,info.texture,8)
    if radial.full_color==false and not cooling then
        texture(icon,0x57fcf14ad069020bULL,hash[0],0)
        return
    end
    -- Native list sprite constructor 183398CC uses this material; its update
    -- 183A1E5..183A25E supplies the channel colors below. The texture is a mask,
    -- so displaying it with the generic emote material exposes red/green channels.
    local category=info.category
    assert(type(category)=='number' and category%1==0 and category>=0 and category<16,'Invalid icon color category')
    local function rgba(rva)
        local bytes=assert(b.read(b.base+rva,16),'Native icon palette unavailable')
        assert(#bytes==16,'Truncated icon palette')
        local v=ffi.new('float[4]');ffi.copy(v,bytes,16)
        for i=0,3 do assert(v[i]==v[i] and v[i]>=0 and v[i]<=1,'Invalid native icon palette') end
        return v
    end
    local accent=rgba(0x3318040+category*16)
    local foreground=rgba(0x21e2d30)
    local background=rgba(0x21e2d60)
    if cooling then
        -- Native palette vectors are A,R,G,B. Keep alpha and desaturate all
        -- three texture-mask channels, including raw-icon display mode.
        for _,v in ipairs({accent,foreground,background}) do
            local gray=0.2126*v[1]+0.7152*v[2]+0.0722*v[3]
            v[1],v[2],v[3]=gray,gray,gray
        end
    end
    texture(icon,0xaf73e09d6d725398ULL,hash[0],0)
    local material=ffi.cast('uintptr_t (*)(uintptr_t)',b.base+0x144f6e0)
    local parameter=ffi.cast('void (*)(uintptr_t, uint32_t, const float *)',b.base+0x14498c0)
    assert(tonumber(material(icon))~=0,'Stratagem icon material unavailable')
    parameter(icon,0x28723f4d,accent)
    parameter(icon,0x851fd4fd,foreground)
    parameter(icon,0x10c353af,background)
end
