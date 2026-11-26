-- Loot council: configuration, sessions, responses, votes, awards, history
local _, ns = ...
local Council = ns.NewModule("lootcouncil")
ns.Council = Council
local L, Names, Comm, Items = ns.L, ns.Names, ns.Comm, ns.Items

Council.session = nil
Council.pending = {}      -- items queued by the loot master before a session

---------------------------------------------------------------------------
-- Configuration (per guild, editable in game, shareable with the guild)
---------------------------------------------------------------------------
local DEFAULT_RESPONSES = {
    { k = "bis",   t = "BiS",      c = { 0.95, 0.55, 0.15 } },
    { k = "up",    t = "Upgrade",  c = { 0.35, 0.80, 0.35 } },
    { k = "os",    t = "Offspec",  c = { 0.35, 0.65, 0.95 } },
    { k = "greed", t = "Greed",    c = { 0.80, 0.80, 0.80 } },
    { k = "pass",  t = "Pass",     c = { 0.50, 0.50, 0.50 } },
}

function Council.Config()
    local gdb = ns.Database.Guild()
    if not gdb.lc then
        gdb.lc = {
            minRank = 1, names = {}, lootMaster = "", quality = 4, timeout = 120,
            announce = true, multiVote = false, selfVote = true, t = 0,
            responses = CopyTable and CopyTable(DEFAULT_RESPONSES) or ns.Serialize.Unpack(ns.Serialize.Pack(DEFAULT_RESPONSES)),
        }
    end
    -- 1.0.81 (Ben): the council may vote for themselves by default – switched on once
    -- for existing setups; a setup shared later (also "off") is kept as it is
    if not gdb.lcSelfVoteOn then
        gdb.lcSelfVoteOn = true
        gdb.lc.selfVote = true
    end
    return Council.Upgrade(gdb.lc)
end

local DEFAULT_REASONS = { en = { "Disenchant", "Guild bank", "Free roll" } }
local EXTRA_COLORS = { { 0.9, 0.3, 0.6 }, { 0.6, 0.4, 0.9 }, { 0.3, 0.8, 0.8 } }

-- Fills fields added after the first version
function Council.Upgrade(cfg)
    if type(cfg.reasons) ~= "table" then
        cfg.reasons = CopyTable and CopyTable(DEFAULT_REASONS.en)
            or { "Disenchant", "Guild bank", "Free roll" }
    end
    if cfg.rolls == nil then cfg.rolls = true end
    if cfg.whispers == nil then cfg.whispers = true end
    return cfg
end

