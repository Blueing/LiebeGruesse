-- Settings pages: "General" and "Appearance"
local _, ns = ...
local UI, Theme, L, Items = ns.UI, ns.Theme, ns.L, ns.Items

local ROLE_LABELS = {
    { "accent", "COLOR_ACCENT" }, { "text", "COLOR_TEXT" }, { "textDim", "COLOR_TEXT_DIM" }, { "muted", "COLOR_MUTED" },
    { "bg", "COLOR_BG" }, { "sidebar", "COLOR_SIDEBAR" }, { "header", "COLOR_HEADER" }, { "panel", "COLOR_PANEL" },
    { "rowAlt", "COLOR_ROW_ALT" }, { "input", "COLOR_INPUT" }, { "border", "COLOR_BORDER" }, { "borderDim", "COLOR_BORDER_DIM" },
    { "button", "COLOR_BUTTON" }, { "buttonHot", "COLOR_BUTTON_HOT" }, { "accentDim", "COLOR_ACCENT_DIM" },
    { "good", "COLOR_GOOD" }, { "warn", "COLOR_WARN" }, { "bad", "COLOR_BAD" },
}

UI.AddPage("general", L.PAGE_GENERAL, 90, function(content, page)
    local settings = ns.Database.Settings()
    local form = UI.Form(content)
    page.Search = function(text) return form:Filter(text) end
    page.SearchEnter = function() form:JumpFirst() end
    page.head = L.HEAD_GENERAL
    form.scroll:SetPoint("TOPLEFT")
    form.scroll:SetPoint("BOTTOMRIGHT", -8, 0)

    local s = form:Section(L.SET_INTERFACE)
    s:Toggle(L.SET_MINIMAP, function() return not settings.minimap.hide end,
        function(v) settings.minimap.hide = not v; UI.UpdateMinimap() end)
    s:Toggle(L.WN_SETTING, function() return ns.WhatsNew.Settings().whatsNew end,
        function(v) ns.WhatsNew.Settings().whatsNew = v end, { tip = L.WN_SETTING_TIP })
    s:Buttons({ { L.WN_OPEN, function() ns.WhatsNew.Show(nil, true) end, width = 170, icon = "scroll-text" },
        { L.PAGE_MODULES, function() ns.Window.Show("modules") end, width = 150, icon = "badge-check", tip = L.SET_MODULES_MOVED },
        { L.TIPS_OPEN, function() ns.Window.Show("tooltips") end, width = 170, icon = "message-circle" } })

    local chars = form:Section(L.SET_CHARACTERS)
    chars:Edit(L.SET_MAIN_SHORT, function() return ns.Database.Char().main end, function(v)
        local old = ns.Database.Char().main
        ns.Database.Char().main = v ~= "" and v or nil
        if old ~= ns.Database.Char().main then ns.Profile.Update(true) end
    end, { placeholder = L.SET_MAIN_PLACEHOLDER, tip = L.SET_MAIN })
    chars:Toggle(L.SET_AUTO_ALTS, function() return ns.Account.Settings().autoAlts end,
        function(v) ns.Account.Settings().autoAlts = v; ns.Profile.Update(true) end, { tip = L.SET_AUTO_ALTS_TIP })
    chars:Edit(L.SET_HOME_GUILD, function() return ns.Account.Settings().homeGuild end, function(v)
        ns.Account.Settings().homeGuild = (v ~= "" and v) or "Liebe Grüße"
        ns.Profile.Update(true)
    end, { tip = L.SET_HOME_GUILD_TIP })
    chars:Note(L.SET_ACCOUNT_CHARS:format(#ns.Account.Alts() + 1, ns.Names.Display(ns.Account.Main() or ns.Names.Me())),
        { height = 26, show = function() return ns.Account.Settings().autoAlts end })

    local group = form:Section(L.SET_GROUP)
    group:Dropdown(L.ROLE_AUTO, function()
        return { { value = "auto", text = L.ROLE_FROM_TALENTS }, { value = "TANK", text = L.ROLE_TANK },
            { value = "HEALER", text = L.ROLE_HEALER }, { value = "DAMAGER", text = L.ROLE_DAMAGE }, { value = "off", text = L.OFF } }
    end, function() return ns.QoL.Setting() end, function(v) ns.Database.Char().role = v; ns.QoL.ApplyRole(true) end,
        { tip = L.ROLE_AUTO_TIP })

    local share = form:Section(L.SET_SHARE)
    share:Note(L.SET_SHARE_HINT)
    share:Buttons({
        { L.SHARE_PART_cooldowns, function() ns.Share.ShowExport({ "cooldowns" }) end, width = 150, icon = "timer" },
        { L.SHARE_PART_council, function() ns.Share.ShowExport({ "council" }) end, width = 150, icon = "gem" },
        { L.SHARE_PART_look, function() ns.Share.ShowExport({ "look" }) end, width = 130, icon = "palette" },
        { L.SHARE_ALL, function() ns.Share.ShowExport(ns.Share.ORDER) end, width = 130, icon = "scroll-text" },
    })
    share:Buttons({ { L.SHARE_IMPORT, function() ns.Share.ShowImport() end, width = 180, icon = "rotate-ccw" } })

    local e = form:Section(L.SET_ENCHANTS, { grid = true, wide = true })
    e:Note(L.SET_ENCHANTS_HINT)
    local n = 0
    for _, slot in ipairs(Items.SLOTS) do
        if not slot.key:match("^FINGER") and not slot.key:match("^TRINKET") then
            n = n + 1
            e:Toggle(L["SLOT_" .. slot.key], function() return settings.enchantSlots[slot.id] end,
                function(v) settings.enchantSlots[slot.id] = v or nil; ns.Fire("LG_PROFILE") end, { col = (n % 2 == 1) and 1 or 2 })
        end
    end

    form:Layout()
    page.OnShow = function() form:Refresh() end
end, { section = "settings", icon = "settings" })

UI.AddPage("appearance", L.PAGE_APPEARANCE, 95, function(content, page)
    local theme = ns.Database.Settings().theme
    local form = UI.Form(content)
    page.Search = function(text) return form:Filter(text) end
    page.SearchEnter = function() form:JumpFirst() end
    page.head = L.HEAD_APPEARANCE
    form.scroll:SetPoint("TOPLEFT")
    form.scroll:SetPoint("BOTTOMRIGHT", -8, 0)

    local w = form:Section(L.SET_LOOK)
    w:Dropdown(L.SET_THEME, function()
        local list = {}
        for _, p in ipairs(Theme.PRESETS) do list[#list + 1] = { value = p.key, text = p.name } end
        return list
    end, function() return theme.preset end, function(v) Theme.SetPreset(v) end)
    w:Dropdown(L.FONT, function() return Theme.Fonts() end, function() return theme.font end,
        function(v) theme.font = v; Theme.Apply() end)
    w:Segment(L.SET_FONT_WEIGHT, { { value = "normal", text = L.SET_WEIGHT_NORMAL }, { value = "strong", text = L.SET_WEIGHT_STRONG }, { value = "bold", text = L.SET_WEIGHT_BOLD } },
        function() return theme.weight or "strong" end, function(v) theme.weight = v; Theme.Apply() end,   -- weights exist for Barlow only
        { tip = L.SET_WEIGHT_TIP, show = function() return theme.font == "Barlow" or (theme.font == "Expressway" and not Theme.HasExpressway()) end })
    w:Slider(L.SET_FONT_SCALE, 0.8, 1.4, 0.05, function() return theme.fontScale end,
        function(v) theme.fontScale = v; ns.Debounce("theme-apply", 0.25, Theme.Apply) end,
        { col = 2, fmt = function(v) return ("%d%%"):format(v * 100 + 0.5) end })
    w:Toggle(L.SET_HEADER_MAPS, function() return theme.headerMaps ~= false end,
        function(v) theme.headerMaps = v; ns.Window.UpdateMap() end, { tip = L.SET_HEADER_MAPS_TIP })
    w:Slider(L.SCALE, 0.6, 1.4, 0.05, function() return theme.windowScale end,
        function(v) theme.windowScale = v; ns.Debounce("theme-apply", 0.25, Theme.Apply) end,
        { col = 2, fmt = function(v) return ("%d%%"):format(v * 100 + 0.5) end })
    w:Slider(L.OPACITY, 0.3, 1, 0.05, function() return theme.windowAlpha end,
        function(v) theme.windowAlpha = v; ns.Debounce("theme-apply", 0.1, Theme.Apply) end,
        { col = 2, fmt = function(v) return ("%d%%"):format(v * 100 + 0.5) end })

    local c = form:Section(L.SET_COLORS)
    c:Note(L.SET_COLORS_HINT)
    for i, entry in ipairs(ROLE_LABELS) do
        local role = entry[1]
        c:Color(L[entry[2]], function() return Theme.Color(role) end,
            function(r, g, b, a) Theme.SetColor(role, r, g, b, a) end, { col = (i % 2 == 1) and 1 or 2, alpha = true })
    end
    c:Buttons({ { L.SET_RESET_COLORS, function() Theme.SetPreset(theme.preset) end, width = 220, icon = "rotate-ccw" } })

    form:Layout()
    page.OnShow = function() form:Refresh() end
end, { section = "settings", icon = "palette" })
