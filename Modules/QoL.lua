-- Quality of life: automatic group role from the talent tree
local _, ns = ...
local QoL = ns.NewModule("qol")
ns.QoL = QoL

-- role per class and talent tree (index of the tree with the most points)
local TREE_ROLES = {
    WARRIOR = { "DAMAGER", "DAMAGER", "TANK" },
    PALADIN = { "HEALER", "TANK", "DAMAGER" },
    HUNTER = { "DAMAGER", "DAMAGER", "DAMAGER" },
    ROGUE = { "DAMAGER", "DAMAGER", "DAMAGER" },
    PRIEST = { "HEALER", "HEALER", "DAMAGER" },
    SHAMAN = { "DAMAGER", "DAMAGER", "HEALER" },
    MAGE = { "DAMAGER", "DAMAGER", "DAMAGER" },
    WARLOCK = { "DAMAGER", "DAMAGER", "DAMAGER" },
    DRUID = { "DAMAGER", "TANK", "HEALER" },
}

function QoL.Setting()
    local char = ns.Database.Char()
    if char.role == nil then char.role = "auto" end
    return char.role
end

-- The role the player should have, or nil
function QoL.WantedRole()
    local setting = QoL.Setting()
    if setting == "off" then return nil end
    if setting ~= "auto" then return setting end
    local _, class = ns.Call(UnitClass, "player")
    local roles = TREE_ROLES[class or ""]
    if not roles then return nil end
    local m = ns.Database.Member(ns.Names.Me())
    local best, bestPoints = nil, -1
    for i, p in ipairs({ strsplit("/", m and m.tp or "") }) do
        local n = tonumber(p) or 0
        if n > bestPoints then best, bestPoints = i, n end
    end
    if not best or bestPoints <= 0 then return nil end
    return roles[best]
end

-- Battlegrounds and arenas ignore group roles: the client keeps reporting
-- NONE, so every roster update during the preparation phase would set the
-- role again (and the game announces each change in chat).
function QoL.RolesUsed()
    local _, kind = ns.Call(IsInInstance)
    if kind == "pvp" or kind == "arena" then return false end
    if UnitInBattleground and ns.Call(UnitInBattleground, "player") then return false end
    return true
end

-- role we already sent in this group; a role that does not stick is not resent
QoL.sent = nil

function QoL.ApplyRole(force)
    if not IsInGroup() or InCombatLockdown() or not QoL.RolesUsed() then return end
    local role = QoL.WantedRole()
    if not role or not UnitSetRole then return end
    local current = ns.Call(UnitGroupRolesAssigned, "player")
    if current == role and not force then QoL.sent = role; return end
    if QoL.sent == role and not force then return end
    local announce = QoL.sent ~= role and current ~= role
    QoL.sent = role
    ns.Call(UnitSetRole, "player", role)
    if announce then ns.Print(ns.L.ROLE_SET:format(ns.L["ROLE_" .. role])) end
end

-- /lg test role: why the role is (not) set, nothing is changed
function QoL.Test()
    local _, kind = ns.Call(IsInInstance)
    ns.Print(("Role: setting %s, wanted %s, current %s, sent %s, group %s, instance %s, roles used %s"):format(
        tostring(QoL.Setting()), tostring(QoL.WantedRole()), tostring(ns.Call(UnitGroupRolesAssigned, "player")),
        tostring(QoL.sent), tostring(IsInGroup() and true or false), tostring(kind), tostring(QoL.RolesUsed())))
end

local function soon() ns.Debounce("qol-role", 2, function() ns.AfterCombat("qol-role", QoL.ApplyRole) end) end
ns.On("GROUP_JOINED", function() QoL.sent = nil; soon() end)
ns.On("GROUP_LEFT", function() QoL.sent = nil end)
ns.On("GROUP_ROSTER_UPDATE", soon)
ns.On("LG_PROFILE", soon)
ns.On("ROLE_POLL_BEGIN", function()
    ns.After(0.2, function()
        if not QoL.RolesUsed() then return end
        QoL.ApplyRole(true)
        if QoL.WantedRole() and RolePollPopup and RolePollPopup:IsShown() then RolePollPopup:Hide() end
    end)
end)