function Council.AddResponse()
    local cfg = Council.Config()
    if #cfg.responses >= 8 then return end
    local n = #cfg.responses + 1
    local color = EXTRA_COLORS[(n % #EXTRA_COLORS) + 1]
    table.insert(cfg.responses, #cfg.responses, { k = "r" .. ns.Now() .. n, t = L.LC_NEW_BUTTON, c = { color[1], color[2], color[3] } })
    Council.ConfigChanged()
end

function Council.RemoveResponse(index)
    local cfg = Council.Config()
    if #cfg.responses <= 2 or not cfg.responses[index] then return end
    table.remove(cfg.responses, index)
    Council.ConfigChanged()
end

function Council.ConfigChanged()
    Council.Config().t = ns.Now()
end

-- Is `key` a council member under `cfg`?
function Council.IsCouncilMember(key, cfg)
    cfg = cfg or Council.Config()
    if not key then return false end
    for _, name in ipairs(cfg.names or {}) do
        if Names.Same(Names.Key(name), key) then return true end
    end
    if cfg.lootMaster and cfg.lootMaster ~= "" and Names.Same(Names.Key(cfg.lootMaster), key) then return true end
    local g = ns.Guild.Find(key)
    return g ~= nil and g.rankIndex ~= nil and g.rankIndex <= (cfg.minRank or 1)
end

-- Who distributes loot: configured loot master, master looter, or raid leader
-- loot method of the group: isMaster, partyID, raidID of the master looter.
-- Unknown values never count as master loot.
local function lootMethod()
    if GetLootMethod then
        local m, p, r = ns.Call(GetLootMethod)
        if m ~= nil then return m == "master", p, r end
    end
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local m, p, r = ns.Call(C_PartyInfo.GetLootMethod)
        if m == nil then return false end
        local E = Enum and Enum.LootMethod
        local master = E and (E.Masterlooter or E.MasterLooter or E.Master)
        if master == nil then master = 2 end   -- Enum.LootMethod.Masterlooter
        return m == master or m == "master", p, r
    end
    return false
end
Council.LootMethod = lootMethod

function Council.LootMasterKey()
    local cfg = Council.Config()
    if cfg.lootMaster and cfg.lootMaster ~= "" then
        local key = Names.Key(cfg.lootMaster)
        if ns.UnitForKey(key) then return key end
    end
    do
        local isMaster, partyID, raidID = lootMethod()
        if isMaster then
            local unit = (raidID and raidID > 0 and "raid" .. raidID) or (partyID == 0 and "player") or (partyID and "party" .. partyID)
            local name = unit and Names.Unit(unit)
            if name then return Names.Key(name) end
        end
    end
    for unit, key in ns.GroupUnits() do
        if ns.Call(UnitIsGroupLeader, unit) then return key end
    end
    return Names.Me()
end

-- true only when the group uses master loot and I am the master looter
function Council.IsMasterLooter()
    if not IsInGroup() then return false end
    local isMaster, partyID, raidID = lootMethod()
    if not isMaster then return false end
    local me = Names.Me()
    -- in a raid the roster says directly who is master looter
    if IsInRaid() and GetRaidRosterInfo then
        for i = 1, (GetNumGroupMembers() or 0) do
            local name, _, _, _, _, _, _, _, _, _, isML = ns.Call(GetRaidRosterInfo, i)
            if name and Names.Same(Names.Key(name), me) and type(isML) == "boolean" then return isML end
        end
    end
    if partyID == 0 then return true end
    local unit = (raidID and raidID > 0 and "raid" .. raidID) or (partyID and partyID > 0 and "party" .. partyID)
    local name = unit and Names.Unit(unit)
    return name ~= nil and Names.Same(Names.Key(name), me)
end

function Council.IAmLootMaster()
    if not IsInGroup() then return false end
    return Names.Same(Council.LootMasterKey(), Names.Me())
end

function Council.ResponseInfo(key, session)
    local list = (session and session.responses) or Council.Config().responses
    for i, r in ipairs(list) do
        if r.k == key then return r, i end
    end
    if key == "none" then return { k = "none", t = L.LC_NO_RESPONSE, c = { 0.5, 0.5, 0.5 } }, 99 end
    if key == "wait" then return { k = "wait", t = L.LC_WAITING, c = { 0.6, 0.6, 0.6 } }, 98 end
    if key == "autopass" then return { k = key, t = L.LC_AUTOPASSED, c = { 0.45, 0.45, 0.45 } }, 96 end
    local reason = type(key) == "string" and key:match("^reason:(.+)$")
    if reason then return { k = key, t = reason, c = { 0.75, 0.6, 0.9 } }, 95 end
    return { k = key, t = key, c = { 0.7, 0.7, 0.7 } }, 97
end

---------------------------------------------------------------------------
-- Sending helpers
---------------------------------------------------------------------------
local function channel(session)
    session = session or Council.session
    return session and session.test and "LOCAL" or "GROUP"
end

local function send(kind, data, session)
    return Comm.Send(kind, data, channel(session), { priority = "alert", loopback = true })
end

---------------------------------------------------------------------------
-- Session state
---------------------------------------------------------------------------
local function newSession(data, test)
    local s = {
        id = data.id, ml = data.ml, items = {}, council = data.council or {}, responses = data.responses or Council.Config().responses,
        timeout = data.timeout or 120, started = data.started or ns.Now(), test = test, multiVote = data.multiVote,
        selfVote = data.selfVote, rolls = data.rolls, cand = {}, votes = {}, mine = {}, receivedAt = GetTime(),
    }
    for i, item in ipairs(data.items or {}) do
        s.items[i] = { s = item.s, awarded = item.awarded, ar = item.ar }
        s.cand[i] = {}
        s.votes[i] = {}
    end
    return s
end

function Council.AmCouncil(session)
    session = session or Council.session
    if not session then return false end
    local me = Names.Me()
    if Names.Same(session.ml, me) then return true end
    for _, key in ipairs(session.council) do
        if Names.Same(key, me) then return true end
    end
    return false
end

function Council.AmML(session)
    session = session or Council.session
    return session ~= nil and Names.Same(session.ml, Names.Me())
end

local function changed()
    ns.Fire("LG_COUNCIL")
end

-- Starts a session with the given item strings/links (loot master only)
function Council.Start(itemList, test)
    if Council.session and not Council.session.ended then
        ns.Print(L.LC_ALREADY_RUNNING)
        return
    end
    if not test then
        if not IsInGroup() then ns.Print(L.NOT_IN_GROUP); return end
        if not Council.IAmLootMaster() then ns.Print(L.LC_NOT_ML); return end
    end
    local items = {}
    for _, item in ipairs(itemList) do
        local s = Items.String(item) or item
        if s then items[#items + 1] = { s = s } end
    end
    if #items == 0 then ns.Print(L.LC_NO_ITEMS); return end
    local cfg = Council.Config()
    local council = {}
    local me = Names.Me()
    if test then
        council[1] = me
    else
        for _, key in ns.GroupUnits() do
            if Council.IsCouncilMember(key, cfg) then council[#council + 1] = key end
        end
        local found = false
        for _, key in ipairs(council) do if Names.Same(key, me) then found = true end end
        if not found then council[#council + 1] = me end
    end
    local data = {
        id = me .. ":" .. ns.Now(), ml = me, items = items, council = council, responses = cfg.responses,
        timeout = cfg.timeout, started = ns.Now(), multiVote = cfg.multiVote, selfVote = cfg.selfVote, rolls = cfg.rolls,
    }
    wipe(Council.pending)
    send("LS", { s = data }, { test = test })
    return data
end

function Council.End()
    local s = Council.session
    if not s then return end
    if Council.AmML(s) then send("LE", { id = s.id }, s) end
    s.ended = true
    changed()
    -- the loot master shares this session's awards with the whole guild (also members outside the raid)
    if Council.AmML(s) and not s.test and IsInGuild() then
        local batch = {}
        for _, r in ipairs(ns.Database.Guild().lootHistory) do
            if type(r.id) == "string" and r.id:sub(1, #tostring(s.id) + 1) == tostring(s.id) .. ":" then batch[#batch + 1] = r end
        end
        if #batch > 0 then
            ns.After(3, function() Comm.Send("HB", { list = batch }, "GUILD", { priority = "bulk" }) end)
        end
    end
end

-- Our answer for item i
function Council.Respond(i, response, note)
    local s = Council.session
    if not s or not s.items[i] or s.ended then return end
    local item = s.items[i]
    local equipped = {}
    local info = Items.Info(item.s)
    local slots = info and Items.EQUIP_SLOTS[info.equipLoc]
    for _, slot in ipairs(slots or {}) do
        local link = ns.Call(GetInventoryItemLink, "player", slot)
        local str = Items.String(link)
        if str then equipped[#equipped + 1] = str end
    end
    local me = ns.Database.Member(Names.Me())
    local _, class = ns.Call(UnitClass, "player")
    s.mine[i] = response
    s.myRolls = s.myRolls or {}
    s.myRolls[i] = s.myRolls[i] or math.random(1, 100)
    send("LR", { id = s.id, i = i, r = response, n = note ~= "" and note or nil, g = equipped,
        il = me and me.il, c = class, name = Names.Unit("player"), roll = s.myRolls[i] }, s)
    changed()
end

function Council.Vote(i, candidate, on)
    local s = Council.session
    if not s or s.ended or not Council.AmCouncil(s) then return end
    send("LV", { id = s.id, i = i, c = candidate, on = on and true or false }, s)
end

function Council.Award(i, candidate, reason)
    local s = Council.session
    if not s or not Council.AmML(s) then return end
    local cand = s.cand[i] and s.cand[i][candidate]
    local r = reason and ("reason:" .. reason) or (cand and cand.r or "none")
    send("LA", { id = s.id, i = i, c = candidate, r = r, name = cand and cand.name }, s)
end

-- Clears the votes of an item (council can vote again)
function Council.ResetVotes(i)
    local s = Council.session
    if not s or not Council.AmML(s) then return end
    send("LX", { id = s.id, i = i }, s)
end

-- Re-sends the session to the group (for people who missed it)
function Council.Reannounce()
    local s = Council.session
    if not s or s.ended or not Council.AmML(s) or s.test then return end
    local items = {}
    for i, item in ipairs(s.items) do items[i] = { s = item.s, awarded = item.awarded, ar = item.ar } end
    Comm.Send("LS", { s = { id = s.id, ml = s.ml, items = items, council = s.council, responses = s.responses, timeout = s.timeout,
        started = s.started, multiVote = s.multiVote, selfVote = s.selfVote, rolls = s.rolls } }, "GROUP", { priority = "alert" })
    ns.Print(L.LC_REANNOUNCED)
end

---------------------------------------------------------------------------
-- Loot master tools (right-click menu in the council window, like RCLC)
---------------------------------------------------------------------------
local function mlSession()
    local s = Council.session
    if s and not s.ended and Council.AmML(s) then return s end
end

-- Sets a candidate's response (e.g. after a whisper or a misclick)
function Council.ChangeResponse(i, candidate, response, name, class)
    local s = mlSession()
    if not s or not s.items[i] then return end
    send("LCR", { id = s.id, i = i, c = candidate, r = response, name = name, cl = class }, s)
end

-- Asks candidates to answer again: one item or all (i = nil), one candidate or everybody (to = nil)
function Council.Reask(i, to)
    local s = mlSession()
    if not s then return end
    send("LN", { id = s.id, i = i, to = to }, s)
    ns.Print(L.LC_REASKED)
end

-- Removes a candidate from consideration (or brings them back)
function Council.SetRemoved(i, candidate, removed)
    local s = mlSession()
    if not s or not s.items[i] then return end
    send("LD", { id = s.id, i = i, c = candidate, on = removed and true or false }, s)
end

-- Gives the item to the loot master to hand out later
function Council.AwardLater(i)
    local s = mlSession()
    if not s then return end
    Council.Award(i, s.ml, L.LC_AWARD_LATER)
end

-- Random rolls 1-100 for every candidate without one
function Council.AddRolls(i)
    local s = mlSession()
    if not s or not s.cand[i] then return end
    local rolls = {}
    for key, c in pairs(s.cand[i]) do if not c.roll then rolls[key] = math.random(1, 100) end end
    send("LRL", { id = s.id, i = i, rolls = rolls }, s)
end

-- Asks candidates to /roll; the results from the chat are recorded
function Council.RequestRoll(i, to)
    local s = mlSession()
    if not s or not s.cand[i] then return end
    s.rollRequests = s.rollRequests or {}
    local wanted = {}
    if to then wanted[to] = true else for key in pairs(s.cand[i]) do wanted[key] = true end end
    s.rollRequests[i] = { keys = wanted, untilTime = GetTime() + 60 }
    send("LRR", { id = s.id, i = i, to = to }, s)
    if not s.test then
        local link = Items.Link(s.items[i].s) or "?"
        local chatType = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
        if chatType and not to then ns.SendChat(L.LC_ROLL_ANNOUNCE:format(link), chatType) end
        if to then ns.SendChat(L.LC_ROLL_ANNOUNCE:format(link), "WHISPER", (ns.Guild.Find(to) or {}).name or to) end
    end
end

-- Posts the item and the current standings to raid chat
function Council.PostStandings(i)
    local s = Council.session
    if not s or not s.items[i] then return end
    local link = Items.Link(s.items[i].s) or "?"
    local list = {}
    for key, c in pairs(s.cand[i]) do
        local info, order = Council.ResponseInfo(c.r, s)
        if not c.removed and order < 90 and c.r ~= "pass" then list[#list + 1] = { name = Names.Display(c.name or key), t = info.t, o = order } end
    end
    table.sort(list, function(a, b) if a.o ~= b.o then return a.o < b.o end return a.name < b.name end)
    local parts = {}
    for j, e in ipairs(list) do if j <= 8 then parts[#parts + 1] = e.name .. " (" .. e.t .. ")" end end
    local chatType = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if chatType then ns.SendChat(link .. ": " .. (#parts > 0 and table.concat(parts, ", ") or L.LC_NO_ANSWERS), chatType) end
end

---------------------------------------------------------------------------
-- Can the player use this item? (armor and weapon proficiencies)
---------------------------------------------------------------------------
local ARMOR = { -- highest armor subclass per class: 1 cloth, 2 leather, 3 mail, 4 plate
    WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
local weaponSet = {}
for class, list in pairs(WEAPONS) do
    weaponSet[class] = {}
    for _, id in ipairs(list) do weaponSet[class][id] = true end
end

function Council.CanUse(item, class)
    if not class then class = select(2, ns.Call(UnitClass, "player")) end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, equipLoc, _, classID, subclassID = ns.Call(instant, item)
    if not classID or not class or not ARMOR[class] then return true end
    if classID == 4 then
        if equipLoc == "INVTYPE_CLOAK" or subclassID == 0 then return true end
        if subclassID == 6 then return SHIELD[class] == true end
        if RELIC[subclassID] then return RELIC[subclassID] == class end
        if subclassID >= 1 and subclassID <= 4 then return subclassID <= ARMOR[class] end
        return true
    elseif classID == 2 then
        if subclassID == 14 or subclassID == 20 then return true end -- misc, fishing poles
        return weaponSet[class][subclassID] == true
    end
    return true
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------
local function senderMayLead(sender, channelName)
    if channelName == "LOCAL" then return true end
    local unit = ns.UnitForKey(sender)
    if not unit then return false end
    if ns.IsGroupLead(unit) then return true end
    return Names.Same(Council.LootMasterKey(), sender)
end

Comm.Register("LS", function(data, sender, ch)
    local d = data.s
    if type(d) ~= "table" or type(d.items) ~= "table" or not d.id then return end
    if not senderMayLead(sender, ch) then return end
    if Council.session and Council.session.id == d.id then return end
    Council.session = newSession(d, ch == "LOCAL")
    Council.session.ml = sender
    Council.session.mlRaw = sender
    changed()
    ns.Fire("LG_COUNCIL_START", Council.session)
end)

local function current(id)
    local s = Council.session
    if s and s.id == id then return s end
end

Comm.Register("LR", function(data, sender, ch)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.cand[i] then return end
    local key = (ch == "LOCAL" and data.fake) or sender
    -- answers whispered to the loot master by players without the addon
    if data.relay and Names.Same(sender, s.ml) then key = Names.Key(data.relay) or key end
    s.cand[i][key] = {
        r = tostring(data.r or "none"), n = data.n, g = type(data.g) == "table" and data.g or {},
        il = tonumber(data.il), c = data.c, name = data.name or key, t = ns.Now(), roll = tonumber(data.roll),
        whisper = data.relay and true or nil,
    }
    changed()
end)

Comm.Register("LV", function(data, sender)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.votes[i] or type(data.c) ~= "string" then return end
    local isCouncil = Names.Same(s.ml, sender)
    for _, key in ipairs(s.council) do if Names.Same(key, sender) then isCouncil = true end end
    if not isCouncil then return end
    if not s.selfVote and Names.Same(data.c, sender) then return end
    local votes = s.votes[i]
    if data.on and not s.multiVote then
        for _, voters in pairs(votes) do voters[sender] = nil end
    end
    votes[data.c] = votes[data.c] or {}
    votes[data.c][sender] = data.on and true or nil
    changed()
end)

-- last killed boss (for the export's boss column); counts for 15 minutes
local lastBoss, lastBossTime = nil, 0
ns.On("ENCOUNTER_END", function(_, _, name, _, _, success)
    if success == 1 or success == true then lastBoss, lastBossTime = name, ns.Now() end
end)
function Council.LastBoss()
    return (lastBoss and ns.Now() - lastBossTime < 900) and lastBoss or nil
end

-- Deleted history entries: [record id] = { t = when, by = who deleted it }.
-- Valid when an officer deleted it, or the loot master who gave the item out.
local REMOVED_KEEP = 180 * 86400
local function removedStore()
    local g = ns.Database.Guild()
    g.lootRemoved = g.lootRemoved or {}
    return g.lootRemoved
end
local function deleteValid(by, record)
    if type(by) ~= "string" then return false end
    if ns.Guild.IsOfficer(by) then return true end
    return record ~= nil and type(record.by) == "string" and Names.Same(record.by, by)
end

local function historyAdd(record)
    if type(record) ~= "table" or not record.id or not record.i then return false end
    local tomb = removedStore()[record.id]
    if type(tomb) == "table" and deleteValid(tomb.by, record) then return false end
    local list = ns.Database.Guild().lootHistory
    for _, r in ipairs(list) do if r.id == record.id then return false end end
    list[#list + 1] = record
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #list > 1500 do table.remove(list, 1) end
    ns.Debounce("lc-history-redraw", 0.5, function() ns.Window.Refresh("council") end)
    return true
end
Council.HistoryAdd = historyAdd

-- test records of /lg test lchistory: only in memory, never stored or sent
Council.testHistory = {}

-- may I delete this record (for the whole guild)?
function Council.CanDeleteRecord(r)
    if not r then return false end
    if r.testOnly then return true end
    if not IsInGuild() then return false end
    return ns.Guild.IsOfficer(Names.Me()) or (type(r.by) == "string" and Names.Same(r.by, Names.Me()))
end

-- deletes records here: ids, by = who deleted them; returns how many went
local function applyRemove(ids, by, t)
    local store, list = removedStore(), ns.Database.Guild().lootHistory
    local drop, n = {}, 0
    for _, id in ipairs(ids) do
        if type(id) == "string" and #id <= 120 then
            if not store[id] then store[id] = { t = t or ns.Now(), by = by } end
            drop[id] = true
        end
    end
    for i = #list, 1, -1 do
        local r = list[i]
        if drop[r.id] and deleteValid(by, r) then table.remove(list, i); n = n + 1 end
    end
    ns.Debounce("lc-history-redraw", 0.2, function() ns.Window.Refresh("council") end)
    return n
end

-- officers (everything) and loot masters (their own awards): delete for the whole guild
function Council.RemoveHistory(records)
    local ids, shared, n = {}, {}, 0
    for _, r in ipairs(records or {}) do
        if r.testOnly then
            for i = #Council.testHistory, 1, -1 do
                if Council.testHistory[i] == r then table.remove(Council.testHistory, i); n = n + 1 end
            end
        elseif Council.CanDeleteRecord(r) then
            ids[#ids + 1] = r.id
            shared[#shared + 1] = r.id
        end
    end
    if #ids > 0 then n = n + applyRemove(ids, Names.Me()) end
    for i = 1, #shared, 30 do
        local part = {}
        for j = i, math.min(i + 29, #shared) do part[#part + 1] = shared[j] end
        Comm.Send("HD", { r = part }, "GUILD", { priority = "normal" })
    end
    ns.Debounce("lc-history-redraw", 0.2, function() ns.Window.Refresh("council") end)
    return n
end

-- deletions from the guild: each record checks who deleted it
Comm.Register("HD", function(data, sender, channel)
    if channel ~= "GUILD" or type(data.r) ~= "table" or not ns.Guild.IsMember(sender) then return end
    local ids = {}
    for i, id in ipairs(data.r) do
        if i > 60 then break end
        if type(id) == "string" then ids[#ids + 1] = id end
    end
    applyRemove(ids, sender)
end)

-- deletions passed on with the history at login (only from the member answering our request)
Comm.Register("HR", function(data, sender, channel)
    if channel ~= "WHISPER" or type(data.r) ~= "table" or not ns.Guild.IsMember(sender) then return end
    if not Comm.Expected("lc-history-sync", sender) then return end
    for i, x in ipairs(data.r) do
        if i > 200 then break end
        if type(x) == "table" and type(x.k) == "string" and type(x.by) == "string" then
            local t = tonumber(x.t)
            applyRemove({ x.k }, x.by, t and math.min(t, ns.Now()) or nil)
        end
    end
end)

Comm.Register("LA", function(data, sender)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.items[i] or not Names.Same(s.ml, sender) then return end
    local item = s.items[i]
    item.awarded, item.ar = data.c, data.r
    local votes = 0
    for _ in pairs(s.votes[i] and s.votes[i][data.c] or {}) do votes = votes + 1 end
    local info = Council.ResponseInfo(data.r, s)
    local zone, _, diff, _, size, _, _, mapID = ns.Call(GetInstanceInfo)
    local record = { id = s.id .. ":" .. i, t = ns.Now(), i = item.s, to = data.c, r = info.t, rk = data.r, by = s.ml, v = votes, test = s.test,
        z = zone, d = diff, m = mapID, gs = size, b = Council.LastBoss() }
    if not s.test then historyAdd(record) end
    if Names.Same(data.c, Names.Me()) then
        ns.UI.Toast(L.LC_YOU_WON, Items.Link(item.s), Items.Icon(item.s))
    end
    if Council.AmML(s) and not s.test then
        if IsInGuild() then
            Comm.Send("LH", { h = record }, "GUILD", { priority = "bulk" })
            ns.Feed.Add({ id = "lc:" .. record.id, t = record.t, k = "lc", a = data.c,
                d = { i = item.s, r = info.t, m = record.b, ins = type(zone) == "string" and zone ~= "" and zone or nil, v = votes } }, { broadcast = true })
        end
        if Council.Config().announce then
            local text = L.LC_ANNOUNCE:format(Items.Link(item.s) or "?", Names.Display(data.name or data.c), info.t)
            ns.AfterCombat("lc-announce-" .. record.id, function()
                local chatType = Council.AnnounceChannel()
                if chatType then ns.SendChat(text, chatType) end
            end)
        end
    elseif s.test and Council.AmML(s) then
        ns.Print(L.LC_TEST_AWARD:format(Items.Link(item.s) or "?", Names.Display(data.name or data.c), info.t))
    end
    changed()
end)

Comm.Register("LX", function(data, sender)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.votes[i] or not Names.Same(s.ml, sender) then return end
    s.votes[i] = {}
    changed()
end)

Comm.Register("LCR", function(data, sender)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.cand[i] or not Names.Same(s.ml, sender) or type(data.c) ~= "string" then return end
    local c = s.cand[i][data.c]
    if not c then
        c = { g = {}, name = data.name or data.c, c = data.cl, t = ns.Now() }
        s.cand[i][data.c] = c
    end
    c.r = tostring(data.r or "none")
    c.changed = true
    changed()
end)

Comm.Register("LN", function(data, sender)
    local s = current(data.id)
    if not s or not Names.Same(s.ml, sender) then return end
    local i = tonumber(data.i)
    local me = Names.Me()
    for idx in ipairs(s.items) do
        if (not i or idx == i) and not s.items[idx].awarded then
            if data.to then s.cand[idx][data.to] = nil else s.cand[idx] = {} end
            if not data.to or Names.Same(data.to, me) then s.mine[idx] = nil end
        end
    end
    changed()
    if (not data.to or Names.Same(data.to, me)) and ns.CouncilPopup then ns.CouncilPopup.Show() end
end)

Comm.Register("LD", function(data, sender)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.cand[i] or not Names.Same(s.ml, sender) then return end
    local c = s.cand[i][data.c]
    if c then c.removed = data.on or nil; changed() end
end)

Comm.Register("LRL", function(data, sender)
    local s = current(data.id)
    local i = tonumber(data.i)
    if not s or not i or not s.cand[i] or not Names.Same(s.ml, sender) or type(data.rolls) ~= "table" then return end
    for key, roll in pairs(data.rolls) do
        local c = s.cand[i][key]
        if c and tonumber(roll) then c.roll = tonumber(roll) end
    end
    changed()
end)

-- Roll request: our client rolls (the loot master reads the result from the chat)
Comm.Register("LRR", function(data, sender)
    local s = current(data.id)
    if not s or not Names.Same(s.ml, sender) then return end
    if data.to and not Names.Same(data.to, Names.Me()) then return end
    local i = tonumber(data.i)
    if not data.to and i and s.cand[i] and not s.cand[i][Names.Me()] then return end
    if s.test then return end
    ns.UI.Toast(L.LC_ROLL_REQUESTED, Items.Link(s.items[i] and s.items[i].s or "") or "", Items.Icon(s.items[i] and s.items[i].s))
    if RandomRoll then ns.Call(RandomRoll, 1, 100) end
end)

local rollPattern
ns.On("CHAT_MSG_SYSTEM", function(_, text)
    local s = Council.session
    if not s or not s.rollRequests or ns.IsSecret(text) or type(text) ~= "string" or not Council.AmML(s) then return end
    if rollPattern == nil then
        rollPattern = false
        local fmt = RANDOM_ROLL_RESULT
        if type(fmt) == "string" then
            local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
            rollPattern = "^" .. p .. "$"
        end
    end
    if not rollPattern then return end
    local who, roll, low, high = text:match(rollPattern)
    roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
    if not who or not roll or low ~= 1 or high ~= 100 then return end
    local key = Names.Key(who)
    for i, req in pairs(s.rollRequests) do
        if GetTime() < req.untilTime and s.cand[i] then
            for wanted in pairs(req.keys) do
                if Names.Same(wanted, key) or Names.Same(Names.First(wanted) or "", key) then
                    local c = s.cand[i][wanted]
                    if c and not c.rolled then
                        c.roll, c.rolled = roll, true
                        send("LRL", { id = s.id, i = i, rolls = { [wanted] = roll } }, s)
                    end
                end
            end
        end
    end
end)

Comm.Register("LE", function(data, sender)
    local s = current(data.id)
    if not s or not Names.Same(s.ml, sender) then return end
    s.ended = true
    changed()
end)

-- Records from other players: cleaned, and only accepted from the loot master
-- who gave the item (the record id starts with the session id = loot master key)
local FUTURE, LIVE_AGE = 120, 1800
local function cleanRecord(raw)
    if type(raw) ~= "table" then return nil end
    local r = ns.Clean(raw, 2)
    if type(r.id) ~= "string" or #r.id > 120 or type(r.i) ~= "string" or type(r.t) ~= "number"
        or type(r.by) ~= "string" or type(r.to) ~= "string" then return nil end
    if r.id:sub(1, #r.by + 1) ~= r.by .. ":" then return nil end
    if r.t > ns.Now() + FUTURE then return nil end
    r.test = nil
    return r
end
Council.CleanRecord = cleanRecord

Comm.Register("LH", function(data, sender, channel)
    if channel ~= "GUILD" then return end
    local r = cleanRecord(data.h)
    if r and Names.Same(r.by, sender) and r.t >= ns.Now() - LIVE_AGE then historyAdd(r) end
end)

-- Late joiners and /reload: ask the loot master for the full state
Comm.Register("LQ", function(_, _, _, raw)
    local s = Council.session
    if not s or s.ended or s.test or not Council.AmML(s) then return end
    local items = {}
    for i, item in ipairs(s.items) do items[i] = { s = item.s, awarded = item.awarded, ar = item.ar } end
    Comm.Send("LF", { s = { id = s.id, ml = s.ml, items = items, council = s.council, responses = s.responses,
        timeout = s.timeout, started = s.started, multiVote = s.multiVote, selfVote = s.selfVote },
        cand = s.cand, votes = s.votes }, "WHISPER", { target = raw, priority = "normal" })
end)

Comm.Register("LF", function(data, sender)
    local d = data.s
    if type(d) ~= "table" or not d.id or not senderMayLead(sender, "GROUP") then return end
    local s = newSession(d, false)
    s.ml = sender
    if type(data.cand) == "table" then for i, c in pairs(data.cand) do if s.cand[i] then s.cand[i] = c end end end
    if type(data.votes) == "table" then for i, v in pairs(data.votes) do if s.votes[i] then s.votes[i] = v end end end
    Council.session = s
    changed()
    ns.Fire("LG_COUNCIL_START", s)
end)

-- Config sharing with the guild (only accepted from council members)
function Council.ShareConfig()
    local cfg = Council.Config()
    if not Council.IsCouncilMember(Names.Me(), cfg) then ns.Print(L.LC_SHARE_DENIED); return end
    if cfg.t == 0 then cfg.t = ns.Now() end
    Comm.Send("LCC", { cfg = cfg }, "GUILD", { priority = "normal" })
    ns.Print(L.LC_SHARED)
end

Comm.Register("LCC", function(data, sender)
    local cfg = data.cfg
    if type(cfg) ~= "table" or type(cfg.responses) ~= "table" then return end
    local mine = Council.Config()
    if not Council.IsCouncilMember(sender, mine) then return end
    if (cfg.t or 0) <= (mine.t or 0) then return end
    local gdb = ns.Database.Guild()
    gdb.lc = cfg
    ns.Print(L.LC_CONFIG_RECEIVED:format(Names.Display(sender)))
    ns.Window.Refresh("council")
end)

ns.On("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() and Council.session and not Council.session.test then
        Council.session.ended = true
        changed()
    end
end)

function Council:OnLogin()
    ns.After(10, function()
        if IsInGroup() and not Council.session then Comm.Send("LQ", {}, "GROUP", { priority = "normal" }) end
    end)
end

---------------------------------------------------------------------------
-- Loot window: offer to start a session with the epic items
---------------------------------------------------------------------------
local lootButton
-- Where awards are announced: raid warning needs lead or assist, else raid chat
function Council.AnnounceChannel()
    local want = Council.Config().announceChannel or "RAID"
    if want == "NONE" then return nil end
    if not IsInGroup() then return nil end
    if not IsInRaid() then return "PARTY" end
    if want == "RAID_WARNING" then
        local lead = ns.Call(UnitIsGroupLeader, "player") == true or ns.Call(UnitIsGroupAssistant, "player") == true
        return lead and "RAID_WARNING" or "RAID"
    end
    return "RAID"
end

---------------------------------------------------------------------------
-- Loot master options (personal): ignore rules and automatic assignment
---------------------------------------------------------------------------
function Council.MLOptions()
    local st = ns.Database.Settings()
    st.lcML = st.lcML or {}
    local o = st.lcML
    if o.ignoreLegendary == nil then o.ignoreLegendary = true end
    if o.ignoreBoP == nil then o.ignoreBoP = false end
    if o.ignoreBoE == nil then o.ignoreBoE = false end
    o.ignore = o.ignore or ""        -- item ids or names, comma separated
    o.assign = o.assign or {}        -- [quality] = "" | "me" | player name
    if o.autoAssign == nil then o.autoAssign = false end
    return o
end

local function bindType(s)
    return select(14, ns.Call((C_Item and C_Item.GetItemInfo) or GetItemInfo, s))
end

-- true when the item must not go into a council session
function Council.IsIgnored(s, info)
    local o = Council.MLOptions()
    info = info or Items.Info(s)
    if not info then return false end
    if o.ignoreLegendary and (info.quality or 0) >= 5 then return true end
    local bind = bindType(s)
    if o.ignoreBoP and bind == 1 then return true end
    if o.ignoreBoE and bind == 2 then return true end
    local id = Items.ID(s)
    for part in o.ignore:gmatch("[^,;]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" and (tonumber(part) == id or (info.name and info.name:lower() == part:lower())) then return true end
    end
    return false
end

-- target name for an item of this quality ("me" = yourself), or nil
local function assignTarget(quality)
    local o = Council.MLOptions()
    if not o.autoAssign then return nil end
    local t = o.assign[quality]
    if not t or t == "" then return nil end
    if t == "me" then return Names.Unit("player") end
    return t
end

-- Gives loot slots to the configured players (master loot only)
function Council.AutoAssign()
    if not GiveMasterLoot or not GetMasterLootCandidate then return 0 end
    local method = GetLootMethod and ns.Call(GetLootMethod)
    if method and method ~= "master" then return 0 end
    local given = 0
    for slot = 1, (ns.Call(GetNumLootItems) or 0) do
        local link = ns.Call(GetLootSlotLink, slot)
        local s = Items.String(link)
        local info = s and Items.Info(s)
        local target = info and assignTarget(info.quality or 0)
        if target and not (Council.MLOptions().ignoreLegendary and (info.quality or 0) >= 5) then
            for i = 1, 40 do
                local cand = ns.Call(GetMasterLootCandidate, slot, i)
                if cand and Names.Same(Names.Key(cand), Names.Key(target)) then
                    ns.Call(GiveMasterLoot, slot, i)
                    given = given + 1
                    break
                end
            end
        end
    end
    return given
end

local function lootItems()
    local items = {}
    local cfg = Council.Config()
    for slot = 1, (ns.Call(GetNumLootItems) or 0) do
        local link = ns.Call(GetLootSlotLink, slot)
        local s = Items.String(link)
        local info = s and Items.Info(s)
        if info and (info.quality or 0) >= (cfg.quality or 4) and not assignTarget(info.quality or 0)
            and not Council.IsIgnored(s, info) then
            items[#items + 1] = s
        end
    end
    return items
end
Council.LootItems = lootItems

ns.On("LOOT_OPENED", function()
    if ns.Database.Settings().modules.council == false then return end
    if not IsInGroup() or not Council.IAmLootMaster() then return end
    ns.Safe(Council.AutoAssign)
    local items = lootItems()
    if #items == 0 then return end
    if not lootButton then
        lootButton = ns.UI.Button(UIParent, "", 220, 26, function()
            local list = lootItems()
            for _, s in ipairs(list) do table.insert(Council.pending, s) end
            lootButton:Hide()
            ns.Fire("LG_COUNCIL")
            ns.CouncilWindow.ShowQueue()
        end)
        lootButton:SetFrameStrata("DIALOG")
    end
    lootButton:ClearAllPoints()
    if LootFrame and LootFrame:IsShown() then
        lootButton:SetPoint("BOTTOMLEFT", LootFrame, "TOPLEFT", 0, 4)
    else
        lootButton:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
    lootButton:SetText(L.LC_ADD_LOOT:format(#items))
    lootButton:Show()
end)
ns.On("LOOT_CLOSED", function() if lootButton then lootButton:Hide() end end)

---------------------------------------------------------------------------
-- Test mode: a local session with fake raiders
---------------------------------------------------------------------------
local FAKE = {
    { "Arwen Silverleaf", "PRIEST" }, { "Borin Ironfist", "WARRIOR" }, { "Celia Morningdew", "MAGE" },
    { "Dorn Shadowpath", "ROGUE" }, { "Elara Stormcall", "SHAMAN" }, { "Finn Greengrove", "DRUID" },
}

-- /lg test lchistory: sample awards of two raid evenings (three sessions), only in
-- memory – never stored or sent; try the evening filter and deleting on them
function Council.TestHistory(off)
    wipe(Council.testHistory)
    if not off then
        local names = { Names.Me() }
        for key in pairs(ns.Database.Guild().members or {}) do
            if #names < 5 and not Names.Same(key, Names.Me()) then names[#names + 1] = key end
        end
        local items = { 16800, 16802, 17069, 18814, 19019, 16916, 19138, 18821 }
        local now = ns.Now()
        local function evening(daysAgo, hour)
            local base = now - daysAgo * 86400
            return base - (tonumber(date("%H", base)) or 0) * 3600 + hour * 3600
        end
        local plan = {
            { t = evening(2, 20), zone = "Molten Core", n = 4 },
            { t = evening(2, 22), zone = "Onyxia's Lair", n = 2 },
            { t = evening(1, 20), zone = "Blackwing Lair", n = 3 },
        }
        local k = 0
        for si, p in ipairs(plan) do
            local sid = Names.Me() .. ":test" .. si
            for i = 1, p.n do
                k = k + 1
                Council.testHistory[#Council.testHistory + 1] = {
                    id = sid .. ":" .. i, t = p.t + i * 300, i = "item:" .. items[(k - 1) % #items + 1], to = names[(k - 1) % #names + 1],
                    r = (k % 3 == 0) and "Offspec" or "Need", by = Names.Me(), v = (k % 3) + 1, z = p.zone, testOnly = true,
                }
            end
        end
        ns.Print(L.TEST_TAG .. " " .. L.LC_TEST_HISTORY:format(#Council.testHistory))
    end
    ns.Window.Refresh("council")
end

function Council.Test()
    if Council.session and not Council.session.ended then Council.session.ended = true end
    local items = {}
    for _, slot in ipairs({ 1, 5, 16, 13 }) do
        local s = Items.String(ns.Call(GetInventoryItemLink, "player", slot))
        if s then items[#items + 1] = s end
    end
    if #items == 0 then items = { "item:19019", "item:16901", "item:18814" } end
    local data = Council.Start(items, true)
    if not data then return end
    ns.Print(L.LC_TEST_STARTED)
    -- the loot master bar is shown during the test (5 min)
    if ns.CouncilBar then
        ns.CouncilBar.testUntil = GetTime() + 300
        ns.CouncilBar.Layout()
        ns.After(301, ns.CouncilBar.Layout)
    end
    local responses = Council.Config().responses
    for f, fake in ipairs(FAKE) do
        for i = 1, #items do
            ns.After(1.5 + f * 0.7 + i * 0.3, function()
                local r = responses[math.random(1, #responses)]
                local key = Names.Key(fake[1])
                Comm.Send("LR", { id = data.id, i = i, r = r.k, fake = key, name = fake[1], c = fake[2],
                    il = math.random(55, 75), g = { items[i] }, n = (math.random() < 0.3) and L.LC_TEST_NOTE or nil }, "LOCAL")
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Whisper answers for raiders without the addon: "!lc 1 bis"
---------------------------------------------------------------------------
local function responseFromWord(s, word)
    if not word or word == "" then return s.responses[1] and s.responses[1].k end
    local n = tonumber(word)
    if n and s.responses[n] then return s.responses[n].k end
    word = word:lower()
    for _, r in ipairs(s.responses) do
        if r.k == word or r.t:lower() == word or r.t:lower():find(word, 1, true) == 1 then return r.k end
    end
end

ns.On("CHAT_MSG_WHISPER", function(_, text, sender)
    if ns.IsSecret(text) or type(text) ~= "string" then return end
    local s = Council.session
    if not s or s.ended or s.test or not Council.AmML(s) or not Council.Config().whispers then return end
    local rest = text:match("^!lc%s*(.-)%s*$")
    if not rest then return end
    if rest == "" or rest == "help" then
        local items = {}
        for i, item in ipairs(s.items) do if not item.awarded then items[#items + 1] = i .. " = " .. (Items.Link(item.s) or "?") end end
        local buttons = {}
        for i, r in ipairs(s.responses) do buttons[#buttons + 1] = i .. "/" .. r.t end
        ns.SendChat(L.LC_WHISPER_HELP:format(table.concat(buttons, ", ")), "WHISPER", sender)
        if #items > 0 then ns.SendChat(table.concat(items, " · "), "WHISPER", sender) end
        return
    end
    local index, word = rest:match("^(%d+)%s*(.*)$")
    index = tonumber(index) or 1
    if not s.items[index] then ns.SendChat(L.LC_WHISPER_BAD, "WHISPER", sender); return end
    local response = responseFromWord(s, word ~= "" and word or nil)
    if not response then ns.SendChat(L.LC_WHISPER_BAD, "WHISPER", sender); return end
    local unit = ns.UnitForKey(Names.Key(sender))
    local _, class = ns.Call(UnitClass, unit or "")
    send("LR", { id = s.id, i = index, r = response, relay = sender, name = Names.Strip(sender), c = class, g = {},
        roll = math.random(1, 100) }, s)
    local info = Council.ResponseInfo(response, s)
    ns.SendChat(L.LC_WHISPER_OK:format(info.t, Items.Link(s.items[index].s) or "?"), "WHISPER", sender)
end)

---------------------------------------------------------------------------
-- Recently looted epics (to start a session from the bags)
---------------------------------------------------------------------------
Council.recent = {}
ns.On("CHAT_MSG_LOOT", function(_, text)
    if ns.IsSecret(text) or type(text) ~= "string" then return end
    local link = text:match("|H(item:[^|]+)|h")
    if not link or not text:find(LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(.-)%%s") or "\0", 1, true) then return end
    local info = Items.Info(link)
    if info and (info.quality or 0) >= (Council.Config().quality or 4) then
        table.insert(Council.recent, { s = Items.String(link), t = ns.Now() })
        while #Council.recent > 30 do table.remove(Council.recent, 1) end
    end
end)

-- Council.AddRecent / adding from the bags: see ItemQueue.lua

-- Trade reminder: which awarded items still go to the trade partner
ns.On("TRADE_SHOW", function()
    local s = Council.session
    if not s or s.test or not Council.AmML(s) then return end
    local partner = Names.Key(Names.Unit("NPC") or "")
    if not partner then return end
    local due = {}
    for _, item in ipairs(s.items) do
        if item.awarded and Names.Same(item.awarded, partner) then due[#due + 1] = Items.Link(item.s) or item.s end
    end
    if #due > 0 then
        ns.Print(L.LC_TRADE_REMINDER:format(Names.Display(partner), table.concat(due, ", ")))
        ns.UI.Toast(L.LC_TRADE_TITLE, table.concat(due, ", "))
    end
end)

---------------------------------------------------------------------------
-- Loot history: export and guild sync
---------------------------------------------------------------------------
-- days: the last n days (0 = all) – or a list of records (one raid evening)
local function historyRange(days)
    if type(days) == "table" then
        local out = {}
        for _, r in ipairs(days) do if not r.test and not r.testOnly then out[#out + 1] = r end end
        return out
    end
    local since = days and days > 0 and (ns.Now() - days * 86400) or 0
    local out = {}
    for _, r in ipairs(ns.Database.Guild().lootHistory) do
        if (r.t or 0) >= since and not r.test then out[#out + 1] = r end
    end
    return out
end

local function csvCell(v, sep)
    v = tostring(v or "")
    if v:find('[' .. sep .. '"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

Council.EXPORT_FORMATS = { "rclc", "gargul", "nota", "csv", "tsv", "discord", "bbcode", "json" }

-- full name with realm, as the import formats expect it
local function fullName(name)
    name = tostring(name or "")
    if name == "" or name:find("-", 1, true) then return name end
    local realm = ns.Call(GetNormalizedRealmName) or (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "")
    return realm ~= "" and (name .. "-" .. realm) or name
end
-- offspec / greed-like answers (for the OS column of Gargul and Nota)
local function isOffspec(r)
    local t = tostring(r.rk or r.r or ""):lower()
    return (t:find("os") == 1 or t:find("off") or t:find("greed") or t:find("transmog")) and true or false
end

function Council.HistoryExport(format, days)
    local list = historyRange(days)
    local lines = {}
    local function row(r)
        local info = Items.Info(r.i)
        local g = ns.Guild.Find(r.to)
        local _, _, _, equipLoc, _, _, subType = nil, nil, nil, nil, nil, nil, nil
        if GetItemInfoInstant then
            local ok, _, _, st, el = pcall(GetItemInfoInstant, Items.ID(r.i) or 0)
            if ok then subType, equipLoc = st, el end
        end
        return {
            full = fullName(r.to), owner = fullName(r.by), instance = r.z or "", boss = r.b or "", difficultyID = r.d or "",
            mapID = r.m or "", groupSize = r.gs or "", responseID = r.rk or "", subType = subType or "", equipLoc = equipLoc or "",
            link = info and info.link or r.i, os = isOffspec(r), id = r.id or "", t = r.t,
            player = Names.Display(g and g.name or r.to), class = g and g.class or "", date = date("%Y-%m-%d", r.t), time = date("%H:%M:%S", r.t),
            item = info and info.name or r.i, itemID = Items.ID(r.i) or "", itemString = r.i, response = r.r or "",
            votes = r.v or 0, by = Names.Display(r.by or ""),
        }
    end
    if format == "rclc" then
        -- "rclc" CSV export layout
        local cols = { "player", "date", "time", "id", "item", "itemID", "itemString", "response", "votes", "class", "instance", "boss",
            "difficultyID", "mapID", "groupSize", "gear1", "gear2", "responseID", "isAwardReason", "subType", "equipLoc", "note", "owner" }
        lines[1] = table.concat(cols, ",")
        for _, r in ipairs(list) do
            local x = row(r)
            local v = { x.full, date("%d/%m/%y", x.t), x.time, x.id, "[" .. tostring(x.item) .. "]", x.itemID, x.itemString, x.response,
                x.votes, x.class, x.instance, x.boss, x.difficultyID, x.mapID, x.groupSize, "", "", x.responseID, "false",
                x.subType, x.equipLoc, "", x.owner }
            for i = 1, #v do v[i] = csvCell(v[i], ",") end
            lines[#lines + 1] = table.concat(v, ",")
        end
    elseif format == "gargul" then
        -- Gargul award history (comma separated)
        lines[1] = "dateTime,character,itemID,offspec,id"
        for _, r in ipairs(list) do
            local x = row(r)
            lines[#lines + 1] = table.concat({ x.date .. " " .. x.time, csvCell(x.full, ","), x.itemID, x.os and 1 or 0, csvCell(x.id, ",") }, ",")
        end
    elseif format == "nota" then
        -- Nota Loot (semicolon separated)
        lines[1] = "date;time;player;class;item;itemID;response;offspec;instance;boss;votes;owner"
        for _, r in ipairs(list) do
            local x = row(r)
            local v = { x.date, x.time, x.full, x.class, x.item, x.itemID, x.response, x.os and 1 or 0, x.instance, x.boss, x.votes, x.owner }
            for i = 1, #v do v[i] = csvCell(v[i], ";") end
            lines[#lines + 1] = table.concat(v, ";")
        end
    elseif format == "csv" or format == "tsv" then
        local sep = format == "csv" and "," or "\t"
        local cols = { "player", "date", "time", "item", "itemID", "itemString", "response", "votes", "class", "by" }
        lines[1] = table.concat(cols, sep)
        for _, r in ipairs(list) do
            local x = row(r)
            local cells = {}
            for i, c in ipairs(cols) do cells[i] = csvCell(x[c], sep) end
            lines[#lines + 1] = table.concat(cells, sep)
        end
    elseif format == "discord" then
        lines[1] = "**" .. L.LC_HISTORY .. "**"
        for _, r in ipairs(list) do
            local x = row(r)
            lines[#lines + 1] = ("%s %s – **%s** – %s (%s)"):format(x.date, x.time:sub(1, 5), x.item, x.player, x.response)
        end
    elseif format == "bbcode" then
        lines[1] = "[b]" .. L.LC_HISTORY .. "[/b][list]"
        for _, r in ipairs(list) do
            local x = row(r)
            lines[#lines + 1] = ("[*]%s – [url=https://www.wowhead.com/classic/item=%s]%s[/url] – %s (%s)"):format(x.date, x.itemID, x.item, x.player, x.response)
        end
        lines[#lines + 1] = "[/list]"
    else -- json
        local items = {}
        for _, r in ipairs(list) do
            local x = row(r)
            items[#items + 1] = ('{"player":"%s","date":"%s","time":"%s","item":"%s","itemID":%s,"response":"%s","votes":%d}'):format(
                x.player:gsub('"', '\\"'), x.date, x.time, tostring(x.item):gsub('"', '\\"'), tonumber(x.itemID) or 0,
                tostring(x.response):gsub('"', '\\"'), x.votes)
        end
        lines[1] = "[" .. table.concat(items, ",") .. "]"
    end
    return table.concat(lines, "\n"), #list
end

-- Manual share: send the history of the last days to the guild
function Council.ShareHistory(days)
    if not IsInGuild() then return 0 end
    local list = historyRange(days or 30)
    -- others only take records we gave out ourselves, unless we are an officer
    if not ns.Guild.IsOfficer(Names.Me()) then
        local mine = {}
        for _, r in ipairs(list) do if Names.Same(r.by, Names.Me()) then mine[#mine + 1] = r end end
        list = mine
    end
    local batch = {}
    for _, r in ipairs(list) do
        batch[#batch + 1] = r
        if #batch == 20 then Comm.Send("HB", { list = batch }, "GUILD", { priority = "bulk" }); batch = {} end
    end
    if #batch > 0 then Comm.Send("HB", { list = batch }, "GUILD", { priority = "bulk" }) end
    ns.Print(L.LC_HISTORY_SHARED:format(#list))
    return #list
end

-- History batches: in the guild channel only records the sender gave out as
-- loot master (officers may share everything); by whisper only as the answer
-- to our own request, from the one member who answered it.
Comm.Register("HB", function(data, sender, channel)
    if type(data.list) ~= "table" then return end
    local req, officer
    if channel == "GUILD" then
        officer = ns.Guild.IsOfficer(sender)
    elseif channel == "WHISPER" then
        if not ns.Guild.IsMember(sender) then return end
        req = Comm.Expected("lc-history-sync", sender)
        if not req then return end
    else
        return
    end
    local added = 0
    for i, raw in ipairs(data.list) do
        if i > 20 then break end
        local r = cleanRecord(raw)
        local ok = r ~= nil
        if ok and channel == "GUILD" then ok = officer or Names.Same(r.by, sender) end
        if ok and req then
            ok = r.t > (req.since or 0) and (req.count or 0) < 400
            if ok then req.count = (req.count or 0) + 1 end
        end
        if ok and historyAdd(r) then added = added + 1 end
    end
    if added > 0 then ns.Debounce("lc-history-redraw", 0.5, function() ns.Window.Refresh("council") end) end
end)

-- Automatic: after login ask for entries newer than ours; one member answers
Comm.Register("HQ", function(data, sender, channel, raw)
    if not IsInGuild() or channel ~= "GUILD" then return end
    local since = tonumber(data.since) or 0
    local newer = {}
    for _, r in ipairs(ns.Database.Guild().lootHistory) do if (r.t or 0) > since then newer[#newer + 1] = r end end
    if #newer == 0 then return end
    Comm.ReplyOnce("lchist:" .. sender, 4, 14, function()
        Comm.Send("HA", { to = sender }, "GUILD", { priority = "alert" })
        -- deletions first, so the records that follow are already filtered
        local rm = {}
        for k, x in pairs(removedStore()) do
            if type(x) == "table" and x.by and (x.t or 0) > since - 30 * 86400 and #rm < 200 then rm[#rm + 1] = { k = k, by = x.by, t = x.t } end
        end
        if #rm > 0 then Comm.Send("HR", { r = rm }, "WHISPER", { target = raw, priority = "bulk" }) end
        local batch = {}
        for i, r in ipairs(newer) do
            if i > 400 then break end
            batch[#batch + 1] = r
            if #batch == 20 then Comm.Send("HB", { list = batch }, "WHISPER", { target = raw, priority = "bulk" }); batch = {} end
        end
        if #batch > 0 then Comm.Send("HB", { list = batch }, "WHISPER", { target = raw, priority = "bulk" }) end
    end)
end)
Comm.Register("HA", function(data, sender)
    if not data.to then return end
    Comm.Answered("lchist:" .. data.to)
    if Names.Same(data.to, Names.Me()) then Comm.Expected("lc-history-sync", sender) end
end)

ns.On("LG_READY", function()
    local store, now = removedStore(), ns.Now()
    for k, x in pairs(store) do
        if type(x) ~= "table" or (x.t or 0) < now - REMOVED_KEEP then store[k] = nil end
    end
    ns.After(55, function()
        if not IsInGuild() then return end
        local list = ns.Database.Guild().lootHistory
        local newest = 0
        for _, r in ipairs(list) do newest = math.max(newest, r.t or 0) end
        Comm.Expect("lc-history-sync", 180, { since = newest })
        Comm.Send("HQ", { since = newest }, "GUILD", { priority = "bulk" })
    end)
end)
