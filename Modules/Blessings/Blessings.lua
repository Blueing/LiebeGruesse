-- Paladin blessings: who blesses which class, who is missing what, and a
-- small bar for paladins with one-click (greater) blessings.
-- Assignments sync between paladins with this addon and with PallyPower users.
-- Cost: nothing outside a group; in a group only UNIT_AURA of group members,
-- throttled, and only while you are a paladin or the page is open.
local _, ns = ...
local L, Names, Comm = ns.L, ns.Names, ns.Comm
local B = ns.NewModule("blessings")
ns.Blessings = B

---------------------------------------------------------------------------
-- Spells (WoW: Forever has Kings, Might and Wisdom; greater = whole class)
---------------------------------------------------------------------------
B.LIST = {
    { key = "kings", single = { 20217 }, greater = { 25898 }, short = "K" },
    { key = "might", single = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, greater = { 25782, 25916 }, short = "M" },
    { key = "wisdom", single = { 19742, 19850, 19852, 19853, 19854, 25290 }, greater = { 25894, 25918 }, short = "W" },
}
B.BY_KEY = {}
for i, b in ipairs(B.LIST) do b.order = i; B.BY_KEY[b.key] = b end

B.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- what each class wants, best first
B.WISHES = {
    WARRIOR = { "kings", "might" }, ROGUE = { "kings", "might" },
    HUNTER = { "kings", "might", "wisdom" }, PALADIN = { "kings", "wisdom", "might" },
    SHAMAN = { "kings", "wisdom", "might" }, DRUID = { "kings", "wisdom", "might" },
    PRIEST = { "kings", "wisdom" }, MAGE = { "kings", "wisdom" }, WARLOCK = { "kings", "wisdom" },
}

local spellOf = {}    -- [spellId] = blessing key
local nameOf = {}     -- [localized aura name] = blessing key
for _, b in ipairs(B.LIST) do
    for _, kind in ipairs({ "single", "greater" }) do
        for _, id in ipairs(b[kind]) do spellOf[id] = b.key end
    end
end
local function learnNames()
    if next(nameOf) then return end
    local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    for id, key in pairs(spellOf) do
        local name = get and ns.Call(get, id)
        if type(name) == "string" and name ~= "" then nameOf[name] = key end
    end
end

local function known(id)
    if IsPlayerSpell then return ns.Call(IsPlayerSpell, id) == true end
    if IsSpellKnown then return ns.Call(IsSpellKnown, id) == true end
    return false
end
-- highest known rank of a blessing ("single"/"greater"), as a spell id
function B.SpellFor(key, kind)
    local b = B.BY_KEY[key]
    local ids = b and b[kind] or {}
    for i = #ids, 1, -1 do if known(ids[i]) then return ids[i] end end
end
function B.SpellName(id)
    local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    return id and get and ns.Call(get, id) or nil
end
function B.Icon(key)
    local b = B.BY_KEY[key]
    if not b then return nil end
    local get = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    return (get and ns.Call(get, b.greater[1])) or (get and ns.Call(get, b.single[1])) or 135995
end
function B.Name(key) return L["BLESS_" .. tostring(key):upper()] end

-- own abilities: { kings = 0/1/2, ... } (1 = single only, 2 = greater)
function B.OwnSkills()
    local out = {}
    for _, b in ipairs(B.LIST) do
        out[b.key] = (B.SpellFor(b.key, "greater") and 2) or (B.SpellFor(b.key, "single") and 1) or 0
    end
    return out
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- paladins[key] = { key, name, unit, addon = "lg"/"pp"/nil, can = {...}, set = { [class] = blessing } }
B.paladins = {}
B.status = {}     -- [class] = { total, have = { [b] = n }, left = { [b] = seconds }, units = { ... } }
B.missing = {}    -- { { key, name, class, list = { blessing, ... } } }

function B.Settings()
    local s = ns.Database.Settings()
    s.blessings = s.blessings or {}
    local o = s.blessings
    local d = { bar = true, raidOnly = false, solo = true, scale = 1, freeAssign = false }
    for k, v in pairs(d) do if o[k] == nil then o[k] = v end end
    return o
end
local function enabled() return ns.Database.Settings().modules.blessings ~= false end
B.Enabled = enabled

