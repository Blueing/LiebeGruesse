-- Cooldown tracking over the shared FA_SPELL_CD addon message format.
--   K;part;total;id,id,...   known tracked spells
--   Q  or  Q;key,key         request for K lists
--   3;id;duration;remaining;rate   a cooldown was just used
local _, ns = ...
local Cooldowns = ns.NewModule("cooldowns")
ns.Cooldowns = Cooldowns
local Spells, Names, Comm, L = ns.CooldownSpells, ns.Names, ns.Comm, ns.L

local PREFIX = "FA_SPELL_CD"
Cooldowns.members = {}   -- [key] = { key, name, class, unit, known = {id=true}, cds = {id = {expires, dur}} }
local members = Cooldowns.members
local myKnown, myKnownSig = {}, ""

local function settings() return ns.Database.Settings().cd end
local function changed() ns.Fire("LG_COOLDOWNS") end

---------------------------------------------------------------------------
-- Group roster
---------------------------------------------------------------------------
local function rebuildRoster()
    local seen = {}
    for unit, key, name in ns.GroupUnits() do
        local m = members[key]
        if not m then
            -- another sender may have been stored under a first-name-only key
            for k, other in pairs(members) do
                if not other.unit and Names.Same(k, key) then m = other; members[k] = nil end
            end
        end
        m = m or { known = {}, cds = {} }
        m.key, m.name, m.unit = key, name, unit
        local _, class = ns.Call(UnitClass, unit)
        m.class = class or m.class
        m.role = UnitGroupRolesAssigned and ns.Call(UnitGroupRolesAssigned, unit) or nil
        members[key] = m
        seen[key] = true
    end
    if not IsInGroup() then
        local key = Names.Me()
        if key then
            local m = members[key] or { known = {}, cds = {} }
            m.key, m.name, m.unit = key, Names.Unit("player"), "player"
            m.class = select(2, ns.Call(UnitClass, "player"))
            members[key] = m
            seen[key] = true
        end
    end
    for key, m in pairs(members) do
        if not seen[key] and not m.fake then members[key] = nil end
    end
    local me = members[Names.Me() or ""]
    if me then me.known = myKnown end
    changed()
end

local function memberFor(sender)
    local key = Names.Key(sender)
    if not key then return nil end
    if members[key] then return members[key] end
    for k, m in pairs(members) do
        if Names.Same(k, key) then return m end
    end
    -- Other senders may append "-Realm"; also try the part before "-"
    local first = Names.Key(sender:match("^[^-]+"))
    for k, m in pairs(members) do
        if first and Names.Same(k, first) then return m end
    end
end

