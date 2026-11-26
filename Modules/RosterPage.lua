-- Roster page: guild members with item level, spec, professions and gear
local _, ns = ...
local UI, Theme, L, Names, Items = ns.UI, ns.Theme, ns.L, ns.Names, ns.Items
local Roster = ns.NewModule("roster")
ns.Roster = Roster

local state = { search = "", online = false, mains = false, missing = false, selected = nil,
    filter = { mine = false, max = false, classes = {}, ranks = {}, profs = {} } }
Roster.state = state
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local SHORT = {}  -- profession short names
-- common abbreviations, the same in every client language
local ABBR = { alchemy = "Alch", blacksmithing = "BS", enchanting = "Ench", engineering = "Engi", jewelcrafting = "JC",
    leatherworking = "LW", tailoring = "T", inscription = "Insc", mining = "M", herbalism = "H", skinning = "Skin",
    cooking = "Cook", firstaid = "FA", fishing = "Fish" }
local function short(name)
    if SHORT[name] then return SHORT[name] end
    local key = ns.Crafts and ns.Crafts.ProfKey(name)
    SHORT[name] = (key and ABBR[key]) or tostring(name):sub(1, 4)
    return SHORT[name]
end

-- Profile of a member from any guild we have data for (own guild first)
function Roster.MemberAny(key)
    local m = ns.Database.Member(key)
    if m then return m end
    for _, g in pairs(ns.db.guilds or {}) do
        if g.members and g.members[key] then return g.members[key] end
    end
    local p = ns.CoGuild and ns.CoGuild.Presence(key)
    if p then
        local pr = {}
        for entry in (p.pr or ""):gmatch("[^,]+") do
            local n, sk = entry:match("^(.-):(%d*)$")
            if n then pr[#pr + 1] = { n = n, s = tonumber(sk) } end
        end
        return { name = p.name, c = p.class, l = p.level, il = p.il, sp = p.sp, m = p.main, v = p.v, pr = pr }
    end
end

-- own characters: every character of this account, and members who named one of them as main
function Roster.IsMine(key, m)
    if not key then return false end
    if Names.Same(key, Names.Me()) or (ns.db and ns.db.chars and ns.db.chars[key]) then return true end
    local main = ns.Account and ns.Account.Main()
    m = m or ns.Database.Member(key)
    return main ~= nil and m ~= nil and m.m ~= nil and Names.Same(m.m, main)
end

-- the extra filters of the "Filter" menu
local function filterCount()
    local f, n = state.filter, 0
    if f.mine then n = n + 1 end
    if f.max then n = n + 1 end
    for _, t in ipairs({ f.classes, f.ranks, f.profs }) do if next(t) then n = n + 1 end end
    return n
end
Roster.FilterCount = filterCount

local function passFilter(row)
    local f = state.filter
    if f.mine and not Roster.IsMine(row.key, row.m) then return false end
    if f.max and (row.level or 0) < 60 then return false end
    if next(f.classes) and not f.classes[row.class or ""] then return false end
    if next(f.ranks) and not f.ranks[row.rank or ""] then return false end
    if next(f.profs) then
        local any = false
        for _, p in ipairs(row.profs or {}) do
            local pk = ns.Crafts and ns.Crafts.ProfKey(p.n) or p.n
            if f.profs[pk] then any = true end
        end
        if not any then return false end
    end
    return true
end

local function keepRow(row, search, hay)
    if not passFilter(row) then return false end
    if state.missing and not (row.enchants and #row.enchants.missing > 0) then return false end
    if state.online and not row.online then return false end
    if state.mains and row.main and not Names.Same(row.main, row.key) then return false end
    return true
end

-- Rows of another guild (partner guild, or the home guild while on an alt):
-- members with the addon (cached profiles, live presence) and /who results
function Roster.OtherRows(guild)
    local rows, seen = {}, {}
    local search = state.search:lower()
    local lower = guild:lower()
    local now = ns.Now()
    local function add(key, base)
        if seen[key] then return end
        seen[key] = true
        local m = Roster.MemberAny(key) or {}
        local p = ns.CoGuild and ns.CoGuild.Presence(key)
        local gear, ilvl = ns.Inspect.Gear(m)
        local lastSeen = (p and p.t) or base.seen or m.seen
        local row = {
            key = key, m = m, other = guild, name = base.name or m.name or key, class = base.class or m.c,
            level = base.level or m.l, rank = "", rankIndex = 99, online = ns.CoGuild and ns.CoGuild.IsOnline(key) or false,
            ilvl = (p and p.il) or ilvl, gear = gear, spec = ns.SpecName((p and p.sp) or m.sp, base.class or m.c, ns.SpecPoints(m)), main = (p and p.main) or m.m,
            version = (p and p.v) or m.v, offline = lastSeen and math.floor((now - lastSeen) / 3600) or nil, zone = (p and p.zone) or base.zone,
        }
        row.profs = {}
        for _, pr in ipairs(m.pr or {}) do row.profs[#row.profs + 1] = pr end
        row.enchants = gear and Items.EnchantStatus(gear) or nil
        if keepRow(row, search, { key, (row.zone or ""):lower(), (row.spec or ""):lower() }) then rows[#rows + 1] = row end
    end
    -- /who results and channel presence
    for key, e in pairs(ns.CoGuild and ns.CoGuild.Store() or {}) do
        if type(e.guild) == "string" and e.guild:lower() == lower then add(key, e) end
    end
    -- profiles cached while playing a character in that guild
    local g = ns.db.guilds and ns.db.guilds[lower]
    for key, m in pairs(g and g.members or {}) do
        add(key, { name = m.name, class = m.c, level = m.l, seen = m.seen })
    end
    return rows
end

-- Builds one row per guild roster member, merged with synced data
function Roster.Rows()
    if state.view and state.view ~= "own" then return Roster.OtherRows(state.view) end
    local rows = {}
    local search = state.search:lower()
    for key, g in pairs(ns.Guild.members) do
        local m = ns.Database.Member(key) or {}
        local gear, ilvl = ns.Inspect.Gear(m)
        local row = {
            key = key, g = g, m = m, name = g.name, class = g.class or m.c, level = g.level or m.l,
            rank = g.rank, rankIndex = g.rankIndex, online = g.online, ilvl = ilvl, gear = gear,
            spec = ns.SpecName(m.sp or (m.insp and m.insp.sp), g.class or m.c, ns.SpecPoints(m)), main = m.m, version = m.v, offline = g.offlineHours,
        }
        local profs = {}
        for _, p in ipairs(m.pr or {}) do profs[#profs + 1] = p end
        row.profs = profs
        row.enchants = gear and Items.EnchantStatus(gear) or nil
        local keep = passFilter(row)
        if state.missing and not (row.enchants and #row.enchants.missing > 0) then keep = false end
        if state.online and not g.online then keep = false end
        if state.mains and m.m and not Names.Same(m.m, key) then keep = false end
        if keep then rows[#rows + 1] = row end
    end
    return rows
end

local function profText(row)
    local parts = {}
    for _, p in ipairs(row.profs) do
        parts[#parts + 1] = ("%s %s"):format(short(p.n), p.s or "?")
    end
    return table.concat(parts, " · ")
end

local function lastSeen(row)
    if row.online then return UI.Glyph("dot", "good", 10) .. " " .. Theme.HexColor("good", L.ONLINE) end
    local h = row.offline
    if not h then return Theme.HexColor("muted", "–") end
    if h < 1 then return Theme.HexColor("muted", L.LESS_HOUR) end
    if h < 48 then return Theme.HexColor("muted", L.HOURS_AGO:format(h)) end
    return Theme.HexColor("muted", L.DAYS_AGO:format(math.floor(h / 24)))
end

-- main professions of a row (no cooking, first aid, fishing), English names, highest skill first
local SECONDARY_PROFS = { cooking = true, firstaid = true, fishing = true }
function Roster.MainProfs(row)
    local out = {}
    for _, p in ipairs(row.profs or {}) do
        local pk = ns.Crafts and ns.Crafts.ProfKey(p.n)
        local info = pk and ns.Crafts.ProfInfo(pk)
        if info and not SECONDARY_PROFS[pk] then
            out[#out + 1] = { key = pk, icon = info.icon, name = ns.Crafts.ProfName(pk), s = p.s, order = info.order }
        end
    end
    table.sort(out, function(a, b)
        if (tonumber(a.s) or 0) ~= (tonumber(b.s) or 0) then return (tonumber(a.s) or 0) > (tonumber(b.s) or 0) end
        return a.order < b.order
    end)
    return out
end

-- row tooltip: who it is, which data is known (source and age), where they are
function Roster.RowTooltip(frame, row)
    local m, g = row.m or {}, row.g or {}
    ns.TipOwner(frame, "ANCHOR_RIGHT")
    local icon = ns.SpecIcon(row.class, ns.SpecPoints(m))
    local iconText = icon and ("|T%s:22:22:0:0:64:64:5:59:5:59|t "):format(icon) or ""
    local ilvl = row.ilvl and Theme.HexColor("gold", L.ARM_ILVL:format(("%.1f"):format(row.ilvl))) or ""
    GameTooltip:AddDoubleLine(iconText .. ns.ColorName(row.name or row.key, row.class), ilvl)
    local class = row.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[row.class] or row.class) or nil
    local who = {}
    if row.level then who[#who + 1] = L.LEVEL .. " " .. row.level end
    if class then who[#who + 1] = ("|c%s%s|r"):format(ns.ClassHex(row.class), class) end
    if row.spec then who[#who + 1] = Theme.HexColor("text", row.spec) end
    if #who > 0 then GameTooltip:AddLine(Theme.HexColor("textDim", table.concat(who, Theme.HexColor("muted", " · ")))) end
    if row.rank and row.rank ~= "" then GameTooltip:AddLine(Theme.HexColor("muted", row.rank)) end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Theme.HexColor("muted", ns.Upper(L.COL_DATA)))
    local function data(glyph, label, value, source, t)
        local left = UI.Glyph(glyph, value and "textDim" or "borderDim", 12) .. " " .. Theme.HexColor("textDim", label .. ": ")
            .. (value and Theme.HexColor("text", value) or Theme.HexColor("muted", L.UNKNOWN))
            .. (source and Theme.HexColor("muted", " · " .. source) or "")
        GameTooltip:AddDoubleLine(left, t and Theme.HexColor("muted", ns.Ago(t)) or "")
    end
    local gear, _, source, gearT = ns.Inspect.Gear(m)
    data("shield", L.GEAR, gear and L.ROSTER_TIP_COMPLETE or nil,
        gear and (source == "inspect" and L.ARM_FROM_INSPECT or L.ARM_FROM_ADDON) or nil, gear and gearT or nil)
    local insp = m.insp or {}
    if tostring(m.tp or ""):find("[1-9]") then data("sparkles", L.ARM_TALENTS, tostring(m.tp), L.ARM_FROM_ADDON, m.t)
    elseif insp.tp then data("sparkles", L.ARM_TALENTS, tostring(insp.tp), L.ARM_FROM_INSPECT, insp.t)
    else data("sparkles", L.ARM_TALENTS) end
    local mains = Roster.MainProfs(row)
    if #mains > 0 then
        -- main professions only (icon, name, skill) – cooking, first aid and fishing stay in the column tip
        local names = {}
        for _, p in ipairs(mains) do
            names[#names + 1] = ("|T%s:12:12:0:0:64:64:5:59:5:59|t %s %s"):format(p.icon, p.name, Theme.HexColor("textDim", p.s or "?"))
        end
        data("hammer", L.COL_PROFESSIONS, table.concat(names, "  "), nil, m.t)
    else
        data("hammer", L.COL_PROFESSIONS)
    end
    if row.online then
        local zone = g.zone or row.zone
        GameTooltip:AddLine(UI.Glyph("dot", "good", 10) .. " " .. Theme.HexColor("good",
            zone and zone ~= "" and L.ROSTER_TIP_ZONE:format(zone) or L.ONLINE))
    elseif row.offline then
        GameTooltip:AddLine(UI.Glyph("ring", "muted", 10) .. " " .. Theme.HexColor("muted", (L.OFFLINE:gsub("^%l", string.upper)) .. " · ") .. lastSeen(row))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Theme.HexColor("muted", L.ROSTER_ROW_TIP))
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local list, countText, summary

local function refresh()
    if not list then return end
    if Roster.UpdateFilterButton then Roster.UpdateFilterButton() end
    list:SetRows(Roster.Rows())
    local online, total = 0, 0
    for _, g in pairs(ns.Guild.members) do total = total + 1; if g.online then online = online + 1 end end
    local ilvlSum, ilvlN, addon, missing = 0, 0, 0, 0
    for _, row in ipairs(list.rows) do
        if row.ilvl and (row.level or 0) >= 60 then ilvlSum, ilvlN = ilvlSum + row.ilvl, ilvlN + 1 end
        if row.version then addon = addon + 1 end
        if row.enchants and #row.enchants.missing > 0 then missing = missing + 1 end
    end
    if state.view and state.view ~= "own" then
        local on = 0
        for _, row in ipairs(list.rows) do if row.online then on = on + 1 end end
        countText:SetText(L.ROSTER_OTHER_SUMMARY:format(state.view, on, #list.rows))
        summary:Set({ { "users", "good", on .. " / " .. #list.rows, L.ROSTER_S_ONLINE } }, countText:GetText())
    else
        countText:SetText(L.ROSTER_SUMMARY:format(online, total, ilvlN > 0 and ("%.1f"):format(ilvlSum / ilvlN) or "–", addon, missing))
        summary:Set({
            { "users", "good", online .. " / " .. total, L.ROSTER_S_ONLINE },
            { "shield", "bronze", ilvlN > 0 and ("%.1f"):format(ilvlSum / ilvlN) or "–", L.ROSTER_S_ILVL },
            { "link", "lapis", tostring(addon), L.ROSTER_S_ADDON },
            { "x", missing > 0 and "warn" or "muted", tostring(missing), L.ROSTER_S_MISSING, missing > 0 and "warn" or "text" },
        })
    end
    if ns.Armory and ns.Armory.IsOpen() then ns.Armory.Fill() end
end
Roster.Refresh = refresh

-- the "Filter" menu (checked entries, sub menus per class, rank, profession)
function Roster.FilterMenu()
    local f = state.filter
    local function toggle(t, k) return function() t[k] = (not t[k]) or nil; UI.CloseContextMenu(); refresh() end end
    local classes, ranks, profs, seenRank, seenProf = {}, {}, {}, {}, {}
    for _, cls in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local r, g, b = ns.ClassColor(cls)
        classes[#classes + 1] = { text = ns.Hex(r, g, b, ns.ClassName(cls)), checked = f.classes[cls] == true, func = toggle(f.classes, cls) }
    end
    local rankList = {}
    for _, g in pairs(ns.Guild.members) do
        if g.rank and not seenRank[g.rank] then seenRank[g.rank] = true; rankList[#rankList + 1] = { g.rankIndex or 99, g.rank } end
    end
    table.sort(rankList, function(a, b) return a[1] < b[1] end)
    for _, r in ipairs(rankList) do ranks[#ranks + 1] = { text = r[2], checked = f.ranks[r[2]] == true, func = toggle(f.ranks, r[2]) } end
    local profList = {}
    for key in pairs(ns.Guild.members) do
        local m = ns.Database.Member(key)
        for _, p in ipairs(m and m.pr or {}) do
            local pk = ns.Crafts and ns.Crafts.ProfKey(p.n) or p.n
            if pk and not seenProf[pk] then
                seenProf[pk] = true
                local info = ns.Crafts and ns.Crafts.ProfInfo and ns.Crafts.ProfInfo(pk)
                profList[#profList + 1] = { pk, info and info.names and info.names[1] or p.n }
            end
        end
    end
    table.sort(profList, function(a, b) return tostring(a[2]) < tostring(b[2]) end)
    for _, p in ipairs(profList) do profs[#profs + 1] = { text = p[2], checked = f.profs[p[1]] == true, func = toggle(f.profs, p[1]) } end
    local entries = {
        { title = L.ROSTER_FILTER },
        { text = L.ROSTER_F_MINE, checked = f.mine, func = function() f.mine = not f.mine; UI.CloseContextMenu(); refresh() end },
        { text = L.ROSTER_F_MAX, checked = f.max, func = function() f.max = not f.max; UI.CloseContextMenu(); refresh() end },
        { divider = true },
        { text = L.ROSTER_F_CLASS .. (next(f.classes) and " •" or ""), submenu = classes },
        { text = L.ROSTER_F_RANK .. (next(f.ranks) and " •" or ""), submenu = ranks },
        { text = L.ROSTER_F_PROF .. (next(f.profs) and " •" or ""), submenu = #profs > 0 and profs or { { text = L.ROSTER_F_NONE, disabled = true } } },
        { divider = true },
        { text = L.ROSTER_F_RESET, disabled = filterCount() == 0, func = function()
            state.filter = { mine = false, max = false, classes = {}, ranks = {}, profs = {} }
            UI.CloseContextMenu()
            refresh()
        end },
    }
    UI.ContextMenu(entries)
end

UI.AddPage("roster", L.PAGE_ROSTER, 10, function(root, page)
    -- tabs: the roster and its settings (enchant check)
    local content, tabs = UI.PageWithSettings(root, page, L.PAGE_ROSTER, function(form)
        local e = form:Section(L.SET_ENCHANTS, { grid = true, wide = true })
        e:Note(L.SET_ENCHANTS_HINT)
        local n = 0
        for _, slot in ipairs(ns.Items.SLOTS) do
            if not slot.key:match("^FINGER") and not slot.key:match("^TRINKET") then
                n = n + 1
                e:Toggle(L["SLOT_" .. slot.key], function() return ns.Database.Settings().enchantSlots[slot.id] end,
                    function(v) ns.Database.Settings().enchantSlots[slot.id] = v or nil; ns.Fire("LG_PROFILE") end,
                    { col = (n % 2 == 1) and 1 or 2 })
            end
        end
    end)
    -- the name search sits in the page header (page.Search below)
    local online = UI.Check(content, L.ONLY_ONLINE, function() return state.online end, function(v) state.online = v; refresh() end)
    online:SetPoint("TOPLEFT", 0, -4)
    local mains = UI.Check(content, L.ONLY_MAINS, function() return state.mains end, function(v) state.mains = v; refresh() end)
    mains:SetPoint("LEFT", online, "RIGHT", 18, 0)
    local missing = UI.Check(content, L.ONLY_MISSING_ENCHANTS, function() return state.missing end, function(v) state.missing = v; refresh() end)
    missing:SetPoint("LEFT", mains, "RIGHT", 18, 0)
    -- more filters: my characters, level 60, class, rank, profession
    local filterBtn = UI.Button(content, L.ROSTER_FILTER, 110, 22, function(self) GameTooltip:Hide(); Roster.FilterMenu() end, "chevron-down")
    filterBtn:SetPoint("LEFT", missing, "RIGHT", 18, 0)
    filterBtn.tip = { L.ROSTER_FILTER_TIP }
    local function updateFilterBtn()
        local n = filterCount()
        filterBtn:SetText(n > 0 and L.ROSTER_FILTER_N:format(n) or L.ROSTER_FILTER)
        filterBtn:SetBackdropBorderColor(Theme.Color(n > 0 and "accent" or "border"))
    end
    Roster.UpdateFilterButton = updateFilterBtn

    -- summary strip: icon, big number, label per item; bronze tint and corner brackets
    countText = UI.Text(content, 12, "textDim", "LEFT")
    countText:Hide()
    summary = CreateFrame("Frame", nil, content, "BackdropTemplate")
    UI.Skin(summary, "panel", "borderDim")
    summary:SetPoint("TOPLEFT", 0, -32)
    summary:SetPoint("TOPRIGHT", 0, -32)
    summary:SetHeight(30)
    local tint = UI.Gradient(summary, "bronze", 0.10, "BORDER")
    tint:SetPoint("TOPLEFT", 1, -1); tint:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.Corners(summary)
    summary.items = {}
    function summary:Set(items, tip)
        for i, it in ipairs(items) do
            local e = self.items[i]
            if not e then
                e = {}
                e.icon = UI.Icon(self, it[1], 13, it[2])
                e.num = UI.Text(self, 16, "text")
                e.label = UI.Text(self, 12, "muted")
                e.num:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
                e.label:SetPoint("LEFT", e.num, "RIGHT", 5, 0)
                if i == 1 then e.icon:SetPoint("LEFT", 12, 0)
                else e.icon:SetPoint("LEFT", self.items[i - 1].label, "RIGHT", 24, 0) end
                self.items[i] = e
            end
            Theme.SetIcon(e.icon, it[1])
            e.icon:SetVertexColor(Theme.Color(it[2]))
            e.num:SetText(it[3])
            e.num:SetTextColor(Theme.Color(it[5] or "text"))
            e.label:SetText(it[4])
            e.icon:Show(); e.num:Show(); e.label:Show()
        end
        for i = #items + 1, #self.items do
            local e = self.items[i]
            e.icon:Hide(); e.num:Hide(); e.label:Hide()
        end
        self.tip = tip
        self.count = #items
        self:Fit()
    end
    -- narrow: labels drop out from the right (numbers stay, the tooltip has everything)
    function summary:Fit()
        local room = (self:GetWidth() or 600) - 24
        local function sw(fs) return fs:IsShown() and ((fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0) or 0 end
        local function total()
            local w = 0
            for i = 1, self.count or 0 do
                local e = self.items[i]
                w = w + 13 + 6 + sw(e.num) + (e.label:IsShown() and (5 + sw(e.label)) or 0) + (i > 1 and 24 or 0)
            end
            return w
        end
        for i = 1, self.count or 0 do self.items[i].label:Show() end
        for i = self.count or 0, 1, -1 do
            if total() <= room then break end
            self.items[i].label:Hide()
        end
    end
    summary:HookScript("OnSizeChanged", function(self) self:Fit() end)
    summary:EnableMouse(true)
    summary:SetScript("OnEnter", function(self) UI.Tooltip(self, L.PAGE_ROSTER, { self.tip or countText:GetText() }) end)
    summary:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- which guild: the own one, or the partner/home guild (members with the addon + /who)
    local function views()
        local own = IsInGuild() and ns.Call(GetGuildInfo, "player") or L.PAGE_ROSTER
        local items = { { value = "own", text = own } }
        for _, g in ipairs(ns.CoGuild and ns.CoGuild.Guilds() or {}) do items[#items + 1] = { value = g, text = g } end
        return items
    end
    local viewSwitch = UI.Segmented(content, 300, views(), function() return state.view or "own" end, function(v)
        state.view = v
        state.selected = nil
        refresh()
    end)
    viewSwitch:SetPoint("TOPRIGHT", 0, 0)
    -- narrow window: the guild switch moves into the summary row so the filters keep their room
    local narrow
    local function placeTop()
        local w = content:GetWidth() or 1000
        local n = w < 1060
        if n == narrow then return end
        narrow = n
        viewSwitch:ClearAllPoints()
        summary:ClearAllPoints()
        summary:SetPoint("TOPLEFT", 0, -32)
        if n then
            viewSwitch:SetWidth(220)
            viewSwitch:SetPoint("TOPRIGHT", 0, -34)
            summary:SetPoint("TOPRIGHT", -230, -32)
        else
            viewSwitch:SetWidth(300)
            viewSwitch:SetPoint("TOPRIGHT", 0, 0)
            summary:SetPoint("TOPRIGHT", 0, -32)
        end
        if viewSwitch.Layout then viewSwitch:Layout() end
    end
    content:HookScript("OnSizeChanged", placeTop)
    placeTop()
    Roster.viewSwitch = viewSwitch

    -- list and armory share the page: a click on a member opens the armory, Back returns
    local listFrame = CreateFrame("Frame", nil, content)
    listFrame:SetPoint("TOPLEFT", 0, -72)
    listFrame:SetPoint("BOTTOMRIGHT")
    local topParts = { online, mains, missing, filterBtn, summary, viewSwitch }
    local armoryHost = CreateFrame("Frame", nil, content)
    armoryHost:SetAllPoints()
    ns.Armory.Build(armoryHost)
    local function showList(on)
        listFrame:SetShown(on)
        for _, part in ipairs(topParts) do part:SetShown(on) end
        armoryHost:SetShown(not on)
    end
    armoryHost:Hide()

    local function profIcons(r)
        local parts = {}
        for _, p in ipairs(r.profs) do
            local pk = ns.Crafts and ns.Crafts.ProfKey(p.n)
            local info = pk and ns.Crafts.ProfInfo(pk)
            if info and pk ~= "cooking" and pk ~= "firstaid" and pk ~= "fishing" then
                parts[#parts + 1] = ("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(info.icon, Theme.HexColor("textDim", p.s or "?"))
            end
        end
        return table.concat(parts, "    ")
    end
    -- which data we have: gear · talents · professions
    local function dataDots(r)
        local m = r.m or {}
        local have = { r.gear ~= nil, (m.tp or (m.insp and m.insp.sp)) ~= nil, (m.pr and #m.pr > 0) or false }
        local out = {}
        for i, h in ipairs(have) do out[i] = h and UI.Glyph("dot", "good", 9) or UI.Glyph("ring", "borderDim", 9) end
        return table.concat(out, " ")
    end

    list = UI.List(listFrame, {
        sortKey = "rank",
        rowHeight = 26,
        columns = {
            { key = "name", title = L.COL_CHARACTER, flex = 1, minWidth = 150, iconSize = 18,
              -- spec icon framed in the class color (class icon until the spec is known)
              iconSet = function(tex, r) return ns.SetSpecIcon(tex, r.class, ns.SpecPoints(r.m)) end,
              text = function(r)
                  local alt = r.main and not Names.Same(r.main, r.key)
                  local me = Names.Same(r.key, Names.Me())
                  return ns.ColorName(r.name, r.class)
                      .. (r.rankIndex == 0 and ("  " .. UI.Glyph("crown", "gold", 11)) or "")
                      .. (alt and Theme.HexColor("muted", " (" .. L.ALT .. ")") or "")
                      .. (me and ("  " .. Theme.HexColor("lapis", L.ROSTER_YOU))
                          or (Roster.IsMine(r.key, r.m) and ("  " .. Theme.HexColor("lapis", L.ROSTER_MINE)) or ""))
              end,
              sort = function(r) return r.key end },
            { key = "rank", title = L.COL_RANK, width = 100, optional = 3,
              text = function(r) return r.other and Theme.HexColor("muted", r.zone or "") or Theme.HexColor("textDim", r.rank or "") end,
              sort = function(r) return r.rankIndex or 99 end },
            { key = "spec", title = L.COL_SPEC, width = 100, optional = 4,
              text = function(r) return r.spec and Theme.HexColor("textDim", r.spec) or Theme.HexColor("muted", "–") end },
            { key = "level", title = L.COL_LEVEL, width = 44, align = "CENTER",
              text = function(r) return tostring(r.level or "") end, sort = function(r) return r.level or 0 end, defaultDesc = true },
            { key = "ilvl", title = L.COL_ILVL, width = 54, align = "CENTER",
              text = function(r) return r.ilvl and Theme.HexColor("text", ("%.1f"):format(r.ilvl)) or Theme.HexColor("muted", "–") end,
              sort = function(r) return r.ilvl or 0 end, defaultDesc = true },
            { key = "ench", title = L.COL_ENCHANTS, width = 58, align = "CENTER", optional = 2,
              text = function(r)
                  local e = r.enchants
                  if not e or e.needed == 0 then return Theme.HexColor("muted", "–") end
                  local miss = e.needed - e.done
                  return Theme.HexColor(miss == 0 and "good" or (miss <= 2 and "warn" or "bad"), e.done .. "/" .. e.needed)
              end,
              sort = function(r) return r.enchants and (r.enchants.needed - r.enchants.done) or -1 end, defaultDesc = true },
            { key = "profs", title = L.COL_PROFESSIONS, width = 150, optional = 1, text = profIcons,
              tip = function(r)
                  if #r.profs == 0 then return end
                  local lines = {}
                  for _, p in ipairs(r.profs) do lines[#lines + 1] = ("%s  %s/%s"):format(p.n, p.s or "?", p.m or "?") end
                  return L.COL_PROFESSIONS, lines
              end },
            { key = "data", title = L.COL_DATA, width = 58, align = "CENTER", optional = 5, text = dataDots,
              tip = function(r)
                  local m = r.m or {}
                  local yes, no = Theme.HexColor("good", L.YES), Theme.HexColor("muted", L.NO)
                  return L.COL_DATA, { L.GEAR .. ": " .. (r.gear and yes or no),
                      L.ARM_TALENTS .. ": " .. ((m.tp or (m.insp and m.insp.sp)) and yes or no),
                      L.COL_PROFESSIONS .. ": " .. ((m.pr and #m.pr > 0) and yes or no), " ", L.COL_DATA_TIP }
              end },
            { key = "seen", title = L.COL_LAST_SEEN, width = 86, text = lastSeen,
              sort = function(r) return r.online and -1 or (r.offline or 99999) end },
        },
        onClick = function(row, button)
            if button == "RightButton" then
                if ChatFrame_SendTell then ChatFrame_SendTell(row.name) end
                return
            end
            state.selected = row.key
            showList(false)
            ns.Armory.Open(row.key, list.rows, function() showList(true); list:Draw() end)
        end,
        onEnter = function(frame, row)
            Roster.RowTooltip(frame, row)
        end,
        isSelected = function(row) return row.key == state.selected end,
        rowMark = function(row) return Roster.IsMine(row.key, row.m) and "lapis" or nil end,
        -- the page search finds name, rank, zone, spec, note and professions (nothing is hidden)
        searchText = function(r)
            local hay = { Names.Display(r.name or r.key), r.rank or "", r.zone or (r.g and r.g.zone) or "", r.spec or "", r.g and r.g.note or "" }
            for _, p in ipairs(r.profs or {}) do hay[#hay + 1] = tostring(p.n) end
            return table.concat(hay, " ")
        end,
    })
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT")
    list:SetEmptyText(L.ROSTER_EMPTY)
    page.searchHint = L.SEARCH_ROSTER
    page.searchList = list
    -- jump to a member: back to the list (own guild), filters loosened if needed, row scrolled into view and flashed
    Roster.JumpTo = function(key)
        if not listFrame:IsShown() then showList(true) end
        if state.view and state.view ~= "own" and ns.Guild.members[key] then state.view = "own"; viewSwitch:Refresh() end
        refresh()
        local found = false
        for _, r in ipairs(list.rows) do if r.key == key then found = true end end
        if not found then
            state.online, state.mains, state.missing = false, false, false
            state.filter = { mine = false, max = false, classes = {}, ranks = {}, profs = {} }
            online:Refresh(); mains:Refresh(); missing:Refresh()
            refresh()
        end
        state.selected = key
        list:JumpTo(key)
    end
    page.Search = function(text)
        state.search = text or ""
        -- typing while an armory is open goes back to the list
        if not listFrame:IsShown() and state.search ~= "" then showList(true) end
        refresh()
        return list:ShowFirstHit(state.search)
    end
    Roster.OpenMember = function(key)
        showList(false)
        ns.Armory.Open(key, list.rows, function() showList(true); list:Draw() end)
    end

    local lastRequest = 0
    page.OnShow = function()
        if GetTime() - lastRequest > 30 then
            lastRequest = GetTime()
            ns.Guild.Request()
        end
        refresh()
    end
    tabs.Finish()
end, { section = "guild", icon = "users" })

ns.On("LG_ROSTER", function() ns.Window.Refresh("roster") end)
ns.On("LG_PROFILE", function() ns.Debounce("roster-redraw", 0.5, function() ns.Window.Refresh("roster") end) end)
ns.On("LG_ITEMS", function() ns.Window.Refresh("roster") end)
