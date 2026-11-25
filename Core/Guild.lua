-- Guild roster cache
local _, ns = ...
local Guild = {}
ns.Guild = Guild

Guild.members = {}   -- [key] = { key, name, rank, rankIndex, level, class, online, zone, note, officerNote }
Guild.order = {}
Guild.ranks = {}     -- [rankIndex] = name (0 = guild master)

function Guild.Request()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then ns.Call(C_GuildInfo.GuildRoster)
    elseif GuildRoster then ns.Call(GuildRoster) end
end

local function readRanks()
    wipe(Guild.ranks)
    local count = ns.Call(GuildControlGetNumRanks)
    if type(count) == "number" then
        for i = 1, count do
            Guild.ranks[i - 1] = ns.Call(GuildControlGetRankName, i) or ("Rank " .. i)
        end
    end
end

function Guild.Scan()
    if not IsInGuild() then
        wipe(Guild.members); wipe(Guild.order)
        return
    end
    local total = ns.Call(GetNumGuildMembers) or 0
    if total == 0 then return end
    local seen = {}
    wipe(Guild.order)
    for i = 1, total do
        local name, rank, rankIndex, level, _, zone, note, officerNote, online, _, classFile =
            ns.Call(GetGuildRosterInfo, i)
        local key = name and ns.Names.Key(name)
        if key then
            local m = Guild.members[key] or {}
            m.key, m.name, m.index = key, name, i
            m.rank, m.rankIndex, m.level, m.class = rank, rankIndex, level, classFile
            m.online, m.zone, m.note, m.officerNote = online and true or false, zone, note, officerNote
            if not m.online then
                local y, mo, d, h = ns.Call(GetGuildRosterLastOnline, i)
                if y then m.offlineHours = (((y * 12 + mo) * 30 + d) * 24) + h else m.offlineHours = nil end
            else
                m.offlineHours = 0
            end
            Guild.members[key] = m
            seen[key] = true
            Guild.order[#Guild.order + 1] = key
        end
    end
    for key in pairs(Guild.members) do
        if not seen[key] then Guild.members[key] = nil end
    end
    readRanks()
    ns.Fire("LG_ROSTER")
end

-- Finds a roster entry by key, tolerating a missing surname on either side.
function Guild.Find(key)
    if not key then return nil end
    local m = Guild.members[key]
    if m then return m end
    for k, entry in pairs(Guild.members) do
        if ns.Names.Same(k, key) then return entry end
    end
end

function Guild.IsMember(key) return Guild.Find(key) ~= nil end

-- officers: rank 0 (guild master) and 1; our own rank comes from the game directly
local OFFICER_RANK = 1
function Guild.IsOfficer(key)
    if not key then return false end
    if ns.Names.Same(key, ns.Names.Me()) then
        local index = Guild.MyRankIndex()
        return type(index) == "number" and index <= OFFICER_RANK
    end
    local g = Guild.Find(key)
    return g ~= nil and type(g.rankIndex) == "number" and g.rankIndex <= OFFICER_RANK
end

function Guild.MyRankIndex()
    local _, _, index = ns.Call(GetGuildInfo, "player")
    return index
end

ns.On("GUILD_ROSTER_UPDATE", function() ns.Debounce("guild-scan", 1, Guild.Scan) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.Debounce("guild-req", 2, Guild.Request) end)
ns.On("LG_READY", function()
    Guild.Request()
    C_Timer.NewTicker(60, function() if not ns.InCombat() then Guild.Request() end end)
end)
