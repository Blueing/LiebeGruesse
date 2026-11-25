-- Badges: guild moments as small achievements in three tiers (bronze, silver,
-- gold). Computed by every client from the community events, the pin board and
-- the guild feed – nothing extra is sent. Shown in the armory and on the
-- community page; a new badge of your own pops up as a notification.
local _, ns = ...
local UI, Theme, L, Names = ns.UI, ns.Theme, ns.L, ns.Names
local Badges = {}
ns.Badges = Badges

local TIER_COLORS = { "bronze", "text", "gold" }

-- stat: key in Badges.Stats; tiers: values for bronze/silver/gold; fmt: value text
Badges.LIST = {
    { id = "slayer", icon = "crown", stat = "kills", tiers = { 10, 50, 200 } },
    { id = "raider", icon = "shield", stat = "nights", tiers = { 5, 25, 100 } },
    { id = "lucky", icon = "gem", stat = "epics", tiers = { 5, 15, 40 } },
    { id = "failpull", icon = "swords", stat = "failpull", tiers = { 3, 10, 25 } },
    { id = "oops", icon = "move", stat = "mispull", tiers = { 3, 10, 25 } },
    { id = "pepega", icon = "x", stat = "death", tiers = { 5, 20, 50 } },
    { id = "gravity", icon = "minus", stat = "fall", tiers = { 3, 10, 25 } },
    { id = "coffee", icon = "timer", stat = "afk", tiers = { 5, 20, 50 } },
    { id = "kangaroo", icon = "sparkles", stat = "jumpNight", tiers = { 200, 500, 1000 } },
    { id = "moneypit", icon = "hammer", stat = "repairGold", tiers = { 100, 500, 2000 }, unit = "g" },
    { id = "marathon", icon = "timer", stat = "sessionHours", tiers = { 6, 10, 16 }, unit = "h" },
    { id = "welcome", icon = "message-circle", stat = "greet1", tiers = { 3, 10, 25 } },
    { id = "crowd", icon = "star", stat = "likes", tiers = { 5, 25, 100 } },
    { id = "quotable", icon = "newspaper", stat = "qotw", tiers = { 1, 3, 10 } },
    { id = "badluck", icon = "scale", stat = "badluck", tiers = { 3, 6, 10 } },
    { id = "ghost", icon = "x", stat = "ghostMin", tiers = { 60, 300, 1000 }, unit = " min" },
    { id = "wanted", icon = "shield", stat = "guard", tiers = { 1, 5, 15 } },
    { id = "regular", icon = "sparkles", stat = "spirit", tiers = { 5, 20, 50 } },
    { id = "flyer", icon = "arrow-left-right", stat = "taxi", tiers = { 25, 100, 300 } },
    { id = "homesick", icon = "rotate-ccw", stat = "hearth", tiers = { 25, 100, 300 } },
    { id = "junk", icon = "scale", stat = "junkGold", tiers = { 50, 250, 1000 }, unit = "g" },
    { id = "shopaholic", icon = "gem", stat = "shopGold", tiers = { 100, 500, 2000 }, unit = "g" },
    { id = "shark", icon = "hammer", stat = "ah", tiers = { 50, 250, 1000 } },
    { id = "postman", icon = "scroll-text", stat = "mail", tiers = { 25, 100, 300 } },
    { id = "interrupter", icon = "swords", stat = "kick", tiers = { 25, 100, 300 } },
    { id = "owl", icon = "star", stat = "owl", tiers = { 5, 20, 50 } },
    { id = "early", icon = "star-filled", stat = "early", tiers = { 5, 20, 50 } },
    { id = "loyal", icon = "badge-check", stat = "streak", tiers = { 7, 30, 100 } },
}

---------------------------------------------------------------------------
-- Stats per member (all time), cached until community data changes
---------------------------------------------------------------------------
local cache
local function inc(t, key, stat, n)
    if not key then return end
    local s = t[key]
    if not s then s = {}; t[key] = s end
    s[stat] = (s[stat] or 0) + (n or 1)
