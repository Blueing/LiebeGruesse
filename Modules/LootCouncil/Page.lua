-- Loot council page: history and setup (council roles in game)
local _, ns = ...
local UI, Theme, L, Items, Names, Council = ns.UI, ns.Theme, ns.L, ns.Items, ns.Names, ns.Council

local search = ""

local function historyRows()
    local rows = {}
    for _, r in ipairs(ns.Database.Guild().lootHistory) do
        local info = Items.Info(r.i)
        rows[#rows + 1] = { key = r.id, r = r, name = info and info.name or "" }
    end
    return rows
end

local function namesText(cfg)
    local out = {}
    for _, n in ipairs(cfg.names or {}) do out[#out + 1] = Names.Display(n) end
    return table.concat(out, ", ")
end

local function parseNames(text)
    local list = {}
    for part in (text or ""):gmatch("[^,;]+") do
        local key = Names.Key(part)
        if key then list[#list + 1] = key end
    end
    return list
end

local function changed() Council.ConfigChanged() end
local exportFormat, exportDays = "rclc", 7

UI.AddPage("council", L.PAGE_COUNCIL, 40, function(content, page)
    local toolbar = UI.Toolbar(content, {
        { text = L.LC_OPEN_WINDOW, width = 150, icon = "gem", onClick = function() ns.CouncilWindow.Show() end },
        { text = L.LC_PREPARE, width = 190, icon = "chevron-right", onClick = function() ns.CouncilWindow.ShowQueue() end, tip = L.LC_PREPARE_TIP },
        { text = L.LC_TEST, width = 120, icon = "sparkles", onClick = function() Council.Test() end, tip = L.LC_TEST_TIP },
        { text = L.LC_SHARE, width = 220, icon = "users", onClick = function() Council.ShareConfig() end, tip = L.LC_SHARE_TIP },
    })
    toolbar:SetPoint("TOPLEFT")
    toolbar:SetPoint("TOPRIGHT", -ns.Window.SearchReserve(), 0)

    local holder = CreateFrame("Frame", nil, content)
    holder:SetPoint("TOPLEFT", 0, -72)
    holder:SetPoint("BOTTOMRIGHT")
    local tabs = {}

    -- history
    local history = CreateFrame("Frame", nil, holder)
    history:SetAllPoints()
    -- the history search sits in the page header; this keeps the row of buttons in place
    local searchBox = CreateFrame("Frame", nil, history)
    searchBox:SetSize(1, 24)
    searchBox:SetPoint("TOPLEFT")
    local share = UI.Button(history, L.LC_SHARE_HISTORY, 170, 24, function() Council.ShareHistory(exportDays > 0 and exportDays or 3650) end, "users")
    share:SetPoint("TOPRIGHT")
    share.tip = { L.LC_SHARE_HISTORY_TIP }
    local export = UI.Button(history, L.LC_EXPORT, 120, 24, function()
        local text, n = Council.HistoryExport(exportFormat, exportDays)
        ns.Share.ShowText(L.LC_EXPORT_TITLE:format(n), L.LC_EXPORT_HINT, text)
    end, "scroll-text")
    export:SetPoint("RIGHT", share, "LEFT", -8, 0)
    local fmt = UI.Dropdown(history, 110, function()
        local items = {}
        for _, f in ipairs(Council.EXPORT_FORMATS) do items[#items + 1] = { value = f, text = L["LC_FMT_" .. f] or f:upper() } end
        return items
    end, function() return exportFormat end, function(v) exportFormat = v end)
    fmt:SetPoint("RIGHT", export, "LEFT", -8, 0)
    local range = UI.Dropdown(history, 120, function()
        return { { value = 1, text = L.LC_RANGE_TODAY }, { value = 7, text = L.PERIOD_WEEK }, { value = 30, text = L.PERIOD_MONTH },
            { value = 0, text = L.PERIOD_ALL } }
    end, function() return exportDays end, function(v) exportDays = v end)
    range:SetPoint("RIGHT", fmt, "LEFT", -8, 0)
    local list = UI.List(history, {
        sortKey = "t", sortDesc = true,
        columns = {
            { key = "t", title = L.COL_DATE, width = 110, text = function(row) return Theme.HexColor("muted", ns.Date(row.r.t)) end,
              sort = function(row) return row.r.t or 0 end, defaultDesc = true },
            { key = "item", title = L.COL_ITEM, flex = true,
              text = function(row) local info = Items.Info(row.r.i); return info and info.link or row.r.i end,
              icon = function(row) return Items.Icon(row.r.i) end, sort = function(row) return row.name end },
            { key = "to", title = L.LC_WINNER, width = 160,
              text = function(row)
                  local g = ns.Guild.Find(row.r.to)
                  return ns.ColorName(g and g.name or row.r.to, g and g.class)
              end, sort = function(row) return row.r.to end },
            { key = "r", title = L.LC_RESPONSE, width = 100, text = function(row) return row.r.r or "" end },
            { key = "v", title = L.LC_VOTES, width = 60, align = "CENTER", text = function(row) return tostring(row.r.v or 0) end,
              sort = function(row) return row.r.v or 0 end },
        },
        onEnter = function(frame, row) Items.ShowTooltip(frame, row.r.i) end,
    })
    list:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT")
    list:SetEmptyText(L.LC_HISTORY_EMPTY)
    function history.Refresh() list:SetRows(historyRows()) end
    tabs.history = history

    -- setup
    local setup = CreateFrame("Frame", nil, holder)
    setup:SetAllPoints()
    local form = UI.Form(setup)
    page.searchHint = L.LC_SEARCH_PAGE
    -- history and setup are both searched; the tab with hits opens
    history.SearchHits = function(q) list:SetRows(historyRows()); return list:SearchHits(q) end
    history.SearchApply = function(q) list:ShowFirstHit(q) end
    page.Search = function(text)
        search = text or ""
        if not ns.CouncilPage or not ns.CouncilPage.bar then return end
        return UI.TabSearch(ns.CouncilPage.bar, tabs, search)
    end
    form.scroll:SetPoint("TOPLEFT")
    form.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    local function cfg() return Council.Config() end

    local who = form:Section(L.LC_ROLES)
    who:Dropdown(L.LC_COUNCIL_RANK, function()
        local items = {}
        for i = 0, 9 do
            local name = ns.Guild.ranks[i]
            if name then items[#items + 1] = { value = i, text = L.LC_RANK_AND_ABOVE:format(name) } end
        end
        items[#items + 1] = { value = -1, text = L.LC_ONLY_NAMES }
        return items
    end, function() return cfg().minRank end, function(v) cfg().minRank = v; changed() end)
    who:Edit(L.LC_EXTRA_NAMES_SHORT, function() return namesText(cfg()) end,
        function(v) cfg().names = parseNames(v); changed() end, { placeholder = L.LC_NAMES_PLACEHOLDER, tip = L.LC_EXTRA_NAMES })
    who:Edit(L.LC_LOOT_MASTER_SHORT, function() return cfg().lootMaster end,
        function(v) cfg().lootMaster = v or ""; changed() end, { col = 2, placeholder = L.LC_LOOT_MASTER_PLACEHOLDER, tip = L.LC_LOOT_MASTER })
    local _, statusRow = who:Note("", { height = 34 })

    local rules = form:Section(L.LC_RULES)
    rules:Dropdown(L.LC_QUALITY, function()
        local items = {}
        for q = 2, 5 do
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
            items[#items + 1] = { value = q, text = (c and c.hex or "") .. name .. "|r" }
        end
        return items
    end, function() return cfg().quality end, function(v) cfg().quality = v; changed() end)
    rules:Segment(L.LC_TIMEOUT, {
        { value = 60, text = "60s" }, { value = 90, text = "90s" }, { value = 120, text = "2m" },
        { value = 180, text = "3m" }, { value = 300, text = "5m" },
    }, function() return cfg().timeout end, function(v) cfg().timeout = v; changed() end, { width = 220 })
    rules:Toggle(L.LC_ANNOUNCE_OPT, function() return cfg().announce end, function(v) cfg().announce = v; changed() end, { col = 2 })
    rules:Toggle(L.LC_MULTI_VOTE, function() return cfg().multiVote end, function(v) cfg().multiVote = v; changed() end,
        { col = 2, tip = L.LC_MULTI_VOTE_TIP })
    rules:Toggle(L.LC_SELF_VOTE, function() return cfg().selfVote end, function(v) cfg().selfVote = v; changed() end, { col = 2 })

    rules:Toggle(L.LC_ROLLS, function() return cfg().rolls end, function(v) cfg().rolls = v; changed() end, { tip = L.LC_ROLLS_TIP })
    rules:Toggle(L.LC_WHISPERS, function() return cfg().whispers end, function(v) cfg().whispers = v; changed() end,
        { col = 2, tip = L.LC_WHISPERS_TIP })
    rules:Edit(L.LC_REASONS, function() return table.concat(cfg().reasons or {}, ", ") end, function(v)
        local list = {}
        for part in v:gmatch("[^,;]+") do
            part = part:gsub("^%s+", ""):gsub("%s+$", "")
            if part ~= "" then list[#list + 1] = part end
        end
        cfg().reasons = list
        changed()
    end, { col = 0, width = 360, tip = L.LC_REASONS_TIP })

    local itemsSec = form:Section(L.LC_ITEMS_SECTION)
    local q = ns.CouncilQueue.Options
    itemsSec:Toggle(L.LC_ALT_CLICK, function() return q().altClick end, function(v) q().altClick = v end, { tip = L.LC_ALT_CLICK_TIP })
    itemsSec:Toggle(L.LC_AUTO_ADD, function() return q().autoAdd end, function(v) q().autoAdd = v end, { col = 2, tip = L.LC_AUTO_ADD_TIP })
    itemsSec:Toggle(L.LC_BAG_BOE, function() return q().boe end, function(v) q().boe = v end, { tip = L.LC_BAG_BOE_TIP })
    itemsSec:Buttons({ { L.LC_OPEN_QUEUE, function() ns.CouncilWindow.ShowQueue() end } }, { col = 2 })

    local answers = form:Section(L.LC_RESPONSES)
    answers:Note(L.LC_RESPONSES_HINT)
    for i = 1, 8 do
        local exists = function() return cfg().responses[i] ~= nil end
        local row = CreateFrame("Frame", nil, form.body)
        row.bg = UI.Fill(row, "panel", "BACKGROUND"); row.bg:SetAllPoints()
        row.label = UI.Text(row, 12, "text"); row.label:SetPoint("LEFT", 14, 0); row.label:SetText(L.LC_BUTTON_N:format(i))
        row.edit = UI.EditBox(row, 220, 24)
        row.edit:SetPoint("LEFT", 140, 0)
        row.edit.onCommit = function(self)
            local r = cfg().responses[i]
            local v = self:GetText()
            if r and v ~= "" and v ~= r.t then r.t = v; changed() end
        end
        row.edit.onEnter = row.edit.onCommit
        row.color = UI.ColorSwatch(row, nil, function()
            local r = cfg().responses[i]
            local c = r and r.c or { 1, 1, 1 }
            return c[1], c[2], c[3], 1
        end, function(r, g, b)
            local resp = cfg().responses[i]
            if resp then resp.c = { r, g, b }; changed() end
        end)
        row.color:SetPoint("LEFT", row.edit, "RIGHT", 14, 0)
        row.del = UI.IconButton(row, "x", 24, function()
            Council.RemoveResponse(i)
            setup.Refresh()
        end, true)
        row.del:SetPoint("RIGHT", -12, 0)
        row.del.tip = L.LC_DELETE_BUTTON
        function row:Refresh()
            local r = cfg().responses[i]
            if r then self.edit:SetText(r.t or "") end
            self.color:Refresh()
            -- at least two buttons stay; "pass" cannot be deleted
            self.del:SetShown(r ~= nil and #cfg().responses > 2 and r.k ~= "pass")
        end
        row.control = row
        answers:Custom(row, 36, { col = 0, show = exists })
    end
    answers:Buttons({
        { L.LC_ADD_BUTTON, function() Council.AddResponse(); setup.Refresh() end, width = 170, icon = "sparkles" },
    })

    -- companion bar for the loot master
    local cb = form:Section(L.LCB_TITLE)
    local B = function() return ns.CouncilBar.Settings() end
    local relayout = function() ns.CouncilBar.Layout() end
    cb:Note(L.LCB_HINT, { col = 0, height = 30 })
    cb:Toggle(L.LCB_ENABLED, function() return B().enabled end, function(v) B().enabled = v; relayout() end)
    cb:Note(L.LCB_ONLY_ML_NOTE, { col = 2, height = 36 })
    cb:Toggle(L.LCB_DOCK, function() return B().dock end, function(v) B().dock = v; relayout() end, { col = 0, tip = L.LCB_DOCK_TIP })
    cb:Toggle(L.LCB_ONLY_RAID, function() return B().onlyRaid end, function(v) B().onlyRaid = v; relayout() end)
    cb:Toggle(L.LCB_LABELS, function() return B().labels end, function(v) B().labels = v; relayout() end, { col = 2 })
    cb:Segment(L.LCB_ORIENTATION, { { value = false, text = L.LCB_HORIZONTAL }, { value = true, text = L.LCB_VERTICAL } },
        function() return B().vertical end, function(v) B().vertical = v; relayout() end, { width = 200 })
    cb:Slider(L.CD_SCALE, 0.5, 2, 0.05, function() return B().scale end, function(v) B().scale = v; relayout() end,
        { col = 2, fmt = function(v) return ("%d%%"):format(v * 100 + 0.5) end })
    cb:Slider(L.LCB_BUTTON_WIDTH, 40, 220, 2, function() return B().width end, function(v) B().width = v; relayout() end)
    cb:Slider(L.LCB_BUTTON_HEIGHT, 14, 48, 1, function() return B().height end, function(v) B().height = v; relayout() end, { col = 2 })
    cb:Slider(OPACITY or L.OPACITY, 0.2, 1, 0.05, function() return B().alpha end, function(v) B().alpha = v; relayout() end,
        { fmt = function(v) return ("%d%%"):format(v * 100 + 0.5) end })
    for i, def in ipairs(ns.CouncilBar.BUTTONS) do
        cb:Toggle(L.LCB_SHOW:format(def.text():gsub(" %(%d+%)", "")), function() return B().buttons[def.key] end,
            function(v) B().buttons[def.key] = v; relayout() end, { col = (i % 2 == 0) and 1 or 2 })
    end
    cb:Buttons({ { L.MOVE_ELEMENTS, function() ns.Window.ToggleMovers() end, width = 170, icon = "move" } }, { col = 0 })

    -- trade expiration timers
    local tt = form:Section(L.TT_TITLE)
    local T = function() return ns.TradeTimers.Settings() end
    local function ttRelayout() ns.TradeTimers.Layout() end
    tt:Note(L.TT_HINT, { col = 0, height = 30 })
    tt:Toggle(L.TT_ENABLED, function() return T().enabled end, function(v) T().enabled = v; ttRelayout() end)
    tt:Toggle(L.TT_ONLY_ML, function() return T().onlyML end, function(v) T().onlyML = v; ttRelayout() end, { tip = L.TT_ONLY_ML_TIP })
    tt:Toggle(L.TT_WARN_OPT, function() return T().warn end, function(v) T().warn = v end, { col = 2 })
    tt:Dropdown(L.TT_MIN_QUALITY, function()
        local list = {}
        for q = 2, 5 do
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            list[#list + 1] = { value = q, text = (c and c.hex or "") .. (_G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)) .. "|r" }
        end
        return list
    end, function() return T().minQuality end, function(v) T().minQuality = v; ns.TradeTimers.Scan() end)
    tt:Slider(L.TT_WIDTH, 160, 420, 2, function() return T().width end, function(v) T().width = v; ttRelayout() end, { col = 2 })
    tt:Buttons({ { L.TT_TEST, function() ns.TradeTimers.Test() end, width = 170 },
        { L.MOVE_ELEMENTS, function() ns.Window.ToggleMovers() end, width = 170, icon = "move" } }, { col = 0 })

    -- announcing awards
    local ann = form:Section(L.LC_ANNOUNCE_SECTION)
    ann:Segment(L.LC_ANNOUNCE_CHANNEL, { { value = "RAID", text = L.LC_CH_RAID }, { value = "RAID_WARNING", text = L.LC_CH_RW },
        { value = "NONE", text = L.LC_CH_NONE } }, function() return cfg().announce == false and "NONE" or (cfg().announceChannel or "RAID") end,
        function(v) cfg().announce = v ~= "NONE"; cfg().announceChannel = v; changed() end, { col = 0, width = 330, tip = L.LC_ANNOUNCE_CHANNEL_TIP })

    -- loot master options (personal)
    local ml = form:Section(L.LC_ML_SECTION)
    local o = Council.MLOptions
    ml:Note(L.LC_ML_HINT, { col = 0, height = 30 })
    ml:Toggle(L.LC_IGNORE_LEGENDARY, function() return o().ignoreLegendary end, function(v) o().ignoreLegendary = v end)
    ml:Toggle(L.LC_IGNORE_BOP, function() return o().ignoreBoP end, function(v) o().ignoreBoP = v end, { col = 2, tip = L.LC_IGNORE_BOP_TIP })
    ml:Toggle(L.LC_IGNORE_BOE, function() return o().ignoreBoE end, function(v) o().ignoreBoE = v end)
    ml:Edit(L.LC_IGNORE_LIST, function() return o().ignore end, function(v) o().ignore = v or "" end,
        { col = 2, width = 220, placeholder = L.LC_IGNORE_LIST_PH, tip = L.LC_IGNORE_LIST_TIP })
    ml:Toggle(L.LC_AUTO_ASSIGN, function() return o().autoAssign end, function(v) o().autoAssign = v end, { col = 0, tip = L.LC_AUTO_ASSIGN_TIP })
    for q = 0, 5 do
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local qname = (c and c.hex or "") .. (_G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)) .. "|r"
        ml:Edit(L.LC_ASSIGN_QUALITY:format(qname), function() return o().assign[q] or "" end, function(v)
            v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            local lower = v:lower()
            if lower == "ich" or lower == "me" or lower == "mir" then v = "me" end
            o().assign[q] = v
        end, { col = (q % 2 == 0) and 1 or 2, width = 160, placeholder = L.LC_ASSIGN_PH,
            show = function() return o().autoAssign end, tip = L.LC_ASSIGN_TIP })
    end

    function setup.Refresh()
        local members = {}
        for _, key in ns.GroupUnits() do
            if Council.IsCouncilMember(key, cfg()) then members[#members + 1] = Names.Display(key) end
        end
        local me = Council.IsCouncilMember(Names.Me(), cfg())
        statusRow.text:SetText(Theme.HexColor(me and "good" or "muted", me and L.LC_YOU_ARE_COUNCIL or L.LC_YOU_ARE_NOT_COUNCIL) ..
            (#members > 0 and ("\n" .. L.LC_COUNCIL_IN_GROUP .. ": " .. table.concat(members, ", ")) or ""))
        form:Refresh()
    end
    tabs.setup = setup

    local bar = UI.SubTabs(content, { { key = "history", title = L.LC_HISTORY }, { key = "setup", title = L.LC_SETUP } }, function(key)
        for k, t in pairs(tabs) do t:SetShown(k == key) end
        tabs[key].Refresh()
    end)
    bar:SetPoint("TOPLEFT", 0, -36)
    bar:SetPoint("TOPRIGHT", 0, -36)
    bar:Select("history")
    ns.CouncilPage = { ShowSetup = function() bar:Select("setup") end, ShowHistory = function() bar:Select("history") end, bar = bar }
    setup.SearchHits = function(q) return form:Filter(q) end
    setup.SearchApply = function(q) form:Filter(q) end
    form.reveal = ns.CouncilPage.ShowSetup
    page.OnShow = function()
        -- only the council (rank, names, loot master) may send the setup to the guild
        toolbar.buttons[4]:SetShown(Council.IsCouncilMember(ns.Names.Me()))
        toolbar:Fit()
        tabs[bar.current].Refresh()
    end
end, { section = "raid", icon = "gem", module = "council", visible = function()
    if not ns.Database.Settings().modules.councilOnlyMembers then return true end
    return Council.IsCouncilMember(Names.Me())
end })

ns.On("LG_ITEMS", function() ns.Window.Refresh("council") end)
