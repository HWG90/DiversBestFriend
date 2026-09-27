local function source(n) local f=assert(io.open('native-selection-poc/'..n,'rb'));local s=f:read('*a');f:close();return s end
local make=assert(loadstring(source('input.lua')..'\n'..source('selection.lua')..'\nreturn selection_controller'))()
local confirmed
local s=make({begin=function(kind) confirmed=kind;return {kind=kind} end},function() end)
-- Storage order is middle, bottom, top, invalid; entry indices have gaps.
local rows={{address=10,entry=0,kind=50,list_y=-68},{address=20,entry=2,kind=33,list_y=-136},
    {address=30,entry=7,kind=3,list_y=0},{address=40,entry=8,kind=0,list_y=68}}
local snap={identity=1,open=true,list_order=true,rows=rows}
local idle={next=false,previous=false,confirm=false}
local now=0
local function tick(buttons) now=now+1;s.step(snap,buttons or idle,now) end
local function press(key) tick();local b={next=false,previous=false,confirm=false};b[key]=true;tick(b) end
tick();assert(s.selected==30,'open selects the displayed top row')
for _,address in ipairs({10,20,30,10,20,30}) do press('next');assert(s.selected==address,'next follows visual order and wraps') end
for _,address in ipairs({20,10,30,20,10,30}) do press('previous');assert(s.selected==address,'previous follows reverse visual order and wraps') end
assert(rows[1].address==10 and rows[2].address==20,'sorting does not mutate native/radial storage order')
-- Native resorting keeps the same selected item, then navigates its new neighbor.
rows[1].list_y=0;rows[3].list_y=-68;tick();assert(s.selected==30)
press('next');assert(s.selected==20)
press('confirm');assert(confirmed==33,'confirm preserves the actual kind, not sorted array index')
s.step(nil,nil,now+1);snap.rows={rows[1]};tick();press('next');press('previous');assert(s.selected==10,'single row wraps to itself')
snap.rows={};tick();assert(s.selected==nil,'empty membership clears selection')
-- Without list mode, native slot order is retained for the radial layout.
s.step(nil,nil,now+1);snap.rows=rows;snap.list_order=false;tick();assert(s.selected==10)
print('List order passed: visual ordering, both wrap directions, native reorder, identity-preserving confirm, single/empty rows and unchanged radial order.')