local function isPaladin() local _, c = ns.Call(UnitClass, "player"); return c == "PALADIN" end
B.IsPaladin = isPaladin

-- saved own choices survive /reload; assignments for others only live per group
local function ownSet()
    local char = ns.Database.Char()
    char.blessings = char.blessings or {}
    return char.blessings
end

local function encode(set)
    local chars = {}
    for i, class in ipairs(B.CLASSES) do
        local b = set and set[class]
        chars[i] = b and B.BY_KEY[b] and B.BY_KEY[b].short or "."
    end
    return table.concat(chars)
end
local BY_SHORT = { K = "kings", M = "might", W = "wisdom" }
local function decode(text)
    local set = {}
    if type(text) ~= "string" then return set end
    for i, class in ipairs(B.CLASSES) do set[class] = BY_SHORT[text:sub(i, i)] end
    return set
end
local function encodeSkills(can)
    local out = {}
    for i, b in ipairs(B.LIST) do out[i] = tostring(can and can[b.key] or 0) end
    return table.concat(out)
end
local function decodeSkills(text)
    local can = {}
    for i, b in ipairs(B.LIST) do can[b.key] = tonumber(tostring(text or ""):sub(i, i)) or 0 end
    return can
end

---------------------------------------------------------------------------
-- Group roster: paladins and class counts (rebuilt on roster changes)
---------------------------------------------------------------------------
local classUnits = {}   -- [class] = { unit, ... }
local lastGood = {}     -- last good aura reading per unit: [unit] = { guid, [blessing] = expires (GetTime) }
B.classUnits = classUnits

function B.Rebuild()
    if B.test then return end
    wipe(classUnits)   -- (lastGood stays: it checks the GUID behind each unit)
    local seen = {}
    local me = Names.Me()
    for unit, key, name in ns.GroupUnits() do
        local _, class = ns.Call(UnitClass, unit)
        if class then
            classUnits[class] = classUnits[class] or {}
            table.insert(classUnits[class], unit)
            if class == "PALADIN" then
                seen[key] = true
                local p = B.paladins[key] or { key = key, set = {}, can = {} }
                p.name, p.unit = name, unit
                if Names.Same(key, me) then
                    p.addon, p.me = "lg", true
                    p.can = B.OwnSkills()
                    p.set = ownSet()
                end
                B.paladins[key] = p
            end
        end
    end
    -- solo paladin: show yourself too
    if not IsInGroup() and isPaladin() then
        local p = B.paladins[me] or { key = me, set = ownSet() }
        p.name, p.unit, p.addon, p.me, p.can, p.set = Names.Unit("player"), "player", "lg", true, B.OwnSkills(), ownSet()
        B.paladins[me] = p
        seen[me] = true
        local _, class = ns.Call(UnitClass, "player")
        if class then classUnits[class] = classUnits[class] or { "player" } end
    end
    for key in pairs(B.paladins) do if not seen[key] then B.paladins[key] = nil end end
end

function B.PaladinList()
    local list = {}
    for _, p in pairs(B.paladins) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if (a.me or false) ~= (b.me or false) then return a.me == true end
        if (a.addon ~= nil) ~= (b.addon ~= nil) then return a.addon ~= nil end
        return a.key < b.key
    end)
    return list
end

function B.Me() return B.paladins[Names.Me()] end

-- may I change this paladin's assignment?
function B.CanEdit(p)
    if not p then return false end
    if B.test then return true end
    if p.me then return true end
    if not IsInGroup() then return false end
    return ns.IsGroupLead("player") or p.free == true
end

---------------------------------------------------------------------------
-- Buff scan: who has which blessing (and how long it lasts)
---------------------------------------------------------------------------
local function auraBlessing(spellId, name)
    return (spellId and spellOf[spellId]) or (name and nameOf[name])
end

