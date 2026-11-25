-- Inspects guild members in range (for those without the addon, or on demand)
local _, ns = ...
local Inspect = ns.NewModule("inspect")
ns.Inspect = Inspect
local Names = ns.Names

local pending        -- { unit, key, guid, at }
local lastAsk = 0
local COOLDOWN, TIMEOUT, FRESH = 2, 4, 1800

local function blizzardInspecting()
    return InspectFrame and InspectFrame:IsShown()
end

local function canInspect(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    if UnitIsUnit(unit, "player") or ns.InCombat() or blizzardInspecting() then return false end
    if CheckInteractDistance and not ns.Call(CheckInteractDistance, unit, 1) then
        -- out of inspect range; CanInspect alone is not enough on some clients
        if not ns.Call(UnitIsVisible, unit) then return false end
    end
    return ns.Call(CanInspect, unit) == true
end

-- Requests inspect data for a unit. force skips the freshness check.
function Inspect.Request(unit, force)
    if pending and GetTime() - pending.at < TIMEOUT then return false end
    if GetTime() - lastAsk < COOLDOWN then return false end
    if not canInspect(unit) then return false end
    local key = Names.Key(Names.Unit(unit))
    if not key then return false end
    if not force then
        if not ns.Guild.IsMember(key) then return false end
        local m = ns.Database.Member(key)
        local newest = math.max(m and m.t or 0, m and m.insp and m.insp.t or 0)
        if ns.Now() - newest < FRESH then return false end
    end
    pending = { unit = unit, key = key, guid = UnitGUID(unit), at = GetTime() }
    lastAsk = GetTime()
    ns.Call(NotifyInspect, unit)
    return true
end

local function finish(guid)
    if not pending or (guid and pending.guid and guid ~= pending.guid) then return end
    local unit, key = pending.unit, pending.key
    pending = nil
    if not UnitExists(unit) or UnitGUID(unit) ~= guid then return end
    local gear = ns.Profile.ReadGear(unit)
    if not next(gear) then return end
    local m = ns.Database.Member(key, true)
    local _, class = ns.Call(UnitClass, unit)
    m.c = m.c or class
    m.name = m.name or Names.Unit(unit)
    -- race and gender for the armory model (members without the addon)
    if not m.rf then
        local _, raceFile, raceId = ns.Call(UnitRace, unit)
        m.rf, m.ri = raceFile, type(raceId) == "number" and raceId or nil
        m.sx = m.sx or ns.Call(UnitSex, unit)
    end
    local spec
    if GetInspectSpecialization and GetSpecializationInfoByID then
        local id = ns.Call(GetInspectSpecialization, unit)
        if id and id > 0 then spec = select(2, ns.Call(GetSpecializationInfoByID, id)) end
    end
    -- talents of the inspected player (classic talent trees)
    local best, tp, tn, most, tk = ns.Profile.ReadTalents(true, true)
    if not (most and most > 0) then best, tp, tn, tk = nil, nil, nil, nil end
    m.insp = { g = gear, il = ns.Profile.AverageLevel(gear), t = ns.Now(), sp = spec or best, tp = tp, tn = tn, tk = tk, l = ns.Call(UnitLevel, unit) }
    if ClearInspectPlayer and not blizzardInspecting() then ns.Call(ClearInspectPlayer) end
    ns.Fire("LG_PROFILE", key)
    -- item data may arrive later; recompute once
    ns.After(3, function()
        if m.insp then m.insp.il = ns.Profile.AverageLevel(m.insp.g) or m.insp.il end
    end)
end

ns.On("INSPECT_READY", function(_, guid) finish(guid) end)

-- Opportunistic inspects: mouseover and target in groups
local function opportunistic(unit)
    if not IsInGuild() then return end
    ns.Safe(Inspect.Request, unit, false)
end
ns.On("UPDATE_MOUSEOVER_UNIT", function() opportunistic("mouseover") end)
ns.On("PLAYER_TARGET_CHANGED", function() opportunistic("target") end)

-- Best gear info for a member: own profile if newer than the last inspect
function Inspect.Gear(m)
    if not m then return nil end
    local profileT, inspT = m.t or 0, m.insp and m.insp.t or 0
    if m.g and next(m.g) and profileT >= inspT then return m.g, m.il, "addon", m.t end
    if m.insp then return m.insp.g, m.insp.il, "inspect", m.insp.t end
    if m.g and next(m.g) then return m.g, m.il, "addon", m.t end
end
