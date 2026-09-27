-- Use the same per-frame camera-input gate as the native radial reader.
-- Do not overwrite an existing capture owned by another native menu.
local function camera_capture(b)
    local owned
    local self={}
    function self.release()
        if owned and b.pointer(b.base+0x346d560)==owned then
            if b.read(owned+0x1a9,1)=='\1' then b.pulse_byte(owned+0x1a9,0) end
        end
        owned=nil
    end
    function self.capture()
        local owner=assert(b.pointer(b.base+0x346d560),'Camera input owner unavailable')
        if owned and owned~=owner then self.release() end
        local value=b.read(owner+0x1a9,1)
        assert(value=='\0' or value=='\1','Invalid camera input gate')
        if value=='\0' then
            b.pulse_byte(owner+0x1a9,1)
            owned=owner
        end
    end
    return self
end
