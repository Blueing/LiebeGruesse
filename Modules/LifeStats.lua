-- Life statistics: the game's own statistics counters for your
-- character (kills, quests, deaths, gold, dungeons, PvP, professions, …),
-- shared with the guild and shown in the addon's design.
-- inspected.
local _, ns = ...
local Life = ns.NewModule("life")
ns.LifeStats = Life
local UI, Theme, L, Names, Comm = ns.UI, ns.Theme, ns.L, ns.Names, ns.Comm
local D = ns.LifeData

local FORMAT = 1

-- One flat field list: stats first, then final bosses (index = position)
local FIELDS, BY_KEY = {}, {}
for _, s in ipairs(D.stats) do
    FIELDS[#FIELDS + 1] = { key = s.key, id = s.id, label = s.en, kind = s.kind, ownOnly = s.ownOnly }
end
for _, b in ipairs(D.bosses) do
    FIELDS[#FIELDS + 1] = { key = b.key, id = b.id, label = b.label, place = b.place, boss = true, forever = b.forever }
end
for i, f in ipairs(FIELDS) do f.index = i; BY_KEY[f.key] = f end
Life.FIELDS, Life.BY_KEY = FIELDS, BY_KEY

---------------------------------------------------------------------------
-- Parsing : plain numbers, grouped numbers, coin strings
---------------------------------------------------------------------------
local function number(v)
    if ns.IsSecret(v) then return nil end
    local n = tonumber(v)
    if n and n == n and n >= 0 and n <= 9007199254740991 then return n end
end

local function integerText(text)
    text = text:gsub("\194\160", " "):gsub("\226\128\175", " "):match("^%s*(.-)%s*$")
    if text:match("^%d+$") then return number(text) end
    local first, sep, rest = text:match("^(%d%d?%d?)([,. ])(.*)$")
    if not first then return nil end
    local digits = first
    while true do
        local group = rest:sub(1, 3)
        if not group:match("^%d%d%d$") then return nil end
        digits = digits .. group
        if #rest == 3 then return number(digits) end
        if rest:sub(4, 4) ~= sep then return nil end
        rest = rest:sub(5)
    end
end

local function parseMoney(raw)
    local n = number(raw)
    if n then return n % 1 == 0 and n or nil end
    if type(raw) ~= "string" or #raw > 400 then return nil end
    local text = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local units = { gold = "g", silver = "s", copper = "c" }
    local function token(icon, atlas)
        local name = icon:lower():gsub("\\", "/")
        local metal = atlas and name:match("^:?coin%-(%a+):") or name:match("^interface/moneyframe/ui%-(%a+)icon:")
        return units[metal] and ("\001" .. units[metal] .. "\002") or "?"
    end
    text = text:gsub("|T(.-)|t", function(i) return token(i, false) end):gsub("|A(.-)|a", function(i) return token(i, true) end)
    local values = { g = 10000, s = 100, c = 1 }
    local total, last, pos, count = 0, 10001, 1, 0
    while true do
        local first, finish, unit = text:find("\001([gsc])\002", pos)
        if not first then break end
        local amount = integerText(text:sub(pos, first - 1))
        local mult = values[unit]
        if amount == nil or mult >= last or (unit ~= "g" and amount > 99) then return nil end
        total, last, pos, count = total + amount * mult, mult, finish + 1, count + 1
    end
    if count > 0 and text:sub(pos):match("^%s*$") then return number(total) end
end

-- number or display text (or nil)
local function parse(raw, field)
    if ns.IsSecret(raw) or raw == nil then return nil end
    if field.kind == "text" then
        if type(raw) == "string" and raw ~= "" and raw ~= "--" and raw ~= "-" and #raw <= 120 then
            return nil, (raw:gsub("|", "/"))
        end
        return nil
    end
    local n
    if field.kind == "money" then n = parseMoney(raw)
    else
        n = number(raw)
        if n and n % 1 ~= 0 then n = nil end
        if not n and type(raw) == "string" then n = integerText(raw) end
    end
    if n then return n end
    if raw == "--" or raw == "-" then return 0 end
end

---------------------------------------------------------------------------
-- Storage: ns.Database.Guild().life[key] = { t, n, c, l, f, v = {[i]=n}, x = {[i]=text} }
---------------------------------------------------------------------------
local function store()
    local g = ns.Database.Guild()
    g.life = g.life or {}
    return g.life
end

function Life.Sheet(key) return store()[key] end
function Life.All() return store() end

function Life.Value(sheet, key)
    local f = BY_KEY[key]
    if not sheet or not f then return nil end
    local v = sheet.v and sheet.v[f.index]
    if v ~= nil then return v end
    return sheet.x and sheet.x[f.index]
end

function Life.BossesKilled(sheet)
    local n, total = 0, 0
    for _, f in ipairs(FIELDS) do
        if f.boss then
            total = total + 1
            if (sheet and sheet.v and sheet.v[f.index] or 0) > 0 then n = n + 1 end
        end
    end
    return n, total
end

---------------------------------------------------------------------------
-- Reading your own statistics
---------------------------------------------------------------------------
function Life.Available() return type(GetStatistic) == "function" end

-- Basic facts about a unit (Forever names are "First Surname")
function Life.Subject(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local guid = ns.Call(UnitGUID, unit)
    if not guid then return nil end
    local _, class = ns.Call(UnitClass, unit)
    local race = ns.Call(UnitRace, unit)
    local faction = ns.Call(UnitFactionGroup, unit)
    local guild = ns.Call(GetGuildInfo, unit)
    return { guid = guid, n = Names.Unit(unit), c = class, r = race, fa = faction, g = guild, l = ns.Call(UnitLevel, unit) }
end

-- Reads statistics with GetStatistic (own) or GetComparisonStatistic (inspected)
function Life.Read(subject, own)
    if own == nil then own = true end
    local getter = own and GetStatistic or GetComparisonStatistic
    if type(getter) ~= "function" then return nil end
    subject = subject or Life.Subject("player")
    if not subject then return nil end
    local sheet = { t = ns.Now(), n = subject.n, c = subject.c, l = subject.l, r = subject.r, fa = subject.fa, g = subject.g,
        guid = subject.guid, own = own or nil, f = FORMAT, v = {}, x = {} }
    local found = 0
    for _, f in ipairs(FIELDS) do
        -- "most …" texts are filled from your own records; never show yours as theirs
        if own or not f.ownOnly then
            local ok, raw, skip = pcall(getter, f.id)
            if ok and not skip then
                local n, text = parse(raw, f)
                if n then sheet.v[f.index] = n; found = found + 1
                elseif text then sheet.x[f.index] = text; found = found + 1 end
            end
        end
    end
    if found == 0 then return nil end
    return sheet
end

---------------------------------------------------------------------------
-- History (account-wide, per character): one snapshot per visit, so the
-- window can show "+522 since last time"
---------------------------------------------------------------------------
local KEEP, SAME_VISIT = 12, 12 * 3600

local function histories()
    ns.db.lifeChars = ns.db.lifeChars or {}
    return ns.db.lifeChars
end

function Life.Remember(key, sheet)
    if type(key) ~= "string" or type(sheet) ~= "table" then return end
    local h = histories()
    local entry = h[key] or { first = sheet.t, list = {} }
    h[key] = entry
    local list = entry.list
    local last = list[#list]
    if last and last.t == sheet.t then return end
    if last and (sheet.t - (last.slot or last.t)) < SAME_VISIT and last.t <= sheet.t then
        sheet.slot = last.slot or last.t
        list[#list] = sheet
    else
        sheet.slot = sheet.t
        list[#list + 1] = sheet
    end
    while #list > KEEP do table.remove(list, 1) end
    entry.n, entry.c, entry.l, entry.g, entry.seen = sheet.n, sheet.c, sheet.l, sheet.g, sheet.t
end

function Life.History(key)
    local entry = histories()[key]
    return entry and entry.list or {}
end

function Life.Characters() return histories() end

-- the sheet to compare against: the visit before this one
function Life.Baseline(key, sheet)
    local list = Life.History(key)
    for i = #list, 1, -1 do
        if list[i] == sheet or list[i].t == sheet.t then return list[i - 1] end
    end
    for i = #list, 1, -1 do
        if list[i].t < sheet.t then return list[i] end
    end
end

function Life.Latest(key)
    local list = Life.History(key)
    return list[#list] or store()[key]
end

local function signature(sheet)
    local parts = {}
    for i = 1, #FIELDS do parts[#parts + 1] = tostring(sheet.v[i] or sheet.x[i] or "") end
    return table.concat(parts, ";")
end

local lastSent, lastSentAt = nil, 0
local function send(sheet, channel, target)
    if not IsInGuild() then return end
    Comm.Send("XS", { o = Names.Me(), s = sheet }, channel or "GUILD", { target = target, priority = "bulk" })
end

-- Reads and stores your sheet; shares it when it changed (at most every 10 min)
function Life.Capture(force)
    if InCombatLockdown() then return false end
    local inInstance = IsInInstance and ns.Call(IsInInstance)
    if inInstance == true and not force then return false end
    local sheet = Life.Read()
    if not sheet then return false end
    local me = Names.Me()
    store()[me] = sheet
    ns.Database.Char().life = sheet
    Life.Remember(me, sheet)
    local sig = signature(sheet)
    if sig ~= lastSent and (force or GetTime() - lastSentAt > 600) then
        lastSent, lastSentAt = sig, GetTime()
        send(sheet)
    end
    ns.Fire("LG_LIFE")
    return true
end

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------
local function accept(owner, sheet)
    if type(owner) ~= "string" or type(sheet) ~= "table" or type(sheet.v) ~= "table" or sheet.f ~= FORMAT then return end
    local old = store()[owner]
    if old and (old.t or 0) >= (sheet.t or 0) then return end
    sheet.x = type(sheet.x) == "table" and sheet.x or {}
    store()[owner] = sheet
    Life.Remember(owner, sheet)
    ns.Debounce("life-redraw", 1, function() ns.Fire("LG_LIFE") end)
end

Comm.Register("XS", function(data, sender)
    local owner = data.o or sender
    if Names.Same(owner, Names.Me()) then return end
    accept(Names.Key(owner) or owner, data.s)
end)

-- Late joiners ask for sheets newer than the newest they have; one member answers
Comm.Register("XQ", function(data, sender, _, raw)
    if not IsInGuild() then return end
    local since = tonumber(data.since) or 0
    local newer = {}
    for key, sheet in pairs(store()) do
        if (sheet.t or 0) > since and not Names.Same(key, sender) then newer[#newer + 1] = key end
    end
    if #newer == 0 then return end
    Comm.ReplyOnce("life:" .. sender, 4, 14, function()
        Comm.Send("XA", { to = sender }, "GUILD", { priority = "alert" })
        for i, key in ipairs(newer) do
            if i > 80 then break end
            Comm.Send("XS", { o = key, s = store()[key] }, "WHISPER", { target = raw, priority = "bulk" })
        end
    end)
end)
Comm.Register("XA", function(data) if data.to then Comm.Answered("life:" .. data.to) end end)

function Life:OnLogin()
    local saved = ns.Database.Char().life
    if type(saved) == "table" and saved.f == FORMAT then store()[Names.Me()] = saved end
    ns.After(15, function() Life.Capture(true) end)
    ns.After(45, function()
        if not IsInGuild() then return end
        local newest = 0
        for key, sheet in pairs(store()) do
            if not Names.Same(key, Names.Me()) then newest = math.max(newest, sheet.t or 0) end
        end
        Comm.Send("XQ", { since = newest }, "GUILD", { priority = "bulk" })
    end)
    C_Timer.NewTicker(20 * 60, function() if not InCombatLockdown() then Life.Capture(false) end end)
end
ns.On("PLAYER_LOGOUT", function() pcall(Life.Capture, false) end)

---------------------------------------------------------------------------
-- Formatting and sections
---------------------------------------------------------------------------
local function grouped(n)
    local s = string.format("%.0f", math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function Life.Format(key, value)
    local f = BY_KEY[key]
    if value == nil then return Theme.HexColor("muted", "–") end
    if type(value) == "string" then return value end
    if f and f.kind == "money" then return ns.Professions.Money(value) end
    return grouped(value)
end

-- Short numbers so labels keep their room: 79.6k, 1.28m (hover shows the exact figure)
function Life.Short(n)
    local a = math.abs(n)
    local function fmt(pattern, v) return (pattern:format(v):gsub("%.?0+$", "")) end
    if a >= 1e9 then return fmt("%.2f", n / 1e9) .. "b" end
    if a >= 1e6 then return fmt("%.2f", n / 1e6) .. "m" end
    if a >= 1e4 then return fmt("%.1f", n / 1e3) .. "k" end
    return grouped(n)
end

-- compact value: numbers from 100000 shortened (money from 100000 gold)
function Life.Compact(key, value, compact)
    local f = BY_KEY[key]
    if compact and type(value) == "number" then
        if f and f.kind == "money" then
            local gold = value / 10000
            if gold >= 100000 then return Life.Short(gold) .. "|cffffd100g|r" end
        elseif value >= 100000 then
            return Life.Short(value)
        end
    end
    return Life.Format(key, value)
end

-- gain since the last visit: short from 10000 (money: from 10000 gold)
function Life.Gain(key, d)
    local f = BY_KEY[key]
    if f and f.kind == "money" then
        local gold = d / 10000
        if gold >= 10000 then return "+" .. Life.Short(gold) .. "g" end
        return "+" .. ns.Professions.Money(d)
    end
    if d >= 10000 then return "+" .. Life.Short(d) end
    return "+" .. grouped(d)
end

-- Dungeons, one row each : the count is the final
-- boss's kills (the best where the game counts several); no keys = the game
-- has no working counter ("not tracked").
Life.DUNGEONS = {
    { "Ragefire Chasm" }, { "Wailing Caverns", { "boss15028" } }, { "Deadmines", { "boss63570" } }, { "Shadowfang Keep", { "boss1092" } },
    { "The Stockade" }, { "Blackfathom Deeps", { "boss6137" } }, { "Gnomeregan", { "boss6140" } }, { "Razorfen Kraul", { "boss6139" } },
    { "Scarlet Monastery", { "boss1093", "boss6786" } }, { "Razorfen Downs", { "boss6141" } },
    { "Uldaman", { "boss6142" } }, { "Zul'Farrak", { "boss1094" } }, { "Maraudon", { "boss6143" } }, { "Sunken Temple", { "boss6144" } },
    { "Blackrock Depths", { "boss1095" } }, { "Dire Maul", { "boss6146" } }, { "Lower Blackrock", { "boss6145" } }, { "Upper Blackrock", { "boss1096" } },
    { "Scholomance", { "boss15030" } }, { "Stratholme", { "boss1097" } },
    { "Ruins of Lordaeron", { "boss63571" }, forever = true }, { "Dalaran", { "boss63572", "boss63589" }, forever = true },
    { "Wetlands Excavation", forever = true }, { "Hall of Thanes", { "boss63573" }, forever = true },
    { "Shaper's Terrace", { "boss63574", "boss63590", "boss63592", "boss63593" }, forever = true }, { "Alcaz Prison", { "boss63575" }, forever = true },
    { "The Drowned City", forever = true }, { "Krol'dok Stronghold", forever = true },
    { "Onyxia's Lair", { "boss1098" }, raid = true }, { "Hyjal Summit", { "boss63580" }, raid = true }, { "Barrow Deeps", { "boss63581" }, raid = true },
}
function Life.DungeonName(d) return d[1] end
function Life.DungeonCount(sheet, d)
    if not d[2] or not sheet then return nil end
    local best
    for _, key in ipairs(d[2]) do
        local n = Life.Value(sheet, key)
        if type(n) == "number" and (not best or n > best) then best = n end
    end
    return best
end
function Life.DungeonsCleared(sheet)
    local cleared, tracked = 0, 0
    for _, d in ipairs(Life.DUNGEONS) do
        if d[2] and not d.raid then
            tracked = tracked + 1
            if (Life.DungeonCount(sheet, d) or 0) > 0 then cleared = cleared + 1 end
        end
    end
    return cleared, tracked
end

-- final bosses grouped: classic dungeons, raids, new Forever dungeons
local RAID_PLACES = { ["Onyxia's Lair"] = true, ["Molten Core"] = true, ["Blackwing Lair"] = true, ["Zul'Gurub"] = true,
    ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Naxxramas"] = true,
    ["Hyjal Summit"] = true, ["Barrow Deeps"] = true }
function Life.BossGroups()
    local groups = {
        { key = "dungeons", title = "Dungeons", icon = "shield", list = {} },
        { key = "raids", title = "Raids", icon = "crown", list = {} },
        { key = "forever", title = "New Forever dungeons", icon = "sparkles", list = {} },
    }
    for _, f in ipairs(FIELDS) do
        if f.boss then
            local g = RAID_PLACES[f.place] and groups[2] or (f.forever and groups[3]) or groups[1]
            table.insert(g.list, f)
        end
    end
    local out = {}
    for _, g in ipairs(groups) do if #g.list > 0 then out[#out + 1] = g end end
    return out
end

Life.SECTIONS = {
    { title = "Combat", icon = "swords",
      keys = { "kills", "critters", "killingBlows", "damage", "healing", "bigHit", "bigHitTaken", "bigHeal", "deaths", "falling", "hogger" } },
    { title = "Adventure", icon = "book-open",
      keys = { "quests", "questsAbandoned", "questsPerDay", "flights", "hearth", "summons", "factions", "camped" } },
    { title = "Dungeons & raids", icon = "crown",
      keys = { "dungeons", "raids10", "raids20", "raids40", "dungeonDeaths", "raidDeaths" } },
    { title = "Wealth", icon = "gem",
      keys = { "peakGold", "acquired", "looted", "questGold", "vendors", "auctions", "travel" } },
    { title = "Player vs. player", icon = "swords",
      keys = { "honorKills", "worldHonorKills", "bgHonorKills", "worldKillingBlows", "bgKillingBlows", "bgPlayed", "bgWon",
          "duelsWon", "duelsLost", "pvpDeaths", "factionDeaths", "bgPlayedMost", "bgWonMost" } },
    { title = "Battlegrounds", icon = "shield",
      keys = { "wsgBattles", "wsgWins", "wsgFlags", "abBattles", "abWins", "avBattles", "avWins", "dsBattles", "dsWins" } },
    { title = "Professions", icon = "scroll-text", skills = true,
      keys = { "professionsLearned", "professionsMaxed", "secondaryMaxed", "weaponsMaxed", "alchemy", "blacksmithing", "enchanting",
          "engineering", "herbalism", "leatherworking", "mining", "skinning", "tailoring", "firstAid", "cooking", "fishing",
          "fishCaught", "allCaught", "cookingDailies", "fishingDailies", "disenchanted", "disenchantMats" } },
    { title = "Recipes known", icon = "scroll-text",
      keys = { "alchemyRecipes", "blacksmithingPlans", "enchantingFormulae", "engineeringSchematics", "leatherworkingPatterns",
          "tailoringPatterns", "smeltingRecipes", "cookingRecipes", "firstAidManuals" } },
    { title = "Consumed & collected", icon = "sparkles",
      keys = { "food", "drinks", "healthPotions", "bandages", "epics", "mounts", "hugs", "waves", "cheers", "lols", "facepalms" } },
}
-- skill levels: hide professions the character does not have
local SKILL = { alchemy = 1, blacksmithing = 1, enchanting = 1, engineering = 1, herbalism = 1, leatherworking = 1, mining = 1,
    skinning = 1, tailoring = 1, firstAid = 1, cooking = 1, fishing = 1 }

---------------------------------------------------------------------------
-- Sheet view (used for yourself and for guild members)
---------------------------------------------------------------------------
local ROW = 19

local function mineColor(text)
    if not text or text == "" then return "" end
    return ns.LifeWindow and ns.LifeWindow.MineText(text) or text
end

function Life.BuildSheet(parent)
    local view = CreateFrame("Frame", nil, parent)
    local head = CreateFrame("Frame", nil, view)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(44)
    view.name = UI.Text(head, 18, "text")
    view.name:SetPoint("TOPLEFT", 2, -2)
    view.info = UI.Text(head, 11, "muted")
    view.info:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -4)
    view.compareText = UI.Text(head, 11, "accent", "RIGHT")
    view.compareText:SetPoint("TOPRIGHT", -4, -6)

    local tiles = {}
    local TILES = { { "kills", "swords" }, { "quests", "book-open" }, { "deaths", "x" }, { "peakGold", "gem" }, { "__bosses", "crown" }, { "dungeons", "shield" } }
    for i, def in ipairs(TILES) do
        local t = UI.Panel(view, "panel", "borderDim")
        UI.Corners(t)
        t.icon = UI.Icon(t, def[2], 14, "bronze"); t.icon:SetPoint("TOPLEFT", 10, -10)
        t.label = UI.Text(t, 11, "muted"); t.label:SetPoint("LEFT", t.icon, "RIGHT", 6, 0)
        t.label:SetText(ns.Upper(def[1] == "__bosses" and L.LIFE_BOSSES or BY_KEY[def[1]].label))
        t.value = UI.Text(t, 18, "text"); t.value:SetPoint("BOTTOMLEFT", 10, 8)
        t.cmp = UI.Text(t, 11, "accent", "RIGHT"); t.cmp:SetPoint("BOTTOMRIGHT", -10, 10)
        t.key = def[1]
        tiles[i] = t
    end

    local scroll, body = UI.ScrollArea(view)
    scroll:SetPoint("TOPLEFT", 0, -128)
    scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    view.cards = {}

    local function card(i)
        local c = view.cards[i]
        if c then return c end
        c = UI.Panel(body, "panel", "borderDim")
        UI.Corners(c)
        c.icon = UI.Icon(c, "sparkles", 14, "bronze"); c.icon:SetPoint("TOPLEFT", 12, -10)
        c.title = UI.Text(c, 13, "text"); c.title:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
        c.rule = UI.Fill(c, "borderDim", "ARTWORK"); c.rule:SetHeight(1)
        c.rule:SetPoint("LEFT", c.title, "RIGHT", 10, 0); c.rule:SetPoint("RIGHT", c, "TOPRIGHT", -12, -17)
        c.rows = {}
        view.cards[i] = c
        return c
    end
    local function row(c, j)
        local r = c.rows[j]
        if r then return r end
        r = CreateFrame("Frame", nil, c)
        r:SetHeight(ROW)
        r.label = UI.Text(r, 12, "textDim")
        r.label:SetPoint("LEFT", 12, 0)
        r.value = UI.Text(r, 12, "text", "RIGHT")
        r.value:SetPoint("RIGHT", -12, 0)
        r.cmp = UI.Text(r, 11, "accent", "RIGHT")
        r.cmp:SetPoint("RIGHT", r.value, "LEFT", -10, 0)
        r.label:SetPoint("RIGHT", r.cmp, "LEFT", -6, 0)
        -- page search hit
        r.hit = UI.Fill(r, "accent", "BACKGROUND")
        r.hit:SetPoint("TOPLEFT", 4, -1); r.hit:SetPoint("BOTTOMRIGHT", -4, 1)
        r.hit:SetAlpha(0.14)
        r.hit:Hide()
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.tipKey or not view.sheet then return end
            local f = BY_KEY[self.tipKey]
            ns.TipOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(f and (f.place and (f.place .. " – " .. f.label) or f.label) or self.tipKey, 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L.LIFE_VALUE, Life.Format(self.tipKey, Life.Value(view.sheet, self.tipKey)), 0.7, 0.7, 0.7, 1, 1, 1)
            if view.compare then
                GameTooltip:AddDoubleLine(L.LIFE_ME, mineColor(Life.Format(self.tipKey, Life.Value(view.compare, self.tipKey))), 0.7, 0.7, 0.7, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c.rows[j] = r
        return r
    end

    function view:Show_(sheet, compare)
        self.sheet, self.compare = sheet, compare
        local w = (scroll:GetWidth() or 800)
        if not sheet then
            self.name:SetText(L.LIFE_NONE)
            self.info:SetText(Life.Available() and L.LIFE_NONE_HINT or L.LIFE_NO_API)
            for _, t in ipairs(tiles) do t:Hide() end
            for _, c in ipairs(self.cards) do c:Hide() end
            return
        end
        self.name:SetText(ns.ColorName(Names.Display(sheet.n or "?"), sheet.c))
        self.info:SetText(("%s %s  ·  %s"):format("Level", sheet.l or "?", L.LIFE_UPDATED:format(ns.Ago(sheet.t))))
        self.compareText:SetText(compare and mineColor(L.LIFE_COMPARE_LEGEND) or "")
        -- tiles
        local tw = (w - 5 * 8) / 6
        for i, t in ipairs(tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), -52)
            t:SetSize(tw, 66)
            local v, cv
            if t.key == "__bosses" then
                local n, total = Life.BossesKilled(sheet)
                v = ("%d / %d"):format(n, total)
                if compare then cv = tostring((Life.BossesKilled(compare))) end
            else
                v = Life.Compact(t.key, Life.Value(sheet, t.key), compare ~= nil)
                if compare then cv = Life.Compact(t.key, Life.Value(compare, t.key), true) end
            end
            t.value:SetText(v)
            t.cmp:SetText(mineColor(cv))
            t:Show()
        end
        -- section cards in two columns
        local cols = w > 620 and 2 or 1
        local cw = (w - (cols - 1) * 10) / cols
        local colY = { 0, 0 }
        local n = 0
        local function place(c, height)
            local col = colY[1] <= colY[2] and 1 or 2
            if cols == 1 then col = 1 end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (col - 1) * (cw + 10), -colY[col])
            c:SetSize(cw, height)
            colY[col] = colY[col] + height + 10
            c:Show()
        end
        local q = self.query or ""
        self.hits = 0
        for _, sec in ipairs(Life.SECTIONS) do
            local lines = {}
            local whole = q ~= "" and ns.SearchMatch(sec.title, q)
            for _, key in ipairs(sec.keys) do
                local v = Life.Value(sheet, key)
                local skip = SKILL[key] and (not v or v == 0)
                if not skip and (v ~= nil or not BY_KEY[key].ownOnly) then lines[#lines + 1] = key end
            end
            if #lines > 0 then
                n = n + 1
                local c = card(n)
                c.title:SetText(ns.Highlight(ns.Upper(sec.title), q))
                c.icon:SetTexture(Theme.Icon(sec.icon))
                for j, key in ipairs(lines) do
                    local r = row(c, j)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 0, -30 - (j - 1) * ROW)
                    r:SetPoint("TOPRIGHT", 0, -30 - (j - 1) * ROW)
                    r.label:SetText(ns.Highlight(BY_KEY[key].label, q))
                    local hit = q:find("%S") and ns.SearchAny(BY_KEY[key].label, q) or false
                    r.hit:SetShown(hit)
                    if hit then self.hits = self.hits + 1 end
                    r.value:SetText(Life.Compact(key, Life.Value(sheet, key), compare ~= nil))
                    r.cmp:SetText(compare and mineColor(Life.Compact(key, Life.Value(compare, key), true)) or "")
                    r.tipKey = key
                    r:Show()
                end
                for j = #lines + 1, #c.rows do c.rows[j]:Hide() end
                place(c, 38 + #lines * ROW)
            end
        end
        -- final bosses
        n = n + 1
        local c = card(n)
        c.title:SetText(ns.Upper(L.LIFE_SEC_DUNGEONS))
        c.icon:SetTexture(Theme.Icon("crown"))
        local j = 0
        local groups = { { title = L.LIFE_CLASSIC, list = {} }, { title = L.LIFE_NEW_FOREVER, list = {} }, { title = L.LIFE_RAIDS, list = {} } }
        for _, d in ipairs(Life.DUNGEONS) do
            table.insert(groups[d.raid and 3 or (d.forever and 2 or 1)].list, d)
        end
        for _, g in ipairs(groups) do
            if #g.list > 0 then
                j = j + 1
                local h = row(c, j)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 0, -30 - (j - 1) * ROW)
                h:SetPoint("TOPRIGHT", 0, -30 - (j - 1) * ROW)
                h.label:SetText(Theme.HexColor("gold", g.title))
                h.value:SetText(Theme.HexColor("muted", L.LIFE_CLEARS))
                h.cmp:SetText(compare and mineColor(L.LIFE_ME) or "")
                h.tipKey = nil
                h.hit:Hide()
                h:Show()
                for _, d in ipairs(g.list) do
                    j = j + 1
                    local r = row(c, j)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 0, -30 - (j - 1) * ROW)
                    r:SetPoint("TOPRIGHT", 0, -30 - (j - 1) * ROW)
                    local n = Life.DungeonCount(sheet, d)
                    local name = Life.DungeonName(d)
                    r.label:SetText("   " .. ns.Highlight(Theme.HexColor(n and n > 0 and "textDim" or "muted", name), q))
                local hit = q:find("%S") and ns.SearchAny(name, q) or false
                r.hit:SetShown(hit)
                if hit then self.hits = self.hits + 1 end
                    if not d[2] then
                        r.value:SetText(Theme.HexColor("muted", L.LIFE_NOT_TRACKED))
                        r.cmp:SetText("")
                    else
                        r.value:SetText(n and n > 0 and Theme.HexColor("good", "×" .. grouped(n)) or Theme.HexColor("muted", "–"))
                        local m = compare and Life.DungeonCount(compare, d)
                        r.cmp:SetText(compare and mineColor(m and m > 0 and grouped(m) or "–") or "")
                    end
                    r.tipKey = d[2] and d[2][1] or nil
                    r:Show()
                end
            end
        end
        for k = j + 1, #c.rows do c.rows[k]:Hide() end
        -- the boss list spans the full width
        local top = math.max(colY[1], colY[2])
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 0, -top)
        c:SetSize(w, 38 + j * ROW)
        c:SetShown(j > 0)
        for k = n + 1, #self.cards do self.cards[k]:Hide() end
        body:SetHeight(top + (j > 0 and (38 + j * ROW) or 0) + 10)
        scroll.UpdateBar()
    end
    view:SetScript("OnSizeChanged", function(self) if self.sheet then self:Show_(self.sheet, self.compare) end end)
    return view
end

---------------------------------------------------------------------------
-- Guild overview list
---------------------------------------------------------------------------
function Life.GuildRows()
    local rows = {}
    local roster = next(ns.Guild.members) ~= nil
    for key, sheet in pairs(store()) do
        if not roster or ns.Guild.IsMember(key) or Names.Same(key, Names.Me()) then
            rows[#rows + 1] = { key = key, sheet = sheet, bosses = (Life.BossesKilled(sheet)) }
        end
    end
    return rows
end

ns.On("LG_LIFE", function() ns.Window.Refresh("stats") end)

---------------------------------------------------------------------------
-- Reading another player (target / inspect). The game answers a comparison
-- request with INSPECT_ACHIEVEMENT_READY; only one request at a time, and not
-- in combat.
---------------------------------------------------------------------------
local pending, nextRequest, externalUntil, ownsComparison, internal = nil, 0, 0, false, false
Life.status = ""

local function setStatus(text)
    Life.status = text or ""
    ns.Fire("LG_LIFE_STATUS")
end

local function release()
    if ownsComparison then
        ownsComparison = false
        if type(ClearAchievementComparisonUnit) == "function" then
            internal = true; pcall(ClearAchievementComparisonUnit); internal = false
        end
    end
end

local function cancel(message)
    pending = nil
    release()
    if message then setStatus(message) end
end
Life.Cancel = cancel

local function hooks()
    if Life.hooked or type(hooksecurefunc) ~= "function" or type(SetAchievementComparisonUnit) ~= "function" then return end
    Life.hooked = true
    local function displaced()
        if internal then return end
        ownsComparison = false
        externalUntil = GetTime() + 5
        if pending then cancel(L.LIFE_DISPLACED) end
    end
    pcall(hooksecurefunc, "SetAchievementComparisonUnit", displaced)
    if type(ClearAchievementComparisonUnit) == "function" then pcall(hooksecurefunc, "ClearAchievementComparisonUnit", displaced) end
end

local function start()
    local p = pending
    if not p then return end
    if ns.Call(UnitGUID, p.unit) ~= p.subject.guid then cancel(L.LIFE_TARGET_CHANGED); return end
    if InCombatLockdown() then cancel(L.LIFE_COMBAT); return end
    if type(SetAchievementComparisonUnit) ~= "function" or type(GetComparisonStatistic) ~= "function" then cancel(L.LIFE_NO_COMPARE); return end
    if CanInspect and not ns.Call(CanInspect, p.unit, false) then cancel(L.LIFE_TOO_FAR); return end
    if AchievementFrame and AchievementFrame:IsShown() and AchievementFrame.isComparison then cancel(L.LIFE_CLOSE_ACHIEVEMENTS); return end
    local readyAt = math.max(nextRequest, externalUntil)
    if readyAt > GetTime() then
        p.queuedUntil = readyAt
        setStatus(L.LIFE_QUEUED:format(math.ceil(readyAt - GetTime())))
        return
    end
    p.queuedUntil, p.deadline = nil, GetTime() + 15
    nextRequest = GetTime() + 5
    ownsComparison, internal = true, true
    local ok, result = pcall(SetAchievementComparisonUnit, p.unit)
    internal = false
    if not ok or result == false then cancel(L.LIFE_REQUEST_FAILED); return end
    setStatus(L.LIFE_READING:format(Names.Display(p.subject.n or "?")))
end

-- Opens the sheet of a unit: own numbers directly, others via the game's comparison request
function Life.Inspect(unit)
    hooks()
    unit = unit or "target"
    local subject = Life.Subject(unit)
    if not subject then setStatus(L.LIFE_NEED_TARGET); return false end
    if UnitIsUnit(unit, "player") then
        Life.Capture(true)
        setStatus("")
        ns.Fire("LG_LIFE_SHOW", Names.Me())
        return true
    end
    if InCombatLockdown() then setStatus(L.LIFE_COMBAT); return false end
    cancel(nil)
    pending = { unit = unit, subject = subject }
    if Life.ticker then Life.ticker:Show() end
    start()
    return true
end

function Life.Pending() return pending end

ns.On("INSPECT_ACHIEVEMENT_READY", function(_, guid)
    local p = pending
    if not p or p.queuedUntil or p.subject.guid ~= guid then return end
    if GetTime() > (p.deadline or 0) then cancel(L.LIFE_TOO_LATE); return end
    if InCombatLockdown() then cancel(L.LIFE_COMBAT); return end
    local sheet = Life.Read(p.subject, false)
    pending = nil
    release()
    if not sheet then setStatus(L.LIFE_NO_DATA); return end
    local key = Names.Key(sheet.n) or sheet.guid
    Life.Remember(key, sheet)
    -- guild members: keep the newest sheet for the guild view too
    if ns.Guild.IsMember(key) then
        local old = store()[key]
        if not old or (old.t or 0) < sheet.t then store()[key] = sheet end
    end
    setStatus("")
    ns.Fire("LG_LIFE_SHOW", key)
    ns.Fire("LG_LIFE")
end)

ns.On("PLAYER_TARGET_CHANGED", function()
    if pending and pending.unit == "target" and ns.Call(UnitGUID, "target") ~= pending.subject.guid then cancel(L.LIFE_TARGET_CHANGED) end
end)

local ticker = CreateFrame("Frame")
ticker:Hide()
Life.ticker = ticker
local acc = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc < 1 then return end
    acc = 0
    local p = pending
    if not p then self:Hide(); return end
    if p.queuedUntil then
        if GetTime() >= p.queuedUntil then start() else setStatus(L.LIFE_QUEUED:format(math.ceil(p.queuedUntil - GetTime()))) end
    elseif GetTime() >= (p.deadline or 0) then
        cancel(L.LIFE_TIMEOUT)
    end
end)
