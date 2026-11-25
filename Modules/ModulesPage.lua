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
    { key = "stats", icon = "badge-check", page = "stats" },
    { key = "greet", icon = "message-circle" },
}

local function settings() return ns.Database.Settings() end

local function apply()
    ns.Window.BuildNav()
    ns.Fire("LG_COOLDOWNS")
    ns.Fire("LG_MODULES")
end

-- A card: icon, name, description, switch on the right
local function card(parent, icon, title, text, get, set)
    local c = CreateFrame("Button", nil, parent)
    c.bg = UI.Fill(c, "panel", "BACKGROUND")
    c.bg:SetAllPoints()
    c.bar = UI.Fill(c, "accent", "ARTWORK")
    c.bar:SetPoint("TOPLEFT"); c.bar:SetPoint("BOTTOMLEFT"); c.bar:SetWidth(2)
    c.icon = UI.Icon(c, icon, 18, "accent")
    c.icon:SetPoint("TOPLEFT", 14, -12)
    c.title = UI.Text(c, 13, "text")
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, 1)
    c.title:SetText(title)
    c.text = UI.Text(c, 11, "muted")
    c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
    c.text:SetPoint("RIGHT", c, "RIGHT", -60, 0)
    c.text:SetWordWrap(true)
    c.text:SetJustifyV("TOP")
    c.text:SetText(text)
    c.toggle = UI.Toggle(c, get, function(v) set(v); c:Refresh() end)
    c.toggle:SetPoint("TOPRIGHT", -14, -14)
    c:SetScript("OnClick", function() c.toggle:Click() end)
    function c:Refresh()
        self.toggle:Refresh()
        local on = get()
        self.bar:SetShown(on)
        self.title:SetTextColor(Theme.Color(on and "text" or "muted"))
        self.icon:SetVertexColor(Theme.Color(on and "accent" or "muted"))
    end
    c.control = c
    c.searchTitle, c.searchText = title, title .. " " .. (text or "")
    function c:Highlight(q)
        self.title:SetText(q and ns.Highlight(title, q) or title)
        self.text:SetText(q and ns.Highlight(text, q) or text)
    end
    return c
end

UI.AddPage("modules", L.PAGE_MODULES, 89, function(content, page)
    local form = UI.Form(content)
    page.Search = function(text) return form:Filter(text) end
    page.SearchEnter = function() form:JumpFirst() end
    page.searchRow = true
    form.scroll:SetPoint("TOPLEFT")
    form.scroll:SetPoint("BOTTOMRIGHT", -8, 0)

    local mods = form:Section(L.SET_MODULES)
    mods:Note(L.MODULES_HINT, { col = 0, height = 30 })
    for i, m in ipairs(MODULES) do
        local c = card(form.body, m.icon, L["PAGE_" .. m.key:upper()] or m.key, L["MOD_" .. m.key:upper() .. "_TEXT"] or "",
            function() return settings().modules[m.key] ~= false end,
            function(v) settings().modules[m.key] = v; apply() end)
        mods:Custom(c, 62, { col = (i % 2 == 1) and 1 or 2 })
    end
    mods:Toggle(L.SET_COUNCIL_ONLY, function() return settings().modules.councilOnlyMembers end, function(v)
        settings().modules.councilOnlyMembers = v
        apply()
    end, { col = 0, tip = L.SET_COUNCIL_ONLY_TIP, show = function() return settings().modules.council ~= false end })

    -- single cooldown displays
    local displays = form:Section(L.MOD_DISPLAYS)
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
