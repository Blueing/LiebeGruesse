-- Blessings page: assignment grid (paladin × class) with live buff status,
-- missing players, suggest / whisper / announce; settings of bar and sync in the tab "Settings".
local _, ns = ...
local UI, Theme, L, Names = ns.UI, ns.Theme, ns.L, ns.Names
local B = ns.Blessings

local COL_W, ROW_H, NAME_W = 74, 46, 170

local function className(class)
    return ns.ClassName(class)
end

local function blessingMenu(anchor, p, class)
    local items = {}
    for _, b in ipairs(B.LIST) do
        local can = p.can and p.can[b.key]
        local note = (p.addon and can == 0) and Theme.HexColor("muted", "  " .. L.BLESS_NOT_KNOWN) or ""
        items[#items + 1] = { value = b.key, text = ("|T%s:16:16:0:0:64:64:5:59:5:59|t  %s%s"):format(B.Icon(b.key), B.Name(b.key), note) }
    end
    items[#items + 1] = { value = "none", text = Theme.HexColor("muted", L.BLESS_NONE) }
    UI.OpenMenu(anchor, items, function(v) B.Set(p, class, v ~= "none" and v or nil) end, 190, p.set and p.set[class] or "none")
end

UI.AddPage("blessings", L.PAGE_BLESSINGS, 33, function(root, page)
    -- tabs: assignments and the settings of bar and sync
    local content, tabs = UI.PageWithSettings(root, page, L.BLESS_ASSIGNMENTS, function(form)
        local function o() return B.Settings() end
        local function barUpdate() ns.AfterCombat("bless-bar", ns.BlessingsBar.Update) end
        local bar = form:Section(L.BLESS_BAR)
        bar:Toggle(L.BLESS_SHOW_BAR, function() return o().bar end, function(v) o().bar = v; barUpdate() end, { tip = L.BLESS_SHOW_BAR_TIP })
        bar:Toggle(L.BLESS_RAID_ONLY, function() return o().raidOnly end, function(v) o().raidOnly = v; barUpdate() end)
        bar:Toggle(L.BLESS_SOLO, function() return o().solo end, function(v) o().solo = v; barUpdate() end, { tip = L.BLESS_SOLO_TIP })
        bar:Toggle(L.BLESS_LIVE, function() return o().live ~= false end, function(v) o().live = v; barUpdate() end, { tip = L.BLESS_LIVE_TIP })
        local sync = form:Section(L.BLESS_SYNC)
        sync:Toggle(L.BLESS_FREE, function() return o().freeAssign end, function(v) o().freeAssign = v; B.Share(B.Me()) end, { tip = L.BLESS_FREE_TIP })
        -- PallyPower: guests without this addon (read) and sending to them (sync)
        sync:Toggle(L.BLESS_PP_READ, function() return o().ppRead end, function(v) o().ppRead = v; if v then B.Request() end end, { tip = L.BLESS_PP_READ_TIP })
        sync:Toggle(L.BLESS_PP_SYNC, function() return o().ppSync end, function(v) o().ppSync = v; if v then B.Share(B.Me()) end end, { tip = L.BLESS_PP_SYNC_TIP })
        local msgs = form:Section(L.MSG_SECTION, { wide = true })
        ns.Messages.Rows(msgs, { "blessWhisper" })
    end)
    -- head: kicker, title, three counters
    local kicker = UI.Text(content, 10, "accent")
    kicker:SetPoint("TOPLEFT", 2, -2)
    kicker:SetText(L.BLESS_ASSIGNMENTS:upper())
    local title = UI.Text(content, 24, "text")
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
    local counters = {}
    for i, key in ipairs({ "duplicates", "missing", "paladins" }) do
        local c = CreateFrame("Frame", nil, content)
        c:SetSize(96, 46)
        -- the top right corner belongs to the page search
        if i == 1 then c:SetPoint("TOPRIGHT", 0, 0) else c:SetPoint("RIGHT", counters[i - 1], "LEFT", -8, 0) end
        c.value = UI.Text(c, 20, "text", "CENTER")
        c.value:SetPoint("TOP", 0, -2)
        c.label = UI.Text(c, 10, "muted", "CENTER")
        c.label:SetPoint("TOP", c.value, "BOTTOM", 0, -4)
        c.label:SetText(L["BLESS_COUNT_" .. key:upper()]:upper())
        counters[i] = c
        counters[key] = c
    end

    -- toolbar
    local suggest = UI.Button(content, L.BLESS_SUGGEST, 120, 26, function()
        if B.Suggest() then ns.Print(L.BLESS_SUGGESTED) else ns.Print(L.BLESS_CANT_EDIT) end
    end, "rotate-ccw")
    suggest:SetPoint("TOPLEFT", 0, -62)
    suggest.tip = { L.BLESS_SUGGEST_TIP }
    local clear = UI.Button(content, L.BLESS_CLEAR_MINE, 120, 26, function() local me = B.Me(); if me then B.Clear(me) end end, "x")
    clear:SetPoint("LEFT", suggest, "RIGHT", 8, 0)
    local info = UI.Text(content, 11, "muted")
    info:SetPoint("LEFT", clear, "RIGHT", 12, 0)
    local announce = UI.Button(content, L.BLESS_ANNOUNCE, 120, 26, function() B.Announce() end, "megaphone")
    announce:SetPoint("TOPRIGHT", 0, -62)
    local whisper = UI.Button(content, L.BLESS_WHISPER_BTN, 120, 26, function() B.WhisperAll() end, "message-circle")
    whisper:SetPoint("RIGHT", announce, "LEFT", -8, 0)

    local scroll, body = UI.ScrollArea(content)
    scroll:SetPoint("TOPLEFT", 0, -100)
    scroll:SetPoint("BOTTOMRIGHT", -6, 0)

    -- grid pieces are created on demand and reused
    local headCells, rowsUI, missUI = {}, {}, {}
    local gridHead = UI.Text(body, 10, "muted")
    gridHead:SetText(L.BLESS_PALADIN:upper())
    local gridLine = UI.Divider(body)
    local legend = UI.Text(body, 11, "muted")
    legend:SetWordWrap(true)
    legend:SetJustifyH("LEFT")
    local missHead = UI.Text(body, 10, "accent")
    missHead:SetText(L.BLESS_MISSING:upper())
    local missLine = UI.Divider(body)
    local empty = UI.Empty(body, 420)

    local function cell(row, i)
        local c = row.cells[i]
        if c then return c end
        c = CreateFrame("Button", nil, row)
        c:SetSize(COL_W - 4, ROW_H - 6)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c.hl = UI.Fill(c, "hover", "HIGHLIGHT"); c.hl:SetAllPoints()
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(24, 24)
        c.icon:SetPoint("LEFT", 4, 0)
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.count = UI.Text(c, 12, "text")
        c.count:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 5, 1)
        c.left = UI.Text(c, 10, "muted")
        c.left:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 5, -1)
        c.dash = UI.Text(c, 12, "borderDim", "CENTER")
        c.dash:SetPoint("CENTER")
        c.dash:SetText("—")
        c:SetScript("OnClick", function(self, button)
            if not self.p then return end
            if not B.CanEdit(self.p) then ns.Print(L.BLESS_CANT_EDIT); return end
            if button == "RightButton" then B.Set(self.p, self.class, nil) else blessingMenu(self, self.p, self.class) end
        end)
        c:EnableMouseWheel(true)
        c:SetScript("OnMouseWheel", function(self, delta)
            if not self.p then return end
            if not B.CanEdit(self.p) then ns.Print(L.BLESS_CANT_EDIT); return end
            B.Cycle(self.p, self.class, delta)
            ns.Window.Refresh("blessings")
            if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
        end)
        c:SetScript("OnEnter", function(self)
            if not self.p then return end
            local lines = {}
            local b = self.p.set and self.p.set[self.class]
            if b then
                local st = B.status[self.class]
                lines[#lines + 1] = L.BLESS_TIP_STATUS:format((st and st.have[b]) or 0, (st and st.total) or 0)
            end
            lines[#lines + 1] = " "
            lines[#lines + 1] = B.CanEdit(self.p) and L.BLESS_CELL_TIP or L.BLESS_CANT_EDIT
            UI.Tooltip(self, (b and B.Name(b) or L.BLESS_NONE) .. " · " .. className(self.class), lines)
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.cells[i] = c
        return c
    end

    local function paladinRow(i)
        local r = rowsUI[i]
        if r then return r end
        r = CreateFrame("Frame", nil, body)
        r:SetHeight(ROW_H)
        r.bg = UI.Fill(r, (i % 2 == 0) and "rowAlt" or "row", "BACKGROUND"); r.bg:SetAllPoints()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(28, 28)
        r.icon:SetPoint("LEFT", 6, 0)
        r.name = UI.Text(r, 13, "text")
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
        r.name:SetWidth(NAME_W - 46)
        r.sub = UI.Text(r, 10, "muted")
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
        r.cells = {}
        rowsUI[i] = r
        return r
    end

    local function draw()
        B.Rebuild()
        counters[1]:ClearAllPoints()
        counters[1]:SetPoint("TOPRIGHT", 0, 0)
        local classes = {}
        -- solo: every class, so you can plan your own blessings before a group
        local solo = not IsInGroup() and not B.test
        for _, class in ipairs(B.CLASSES) do if solo or B.classUnits[class] then classes[#classes + 1] = class end end
        if #classes == 0 then classes = B.CLASSES end
        local pals = B.PaladinList()
        -- page search: a paladin's name narrows the rows, a class name the columns
        -- page search: matching paladins and classes are marked (nothing is hidden)
        local q = page.query or ""
        page.hits = 0
        if q ~= "" then
            for _, p in ipairs(pals) do if ns.SearchAny(ns.Names.Display(p.name or p.key), q) then page.hits = page.hits + 1 end end
            for _, c in ipairs(classes) do if ns.SearchAny(className(c), q) then page.hits = page.hits + 1 end end
        end
        local W = math.max(400, (scroll:GetWidth() or 800) - 8)
        local colW = math.max(60, math.min(COL_W + 20, math.floor((W - NAME_W) / math.max(1, #classes))))

        -- title + counters
        local zone = ns.Call(GetInstanceInfo)
        title:SetText(B.test and (L.TEST_TAG .. " " .. L.BLESS_RAID)
            or (IsInGroup() and zone and zone ~= "") and zone or (IsInRaid() and L.BLESS_RAID or IsInGroup() and L.BLESS_GROUP or L.BLESS_SOLO_TITLE))
        local sum = B.Summary()
        counters.paladins.value:SetText(("%d/%d"):format(sum.synced, sum.paladins))
        counters.missing.value:SetText(tostring(sum.missing))
        counters.missing.value:SetTextColor(Theme.Color(sum.missing > 0 and "accent" or "good"))
        counters.duplicates.value:SetText(tostring(sum.duplicates))
        counters.duplicates.value:SetTextColor(Theme.Color(sum.duplicates > 0 and "bad" or "text"))
        local pp = 0
        for _, p in ipairs(pals) do if p.addon == "pp" then pp = pp + 1 end end
        info:SetText(L.BLESS_INFO:format(sum.synced, sum.paladins, pp))
        local lead = not IsInGroup() or ns.IsGroupLead("player")
        suggest:SetEnabled(#pals > 0 and (lead or B.Me() ~= nil))
        clear:SetEnabled(B.Me() ~= nil)

        if #pals == 0 then
            for _, r in ipairs(rowsUI) do r:Hide() end
            for _, h in ipairs(headCells) do h:Hide() end
            for _, m in ipairs(missUI) do m:Hide() end
            gridHead:Hide(); gridLine:Hide(); legend:Hide(); missHead:Hide(); missLine:Hide()
            empty:ClearAllPoints()
            empty:SetPoint("TOP", body, "TOP", 0, -40)
            empty:SetTextWidth(math.min(420, W - 40))
            empty:Set("sparkles", IsInGroup() and L.BLESS_NO_PALADINS or L.BLESS_NO_GROUP)
            empty:Show()
            body:SetHeight(200)
            scroll.UpdateBar()
            return
        end
        empty:Hide()
        gridHead:Show(); gridLine:Show(); legend:Show()

        -- header: class names in class colour
        gridHead:ClearAllPoints()
        gridHead:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -4)
        for i, class in ipairs(classes) do
            local h = headCells[i]
            if not h then h = UI.Text(body, 10, "text", "LEFT"); headCells[i] = h end
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", body, "TOPLEFT", NAME_W + (i - 1) * colW + 4, -4)
            h:SetWidth(colW - 4)
            local r, g, b = ns.ClassColor(class)
            h:SetText(ns.Highlight(ns.Hex(r, g, b, className(class):upper()), q))
            h:Show()
        end
        for i = #classes + 1, #headCells do headCells[i]:Hide() end
        gridLine:ClearAllPoints()
        gridLine:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -20)
        gridLine:SetWidth(NAME_W + #classes * colW)

        local y = 24
        for i, p in ipairs(pals) do
            local r = paladinRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            r:SetWidth(NAME_W + #classes * colW)
            ns.SetClassIcon(r.icon, "PALADIN")
            r.name:SetText(ns.Highlight(ns.ColorName(p.name or p.key, "PALADIN"), q))
            r.sub:SetText(p.me and Theme.HexColor("accent", L.BLESS_YOU) or (p.addon == "lg" and L.BLESS_ADDON)
                or (p.addon == "pp" and L.BLESS_PP_GUEST) or Theme.HexColor("muted", L.BLESS_NO_ADDON))
            for c, class in ipairs(classes) do
                local cl = cell(r, c)
                cl:ClearAllPoints()
                cl:SetPoint("LEFT", r, "LEFT", NAME_W + (c - 1) * colW, 0)
                cl:SetWidth(colW - 4)
                cl.p, cl.class = p, class
                local b = p.set and p.set[class]
                local st = B.status[class]
                if b then
                    cl.icon:SetTexture(B.Icon(b)); cl.icon:Show(); cl.dash:Hide()
                    local have, total = (st and st.have[b]) or 0, (st and st.total) or 0
                    if total > 0 then
                        cl.count:SetText(Theme.HexColor(have >= total and "good" or "bad", ("%d/%d"):format(have, total)))
                    else
                        cl.count:SetText(Theme.HexColor("muted", "—"))
                    end
                    local left = st and st.left[b]
                    cl.left:SetText(left and left ~= math.huge and ("%dm"):format(math.floor(left / 60)) or "")
                    cl.count:Show(); cl.left:Show()
                else
                    cl.icon:Hide(); cl.count:Hide(); cl.left:Hide(); cl.dash:Show()
                end
                cl:Show()
            end
            for c = #classes + 1, #r.cells do r.cells[c]:Hide() end
            r:Show()
            y = y + ROW_H + 2
        end
        for i = #pals + 1, #rowsUI do rowsUI[i]:Hide() end

        -- legend
        local parts = {}
        for _, b in ipairs(B.LIST) do parts[#parts + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(B.Icon(b.key), B.Name(b.key)) end
        legend:ClearAllPoints()
        legend:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -(y + 8))
        legend:SetWidth(W - 8)
        legend:SetText(table.concat(parts, "     ") .. Theme.HexColor("muted", "     " .. L.BLESS_LEGEND_HINT))
        y = y + 34

        -- missing players, four per line
        missHead:SetShown(#B.missing > 0)
        missLine:SetShown(#B.missing > 0)
        if #B.missing > 0 then
            missHead:ClearAllPoints()
            missHead:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -(y + 6))
            missLine:ClearAllPoints()
            missLine:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + 22))
            missLine:SetWidth(W)
            y = y + 30
        end
        local perLine = math.max(1, math.floor(W / 200))
        local mw = math.floor(W / perLine)
        for i, m in ipairs(B.missing) do
            local t = missUI[i]
            if not t then t = UI.Text(body, 12, "text"); missUI[i] = t end
            local icons = {}
            for _, b in ipairs(m.list) do icons[#icons + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t"):format(B.Icon(b)) end
            t:SetText(table.concat(icons, "") .. "  " .. ns.ColorName(m.name, m.class))
            t:ClearAllPoints()
            local col, line = (i - 1) % perLine, math.floor((i - 1) / perLine)
            t:SetPoint("TOPLEFT", body, "TOPLEFT", 4 + col * mw, -(y + line * 22))
            t:SetWidth(mw - 8)
            t:Show()
        end
        for i = #B.missing + 1, #missUI do missUI[i]:Hide() end
        y = y + math.ceil(#B.missing / perLine) * 22 + 10
        body:SetHeight(y)
        scroll.UpdateBar()
    end

    page.searchHint = L.BLESS_SEARCH
    page.Search = function(text) page.query = text; draw(); return page.hits end
    page.OnShow = function()
        draw()
        if not B.test and (B.IsPaladin() or IsInGroup()) and GetTime() - (B.lastScan or -99) > 3 then B.Scan() end
    end
    B.PageDraw = draw
    content:HookScript("OnSizeChanged", function() if content:IsVisible() then ns.Debounce("bless-page", 0.05, draw) end end)
    tabs.Finish()
end, { section = "raid", icon = "sparkles", module = "blessings" })

ns.On("LG_BLESSINGS", function()
    if ns.Window.IsShown("blessings") and B.PageDraw then ns.Debounce("bless-page-draw", 0.2, B.PageDraw) end
end)
