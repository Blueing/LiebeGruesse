-- Life statistics window: your own sheet or any
-- player you target/inspect. Opens beside the Inspect window if wanted.
local _, ns = ...
local Life = ns.LifeStats
local UI, Theme, L, Names = ns.UI, ns.Theme, ns.L, ns.Names
local Win = {}
ns.LifeWindow = Win

local W, H = 1000, 700
local MIN_W, MIN_H = 700, 520
local ROW = 21
local frame
local state = { key = nil, tab = "overview" }

local function settings()
    local s = ns.Database.Settings()
    s.life = s.life or {}
    if s.life.autoInspect == nil then s.life.autoInspect = true end
    if s.life.compare == nil then s.life.compare = false end
    if s.life.filter == nil then s.life.filter = "guild" end
    return s.life
end
Win.Settings = settings

local function val(sheet, key) return sheet and Life.Value(sheet, key) end
local function num(sheet, key) local v = val(sheet, key); return type(v) == "number" and v or nil end

local function gainOf(key, sheet, base)
    local a, b = num(sheet, key), num(base, key)
    if not a or not b or a <= b then return nil end
    return a - b
end

local function delta(key, sheet, base)
    local d = gainOf(key, sheet, base)
    if not d then return "" end
    return Theme.HexColor("good", Life.Gain(key, d))
end

-- your own values are shown in your class colour
local function myHex()
    local _, class = ns.Call(UnitClass, "player")
    return ns.ClassHex(class)
