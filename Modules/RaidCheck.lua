-- Buff scan for the consumables tracker of the community page: at ready checks
-- it reads flasks, elixirs and food of the group (silently, outside of combat).
local _, ns = ...
local RaidCheck = ns.NewModule("raidcheck")
ns.RaidCheck = RaidCheck
local Names = ns.Names

local FLASK_IDS = { [17626] = true, [17627] = true, [17628] = true, [17629] = true, [17624] = true }
local ELIXIR_IDS = {
    [11405] = true, [17538] = true, [17539] = true, [11474] = true, [26276] = true, [21920] = true, [11334] = true,
    [3593] = true, [11348] = true, [24361] = true, [24363] = true, [16323] = true, [16329] = true, [17038] = true,
    [24382] = true, [25804] = true, [11390] = true, [11396] = true, [3166] = true, [7844] = true, [17535] = true,
    [10668] = true, [10692] = true, [10693] = true, [10669] = true, [15233] = true, [16321] = true, [16322] = true,
    [16325] = true, [16326] = true, [16327] = true,
}
local FOOD_IDS = { [19705] = true, [19706] = true, [19708] = true, [19709] = true, [19710] = true, [19711] = true,
    [24799] = true, [25661] = true, [18192] = true, [18193] = true, [18194] = true, [18222] = true, [22730] = true,
    [25694] = true, [25941] = true, [24870] = true }
local FLASK_WORDS = { "flask", "fläschchen" }
local ELIXIR_WORDS = { "elixir", "elixier", "juju", "firewater", "feuerwasser", "zanza", "rumsey" }
local FOOD_WORDS = { "well fed", "satt", "gut gesättigt" }

local function has(name, words)
    if not name then return false end
    local lower = name:lower()
    for _, w in ipairs(words) do if lower:find(w, 1, true) then return true end end
    return false
end

local function auras(unit)
    local list = {}
    for i = 1, 40 do
        local name, id
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = ns.Call(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not a then break end
            name, id = a.name, a.spellId
        elseif UnitBuff then
            local r = { ns.Call(UnitBuff, unit, i) }
            if not r[1] then break end
            name, id = r[1], r[10]
        else
            break
        end
        if name or id then list[#list + 1] = { name = name, id = id } end
    end
    return list
end

-- { flask = name|nil, elixirs = { names }, food = bool, scanned = bool }
function RaidCheck.ScanUnit(unit)
    local out = { elixirs = {}, food = false, scanned = false }
    if not UnitExists(unit) or ns.Call(UnitIsConnected, unit) == false then return out end
    out.scanned = true
    for _, a in ipairs(auras(unit)) do
        if (a.id and FLASK_IDS[a.id]) or has(a.name, FLASK_WORDS) then
            out.flask = a.name or tostring(a.id)
        elseif (a.id and ELIXIR_IDS[a.id]) or has(a.name, ELIXIR_WORDS) then
            out.elixirs[#out.elixirs + 1] = a.name or tostring(a.id)
        elseif (a.id and FOOD_IDS[a.id]) or has(a.name, FOOD_WORDS) then
            out.food = true
        end
    end
    return out
end

function RaidCheck.Scan()
    if InCombatLockdown() then return {} end
    local rows = {}
    for unit, key, name in ns.GroupUnits() do
        local scan = RaidCheck.ScanUnit(unit)
        rows[#rows + 1] = { key = key, name = name, flask = scan.flask, elixirs = scan.elixirs, food = scan.food, scanned = scan.scanned }
    end
    return rows
end

ns.On("READY_CHECK", function()
    if not IsInRaid() or ns.Database.Settings().modules.community == false then return end
    ns.After(1.5, function()
        if ns.Community then ns.Community.RecordConsumables(RaidCheck.Scan()) end
    end)
end)