-- Reads the blessings on a unit. Returns out, reliable: in combat the game can
-- hide aura data (secret values); then the result is not trustworthy and the
-- caller keeps the last good reading instead of showing "nobody buffed".
local function unitBlessings(unit, out)
    wipe(out)
    local reliable = true
    for i = 1, 40 do
        local name, spellId, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or ns.IsSecret(a) then reliable = false; break end
            if type(a) ~= "table" then break end
            name, spellId, expires = a.name, a.spellId, a.expirationTime
        else
            local ok, n, _, _, _, _, exp, _, _, _, id = pcall(UnitBuff, unit, i)
            if not ok or ns.IsSecret(n) then reliable = false; break end
            if not n then break end
            name, spellId, expires = n, id, exp
        end
        if ns.IsSecret(name) then name = nil end
        if ns.IsSecret(spellId) then spellId = nil end
        if ns.IsSecret(expires) then expires = nil end
        if name == nil and spellId == nil then
            reliable = false
        else
            local key = auraBlessing(spellId, name)
            if key then out[key] = (type(expires) == "number" and expires > 0) and (expires - GetTime()) or 3600 end
        end
    end
    return out, reliable
end

local function rememberedBlessings(unit, out)
    wipe(out)
    local m = lastGood[unit]
    local guid = ns.Call(UnitGUID, unit)
    if not m or (guid and m.guid and m.guid ~= guid) then return out end
    local now = GetTime()
    for b, exp in pairs(m) do
        if b ~= "guid" and exp > now then out[b] = exp - now end
    end
    return out
end
local function remember(unit, has)
    local m = { guid = ns.Call(UnitGUID, unit) }
    local now = GetTime()
    for b, left in pairs(has) do m[b] = now + left end
    lastGood[unit] = m
end