end
local function mineText(text)
    if not text or text == "" then return "" end
    return ("|c%s%s|r"):format(myHex(), (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end
Win.MineText = mineText

-- exact figures for the hover tooltip
local function exactTip(label, key, sheet, base, mine)
    local lines = { title = label }
    local v = val(sheet, key)
    lines[#lines + 1] = { L.LIFE_VALUE, Life.Format(key, v) }
    local d = gainOf(key, sheet, base)
    if d then
        local f = Life.BY_KEY[key]
        lines[#lines + 1] = { L.LIFE_GAIN, Theme.HexColor("good", "+" .. (f and f.kind == "money" and ns.Professions.Money(d) or Life.Format(key, d))) }
    end
    if mine then lines[#lines + 1] = { L.LIFE_ME, mineText(Life.Format(key, val(mine, key))) } end
    return lines
end

local function showTip(owner, tip)
    if not tip then return end
    ns.TipOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tip.title or "", 1, 0.82, 0)
    for _, l in ipairs(tip) do GameTooltip:AddDoubleLine(l[1], l[2], 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:Show()
end

-- columns for a given width: 3 / 2 / 1
local function columnsFor(w) return w >= 860 and 3 or (w >= 540 and 2 or 1) end

-- puts cards into the shortest column; cards are filled after their width is known
local function flow(cards, w, fillers, maxCols)
    local cols = math.min(columnsFor(w), maxCols or 3)
    local gap = 24
    local cw = (w - (cols - 1) * gap) / cols
    local heights = {}
    for i = 1, cols do heights[i] = 0 end
    for i, card in ipairs(cards) do
        card:SetWidth(cw)
        if fillers and fillers[i] then fillers[i]() end
        local col = 1
        for c = 2, cols do if heights[c] < heights[col] then col = c end end
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", (col - 1) * (cw + gap), -heights[col])
        card:Show()
        heights[col] = heights[col] + card:GetHeight() + 14
    end
    local bottom = 0
    for _, h in ipairs(heights) do bottom = math.max(bottom, h) end
    return bottom
end

---------------------------------------------------------------------------
-- Cards with rows (label · gain · value · mine)
---------------------------------------------------------------------------
local function newCard(parent, icon, title)
    local c = CreateFrame("Frame", nil, parent)
    c.icon = UI.Icon(c, icon, 16, "accent")
    c.icon:SetPoint("TOPLEFT", 2, -4)
    c.title = UI.Text(c, 14, "text")
    c.title:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
    c.title:SetText(ns.Upper(title))
    c.line = UI.Fill(c, "bronzeDim", "ARTWORK")
    c.line:SetHeight(1)
    c.line:SetPoint("TOPLEFT", 0, -26); c.line:SetPoint("TOPRIGHT", 0, -26)
    c.heads = UI.Text(c, 11, "muted", "RIGHT")
    c.heads:SetPoint("RIGHT", c, "TOPRIGHT", -8, -14)
    c.rows = {}
    function c:Row(i)
        local r = self.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, self)
        r:SetHeight(ROW)
        r.bg = UI.Fill(r, (i % 2 == 1) and "row" or "rowAlt", "BACKGROUND")
        r.bg:SetAllPoints()
        r.label = UI.Text(r, 13, "textDim")
        r.label:SetPoint("LEFT", 8, 0)
        r.value = UI.Text(r, 13, "text", "RIGHT")
        r.value:SetPoint("RIGHT", -8, 0)
        r.gain = UI.Text(r, 12, "good", "RIGHT")
        r.gain:SetPoint("RIGHT", r.value, "LEFT", -10, 0)
        r.mine = UI.Text(r, 12, "accent", "RIGHT")
        r.mine:SetPoint("RIGHT", r.gain, "LEFT", -8, 0)
        r.label:SetPoint("RIGHT", r.mine, "LEFT", -6, 0)
        r.bar = UI.Fill(r, "accent", "ARTWORK")
        r.bar:SetHeight(3)
        r.bar:SetPoint("BOTTOMLEFT", 8, 1)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(row) showTip(row, row.tip) end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.rows[i] = r
        return r
    end
    -- rows = { { label, value text, gain text, mine text, bar fraction, tip, header = bool } }
    function c:Fill(rows, heads)
        self.heads:SetText(heads or "")
        for i, data in ipairs(rows) do
            local r = self:Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -30 - (i - 1) * ROW)
            r:SetPoint("TOPRIGHT", 0, -30 - (i - 1) * ROW)
            r.label:SetText(data.header and Theme.HexColor("gold", data[1]) or data[1])
            r.value:SetText(data[2] or (data.header and "" or Theme.HexColor("muted", "–")))
            r.gain:SetText(data[3] or "")
            r.mine:SetText(mineText(data[4]))
            r.tip = data[6]
            if data[5] then
                r.bar:SetWidth(math.max(1, ((self:GetWidth() or 200) - 16) * math.min(1, data[5])))
                r.bar:Show()
            else
                r.bar:Hide()
            end
            r:Show()
        end
        for i = #rows + 1, #self.rows do self.rows[i]:Hide() end
        self:SetHeight(34 + #rows * ROW)
    end
    return c
end

-- standard rows for statistic keys
local function statRows(keys, sheet, base, mine, opts)
    local rows = {}
    local compact = mine ~= nil
    for _, key in ipairs(keys) do
        local f = Life.BY_KEY[key]
        local v = val(sheet, key)
        if not (opts and opts.hideEmpty and (v == nil or v == 0)) and not (f.ownOnly and v == nil) then
            rows[#rows + 1] = { f.label, v ~= nil and Life.Compact(key, v, compact) or nil, delta(key, sheet, base),
                mine and Life.Compact(key, val(mine, key), compact) or nil, nil, exactTip(f.label, key, sheet, base, mine) }
        end
    end
    return rows
end

local function heads(mine, base)
    local parts = {}
    if mine then parts[#parts + 1] = mineText(L.LIFE_ME) end
    if base then parts[#parts + 1] = Theme.HexColor("good", L.LIFE_GAIN_SHORT) end
    parts[#parts + 1] = L.LIFE_VALUE
    return table.concat(parts, "   ")
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local SKILLS = { "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism", "leatherworking", "mining", "skinning",
    "tailoring", "firstAid", "cooking", "fishing" }

local function skillRows(sheet, base, mine)
    local rows = {}
    local list = {}
    for _, key in ipairs(SKILLS) do
        local v = num(sheet, key)
        if v and v > 0 then list[#list + 1] = { key = key, v = v } end
    end
    table.sort(list, function(a, b) return a.v > b.v end)
    for _, e in ipairs(list) do
        local cap = e.v > 300 and 375 or 300
        rows[#rows + 1] = { Life.BY_KEY[e.key].label, ("%d / %d"):format(e.v, cap), delta(e.key, sheet, base),
            mine and num(mine, e.key) and tostring(num(mine, e.key)) or nil, e.v / cap,
            exactTip(Life.BY_KEY[e.key].label, e.key, sheet, base, mine) }
    end
    if #rows == 0 then rows[1] = { Theme.HexColor("muted", L.LIFE_NO_SKILLS) } end
    return rows
end

local TABS = {}

TABS.overview = function(body, sheet, base, mine)
    local w = body:GetWidth() or (W - 40)
    body.cards = body.cards or {
        combat = newCard(body, "swords", L.LIFE_SEC_COMBAT), adventure = newCard(body, "book-open", L.LIFE_SEC_ADVENTURE),
        pvp = newCard(body, "shield", L.LIFE_SEC_PVP), prof = newCard(body, "scroll-text", L.LIFE_SEC_PROF),
        wealth = newCard(body, "gem", L.LIFE_SEC_WEALTH), consumed = newCard(body, "sparkles", L.LIFE_SEC_CONSUMED),
    }
    local c, h = body.cards, heads(mine, base)
    local bottom = flow({ c.combat, c.adventure, c.pvp, c.prof, c.wealth, c.consumed }, w, {
        function() c.combat:Fill(statRows({ "damage", "healing", "bigHit", "bigHitTaken", "bigHeal", "killingBlows" }, sheet, base, mine), h) end,
        function() c.adventure:Fill(statRows({ "dungeons", "raids40", "flights", "hearth", "summons", "factions" }, sheet, base, mine), h) end,
        function() c.pvp:Fill(statRows({ "honorKills", "bgWon", "duelsWon", "duelsLost", "factionDeaths", "wsgFlags" }, sheet, base, mine), h) end,
        function() c.prof:Fill(skillRows(sheet, base, mine), h) end,
        function() c.wealth:Fill(statRows({ "acquired", "looted", "questGold", "vendors", "auctions", "travel" }, sheet, base, mine), h) end,
        function() c.consumed:Fill(statRows({ "food", "drinks", "healthPotions", "bandages", "epics", "mounts" }, sheet, base, mine), h) end,
    })
    body.footer = body.footer or UI.Text(body, 12, "muted", "CENTER")
    local fun = {}
    for _, k in ipairs({ "hugs", "waves", "cheers", "lols", "facepalms", "camped", "hogger" }) do
        local v = num(sheet, k)
        if v and v > 0 then fun[#fun + 1] = Life.Format(k, v) .. " " .. Life.BY_KEY[k].label end
    end
    body.footer:ClearAllPoints()
    body.footer:SetPoint("TOP", body, "TOP", 0, -bottom - 4)
    body.footer:SetWidth(w)
    body.footer:SetText(table.concat(fun, "  ·  "))
    return bottom + 30
end

-- one row per dungeon: gold mark, name, ×count (your count in your class colour)
local DROW = 24
local function dungeonRow(body, i)
    body.drows = body.drows or {}
    local r = body.drows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, body)
    r:SetHeight(DROW)
    local function tex(layer)
        local t = r:CreateTexture(nil, layer)
        t:SetTexture(Theme.WHITE)
        t:SetVertexColor(0, 0, 0, 0)
        return t
    end
    r.stripe = tex("BACKGROUND"); r.stripe:SetAllPoints()
    r.hover = tex("BORDER"); r.hover:SetAllPoints()
    r.mark = tex("ARTWORK"); r.mark:SetSize(5, 5); r.mark:SetPoint("LEFT", 8, 0)
    function r:Mark(alpha) local cr, cg, cb = Theme.Color("gold"); self.mark:SetVertexColor(cr, cg, cb, alpha) end
    r.value = UI.Text(r, 13, "text", "RIGHT"); r.value:SetPoint("RIGHT", -8, 0)
    r.you = UI.Text(r, 13, "text", "RIGHT"); r.you:SetPoint("RIGHT", -74, 0); r.you:SetWidth(40)
    r.label = UI.Text(r, 13, "text"); r.label:SetPoint("LEFT", 20, 0); r.label:SetPoint("RIGHT", r.you, "LEFT", -6, 0)
    r.label:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) local cr, cg, cb = Theme.Color("gold"); self.hover:SetVertexColor(cr, cg, cb, 0.09); showTip(self, self.tip) end)
    r:SetScript("OnLeave", function(self) self.hover:SetVertexColor(0, 0, 0, 0); GameTooltip:Hide() end)
    body.drows[i] = r
    return r
end

local function dungeonHeading(body, key, icon, text)
    body.dheads = body.dheads or {}
    local h = body.dheads[key]
    if not h then
        h = CreateFrame("Frame", nil, body)
        h:SetHeight(28)
        h.icon = UI.Icon(h, icon, 16, "accent"); h.icon:SetPoint("LEFT", 2, 0)
        h.text = UI.Text(h, 15, "gold"); h.text:SetPoint("LEFT", h.icon, "RIGHT", 8, 0)
        h.line = UI.Fill(h, "borderDim", "ARTWORK"); h.line:SetHeight(1)
        h.line:SetPoint("BOTTOMLEFT"); h.line:SetPoint("BOTTOMRIGHT")
        h.cols = UI.Text(h, 11, "muted", "RIGHT"); h.cols:SetPoint("RIGHT", -8, 0)
        body.dheads[key] = h
    end
    h.text:SetText(text)
    return h
end

TABS.dungeons = function(body, sheet, base, mine)
    local w = body:GetWidth() or (W - 40)
    local wide = w >= 860
    local gap = 24
    local colW = wide and (w - 2 * gap) / 3 or (w - gap) / 2
    local classic, forever, raids = {}, {}, {}
    for _, d in ipairs(Life.DUNGEONS) do
        if d.raid then raids[#raids + 1] = d elseif d.forever then forever[#forever + 1] = d else classic[#classic + 1] = d end
    end
    local n = 0
    local function paint(d, x, y)
        n = n + 1
        local r = dungeonRow(body, n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", x, -y)
        r:SetWidth(colW)
        r.stripe:SetVertexColor(1, 1, 1, n % 2 == 0 and 0 or 0.035)
        local name = Life.DungeonName(d)
        r.label:SetText(name)
        r.you:SetShown(mine ~= nil)
        if not d[2] then
            r.label:SetTextColor(Theme.Color("muted"))
            r:Mark(0.15)
            r.value:SetText(Theme.HexColor("muted", L.LIFE_NOT_TRACKED))
            r.you:SetText("")
            r.tip = { title = name, { L.LIFE_NOT_TRACKED_TIP, "" } }
        else
            local c = Life.DungeonCount(sheet, d)
            local done = c and c > 0
            r.label:SetTextColor(Theme.Color(done and "text" or "muted"))
            r:Mark(done and 1 or 0.2)
            r.value:SetText(done and ((mine and "" or "×") .. Life.Short(c)) or Theme.HexColor("muted", "–"))
            local m = mine and Life.DungeonCount(mine, d)
            r.you:SetText(mine and mineText(m and m > 0 and Life.Short(m) or "–") or "")
            local bosses = {}
            for _, key in ipairs(d[2]) do bosses[#bosses + 1] = Life.BY_KEY[key].label end
            local b = base and Life.DungeonCount(base, d)
            r.tip = { title = name, { Names.Display(sheet.n or ""), done and L.LIFE_N_CLEARS:format(c) or L.LIFE_NOT_YET } }
            if c and b and c > b then r.tip[#r.tip + 1] = { L.LIFE_GAIN, Theme.HexColor("good", "+" .. (c - b)) } end
            if mine then r.tip[#r.tip + 1] = { L.LIFE_ME, mineText(m and m > 0 and L.LIFE_N_CLEARS:format(m) or L.LIFE_NOT_YET) } end
            r.tip[#r.tip + 1] = { L.LIFE_COUNTED_AS:format(table.concat(bosses, " / ")), "" }
        end
        r:Show()
    end
    local function heading(key, icon, text, x, y, width)
        local h = dungeonHeading(body, key, icon, text)
        h.cols:SetText((mine and (mineText(L.LIFE_ME) .. "      ") or "") .. L.LIFE_CLEARS)
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", x, -y); h:SetWidth(width); h:Show()
        return y + 32
    end
    local cleared, tracked = Life.DungeonsCleared(sheet)
    local bottom
    -- classic dungeons: two columns of ten
    local top = heading("classic", "shield", L.LIFE_CLASSIC .. Theme.HexColor("muted", ("  %d / %d"):format(cleared, tracked)), 0, 0, colW * 2 + gap)
    local half = math.ceil(#classic / 2)
    for i, d in ipairs(classic) do
        local col = i <= half and 0 or 1
        paint(d, col * (colW + gap), top + ((i - 1) % half) * DROW)
    end
    bottom = top + half * DROW
    -- Forever's dungeons, then raids: third column when wide, below otherwise
    local fx, fy = wide and 2 * (colW + gap) or 0, wide and 0 or bottom + 16
    local y = heading("forever", "sparkles", L.LIFE_NEW_FOREVER, fx, fy, colW)
    for _, d in ipairs(forever) do paint(d, fx, y); y = y + DROW end
    local rx, ry = fx, y + 8
    if not wide then rx, ry = colW + gap, fy end
    local y2 = heading("raids", "crown", L.LIFE_RAIDS, rx, ry, colW)
    for _, d in ipairs(raids) do paint(d, rx, y2); y2 = y2 + DROW end
    for k = n + 1, #(body.drows or {}) do body.drows[k]:Hide() end
    return math.max(bottom, y, y2) + 10
end

TABS.pvp = function(body, sheet, base, mine)
    local w = body:GetWidth() or (W - 40)
    body.cards = body.cards or {
        total = newCard(body, "shield", L.LIFE_SEC_PVP), world = newCard(body, "swords", L.LIFE_SEC_WORLD),
        wsg = newCard(body, "crown", L.LIFE_BG_WSG), ab = newCard(body, "crown", L.LIFE_BG_AB),
        av = newCard(body, "crown", L.LIFE_BG_AV), ds = newCard(body, "crown", L.LIFE_BG_DS),
    }
    local c, h = body.cards, heads(mine, base)
    local function filler(card, keys) return function() card:Fill(statRows(keys, sheet, base, mine), h) end end
    return flow({ c.total, c.world, c.av, c.wsg, c.ab, c.ds }, w, {
        filler(c.total, { "honorKills", "killingBlows", "bgPlayed", "bgWon", "duelsWon", "duelsLost", "pvpDeaths", "factionDeaths", "bgPlayedMost", "bgWonMost" }),
        filler(c.world, { "worldHonorKills", "worldKillingBlows", "bgHonorKills", "bgKillingBlows", "continentHonor", "continentBlows" }),
        filler(c.av, { "avBattles", "avWins", "avTowersTaken", "avTowersHeld", "avHonor", "avBlows", "avDeaths" }),
        filler(c.wsg, { "wsgBattles", "wsgWins", "wsgFlags", "wsgReturns", "wsgHonor", "wsgBlows", "wsgDeaths" }),
        filler(c.ab, { "abBattles", "abWins", "abAssaulted", "abDefended", "abHonor", "abBlows", "abDeaths" }),
        filler(c.ds, { "dsBattles", "dsWins", "dsAssaulted", "dsDefended", "dsFlags", "dsHonor", "dsBlows", "dsDeaths" }),
    })
end

TABS.skills = function(body, sheet, base, mine)
    local w = body:GetWidth() or (W - 40)
    body.cards = body.cards or { skills = newCard(body, "scroll-text", L.LIFE_SEC_PROF), recipes = newCard(body, "book-open", L.LIFE_SEC_RECIPES),
        more = newCard(body, "sparkles", L.LIFE_SEC_MORE) }
    local c, h = body.cards, heads(mine, base)
    return flow({ c.skills, c.recipes, c.more }, w, {
        function() c.skills:Fill(skillRows(sheet, base, mine), h) end,
        function() c.recipes:Fill(statRows({ "alchemyRecipes", "blacksmithingPlans", "enchantingFormulae", "engineeringSchematics", "leatherworkingPatterns",
            "tailoringPatterns", "smeltingRecipes", "cookingRecipes", "firstAidManuals" }, sheet, base, mine, { hideEmpty = true }), h) end,
        function() c.more:Fill(statRows({ "professionsLearned", "professionsMaxed", "secondaryMaxed", "weaponsMaxed", "fishCaught", "allCaught",
            "cookingDailies", "fishingDailies", "disenchanted", "disenchantMats" }, sheet, base, mine), h) end,
    }) + 10
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function sumOf(sheet, ...)
    local total, any = 0, false
    for _, k in ipairs({ ... }) do
        local v = num(sheet, k)
        if v then total = total + v; any = true end
    end
    return any and total or nil
end

-- tiles of the Dungeons & Raids tab (value = function → plain number, no stat key)
local DUNGEON_TILES = {
    { key = "dungeons", icon = 134244, sub = function() return L.LIFE_SUB_5PLAYER end },
    { label = function() return L.LIFE_RAIDS_ENTERED end, icon = 134154, value = function(s) return sumOf(s, "raids10", "raids20", "raids40") end,
      sub = function() return L.LIFE_SUB_RAIDSIZES end },
    { key = "dungeonDeaths", icon = 136187, sub = function(s) local n = num(s, "deaths"); return n and L.LIFE_SUB_OF_ALL:format(Life.Format("deaths", n)) or "" end },
    { label = function() return L.LIFE_CLEARED end, icon = 132333, value = function(s) return (Life.DungeonsCleared(s)) end,
      sub = function(s) local _, t = Life.DungeonsCleared(s); return L.LIFE_SUB_TRACKED:format(t) end },
}

local TILES = {
    { key = "kills", icon = "Interface\\Icons\\Ability_DualWield", sub = function(s) return L.LIFE_SUB_CRITTERS:format(Life.Format("critters", val(s, "critters"))) end },
    { key = "quests", icon = "Interface\\Icons\\INV_Misc_Book_09", sub = function(s) return L.LIFE_SUB_ABANDONED:format(Life.Format("questsAbandoned", val(s, "questsAbandoned"))) end },
    { key = "deaths", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", sub = function(s) return L.LIFE_SUB_FALLING:format(Life.Format("falling", val(s, "falling"))) end },
    { key = "peakGold", icon = "Interface\\Icons\\INV_Misc_Coin_02", sub = function(s) return L.LIFE_SUB_EARNED:format(Life.Format("acquired", val(s, "acquired"))) end },
}

local function portrait(tex, sheet)
    local unit
    for _, u in ipairs({ "player", "target", "mouseover" }) do
        if UnitExists(u) and sheet.guid and ns.Call(UnitGUID, u) == sheet.guid then unit = u end
    end
    if not unit and sheet.own and Names.Same(Names.Key(sheet.n or ""), Names.Me()) then unit = "player" end
    if unit and SetPortraitTexture then
        SetPortraitTexture(tex, unit)
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    local coords = CLASS_ICON_TCOORDS and sheet.c and CLASS_ICON_TCOORDS[sheet.c]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(unpack(coords))
    else
        tex:SetTexture(ns.media .. "icon")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function create()
    frame = UI.Panel(UIParent, "bg", "border")
    if frame.SetClipsChildren then frame:SetClipsChildren(true) end
    local saved = settings()
    frame:SetSize(math.max(MIN_W, saved.w or W), math.max(MIN_H, saved.h or H))
    UI.Float(frame, "DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    UI.RememberPosition(frame, "lifeWindow", { "CENTER", "CENTER", 0, 0 })
    -- resizable: drag the corner; the layout follows (3 / 2 / 1 columns)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, 1800, 1300)
    elseif frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        settings().w, settings().h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
        Win.Render()
    end)
    grip:SetScript("OnEnter", function(self) UI.Tooltip(self, L.LIFE_RESIZE) end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.grip = grip
    frame:SetScript("OnSizeChanged", function()
        if Win.layoutTiles then Win.layoutTiles() end
        ns.Debounce("life-resize", 0.08, Win.Render)
    end)
    tinsert(UISpecialFrames, "LiebeGruesseLifeWindow")
    _G.LiebeGruesseLifeWindow = frame
    frame:Hide()

    -- header
    local glow = UI.Gradient(frame, "accent", 0.12, "BACKGROUND")
    glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("TOPRIGHT", -1, -1); glow:SetHeight(110)
    frame.ring = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.ring:SetTexture(Theme.Icon("portrait-ring"))
    frame.ring:SetSize(84, 84); frame.ring:SetPoint("TOPLEFT", 16, -14)
    frame.ring:SetVertexColor(Theme.Color("gold"))
    frame.portrait = frame:CreateTexture(nil, "ARTWORK")
    frame.portrait:SetSize(74, 74); frame.portrait:SetPoint("CENTER", frame.ring, "CENTER")
    frame.name = UI.Text(frame, 26, "gold")
    frame.name:SetPoint("TOPLEFT", frame.ring, "TOPRIGHT", 18, -6)
    frame.info = UI.Text(frame, 13, "textDim")
    frame.info:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -8)
    frame.updated = UI.Text(frame, 13, "muted", "RIGHT")
    frame.updated:SetPoint("TOPRIGHT", -56, -16)
    frame.since = UI.Text(frame, 13, "good", "RIGHT")
    frame.since:SetPoint("TOPRIGHT", frame.updated, "BOTTOMRIGHT", 0, -4)
    local close = UI.IconButton(frame, "x", 26, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -14)

    -- tabs and buttons
    frame.tabs = UI.SubTabs(frame, {
        { key = "overview", title = L.LIFE_T_OVERVIEW }, { key = "dungeons", title = L.LIFE_T_DUNGEONS },
        { key = "pvp", title = "PvP" }, { key = "skills", title = L.LIFE_T_SKILLS }, { key = "chars", title = L.LIFE_T_CHARS },
    }, function(key) state.tab = key; Win.Render() end)
    frame.tabs:SetPoint("TOPLEFT", 20, -112)
    frame.tabs:SetPoint("TOPRIGHT", -20, -112)
    local refresh = UI.Button(frame, L.LIFE_REFRESH, 120, 26, function() Win.Refresh() end, "rotate-ccw")
    refresh:SetPoint("TOPRIGHT", -20, -74)
    local target = UI.Button(frame, L.LIFE_TARGET, 90, 26, function() Life.Inspect("target") end)
    target:SetPoint("RIGHT", refresh, "LEFT", -8, 0)
    local me = UI.Button(frame, L.LIFE_ME, 70, 26, function() Life.Inspect("player") end)
    me:SetPoint("RIGHT", target, "LEFT", -8, 0)
    frame.status = UI.Text(frame, 12, "warn")
    frame.status:SetPoint("TOPLEFT", 22, -146)

    -- tiles (4 in a row, 2 x 2 when narrow); hover shows the exact figures
    frame.tiles = {}
    for i, def in ipairs(TILES) do
        local t = UI.Panel(frame, "panel", "borderDim")
        UI.Corners(t)
        t:SetHeight(70)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(48, 48); t.icon:SetPoint("LEFT", 11, 0)
        t.icon:SetTexture(def.icon); t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.label = UI.Text(t, 13, "gold"); t.label:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 2)
        t.label:SetText(Life.BY_KEY[def.key].label)
        t.value = UI.Text(t, 26, "text"); t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -2)
        t.gain = UI.Text(t, 13, "good"); t.gain:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 8, 3)
        t.sub = UI.Text(t, 12, "muted"); t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -2)
        t.mine = UI.Text(t, 12, "accent", "RIGHT"); t.mine:SetPoint("TOPRIGHT", 0, -2)
        t:EnableMouse(true)
        t:SetScript("OnEnter", function(self) showTip(self, self.tip) end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t.def = def
        frame.tiles[i] = t
    end
    function Win.layoutTiles()
        local fw = frame:GetWidth() or W
        local perRow = fw >= 860 and 4 or 2
        local tw = (fw - 40 - (perRow - 1) * 16) / perRow
        for i, t in ipairs(frame.tiles) do
            local col, rowN = (i - 1) % perRow, math.floor((i - 1) / perRow)
            t:ClearAllPoints()
            t:SetWidth(tw)
            t:SetPoint("TOPLEFT", 20 + col * (tw + 16), -164 - rowN * 78)
        end
        local rows = math.ceil(#frame.tiles / perRow)
        if frame.scroll then
            frame.scroll:ClearAllPoints()
            frame.scroll:SetPoint("TOPLEFT", 20, -164 - rows * 78 - 8)
            frame.scroll:SetPoint("BOTTOMRIGHT", -24, 44)
        end
    end

    -- scrollable body per tab
    local scroll, body = UI.ScrollArea(frame)
    scroll:SetPoint("TOPLEFT", 20, -250)
    scroll:SetPoint("BOTTOMRIGHT", -24, 44)
    frame.scroll, frame.bodies = scroll, {}
    frame.bodyRoot = body
    Win.layoutTiles()

    -- character list
    frame.chars = UI.List(frame, {
        sortKey = "seen", sortDesc = true,
        columns = {
            { key = "name", title = L.COL_NAME, flex = true, text = function(r) return ns.ColorName(Names.Display(r.e.n or r.key), r.e.c) end,
              sort = function(r) return r.key end },
            { key = "level", title = L.COL_LEVEL, width = 50, align = "CENTER", text = function(r) return tostring(r.e.l or "") end,
              sort = function(r) return r.e.l or 0 end, defaultDesc = true },
            { key = "guild", title = L.LIFE_GUILD, width = 180, text = function(r) return Theme.HexColor("muted", r.e.g and ("<" .. r.e.g .. ">") or "") end },
            { key = "kills", title = Life.BY_KEY.kills.label, width = 120, align = "RIGHT", text = function(r) return Life.Format("kills", val(r.last, "kills")) end,
              sort = function(r) return num(r.last, "kills") or -1 end, defaultDesc = true },
            { key = "quests", title = Life.BY_KEY.quests.label, width = 140, align = "RIGHT", text = function(r) return Life.Format("quests", val(r.last, "quests")) end,
              sort = function(r) return num(r.last, "quests") or -1 end, defaultDesc = true },
            { key = "deaths", title = Life.BY_KEY.deaths.label, width = 70, align = "RIGHT", text = function(r) return Life.Format("deaths", val(r.last, "deaths")) end,
              sort = function(r) return num(r.last, "deaths") or -1 end, defaultDesc = true },
            { key = "seen", title = L.COL_LAST_SEEN, width = 100, text = function(r) return Theme.HexColor("muted", ns.Ago(r.e.seen)) end,
              sort = function(r) return r.e.seen or 0 end, defaultDesc = true },
        },
        onClick = function(row) state.key = row.key; frame.tabs:Select("overview") end,
    })
    frame.chars:SetPoint("TOPLEFT", 20, -196)
    frame.chars:SetPoint("BOTTOMRIGHT", -20, 44)
    frame.chars:SetEmptyText(L.LIFE_NO_CHARS)
    frame.filter = UI.Segmented(frame, 330, { { value = "guild", text = L.LIFE_F_GUILD }, { value = "others", text = L.LIFE_F_OTHERS },
        { value = "all", text = L.LIFE_F_ALL } }, function() return settings().filter end, function(v) settings().filter = v; Win.Render() end)
    frame.filter:SetPoint("TOPLEFT", 20, -162)
    frame.filterHint = UI.Text(frame, 11, "muted")
    frame.filterHint:SetPoint("LEFT", frame.filter, "RIGHT", 12, 0)
    frame.filterHint:SetText(L.LIFE_SYNC_HINT)

    -- footer options
    frame.auto = UI.Check(frame, L.LIFE_AUTO_INSPECT, function() return settings().autoInspect end,
        function(v) settings().autoInspect = v end, L.LIFE_AUTO_INSPECT_TIP)
    frame.auto:SetPoint("BOTTOMLEFT", 20, 12)
    frame.compare = UI.Check(frame, L.LIFE_COMPARE, function() return settings().compare end,
        function(v) settings().compare = v; Win.Render() end)
    frame.compare:SetPoint("BOTTOMLEFT", 280, 12)
    frame.legend = UI.Text(frame, 11, "accent", "RIGHT")
    frame.legend:SetPoint("BOTTOMRIGHT", -24, 16)
    frame.tabs:Select("overview")
end

function Win.Render()
    if not frame or not frame:IsShown() then return end
    local key = state.key or Names.Me()
    local sheet = Life.Latest(key)
    local chars = state.tab == "chars"
    Win.layoutTiles()
    frame.chars:SetShown(chars)
    frame.filter:SetShown(chars); frame.filterHint:SetShown(chars)
    if chars and frame.filter.Refresh then frame.filter:Refresh() end
    frame.scroll:SetShown(not chars and sheet ~= nil)
    for _, t in ipairs(frame.tiles) do t:SetShown(not chars and sheet ~= nil) end
    frame.status:SetText(Life.status or "")
    frame.auto:Refresh(); frame.compare:Refresh()
    if not sheet then
        frame.name:SetText(L.LIFE_NONE)
        frame.info:SetText(L.LIFE_NONE_HINT)
        frame.updated:SetText(""); frame.since:SetText("")
        portrait(frame.portrait, {})
    else
        local base = Life.Baseline(key, sheet)
        local mineSheet = settings().compare and not Names.Same(key, Names.Me()) and Life.Latest(Names.Me()) or nil
        portrait(frame.portrait, sheet)
        frame.name:SetText(Names.Display(sheet.n or key))
        local class = sheet.c and ns.ClassName(sheet.c) or ""
        local parts = { ("%s %s %s %s"):format(L.LIFE_LEVEL, sheet.l or "?", sheet.r or "", class) }
        if sheet.g then parts[#parts + 1] = "<" .. sheet.g .. ">" end
        frame.info:SetText(table.concat(parts, "  ·  "))
        frame.updated:SetText(L.LIFE_UPDATED:format(ns.Ago(sheet.t)))
        frame.since:SetText(base and ("+ " .. L.LIFE_SINCE:format(ns.Ago(base.t))) or "")
        frame.legend:SetText(mineSheet and mineText(L.LIFE_COMPARE_LEGEND) or "")
        local set = state.tab == "dungeons" and DUNGEON_TILES or TILES
        for i, t in ipairs(frame.tiles) do
            local def = set[i]
            t.def = def
            t.icon:SetTexture(def.icon)
            local k = def.key
            local label = k and Life.BY_KEY[k].label or def.label()
            t.label:SetText(label)
            if def.value then
                local v, b, m = def.value(sheet), base and def.value(base), mineSheet and def.value(mineSheet)
                t.value:SetText(v and Life.Short(v) or Theme.HexColor("muted", "–"))
                t.gain:SetText(v and b and v > b and Theme.HexColor("good", "+" .. Life.Short(v - b)) or "")
                t.mine:SetText(mineSheet and mineText(L.LIFE_ME .. " " .. (m and Life.Short(m) or "–")) or "")
                local tip = { title = label, { L.LIFE_VALUE, v and tostring(v) or "–" } }
                if mineSheet then tip[#tip + 1] = { L.LIFE_ME, mineText(m and tostring(m) or "–") } end
                t.tip = tip
            else
                t.value:SetText(Life.Compact(k, val(sheet, k), mineSheet ~= nil))
                t.gain:SetText(delta(k, sheet, base))
                t.mine:SetText(mineSheet and mineText(L.LIFE_ME .. " " .. Life.Compact(k, val(mineSheet, k), true)) or "")
                t.tip = exactTip(label, k, sheet, base, mineSheet)
            end
            t.sub:SetText(def.sub(sheet) or "")
        end
        if not chars then
            for k, b in pairs(frame.bodies) do b:SetShown(k == state.tab) end
            local body = frame.bodies[state.tab]
            if not body then
                body = CreateFrame("Frame", nil, frame.bodyRoot)
                body:SetPoint("TOPLEFT"); body:SetPoint("TOPRIGHT")
                frame.bodies[state.tab] = body
            end
            body:SetWidth(frame.scroll:GetWidth() or (W - 44))
            body:Show()
            local height = TABS[state.tab](body, sheet, base, mineSheet)
            body:SetHeight(height)
            frame.bodyRoot:SetHeight(height)
            frame.scroll:SetVerticalScroll(0)
            frame.scroll.UpdateBar()
        end
    end
    if chars then
        local rows, seen = {}, {}
        local filter = settings().filter
        local function want(k)
            local inGuild = ns.Guild.Find(k) ~= nil or Names.Same(k, Names.Me())
            if filter == "guild" then return inGuild end
            if filter == "others" then return not inGuild end
            return true
        end
        for k, e in pairs(Life.Characters()) do
            seen[k] = true
            if want(k) then
                local list = e.list or {}
                rows[#rows + 1] = { key = k, e = e, last = list[#list] }
            end
        end
        -- synced guild sheets without a local visit
        for k, sheet in pairs(Life.All()) do
            if not seen[k] and want(k) then
                rows[#rows + 1] = { key = k, e = { n = sheet.n, c = sheet.c, l = sheet.l, g = sheet.g, seen = sheet.t }, last = sheet }
            end
        end
        frame.chars:SetRows(rows)
    end
end

function Win.Show(key, nearInspect)
    if not frame then create() end
    state.key = key or state.key or Names.Me()
    if nearInspect and InspectFrame and InspectFrame:IsShown() and not UI.HasWindowPosition("lifeWindow") then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", InspectFrame, "TOPRIGHT", 12, 0)
    end
    frame:Show()
    if state.tab == "chars" then frame.tabs:Select("overview") else Win.Render() end
end

function Win.Toggle()
    if frame and frame:IsShown() then frame:Hide() else Win.Show() end
end

function Win.Refresh()
    local key = state.key or Names.Me()
    if Names.Same(key, Names.Me()) then Life.Inspect("player"); return end
    -- someone else: needs them as target (or inspected)
    for _, unit in ipairs({ "target", "mouseover" }) do
        if UnitExists(unit) and Names.Same(Names.Key(Names.Unit(unit) or ""), key) then Life.Inspect(unit); return end
    end
    if InspectFrame and InspectFrame:IsShown() and InspectFrame.unit then Life.Inspect(InspectFrame.unit); return end
    Life.status = L.LIFE_TARGET_TO_REFRESH
    Win.Render()
end

ns.On("LG_LIFE_SHOW", function(_, key)
    state.key = key
    Win.Show(key, Win.fromInspect)
    Win.fromInspect = nil
end)
ns.On("LG_LIFE_STATUS", function() if frame and frame:IsShown() then frame.status:SetText(Life.status or "") end end)
ns.On("LG_LIFE", function() ns.Debounce("life-window", 0.3, Win.Render) end)

-- Inspect window: open beside it, and a "Statistics" button on it
local function hookInspect()
    if Win.inspectHooked or not InspectFrame then return end
    Win.inspectHooked = true
    InspectFrame:HookScript("OnShow", function(self)
        if not settings().autoInspect or ns.Database.Settings().modules.stats == false then return end
        if self.unit then
            Win.fromInspect = true
            Life.Inspect(self.unit)
        end
    end)
    local b = UI.Button(InspectFrame, L.LIFE_STATS_BUTTON, 90, 22, function()
        if InspectFrame.unit then Win.fromInspect = true; Life.Inspect(InspectFrame.unit) end
    end, "badge-check")
    b:SetPoint("TOPRIGHT", InspectFrame, "BOTTOMRIGHT", -18, 0)
end
ns.On("ADDON_LOADED", function(_, name) if name == "Blizzard_InspectUI" then hookInspect() end end)
ns.On("LG_READY", function()
    hookInspect()
end)
