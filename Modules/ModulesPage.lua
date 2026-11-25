-- "Modules" page: switch whole modules and single cooldown displays on/off.
-- Everything is on by default; each player decides for themselves.
local _, ns = ...
local UI, Theme, L = ns.UI, ns.Theme, ns.L

local MODULES = {
    { key = "cooldowns", icon = "timer", page = "cooldowns" },
    { key = "council", icon = "gem", page = "council" },
    { key = "blessings", icon = "sparkles", page = "blessings" },
    { key = "community", icon = "crown", page = "community" },
    { key = "professions", icon = "scroll-text", page = "professions" },
    { key = "feed", icon = "newspaper", page = "feed" },
    { key = "dungeons", icon = "compass", page = "dungeons" },
    { key = "stats", icon = "badge-check", page = "stats" },
    { key = "greet", icon = "message-circle" },
}

local function settings() return ns.Database.Settings() end

local function apply()
    ns.Window.BuildNav()
    ns.Fire("LG_COOLDOWNS")
    ns.Fire("LG_MODULES")
end

UI.AddPage("modules", L.PAGE_MODULES, 89, function(content, page)
    local form = UI.Form(content)
    page.Search = function(text) return form:Filter(text) end
    page.SearchEnter = function() form:JumpFirst() end
    page.head = L.HEAD_MODULES
    form.scroll:SetPoint("TOPLEFT")
    form.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    local st = settings()
    local function isOn(key) return function() return st.modules[key] ~= false end end

    -- every module: icon, name, switch (two columns); what it does in the tooltip
    local mods = form:Section(L.SET_MODULES, { wide = true, grid = true })
    for _, m in ipairs(MODULES) do
        local name = L["PAGE_" .. m.key:upper()] or m.key
        local _, row = mods:Toggle(name, isOn(m.key), function(v) st.modules[m.key] = v; apply() end,
            { tip = L["MOD_" .. m.key:upper() .. "_TEXT"] })
        row.icon = UI.Icon(row, m.icon, 16, "accent")
        row.icon:SetPoint("LEFT", 16, 0)
        row.label:SetPoint("LEFT", 42, 0)
        row.searchText = L["MOD_" .. m.key:upper() .. "_TEXT"] or ""
    end

    -- the features of each module ("submodules"); a card only while its module is on
    local feed = form:Section(L.PAGE_FEED, { show = isOn("feed") })
    feed:Toggle(L.SET_TOASTS, function() return st.toasts end, function(v) st.toasts = v end, { tip = L.SET_TOASTS_TIP })
    feed:Buttons({ { L.PAGE_NOTIFY, function() ns.Window.Show("notifications") end, width = 170, icon = "newspaper" } })

    local prof = form:Section(L.PAGE_PROFESSIONS, { show = isOn("professions") })
    prof:Toggle(L.SET_CRAFT_ANSWER, function() return st.craft.answer end, function(v) st.craft.answer = v end,
        { tip = L.SET_CRAFT_ANSWER_TIP .. "\n\n" .. L.SET_CRAFT_HINT })
    prof:Edit(L.SET_CRAFT_PREFIX, function() return st.craft.prefix end, function(v)
        if v ~= "" then st.craft.prefix = v end
    end, { width = 120 })
    prof:Toggle(L.SET_PSYNC_CHAT, function() return ns.ProfSync.Settings().profSyncChat end,
        function(v) ns.ProfSync.Settings().profSyncChat = v end, { tip = L.SET_PSYNC_CHAT_TIP })
    prof:Toggle(L.SET_PSYNC_HINT, function() return ns.ProfSync.Settings().profSyncHint ~= false end,
        function(v) ns.ProfSync.Settings().profSyncHint = v end, { tip = L.SET_PSYNC_HINT_TIP })
    prof:Buttons({ { L.PSYNC_SHOW, function()
        if #ns.ProfSync.All() == 0 then ns.Print(L.PSYNC_NONE) else ns.ProfSync.Show() end
    end, width = 180, icon = "scroll-text" } })

    local council = form:Section(L.PAGE_COUNCIL, { show = isOn("council") })
    council:Toggle(L.LC_AUTOPASS, function() return st.lcAutoPass end, function(v) st.lcAutoPass = v end, { tip = L.LC_AUTOPASS_TIP })
    council:Toggle(L.SET_COUNCIL_ONLY, function() return st.modules.councilOnlyMembers end, function(v)
        st.modules.councilOnlyMembers = v
        apply()
    end, { tip = L.SET_COUNCIL_ONLY_TIP })

    local bless = form:Section(L.PAGE_BLESSINGS, { show = isOn("blessings") })
    local function bo() return ns.Blessings.Settings() end
    local function barUpdate() if ns.BlessingsBar then ns.BlessingsBar.Update() end end
    bless:Toggle(L.BLESS_SHOW_BAR, function() return bo().bar end, function(v) bo().bar = v; barUpdate() end, { tip = L.BLESS_SHOW_BAR_TIP })
    bless:Toggle(L.BLESS_RAID_ONLY, function() return bo().raidOnly end, function(v) bo().raidOnly = v; barUpdate() end)
    bless:Toggle(L.BLESS_SOLO, function() return bo().solo end, function(v) bo().solo = v; barUpdate() end, { tip = L.BLESS_SOLO_TIP })
    bless:Toggle(L.BLESS_FREE, function() return bo().freeAssign end, function(v) bo().freeAssign = v; ns.Blessings.Share(ns.Blessings.Me()) end,
        { tip = L.BLESS_FREE_TIP })
    bless:Toggle(L.BLESS_PP_READ, function() return bo().ppRead end, function(v) bo().ppRead = v; if v then ns.Blessings.Request() end end,
        { tip = L.BLESS_PP_READ_TIP })
    bless:Toggle(L.BLESS_PP_SYNC, function() return bo().ppSync end, function(v) bo().ppSync = v; if v then ns.Blessings.Share(ns.Blessings.Me()) end end,
        { tip = L.BLESS_PP_SYNC_TIP })

    local greet = form:Section(L.SET_GREET, { show = isOn("greet") })
    greet:Note(L.SET_GREET_HINT, { height = 34 })

    -- single cooldown displays
    local displays = form:Section(L.MOD_DISPLAYS, { show = isOn("cooldowns") })
    displays:Note(L.MOD_DISPLAYS_HINT, { col = 0, height = 20 })
    local rows = {}
    local holder = CreateFrame("Frame", nil, form.body)
    displays:Custom(holder, 10, { col = 0, show = function() return settings().modules.cooldowns ~= false end })
    local buttons = CreateFrame("Frame", nil, form.body)
    local newBar = UI.Button(buttons, L.CD_ADD_DISPLAY, 150, 26, function()
        ns.Window.Show("cooldowns")
    end, "timer")
    newBar:SetPoint("LEFT")
    local move = UI.Button(buttons, L.MOVE_ELEMENTS, 170, 26, function() ns.Window.ToggleMovers() end, "move")
    move:SetPoint("LEFT", newBar, "RIGHT", 8, 0)
    displays:Custom(buttons, 28, { col = 0, show = function() return settings().modules.cooldowns ~= false end })

    local function buildDisplays()
        local Bars = ns.CooldownBars
        local keys = Bars.Keys()
        for _, r in ipairs(rows) do r:Hide() end
        for i, key in ipairs(keys) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Button", nil, holder)
                r:SetHeight(30)
                r.bg = UI.Fill(r, (i % 2 == 0) and "rowAlt" or "row", "BACKGROUND")
                r.bg:SetAllPoints()
                r.name = UI.Text(r, 12, "text")
                r.name:SetPoint("LEFT", 12, 0)
                r.info = UI.Text(r, 11, "muted")
                r.info:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
                rows[i] = r
            end
            local d = Bars.Display(key)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * 32)
            r.name:SetText(d.name)
            r.name:SetTextColor(Theme.Color(d.enabled and "text" or "muted"))
            local kind = d.mode == "icons" and L.CD_MODE_ICONS or L.CD_MODE_BARS
            if not Bars.IsBuiltin(key) then kind = kind .. " · " .. L.CD_OWN_BAR end
            r.info:SetText(kind)
            if r.toggle then r.toggle:Hide() end
            r.toggle = UI.Toggle(r, function() return Bars.Display(key).enabled end, function(v)
                Bars.Display(key).enabled = v
                Bars.Layout()
                ns.Window.Refresh("cooldowns")
                r.name:SetTextColor(Theme.Color(v and "text" or "muted"))
            end)
            r.toggle:SetPoint("RIGHT", -14, 0)
            r:SetScript("OnClick", function() r.toggle:Click() end)
            r:Show()
        end
        holder:SetHeight(math.max(10, #keys * 32))
    end

    page.OnShow = function()
        buildDisplays()
        form:Refresh()
    end
end, { section = "settings", icon = "badge-check" })
