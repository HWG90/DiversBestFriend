-- Offline check of the "Compact row" cooldown layout in stock LuaJIT:
--   luajit offline_compact_row.lua <source tree>
local tree=arg[1]
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local scope=setmetatable({},{__index=_G})
local chunk=assert(loadstring(slurp(tree..'/src/cooldown_dock.lua'),'@cooldown_dock.lua'));setfenv(chunk,scope)
local M=chunk()
local passed=0
local function check(label,cond)assert(cond,label);passed=passed+1;print('PASS '..label)end
local function snapshot(rows)return {identity=1,rows=rows}end
local function row(entry,kind,timer_kind,seconds)return {entry=entry,kind=kind,timer_kind=timer_kind,timer_seconds=seconds}end
local health={left=-855.5,right=-658.5,bottom=57.5,top=102.5}

local model=M.cooldown_dock_model()
model.sample(snapshot({row(1,10,'cooldown',90),row(2,11,'incoming',5),row(3,12,'cooldown',30),row(4,13,'incoming',3)}),0)
local items,divider,panels=model.layout(10000,150,false,3,10,80,true,nil,health)
local by={};for _,item in ipairs(items)do by[item.row.entry]=item end
check('every item is laid out',#items==4)
check('items are flagged compact row',items[1].compact_row==true and not items[1].below_stamina)
check('row sits under the health row box',by[1].y==health.bottom-3-16 and by[2].y==by[1].y)
check('first cooldown is left-aligned with the health bar',by[1].x==health.left+16)
check('cooldowns come first at a 40 px pitch',by[3].x==by[1].x+40)
check('separator is 12 px right of the last cooldown',divider and divider.x==by[3].x+16+12)
check('incoming starts 12 px right of the separator',by[2].x==divider.x+12+16 and by[4].x==by[2].x+40)
check('separator spans the 32 px tiles',divider.half==16 and divider.y==by[1].y)
check('no overview panels in the row',panels==nil)

local only=M.cooldown_dock_model()
only.sample(snapshot({row(1,10,'cooldown',90),row(3,12,'cooldown',30)}),0)
local items2,divider2=only.layout(10000,150,false,3,10,80,true,nil,health)
check('no separator without incoming',divider2==nil and items2[1].x==health.left+16)

local inc=M.cooldown_dock_model()
inc.sample(snapshot({row(2,11,'incoming',5)}),0)
local items3,divider3=inc.layout(10000,150,false,3,10,80,true,nil,health)
check('incoming alone starts at the bar',divider3==nil and items3[1].x==health.left+16)

local dock=M.cooldown_dock_model()
dock.sample(snapshot({row(1,10,'cooldown',90),row(2,11,'incoming',5)}),0)
local items4=dock.layout(10000,150,false,1,10,80,true,nil,nil)
check('without health bounds the normal dock layout is used',items4[1].compact_row==false and items4[1].y==150)
print(string.format('PASS compact row (%d checks)',passed))
