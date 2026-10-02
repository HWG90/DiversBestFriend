-- Pointing and discrete navigation share the proven explicit-confirm path.
local function selection_controller(input,report)
    local self={selected=nil,status='Open the native stratagem menu',job=nil,interval_ms=70}
    local previous,opened={},false
    local owner,next_at,last_vector,point_mode,selected_kind
    function self.step(snapshot,buttons,now,vector)
        local edges={}
        for _,key in ipairs({'next','previous','confirm'}) do
            edges[key]=buttons and buttons[key]==true and previous[key]==false
            if buttons then previous[key]=buttons[key] else previous[key]=nil end
        end
        local active=snapshot and snapshot.open and buttons~=nil
        if not active or (owner and snapshot.identity~=owner) then
            if self.job then report('Cancelled: menu closed, input unavailable, or HUD changed') end
            self.job=nil; self.selected=nil; opened=false
            owner=nil;last_vector=nil;point_mode=false;selected_kind=nil; return
        end
        owner=snapshot.identity
        local eligible={}
        for _,row in ipairs(snapshot.rows) do
            if selectable_kind(row.kind) then eligible[#eligible+1]=row end
        end
        if snapshot.list_order then
            -- Native payload/storage indices are not display indices. Use the
            -- native settled row positions (Y increases upward), so opening
            -- animations and the selected row's scale cannot change the order.
            table.sort(eligible,function(a,b)
                local ay,by=a.list_y or 0,b.list_y or 0
                if ay~=by then return ay>by end
                if a.entry~=b.entry then return (a.entry or 0)<(b.entry or 0) end
                return a.address<b.address
            end)
        end
        if not opened then
            self.selected=not snapshot.pointer_only and eligible[1] and eligible[1].address or nil
            opened=true
            -- Opening a menu with a held confirmation binding must not trigger it.
            edges.confirm=false
        end
        local chosen
        for i,row in ipairs(eligible) do
            if row.address==self.selected and (not selected_kind or row.kind==selected_kind) then chosen=i end
        end
        if not chosen and self.selected then
            self.job=nil; chosen=1; self.selected=eligible[1] and eligible[1].address
            edges.confirm=false
        end
        if self.job then
            if now>self.job.deadline then self.job=nil; report('Cancelled: input sequence timed out'); return end
            local row=eligible[chosen]
            if not row or row.kind~=self.job.kind then self.job=nil; report('Cancelled: card membership changed'); return end
            if now>=next_at then
                local ok,done,message=pcall(input.advance,self.job)
                if not ok then self.job=nil; report('Stopped: '..tostring(done)); return end
                report(message)
                if done then self.job=nil else next_at=now+self.job.interval_ms end
            end
            return
        end
        if #eligible==0 then self.status='No selectable stratagem cards are present'; return end
        if vector then
            local changed=not last_vector or math.abs(vector[1]-last_vector[1])+math.abs(vector[2]-last_vector[2])>0.001
            if changed or point_mode then
                local current
                for i,row in ipairs(snapshot.rows) do if row.address==self.selected then current=i end end
                local index=(snapshot.pointing_index or pointing_index)(snapshot.rows,vector,current)
                if index then
                    local address=snapshot.rows[index].address
                    for i,row in ipairs(eligible) do
                        if row.address==address then chosen=i;self.selected=address;point_mode=true end
                    end
                elseif point_mode then chosen=nil;self.selected=nil end
            end
            last_vector={vector[1],vector[2]}
        end
        if edges.next~=edges.previous then
            local delta=edges.next and 1 or -1
            chosen=chosen and (chosen-1+delta)%#eligible+1 or (delta==1 and 1 or #eligible)
            self.selected=eligible[chosen].address
            point_mode=false
        end
        if not chosen then self.status='Point at a card, then press Confirm';return end
        local row=eligible[chosen]
        selected_kind=row.kind
        self.status='Highlighted kind '..row.kind..'; press Confirm while keeping the menu open'
        if edges.confirm then
            local ok,result=pcall(input.begin,row.kind)
            if ok then
                local interval=input_interval(self.interval_ms,70)
                self.job=result;self.job.interval_ms=interval
                self.job.deadline=now+math.max(3000,(self.job.code and #self.job.code or 12)*interval+1500)
                next_at=now;report('Started native input for kind '..row.kind..'; interval='..interval..'ms')
            else report('Not started: '..tostring(result)) end
        end
    end
    return self
end