end
local function max(t, key, stat, n)
    if not key then return end
    local s = t[key]
    if not s then s = {}; t[key] = s end
    if n > (s[stat] or 0) then s[stat] = n end
end

function Badges.Stats()
    if cache then return cache end
    local t = {}
    local C = ns.Community
    local events = C and C.Store().events or {}
    if C and C.testEvents then
        local merged = {}
        for _, e in ipairs(events) do merged[#merged + 1] = e end
        for _, e in ipairs(C.testEvents) do merged[#merged + 1] = e end
        events = merged
    end
    for _, e in ipairs(events) do
        local d = type(e.d) == "table" and e.d or {}
        local k = e.k
        if k == "failpull" or k == "mispull" or k == "death" or k == "fall" or k == "afk" or k == "greet1" then
            inc(t, e.who, k)
        elseif k == "repair" then inc(t, e.who, "repair", tonumber(d.c) or 0)
        elseif k == "session" then max(t, e.who, "session", tonumber(d.s) or 0)
        elseif k == "jump" then max(t, e.who, "jumpNight", tonumber(d.n) or 0)
        elseif k == "raidday" then inc(t, e.who, "nights"); inc(t, e.who, "kills", 3)
        elseif k == "epic" then inc(t, e.who, "epics")
        end
    end
    -- pin board: likes received, quotes of the week won
    local posts = C and C.Store().posts or {}
    local weeks = {}
    for _, p in ipairs(posts) do
        local n = 0
        for _ in pairs(p.likes or {}) do n = n + 1 end
        if n > 0 then inc(t, p.a, "likes", n) end
        if C then weeks[C.Week(p.t)] = true end
    end
    if C then
        local current = C.Week()
        for w in pairs(weeks) do
            if w < current then
                local best = C.QuoteOfWeek(w)
                if best then inc(t, best.a, "qotw") end
            end
        end
    end
    -- guild feed: raid boss kills, raid nights, epics in instances
    local nights = {}
    for _, e in ipairs(ns.Database.Guild().feed or {}) do
        local d = type(e) == "table" and type(e.d) == "table" and e.d
        if d then
            if e.k == "boss" and d.r and type(d.g) == "table" then
                local day = date("%Y%m%d", e.t or 0)
                for _, key in ipairs(d.g) do
                    inc(t, key, "kills")
                    nights[key] = nights[key] or {}
                    if not nights[key][day] then nights[key][day] = true; inc(t, key, "nights") end
                end
            elseif e.k == "loot" and (d.q or 0) >= 4 and d.ins then
                inc(t, e.a, "epics")
            end
        end
    end
    -- daily counters (all time) and the longest raid-night streak without an epic
    if C then
        for who, d in pairs(C.DailyTotals(0, events)) do
            for k, v in pairs(d) do
                if k == "streak" then max(t, who, k, v) else inc(t, who, k, v) end
            end
        end
        for who, n in pairs(C.BadLuck(0)) do max(t, who, "badluck", n) end
    end
    for _, s in pairs(t) do
        s.ghostMin = math.floor((s.ghost or 0) / 60)
        s.junkGold = math.floor((s.junk or 0) / 10000)
        s.shopGold = math.floor((s.shop or 0) / 10000)
        s.repairGold = math.floor((s.repair or 0) / 10000)
        s.sessionHours = math.floor((s.session or 0) / 3600)
    end
    cache = t
    return t
end

local function invalidate() cache = nil end
ns.On("LG_COMMUNITY", invalidate)
ns.On("LG_PROFILE", invalidate)

-- tier reached (0–3) and the value
function Badges.Tier(def, stats)
    local v = stats and stats[def.stat] or 0
    local tier = 0
    for i, need in ipairs(def.tiers) do if v >= need then tier = i end end
    return tier, v
end

-- earned badges of one member: { { def, tier, value } }, best first
function Badges.Of(key)
    local stats
    for k, s in pairs(Badges.Stats()) do if Names.Same(k, key) then stats = s; break end end
    local list = {}
    for _, def in ipairs(Badges.LIST) do
        local tier, v = Badges.Tier(def, stats)
        list[#list + 1] = { def = def, tier = tier, value = v }
    end
    return list
end

local function valueText(def, v) return tostring(v) .. (def.unit or "") end

function Badges.Name(def) return L["BADGE_" .. def.id:upper()] or def.id end

-- tooltip lines for one badge (with progress)
function Badges.TipLines(def, tier, v)
    local lines = { L["BADGE_" .. def.id:upper() .. "_TIP"] or "" , " " }
    for i, need in ipairs(def.tiers) do
        local got = tier >= i
        lines[#lines + 1] = Theme.HexColor(got and TIER_COLORS[i] or "muted",
            L["BADGE_TIER" .. i] .. ": " .. valueText(def, need)) .. (got and ("  " .. UI.Glyph("badge-check", TIER_COLORS[i], 11)) or "")
    end
    if tier < 3 then lines[#lines + 1] = Theme.HexColor("muted", L.BADGE_NOW:format(valueText(def, v))) end
    return lines
end

---------------------------------------------------------------------------
-- Armory card: earned badges as icons in tier colours (hover for details)
---------------------------------------------------------------------------
local ICON = 30
function Badges.FillCard(c, key, width)
    c.icons = c.icons or {}
    local earned = {}
    for _, b in ipairs(Badges.Of(key)) do if b.tier > 0 then earned[#earned + 1] = b end end
    table.sort(earned, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return a.def.id < b.def.id end)
    local perRow = math.max(1, math.floor((width - 24 + 8) / (ICON + 8)))
    for i, b in ipairs(earned) do
        local f = c.icons[i]
        if not f then
            f = CreateFrame("Frame", nil, c, "BackdropTemplate")
            f:SetSize(ICON, ICON)
            UI.Skin(f, "input", "bronze")
            f.icon = UI.Icon(f, "star", 16, "bronze")
            f.icon:SetPoint("CENTER")
            f:EnableMouse(true)
            f:SetScript("OnEnter", function(self)
                UI.Tooltip(self, Badges.Name(self.b.def) .. "  " .. Theme.HexColor(TIER_COLORS[self.b.tier], L["BADGE_TIER" .. self.b.tier]),
                    Badges.TipLines(self.b.def, self.b.tier, self.b.value))
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            c.icons[i] = f
        end
        f.b = b
        f.icon:SetTexture(Theme.Icon(b.def.icon))
        f.icon:SetVertexColor(Theme.Color(TIER_COLORS[b.tier]))
        f:SetBackdropBorderColor(Theme.Color(TIER_COLORS[b.tier]))
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 12 + ((i - 1) % perRow) * (ICON + 8), -38 - math.floor((i - 1) / perRow) * (ICON + 8))
        f:Show()
    end
    for i = #earned + 1, #c.icons do c.icons[i]:Hide() end
    c.right:SetText(#earned > 0 and ("%d/%d"):format(#earned, #Badges.LIST) or "")
    c.empty = c.empty or UI.Text(c, 12, "muted")
    c.empty:ClearAllPoints()
    c.empty:SetPoint("TOPLEFT", 12, -38)
    c.empty:SetText(#earned == 0 and L.BADGE_NONE or "")
    local rows = #earned > 0 and math.ceil(#earned / perRow) or 0
    local h = 38 + (rows > 0 and rows * (ICON + 8) or 22) + 8
    c:SetHeight(h)
    return h
end

---------------------------------------------------------------------------
-- Community tab: every badge, how to get it, who has which tier
---------------------------------------------------------------------------
function Badges.BuildPage(parent)
    local f = CreateFrame("Frame", nil, parent)
    local list = UI.List(f, {
        sortKey = "gold", sortDesc = true,
        columns = {
            { key = "name", title = L.BADGE_COL, width = 190,
              text = function(r) return Badges.Name(r.def) end,
              icon = function(r) return Theme.Icon(r.def.icon) end,
              sort = function(r) return Badges.Name(r.def) end },
            { key = "how", title = L.BADGE_COL_HOW, flex = true, minWidth = 160, optional = 1,
              text = function(r) return Theme.HexColor("muted", L["BADGE_" .. r.def.id:upper() .. "_TIP"] or "") end },
            { key = "gold", title = L.BADGE_TIER3, width = 170, defaultDesc = true,
              text = function(r) return r.text[3] end, sort = function(r) return r.count[3] * 10000 + r.count[2] * 100 + r.count[1] end },
            { key = "silver", title = L.BADGE_TIER2, width = 170, optional = 2,
              text = function(r) return r.text[2] end, sort = function(r) return r.count[2] end },
            { key = "bronze", title = L.BADGE_TIER1, width = 170, optional = 3,
              text = function(r) return r.text[1] end, sort = function(r) return r.count[1] end },
        },
        onEnter = function(frame, r)
            UI.Tooltip(frame, Badges.Name(r.def), Badges.TipLines(r.def, 0, 0))
        end,
        -- all holders count for the search, not only the three shown
        searchText = function(r) return r.hay end,
    })
    list:SetAllPoints()
    f.list = list
    function f.Refresh()
        local stats = Badges.Stats()
        local rows = {}
        for _, def in ipairs(Badges.LIST) do
            local holders = { {}, {}, {} }
            for key, s in pairs(stats) do
                local tier = Badges.Tier(def, s)
                if tier > 0 then holders[tier][#holders[tier] + 1] = key end
            end
            local text, count = {}, {}
            for i = 1, 3 do
                table.sort(holders[i])
                count[i] = #holders[i]
                local names = {}
                for n, key in ipairs(holders[i]) do
                    if n > 3 then names[#names + 1] = Theme.HexColor("muted", "+" .. (#holders[i] - 3)); break end
                    local g = ns.Guild.Find(key)
                    names[#names + 1] = ns.ColorName(g and g.name or Names.Display(key), g and g.class)
                end
                text[i] = #names > 0 and table.concat(names, ", ") or Theme.HexColor("muted", "–")
            end
            local hay = Badges.Name(def) .. " " .. (L["BADGE_" .. def.id:upper() .. "_TIP"] or "")
            for i = 1, 3 do for _, key in ipairs(holders[i]) do hay = hay .. " " .. Names.Display(key) end end
            rows[#rows + 1] = { key = def.id, def = def, text = text, count = count, hay = hay }
        end
        list:SetRows(rows)
    end
    return f
end

---------------------------------------------------------------------------
-- A new badge (or tier) of your own: notification. The first run only
-- remembers what you already have.
---------------------------------------------------------------------------
function Badges.Check(quiet)
    if ns.Database.Settings().modules.community == false then return end
    local char = ns.Database.Char()
    local seen = char.badges
    local first = seen == nil
    seen = seen or {}
    for _, b in ipairs(Badges.Of(Names.Me())) do
        if b.tier > (seen[b.def.id] or 0) then
            if not first and not quiet then
                UI.Toast(L.BADGE_NEW, Badges.Name(b.def) .. "  " .. Theme.HexColor(TIER_COLORS[b.tier], L["BADGE_TIER" .. b.tier]))
                ns.Sound("milestone")
            end
            seen[b.def.id] = b.tier
        end
    end
    char.badges = seen
end
ns.On("LG_COMMUNITY", function()
    if ns.Community and ns.Community.testEvents then return end
    ns.Debounce("badges-check", 3, Badges.Check)
end)
ns.On("LG_READY", function() ns.After(70, Badges.Check) end)

-- /lg test badge: the notification for a sample badge (nothing stored)
function Badges.Test()
    UI.Toast(L.TEST_TAG .. " " .. L.BADGE_NEW, Badges.Name(Badges.LIST[9]) .. "  " .. Theme.HexColor("gold", L.BADGE_TIER3))
end
