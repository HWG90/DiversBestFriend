local function source(n) local f=assert(io.open('native-selection-poc/'..n,'rb'));local s=f:read('*a');f:close();return s end
local point,make=assert(loadstring(source('input.lua')..'\n'..source('pointing.lua')..'\n'..source('selection.lua')..'\nreturn pointing_index,selection_controller'))()
local checks=0
for n=1,16 do
    local rows={};for i=1,n do rows[i]={address=i,kind=33} end
    local rx,ry=n>10 and 550 or 470,n>10 and 330 or 280
    for i=1,n do
        local a=math.pi/2-(i-1)*2*math.pi/n
        local x,y=rx*math.cos(a),ry*math.sin(a);local length=math.sqrt(x*x+y*y)
        assert(point(rows,{x/length,y/length})==i,'pointing must match the displayed card center');checks=checks+1
    end
    assert(point(rows,{0.1,0.1})==nil);checks=checks+1
end
local rows={{address=1,kind=1},{address=2,kind=33},{address=3,kind=124},{address=4,kind=25}}
local function vector(degrees) local a=math.rad(degrees);return {math.cos(a),math.sin(a)} end
assert(point(rows,vector(44),1)==1,'hysteresis near top/right boundary')
assert(point(rows,vector(40),1)==2,'clear movement crosses boundary')
local starts,advances=0,0
local s=make({begin=function(k) starts=starts+1;return {kind=k} end,advance=function() advances=advances+1;return false,'prefix' end},function() end)
local snap={identity=1,open=true,rows=rows}
local idle={next=false,previous=false,confirm=false}
local confirm={next=false,previous=false,confirm=true}
s.step(snap,idle,0,{1,0});assert(s.selected==2)
s.step(snap,idle,1,{0,0});assert(s.selected==nil,'stick center clears pointing selection')
s.step(snap,confirm,2,{0,0});assert(starts==0,'center cannot confirm')
s.step(snap,idle,3,{0,-1});assert(s.selected==3,'kinds outside the old five-item allowlist are selectable')
s.step(snap,confirm,4,{0,-1});assert(starts==1 and s.job.kind==124)
s.step(snap,idle,5,{-1,0});assert(s.selected==3 and advances==1,'pointing cannot retarget an active code')
s.step(nil,nil,6);assert(not s.job and not s.selected)
s.step(snap,confirm,7,{1,0});assert(starts==1,'held confirm cannot activate on reopen')
s.step(snap,idle,8,{1,0})
s.step(snap,{next=true,previous=false,confirm=false},9,{1,0});assert(s.selected==3)
s.step(snap,idle,10,{1,0});assert(s.selected==3,'stationary pointer does not undo discrete navigation')
s.step(snap,idle,11,{-1,0});assert(s.selected==4)
print('Pointing passed: '..checks..' geometry/dead-zone checks, hysteresis, dynamic kinds, center-confirm rejection, job pinning, reopen and discrete fallback.')