local scratch = {}
function B.Scan()
    if B.test then return B.TestScan() end
    B.lastScan = GetTime()
    learnNames()
    wipe(B.status)
    wipe(B.missing)
    local wanted = {}   -- [class] = { blessing = true } from all assignments
    for _, p in pairs(B.paladins) do
        for class, b in pairs(p.set or {}) do
            wanted[class] = wanted[class] or {}
            wanted[class][b] = true
        end
    end
    for class, units in pairs(classUnits) do
        local st = { total = 0, have = {}, left = {}, need = {} }
        for _, unit in ipairs(units) do
            if ns.Call(UnitExists, unit) then
                st.total = st.total + 1
                local has, reliable = unitBlessings(unit, scratch)
                if reliable then remember(unit, has) else has = rememberedBlessings(unit, scratch) end
                local miss = {}
                for b in pairs(wanted[class] or {}) do
                    if has[b] then
                        st.have[b] = (st.have[b] or 0) + 1
                        st.left[b] = math.min(st.left[b] or math.huge, has[b])
                    else
                        miss[#miss + 1] = b
                        st.need[b] = st.need[b] or {}
                        table.insert(st.need[b], unit)
                    end
                end
                if #miss > 0 then
                    local name = Names.Unit(unit)
                    B.missing[#B.missing + 1] = { key = Names.Key(name), name = name, class = class, list = miss, unit = unit }
                end
            end
        end
        B.status[class] = st
    end
    table.sort(B.missing, function(a, b) return a.key < b.key end)
    ns.Fire("LG_BLESSINGS")
end

-- counts for the page header
function B.Summary()
    local pal, synced = 0, 0
    for _, p in pairs(B.paladins) do pal = pal + 1; if p.addon then synced = synced + 1 end end
    local dup = 0
    local given = {}
    for _, p in pairs(B.paladins) do
        for class, b in pairs(p.set or {}) do
            local k = class .. b
            if given[k] then dup = dup + 1 end
            given[k] = true
        end
    end
    return { paladins = pal, synced = synced, missing = #B.missing, duplicates = dup }
end

---------------------------------------------------------------------------
-- Changing assignments
---------------------------------------------------------------------------
local function changed(p, quiet)
    if p.me and not B.test then
        -- p.set usually IS the saved table (Rebuild): wiping it would lose
        -- every assignment, so copy only when they are different tables
        local saved = ownSet()
        if saved ~= p.set then
            wipe(saved)
            for class, b in pairs(p.set or {}) do saved[class] = b end
        end
    end
    if not quiet then B.Share(p) end
    ns.Debounce("bless-scan", 0.3, B.Scan)
    if ns.BlessingsBar then ns.BlessingsBar.Update() end
end

function B.Set(p, class, blessing)
    if not B.CanEdit(p) then return false end
    p.set = p.set or {}
    p.set[class] = blessing
    changed(p)
    return true
end

-- Mouse wheel: next/previous blessing the paladin knows (then "none").
-- Assignments change at once; the sync is sent once the wheel rests.
function B.Cycle(p, class, delta, keep)
    if not B.CanEdit(p) then return false end
    local options = {}
    for _, b in ipairs(B.LIST) do
        if not (p.addon and p.can and p.can[b.key] == 0) then options[#options + 1] = b.key end
    end
    if not keep then options[#options + 1] = false end   -- the bar keeps its row
    if #options == 0 then return false end
    p.set = p.set or {}
    local current = p.set[class] or false
    local pos = keep and 0 or #options
    for i, v in ipairs(options) do if v == current then pos = i end end
    pos = ((pos - 1 + (delta < 0 and 1 or -1)) % #options) + 1
    p.set[class] = options[pos] or nil
    changed(p, true)
    ns.Debounce("bless-wheel-share", 1, function() B.Share(p) end)
    return true
end

function B.Clear(p)
    if not B.CanEdit(p) then return false end
    p.set = {}
    changed(p)
    return true
end

-- Suggestion: one paladin per blessing, every class gets its wishes in order;
-- a paladin only gets blessings he knows (Kings needs the talent).
-- onlyMe: change only your own assignments (first start of the bar).
function B.Suggest(onlyMe)
    local list = {}
    for _, p in ipairs(B.PaladinList()) do if B.CanEdit(p) or not IsInGroup() then list[#list + 1] = p end end
    if #list == 0 then return false end
    local all = B.PaladinList()
    -- paladins with Kings first, so the Kings paladin is the same for every class
    table.sort(all, function(a, b)
        local ka, kb = (a.can and a.can.kings or 0) > 0, (b.can and b.can.kings or 0) > 0
        if ka ~= kb then return ka end
        return a.key < b.key
    end)
    local new = {}
    for _, p in ipairs(all) do new[p.key] = {} end
    -- solo there is nobody to count: plan every class for later
    local classes = {}
    if IsInGroup() or B.test then
        for class in pairs(classUnits) do classes[#classes + 1] = class end
    else
        for _, class in ipairs(B.CLASSES) do classes[#classes + 1] = class end
    end
    for _, class in ipairs(classes) do
        local wishes = B.WISHES[class] or {}
        local taken = {}
        for _, p in ipairs(all) do
            for _, b in ipairs(wishes) do
                local can = p.can and p.can[b]
                if not taken[b] and (can == nil or can > 0 or not p.addon) then
                    new[p.key][class] = b
                    taken[b] = true
                    break
                end
            end
        end
    end
    for _, p in ipairs(all) do
        if B.CanEdit(p) and (not onlyMe or p.me) then
            p.set = new[p.key]
            changed(p)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Telling people: whisper each paladin, announce in the group
---------------------------------------------------------------------------
local function describe(set)
    local byB = {}
    for _, class in ipairs(B.CLASSES) do
        local b = set and set[class]
        if b and classUnits[class] then
            byB[b] = byB[b] or {}
            local cname = ns.ClassName(class)
            table.insert(byB[b], cname)
        end
    end
    local parts = {}
    for _, b in ipairs(B.LIST) do
        if byB[b.key] then parts[#parts + 1] = B.Name(b.key) .. ": " .. table.concat(byB[b.key], ", ") end
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end
B.Describe = describe

function B.WhisperAll()
    local n = 0
    for _, p in ipairs(B.PaladinList()) do
        local text = describe(p.set)
        if text and not p.me then
            if B.test then ns.Print(L.TEST_TAG .. " " .. p.name .. ": " .. L.BLESS_WHISPER:format(text))
            else ns.SendChat(L.BLESS_WHISPER:format(text), "WHISPER", p.name) end
            n = n + 1
        end
    end
    ns.Print(L.BLESS_WHISPERED:format(n))
end

function B.Announce()
    if B.test then
        ns.Print(L.TEST_TAG .. " " .. L.BLESS_ANNOUNCE_HEAD)
        for _, p in ipairs(B.PaladinList()) do
            local text = describe(p.set)
            if text then ns.Print(L.TEST_TAG .. " " .. ("%s – %s"):format(Names.Display(p.name), text)) end
        end
        return
    end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
    if not channel then ns.Print(L.NOT_IN_GROUP); return end
    ns.SendChat(L.BLESS_ANNOUNCE_HEAD, channel)
    for _, p in ipairs(B.PaladinList()) do
        local text = describe(p.set)
        if text then ns.SendChat(("%s – %s"):format(Names.Display(p.name), text), channel) end
    end
end

---------------------------------------------------------------------------
-- Sync: own protocol ("BL") plus PallyPower ("PLPWR")
---------------------------------------------------------------------------
local PP = "PLPWR"
local PP_CLASSES = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
local PP_BLESS = { ["1"] = "wisdom", ["2"] = "might", ["3"] = "kings" }
local PP_DIGIT = { wisdom = "1", might = "2", kings = "3" }
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then ns.Call(C_ChatInfo.RegisterAddonMessagePrefix, PP) end

local function ppSet(set)
    local out = {}
    for i, class in ipairs(PP_CLASSES) do out[i] = set and PP_DIGIT[set[class]] or "n" end
    return table.concat(out)
end

function B.Share(p)
    if B.test then return end
    if not IsInGroup() or not enabled() then return end
    local me = Names.Me()
    p = p or B.Me()
    if not p then return end
    local mine = Names.Same(p.key, me)
    Comm.Send("BL", { p = p.key, s = encode(p.set), c = mine and encodeSkills(p.can) or nil, f = mine and (B.Settings().freeAssign and 1 or nil) or nil },
        "GROUP", { priority = "normal" })
    -- PallyPower users see it too
    local channel = ns.GroupChannel()
    if channel then
        if mine then
            local skills = {}
            for _, k in ipairs({ "wisdom", "might", "kings" }) do skills[#skills + 1] = (p.can and (p.can[k] or 0) > 0) and "40" or "nn" end
            for _ = 1, 3 do skills[#skills + 1] = "nn" end
            Comm.SendRaw(PP, "SELF " .. table.concat(skills) .. "@" .. ppSet(p.set), channel, { priority = "normal" })
        else
            Comm.SendRaw(PP, ("PASSIGN %s@%s"):format(p.name or Names.Display(p.key), ppSet(p.set)), channel, { priority = "normal" })
        end
    end
end

function B.Request()
    if not IsInGroup() or not enabled() then return end
    Comm.Send("BLQ", {}, "GROUP", { priority = "normal" })
    local channel = ns.GroupChannel()
    if channel then Comm.SendRaw(PP, "REQ", channel, { priority = "normal" }) end
end

local function senderMayAssign(senderKey, targetKey)
    if Names.Same(senderKey, targetKey) then return true end
    local unit = ns.UnitForKey(senderKey)
    if unit and ns.IsGroupLead(unit) then return true end
    local target = B.paladins[targetKey]
    return target ~= nil and target.free == true
end

local function apply(targetKey, set, can, free, via)
    B.Rebuild()
    local p = B.paladins[targetKey]
    if not p then return end
    if p.me then
        -- someone (lead) assigned us: take it over
        p.set = set
        changed(p, true)
    else
        p.set = set
        if can then p.can = can end
        if free ~= nil then p.free = free end
        p.addon = p.addon == "lg" and "lg" or via
        ns.Debounce("bless-scan", 0.3, B.Scan)
        if ns.BlessingsBar then ns.BlessingsBar.Update() end
    end
end

Comm.Register("BL", function(data, sender)
    if not enabled() or type(data.p) ~= "string" then return end
    local target = Names.Key(data.p)
    if not target or not senderMayAssign(sender, target) then return end
    if Names.Same(sender, Names.Me()) then return end
    local p = B.paladins[target]
    if p and Names.Same(target, sender) then p.addon = "lg" end
    apply(target, decode(data.s), data.c and decodeSkills(data.c) or nil, data.c and (data.f == 1) or nil, "lg")
end)

Comm.Register("BLQ", function()
    if not enabled() or not isPaladin() then return end
    ns.Debounce("bless-reply", 1 + math.random() * 2, function() B.Rebuild(); B.Share(B.Me()) end)
end)

local function hearPallyPower(text, senderKey)
    local me = Names.Me()
    if Names.Same(senderKey, me) then return end
    B.Rebuild()
    if text == "REQ" then
        if isPaladin() then ns.Debounce("bless-reply", 1 + math.random() * 2, function() B.Share(B.Me()) end) end
        return
    end
    local skills, set = text:match("^SELF ([0-9n]*)@([0-9n]*)")
    if skills then
        local p = B.paladins[senderKey]
        if not p then return end
        local can = {}
        for i, k in ipairs({ "wisdom", "might", "kings" }) do can[k] = skills:sub(2 * i - 1, 2 * i - 1) == "n" and 0 or 2 end
        local s = {}
        for i, class in ipairs(PP_CLASSES) do s[class] = PP_BLESS[set:sub(i, i)] end
        if p.addon ~= "lg" then apply(senderKey, s, can, nil, "pp") end
        return
    end
    local function target(name)
        local key = Names.Key(Names.Strip(name))
        if key and B.paladins[key] and senderMayAssign(senderKey, key) then return key end
    end
    local name, classIdx, digit = text:match("^ASSIGN (.*) (%d+) (%d+)$")
    if name then
        local key, class = target(name), PP_CLASSES[tonumber(classIdx)]
        if key and class then
            local s = {}
            for c, b in pairs(B.paladins[key].set or {}) do s[c] = b end
            s[class] = PP_BLESS[digit]
            apply(key, s, nil, nil, "pp")
        end
        return
    end
    local pname, pset = text:match("^PASSIGN (.*)@([0-9n]*)$")
    if pname then
        local key = target(pname)
        if key then
            local s = {}
            for i, class in ipairs(PP_CLASSES) do s[class] = PP_BLESS[pset:sub(i, i)] end
            apply(key, s, nil, nil, "pp")
        end
        return
    end
    local mname, mdigit = text:match("^MASSIGN (.*) (%d+)$")
    if mname then
        local key = target(mname)
        if key then
            local s = {}
            for _, class in ipairs(PP_CLASSES) do s[class] = PP_BLESS[mdigit] end
            apply(key, s, nil, nil, "pp")
        end
        return
    end
    if text:find("^CLEAR") then
        for key in pairs(B.paladins) do if senderMayAssign(senderKey, key) then apply(key, {}, nil, nil, "pp") end end
    end
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if prefix ~= PP or not enabled() then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= "string" then return end
    if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "WHISPER" and channel ~= "INSTANCE_CHAT" then return end
    local key = Names.Key(Names.Strip(sender))
    if key then ns.Safe(hearPallyPower, text, key) end
end)

---------------------------------------------------------------------------
-- Events (cheap: nothing outside a group unless you are a paladin)
---------------------------------------------------------------------------
local function wanted()
    if B.test then return true end
    local shown = ns.Window.IsShown("blessings") and true or false
    if not enabled() then return shown end
    if isPaladin() then
        local o = B.Settings()
        -- solo: the bar shows your own buffs (only "player" auras get scanned)
        if o.bar and (IsInGroup() or o.solo) then return true end
        return shown
    end
    if not IsInGroup() then return shown end
    return shown
end
B.Active = wanted

local function rosterChanged()
    if not enabled() then return end
    B.Rebuild()
    if wanted() then ns.Debounce("bless-scan", 0.5, B.Scan) end
    if ns.BlessingsBar then ns.BlessingsBar.Update() end
end
ns.On("GROUP_ROSTER_UPDATE", function() ns.Debounce("bless-roster", 1, rosterChanged) end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.Debounce("bless-roster", 2, rosterChanged) end)
ns.On("GROUP_JOINED", function() ns.After(3, B.Request) end)
ns.On("SPELLS_CHANGED", function()
    if not isPaladin() then return end
    ns.Debounce("bless-skills", 2, function()
        local p = B.Me()
        if p then p.can = B.OwnSkills() end
    end)
end)
-- raids fire UNIT_AURA constantly: one scan at most every 1.5 s (5 s in combat);
-- a throttle, not a debounce, so it still runs while auras keep changing
local scanPending = false
ns.On("UNIT_AURA", function(_, unit)
    if scanPending or type(unit) ~= "string" then return end
    if not (unit == "player" or unit:find("^raid%d") or unit:find("^party%d")) then return end
    if not wanted() then return end
    scanPending = true
    ns.After((InCombatLockdown and InCombatLockdown()) and 5 or 1.5, function() scanPending = false; B.Scan() end)
end)
ns.On("LG_READY", function()
    if isPaladin() then ns.After(4, rosterChanged) end
end)

---------------------------------------------------------------------------
-- Test mode (/lg test bless): made-up paladins and raiders for 3 minutes.
-- Nothing is sent, whispered or saved; the bar shows even for non-paladins
-- and its clicks cast nothing.
---------------------------------------------------------------------------
local TEST_RAID = { WARRIOR = 6, ROGUE = 3, HUNTER = 3, PRIEST = 4, MAGE = 5, WARLOCK = 3, DRUID = 3, PALADIN = 4 }
local TEST_NAMES = { "Arwen Stormwind", "Borin Ironfist", "Cara Lightweaver", "Dorn Shadowsong", "Elin Morningdew", "Falk Greyholt" }

function B.TestScan()
    wipe(B.status)
    wipe(B.missing)
    local n = 0
    for class, units in pairs(classUnits) do
        local st = { total = #units, have = {}, left = {}, need = {} }
        for _, p in pairs(B.paladins) do
            local b = p.set and p.set[class]
            if b and not st.have[b] then
                -- some classes fully buffed, some missing one or two, some running out
                local hash = (#class * 7 + #b * 3) % 4
                st.have[b] = math.max(0, #units - (hash == 0 and 0 or hash == 1 and 1 or hash == 2 and 2 or 0))
                st.left[b] = hash == 3 and 140 or (600 + hash * 300)
                if st.have[b] < #units then
                    st.need[b] = {}
                    for i = st.have[b] + 1, #units do
                        n = n + 1
                        st.need[b][#st.need[b] + 1] = units[i]
                        local name = TEST_NAMES[(n - 1) % #TEST_NAMES + 1]
                        B.missing[#B.missing + 1] = { key = Names.Key(name) .. n, name = name, class = class, list = { b }, unit = units[i] }
                    end
                end
            end
        end
        B.status[class] = st
    end
    ns.Fire("LG_BLESSINGS")
end

function B.Test(seconds)
    seconds = seconds or 180
    B.test = GetTime() + seconds
    wipe(B.paladins)
    wipe(classUnits)
    for class, count in pairs(TEST_RAID) do
        classUnits[class] = {}
        for i = 1, count do classUnits[class][i] = ("lgtest-%s-%d"):format(class:lower(), i) end
    end
    local me = Names.Me()
    local full = { kings = 2, might = 2, wisdom = 2 }
    B.paladins[me] = { key = me, name = Names.Unit("player") or Names.Display(me), unit = "player", addon = "lg", me = true,
        can = isPaladin() and B.OwnSkills() or full, set = { WARRIOR = "might", ROGUE = "might", HUNTER = "might" } }
    B.paladins["test lightbringer"] = { key = "test lightbringer", name = "Test Lightbringer", addon = "lg", can = full,
        set = { WARRIOR = "kings", ROGUE = "kings", PRIEST = "kings", MAGE = "kings" } }
    B.paladins["test silverhand"] = { key = "test silverhand", name = "Test Silverhand", addon = "lg", can = { kings = 0, might = 2, wisdom = 2 },
        set = { PRIEST = "wisdom", MAGE = "wisdom", WARLOCK = "wisdom", DRUID = "wisdom" } }
    B.paladins["test pallypower"] = { key = "test pallypower", name = "Test PallyPower", addon = "pp", can = full, set = {} }
    B.TestScan()
    if ns.BlessingsBar then ns.BlessingsBar.Update() end
    ns.Window.Show("blessings")
    ns.Print(L.TEST_TAG .. " " .. L.BLESS_TEST_ON:format(math.floor(seconds / 60)))
    ns.After(seconds, function()
        if not B.test or GetTime() < B.test - 1 then return end
        B.StopTest()
    end)
end

function B.StopTest()
    if not B.test then return end
    B.test = nil
    wipe(B.paladins)
    wipe(B.status)
    wipe(B.missing)
    rosterChanged()
    if wanted() then B.Scan() else ns.Fire("LG_BLESSINGS") end
    ns.AfterCombat("bless-bar", function() if ns.BlessingsBar then ns.BlessingsBar.Update() end end)
    ns.Print(L.TEST_TAG .. " " .. L.BLESS_TEST_OFF)
end
