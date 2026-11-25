-- SavedVariables: account settings, per-character settings, per-guild data
local _, ns = ...
local Database = {}
ns.Database = Database

local DEFAULTS = {
    settings = {
        minimap = { angle = 200, hide = false },
        toasts = true,
        tooltips = { unit = true, crafters = true },
        window = {},
        theme = { preset = "ember", colors = {}, font = "Expressway", weight = "strong", fontScale = 1.05, windowScale = 1, windowAlpha = 1 },
        modules = { feed = true, community = true, council = true, cooldowns = true, professions = true,
            stats = true, councilOnlyMembers = false },
        craft = { answer = true, prefix = "!lg" },
        community = { failVote = true },
        lcAutoPass = true,
        enchantSlots = { [2] = true, [1] = true, [3] = true, [15] = true, [5] = true, [9] = true, [10] = true, [7] = true,
            [8] = true, [16] = true, [17] = true },
        cd = {
            enabled = true, locked = true, showSolo = false, observe = true, clickWhisper = true, preview = false,
            clickLeft = "whisper", clickShift = "call", clickRight = "none", onlyReady = false,
            displays = {}, spells = {}, custom = {}, pos = {},
        },
    },
    chars = {},
    guilds = {},
}

local GUILD_DEFAULTS = {
    members = {},   -- [key] = synced profile + inspect data
    feed = {},      -- list of feed entries (newest last)
    lootHistory = {},
    lc = nil,       -- loot council config (see Council.lua)
}

local function fill(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            fill(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end
Database.Fill = fill

function Database.Init()
    LiebeGruesseDB = LiebeGruesseDB or {}
    ns.db = fill(LiebeGruesseDB, DEFAULTS)
    ns.db.schema = 1
    ns.Theme.Migrate()
    ns.Theme.Migrate4()
    ns.Theme.Migrate5()
    ns.Theme.Migrate6()
    local st = ns.db.settings
    if not st.cd.clickMigrated then
        st.cd.clickMigrated = true
        if st.cd.clickWhisper == false then st.cd.clickLeft = "none" end
    end
    if not st.neckMigrated then st.neckMigrated = true; st.enchantSlots[2] = true end
    ns.Theme.Load()
end

function Database.Settings() return ns.db.settings end

function Database.Char()
    local key = ns.Names.Me() or "_"
    ns.db.chars[key] = ns.db.chars[key] or {}
    return ns.db.chars[key]
end

-- Key of the player's guild, or nil when not (yet) known
function Database.GuildKey()
    if not IsInGuild() then return nil end
    local name = ns.Call(GetGuildInfo, "player")
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

local scratch = fill({}, GUILD_DEFAULTS)
-- Data of the current guild. Before the guild is known a scratch table is
-- returned that is never saved.
function Database.Guild()
    local key = Database.GuildKey()
    if not key then return scratch end
    local g = ns.db.guilds[key]
    if not g then
        g = {}
        ns.db.guilds[key] = g
    end
    return fill(g, GUILD_DEFAULTS)
end

function Database.Member(key, create)
    if not key then return nil end
    local members = Database.Guild().members
    local m = members[key]
    if not m and create then
        m = {}
        members[key] = m
    end
    return m
end