---------------------------------------------------------------------------
-- Known spells
---------------------------------------------------------------------------
local function knownById(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and ns.Call(C_SpellBook.IsSpellKnown, id) == true then return true end
    if IsPlayerSpell and ns.Call(IsPlayerSpell, id) == true then return true end
    if IsSpellKnown and ns.Call(IsSpellKnown, id) == true then return true end
    return false
end

local function knownSpell(spell)
    if knownById(spell.id) then return true end
    -- another rank of the same spell
    local name = Spells.Name(spell)
    if name and C_Spell and C_Spell.GetSpellInfo then
        local info = ns.Call(C_Spell.GetSpellInfo, name)
        local other = type(info) == "table" and info.spellID
        if type(other) == "number" and other ~= spell.id and knownById(other) then return true end
    elseif name and GetSpellInfo then
        local other = select(7, ns.Call(GetSpellInfo, name))
        if type(other) == "number" and other ~= spell.id and knownById(other) then return true end
    end
    return false
end

local function groupSend(text, opts)
    local channel = ns.GroupChannel()
    if not channel then return end
    Comm.SendRaw(PREFIX, text, channel, opts or { priority = "alert" })
end

local function announceKnown()
    if not IsInGroup() then return end
    local ids = {}
    for id in pairs(myKnown) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts, current = {}, ""
    for _, id in ipairs(ids) do
        local piece = tostring(id)
        if #current + #piece + 1 > 200 then parts[#parts + 1] = current; current = piece
        else current = current == "" and piece or (current .. "," .. piece) end
    end
    parts[#parts + 1] = current
    for i, part in ipairs(parts) do groupSend(("K;%d;%d;%s"):format(i, #parts, part), { priority = "normal" }) end
end

function Cooldowns.UpdateKnown(force)
    if InCombatLockdown() then
        ns.AfterCombat("cd-known", function() Cooldowns.UpdateKnown(force) end)
        return
    end
    local _, class = ns.Call(UnitClass, "player")
    local known, ids = {}, {}
    for _, spell in ipairs(Spells.list) do
        if (spell.class == class or spell.class == "ALL") and knownSpell(spell) then known[spell.id] = true; ids[#ids + 1] = spell.id end
    end
    table.sort(ids)
    local sig = table.concat(ids, ",")
    myKnown = known
    local me = members[Names.Me() or ""]
    if me then me.known = known end
    if force or sig ~= myKnownSig then
        myKnownSig = sig
        announceKnown()
    end
    changed()
end

---------------------------------------------------------------------------
-- Own casts
---------------------------------------------------------------------------
local function readCooldown(spellID, castAt)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = ns.Call(C_Spell.GetSpellCooldown, spellID)
        if type(info) == "table" then start, duration = info.startTime, info.duration end
    elseif GetSpellCooldown then
        start, duration = ns.Call(GetSpellCooldown, spellID)
    end
    if not ns.Num(start) or not ns.Num(duration) then return nil end
    if duration <= 2 or duration > 3600 or start < castAt - 0.5 then return nil end
    local remaining = start + duration - GetTime()
    if remaining <= 0 then return nil end
    return duration, remaining
end

local function record(m, id, duration, remaining)
    if not m then return end
    m.cds[id] = { expires = GetTime() + remaining, dur = duration }
    m.known[id] = true
    changed()
end

local function sendCast(id, duration, expires)
    groupSend(nil, {
        priority = "alert",
        build = function()
            local remaining = expires - GetTime()
            if remaining < 0.5 then return nil end
            return ("3;%d;%.3f;%.3f;%.3f"):format(id, duration, remaining, 1)
        end,
    })
end

-- Group members without the addon: their casts are seen
-- through UNIT_SPELLCAST_SUCCEEDED (when the game does not hide them) and
-- tracked with the spell's base cooldown.
local function observeOther(unit, spellID)
    if settings().observe == false then return end
    if not (unit:match("^raid%d+$") or unit:match("^party%d+$")) then return end
    local id = Spells.Resolve(spellID)
    if not id then return end
    local key = Names.Key(Names.Unit(unit) or "")
    local m = key and members[key]
    if not m or m.speaks or Names.Same(key, Names.Me()) then return end
    local spell = Spells.byId[id]
    if spell and spell.class ~= "ALL" and m.class and spell.class ~= m.class then return end
    local duration = Spells.Cooldown(spell)
    if not duration or duration <= 0 then return end
    m.observed = true
    record(m, id, duration, duration)
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if ns.IsSecret(unit) or ns.IsSecret(spellID) then return end
    if unit ~= "player" then
        if type(unit) == "string" and type(spellID) == "number" then observeOther(unit, spellID) end
        return
    end
    local id = Spells.Resolve(spellID)
    if not id then return end
    local castAt = GetTime()
    ns.After(0.3, function()
        local duration, remaining = readCooldown(spellID, castAt)
        if not duration then
            duration = Spells.Cooldown(Spells.byId[id])
            remaining = duration - (GetTime() - castAt)
        end
        local me = members[Names.Me() or ""]
        record(me, id, duration, remaining)
        sendCast(id, duration, GetTime() + remaining)
    end)
end)

---------------------------------------------------------------------------
-- Receiving 
---------------------------------------------------------------------------
local lastAsk = 0
local function askAll()
    if not IsInGroup() or GetTime() - lastAsk < 20 then return end
    lastAsk = GetTime()
    groupSend("Q", { priority = "normal" })
end

Comm.Listen(PREFIX, function(text, channel, sender)
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
    if Names.IsMe(sender) then return end
    if text:match("^Q") then
        local wanted = text:match("^Q;(.*)$")
        local me = Names.Me()
        if wanted and wanted ~= "" then
            local mine = false
            for key in wanted:gmatch("[^,]+") do if Names.Same(Names.Key(key), me) then mine = true end end
            if not mine then return end
        end
        ns.Debounce("cd-answer", 1 + math.random() * 2, function() announceKnown() end)
        return
    end
    local part, total, list = text:match("^K;(%d+);(%d+);(.*)$")
    if part then
        local m = memberFor(sender)
        if not m then return end
        m.speaks = true
        if tonumber(part) == 1 then m.known = {} end
        for raw in list:gmatch("%d+") do
            local id = Spells.Resolve(tonumber(raw))
            if id then m.known[id] = true end
        end
        if tonumber(part) == tonumber(total) then changed() end
        return
    end
    local id, duration, remaining = text:match("^3;(%d+);([%d%.]+);([%d%.]+)")
    if id then
        local spellId = Spells.Resolve(tonumber(id))
        local m = memberFor(sender)
        if m then m.speaks = true end
        if spellId and m then record(m, spellId, tonumber(duration), tonumber(remaining)) end
    end
end)

---------------------------------------------------------------------------
-- Persistence across /reload (server time based)
---------------------------------------------------------------------------
ns.On("PLAYER_LOGOUT", function()
    local saved = {}
    local now, server = GetTime(), ns.Now()
    for key, m in pairs(members) do
        if not m.fake then
            for id, cd in pairs(m.cds) do
                if cd.expires > now then
                    saved[#saved + 1] = { key = key, id = id, dur = cd.dur, until_ = server + (cd.expires - now) }
                end
            end
        end
    end
    ns.Database.Char().cds = saved
end)

local function restore()
    local saved = ns.Database.Char().cds
    if type(saved) ~= "table" then return end
    local now, server = GetTime(), ns.Now()
    for _, e in ipairs(saved) do
        local m = members[e.key]
        if m and e.until_ and e.until_ > server then
            m.cds[e.id] = { expires = now + (e.until_ - server), dur = e.dur }
        end
    end
    ns.Database.Char().cds = nil
    changed()
end

---------------------------------------------------------------------------
-- Preview: fake group members with running cooldowns
---------------------------------------------------------------------------
local FAKE = {
    { "Borin Ironfist", "WARRIOR", "TANK" }, { "Lia Sunshield", "PALADIN", "HEALER" },
    { "Finn Greengrove", "DRUID", "HEALER" }, { "Arwen Silverleaf", "PRIEST", "HEALER" },
    { "Celia Morningdew", "MAGE", "DAMAGER" }, { "Dorn Shadowpath", "ROGUE", "DAMAGER" },
    { "Elara Stormcall", "SHAMAN", "HEALER" }, { "Mira Ashvale", "WARLOCK", "DAMAGER" },
    { "Tarek Hawkeye", "HUNTER", "DAMAGER" }, { "Salty Brown", "WARRIOR", "DAMAGER" },
}
local previewUntil

local function randomCd(m, spell)
    local cd = Spells.Cooldown(spell)
    m.cds[spell.id] = { expires = GetTime() + math.random() * math.min(cd, 240), dur = cd }
end

---------------------------------------------------------------------------
-- "Is it ready?" – when someone clicks one of your cooldowns, their addon asks
-- yours (hidden addon message, never chat) and gets the exact time left back.
---------------------------------------------------------------------------
local pendingAsk = {}

local function ownLeft(id)
    if not (IsPlayerSpell and ns.Call(IsPlayerSpell, id)) and not (IsSpellKnown and ns.Call(IsSpellKnown, id)) then return nil, false end
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = ns.Call(C_Spell.GetSpellCooldown, id)
        if type(info) == "table" then start, duration = info.startTime, info.duration end
    elseif GetSpellCooldown then
        start, duration = ns.Call(GetSpellCooldown, id)
    end
    if not ns.Num(start) or not ns.Num(duration) then return nil, true end   -- hidden (e.g. in combat)
    if duration <= 2 then return 0, true end                               -- global cooldown only
    return math.max(0, start + duration - GetTime()), true
end

local function fmtLeft(sec) return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60)) end

local function showAnswer(m, spell, left, exact)
    local text = (exact and L.CD_ANSWER_LEFT or L.CD_ANSWER_GUESS):format(Names.Display(m.name), Spells.Name(spell), fmtLeft(left))
    ns.UI.Toast(L.CD_ANSWER_TITLE, text, Spells.Icon(spell))
    ns.Print(text)
end

-- called by the bars after a click on someone's cooldown
function Cooldowns.AskReady(m, spell)
    if not m or not spell or m.fake or Names.Same(m.key, Names.Me()) then return end
    local key = m.key .. ":" .. spell.id
    local cd = m.cds[spell.id]
    local guess = cd and cd.expires - GetTime() or 0
    pendingAsk[key] = { at = GetTime(), m = m, spell = spell }
    local target = m.name
    if m.unit and UnitExists(m.unit) then target = Names.Unit(m.unit) or target end
    Comm.Send("CDQ", { i = spell.id }, "WHISPER", { target = target, priority = "alert" })
    -- no answer (no addon, or the value is hidden): fall back to what the tracker knows
    ns.After(2, function()
        if not pendingAsk[key] then return end
        pendingAsk[key] = nil
        if guess > 1 then showAnswer(m, spell, guess, false) end
    end)
end

Comm.Register("CDQ", function(data, _, _, raw)
    local id = tonumber(data.i)
    if not id or not raw then return end
    local left, known = ownLeft(id)
    Comm.Send("CDA", { i = id, l = left and math.floor(left + 0.5) or -1, k = known and 1 or 0 }, "WHISPER", { target = raw, priority = "alert" })
end)

Comm.Register("CDA", function(data, senderKey)
    local id, left = tonumber(data.i), tonumber(data.l)
    if not id or not senderKey then return end
    local key = senderKey .. ":" .. id
    local ask = pendingAsk[key]
    if not ask or not left or left < 0 then return end   -- unknown: the timeout shows the tracker's guess
    pendingAsk[key] = nil
    -- correct the tracker with the real value
    if left > 1 then
        local old = ask.m.cds[id]
        ask.m.cds[id] = { expires = GetTime() + left, dur = old and old.dur or left }
        showAnswer(ask.m, ask.spell, left, true)
    else
        ask.m.cds[id] = nil
    end
    changed()
end)

function Cooldowns.IsPreview()
    return previewUntil ~= nil and GetTime() < previewUntil
end

local previewTicker
-- seconds: nil = until switched off
function Cooldowns.SetPreview(on, seconds)
    for key, m in pairs(members) do if m.fake then members[key] = nil end end
    previewUntil = nil
    if on then
        previewUntil = GetTime() + (seconds or 1e9)
        for _, fake in ipairs(FAKE) do
            local key = Names.Key(fake[1])
            local m = { key = key, name = fake[1], class = fake[2], role = fake[3], known = {}, cds = {}, fake = true }
            for _, spell in ipairs(Spells.list) do
                if spell.class == fake[2] or spell.class == "ALL" then
                    m.known[spell.id] = true
                    if math.random() < 0.4 then randomCd(m, spell) end
                end
            end
            members[key] = m
        end
        if seconds then
            ns.After(seconds, function()
                if previewUntil and GetTime() >= previewUntil - 0.5 then Cooldowns.SetPreview(false) end
            end)
        end
    end
    settings().preview = on and not seconds or false
    if on and not previewTicker then previewTicker = C_Timer.NewTicker(2, Cooldowns.PreviewTick) end
    changed()
end

function Cooldowns.Test()
    Cooldowns.SetPreview(true, 120)
    ns.Print(ns.L.CD_TEST_STARTED)
end

-- keep the preview lively (the ticker only runs while a preview is shown)
function Cooldowns.PreviewTick()
    if not Cooldowns.IsPreview() then
        if previewTicker then previewTicker:Cancel(); previewTicker = nil end
        return
    end
    local now = GetTime()
    for _, m in pairs(members) do
        if m.fake then
            for id in pairs(m.known) do
                local cd = m.cds[id]
                if (not cd or cd.expires < now) and math.random() < 0.04 and Spells.byId[id] then randomCd(m, Spells.byId[id]) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Cooldowns:OnInit()
    Spells.Rebuild()
    settings().preview = false
end

function Cooldowns:OnLogin()
    Spells.Index()
    rebuildRoster()
    ns.After(3, function()
        Cooldowns.UpdateKnown(true)
        restore()
        askAll()
    end)
end

ns.On("GROUP_ROSTER_UPDATE", function()
    ns.Debounce("cd-roster", 1, function()
        local before = 0
        for _ in pairs(members) do before = before + 1 end
        rebuildRoster()
        local missing = false
        for key, m in pairs(members) do
            if not m.fake and not Names.Same(key, Names.Me()) and not next(m.known) then missing = true end
        end
        if missing then ns.After(2, askAll) end
        ns.Debounce("cd-announce", 3, function() announceKnown() end)
    end)
end)
ns.On("GROUP_LEFT", function() ns.Debounce("cd-roster", 1, rebuildRoster) end)
ns.On("SPELLS_CHANGED", function() ns.Debounce("cd-known", 2, function() Cooldowns.UpdateKnown(false) end) end)
ns.On("PLAYER_LEVEL_UP", function() ns.Debounce("cd-known", 2, function() Cooldowns.UpdateKnown(false) end) end)
ns.On("SPELL_DATA_LOAD_RESULT", function() ns.Debounce("cd-index", 1, Spells.Index) end)
ns.On("UNIT_CONNECTION", function() changed() end)
ns.On("UNIT_FLAGS", function() ns.Debounce("cd-flags", 0.5, changed) end)
