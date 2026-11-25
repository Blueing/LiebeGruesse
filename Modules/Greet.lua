-- Login greetings: when one of these characters logs in, every addon user
-- writes the greeting into guild chat – each player once per day and greeting.
local _, ns = ...
local L, Names = ns.L, ns.Names
local Greet = ns.NewModule("greet")
ns.Greet = Greet

-- fixed on purpose (guild tradition): characters -> text
Greet.LIST = {
    { key = "salty", names = { "Salty Brown", "Salty Yellow" }, text = "glaun hs" },
    { key = "marcha", names = { "Mar Cha" }, text = "marcha hs" },
}

local function enabled() return ns.Database.Settings().modules.greet ~= false end

function Greet.Today() return date("%Y-%m-%d") end

-- per account: one player greets once a day, also when switching characters
local function days()
    local s = ns.Database.Settings()
    s.greetDays = s.greetDays or {}
    return s.greetDays
end
function Greet.Done(key) return days()[key] == Greet.Today() end
local function markDone(key) days()[key] = Greet.Today() end

-- the greeting entry for a character name, or nil
function Greet.For(name)
    if type(name) ~= "string" or name == "" then return nil end
    local key = Names.Key(name)
    for _, g in ipairs(Greet.LIST) do
        for _, n in ipairs(g.names) do
            if Names.Same(Names.Key(n), key) then return g end
        end
    end
end

-- "|Hplayer:Salty Brown|h[Salty Brown]|h has come online." -> "Salty Brown"
local onlinePattern
function Greet.OnlineName(text)
    if type(text) ~= "string" then return nil end
    if not onlinePattern then
        local fmt = ERR_FRIEND_ONLINE_SS or "|Hplayer:%s|h[%s]|h has come online."
        onlinePattern = "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.-)") .. "$"
    end
    local link, shown = text:match(onlinePattern)
    return shown or link
end

local pending = {}

function Greet.Trigger(name)
    if not enabled() or not IsInGuild() then return end
    local g = Greet.For(name)
    if not g or Greet.Done(g.key) or pending[g.key] then return end
    -- the greeted player (and their own characters) do not greet themselves
    for _, n in ipairs(g.names) do if Names.Same(Names.Key(n), Names.Me()) then return end end
    if not ns.Guild.IsMember(Names.Key(name)) then return end
    pending[g.key] = true
    -- a short random pause, so the guild's greetings do not all land in the same second
    ns.After(1 + math.random() * 3, function()
        -- never from combat: the greeting waits until it ends
        ns.AutoChat("greet-" .. g.key, function()
            pending[g.key] = nil
            if Greet.Done(g.key) or not enabled() then return end
            markDone(g.key)
            ns.SendChat(g.text, "GUILD")
        end)
    end)
end

ns.On("CHAT_MSG_SYSTEM", function(_, text)
    if ns.IsSecret(text) then return end
    local name = Greet.OnlineName(text)
    if name then Greet.Trigger(name) end
end)

-- typed by hand: counts as today's greeting for this player
ns.On("CHAT_MSG_GUILD", function(_, text, sender)
    if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if not Names.IsMe(sender) then return end
    for _, g in ipairs(Greet.LIST) do
        if text:lower() == g.text then markDone(g.key) end
    end
end)

-- /lg test greet: the greetings and whether you already wrote them today (nothing sent)
function Greet.Test()
    for _, g in ipairs(Greet.LIST) do
        ns.Print(L.GREET_TEST:format(table.concat(g.names, " / "), ns.Theme.HexColor("text", g.text),
            Greet.Done(g.key) and L.GREET_TEST_DONE or L.GREET_TEST_OPEN))
    end
end
