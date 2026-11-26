-- Addon messages: serialization, chunking, throttling, restriction-aware queue
local _, ns = ...
local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "LieGrue"
local MAX_CHUNK = 248          -- bytes per message after the 3-byte header (kind + 2-char id)
local ID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local nextId = math.random(0, 3843)
local function newId()
    nextId = (nextId + 1) % 3844
    local a, b = math.floor(nextId / 62) + 1, nextId % 62 + 1
    return ID_CHARS:sub(a, a) .. ID_CHARS:sub(b, b)
end
local BURST, RATE = 10, 0.8    -- token bucket: burst size, seconds per token
local BUFFER_TTL = 120

local handlers = {}
local channelKinds = {}   -- kinds allowed on custom chat channels (the Bund channel)
local queue = { alert = {}, normal = {}, bulk = {} }
local tokens, lastRefill = BURST, 0
local pausedUntil = 0
local buffers = {}
local stats = { sent = 0, received = 0, dropped = 0 }
Comm.stats = stats

-- handler(data, senderKey, channel, senderName)
-- opts.channel = true: the kind may also arrive on a custom chat channel
-- (everything else from such channels is dropped – anyone can join one)
function Comm.Register(kind, handler, opts)
    -- two modules must never share a message kind (the second would silently replace the first)
    if handlers[kind] then error("LiebeGruesse: message kind '" .. kind .. "' registered twice", 2) end
    handlers[kind] = handler
    if opts and opts.channel then channelKinds[kind] = true end
end

-- Remembers that we asked for something (e.g. history sync), so whispered
-- answers are only taken while we wait for them – and only from one player.
local expecting = {}
function Comm.Expect(topic, seconds, data)
    expecting[topic] = { untilT = GetTime() + (seconds or 120), data = data or {} }
end
-- Returns the request's data if an answer from sender is welcome; the first
-- answering player is locked in (later answers from others are ignored).
function Comm.Expected(topic, sender)
    local e = expecting[topic]
    if not e then return nil end
    if GetTime() > e.untilT then expecting[topic] = nil; return nil end
    if sender then
        if e.from and not ns.Names.Same(e.from, sender) then return nil end
        e.from = e.from or sender
    end
    return e.data
end

local function dispatch(data, sender, channel)
    if type(data) ~= "table" or type(data.k) ~= "string" then return end
    local handler = handlers[data.k]
    if not handler then return end
    if channel == "CHANNEL" and not channelKinds[data.k] then return end
    local key = ns.Names.Key(sender)
    if not key then return end
    ns.Safe(handler, data, key, channel, sender)
end

---------------------------------------------------------------------------
-- Splitting: pieces of the raw serialized text whose escaped size fits.
---------------------------------------------------------------------------
local function split(raw)
    local pieces, start, size = {}, 1, 0
    for i = 1, #raw do
        local c = raw:sub(i, i)
        local w = (c == "\0" or c == "\n" or c == "\r" or c == "|" or c == "~") and 2 or 1
        if size + w > MAX_CHUNK then
            pieces[#pieces + 1] = raw:sub(start, i - 1)
            start, size = i, 0
        end
        size = size + w
    end
    pieces[#pieces + 1] = raw:sub(start)
    return pieces
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function channelReady(channel)
    if channel == "GUILD" then return IsInGuild() end
    if channel == "RAID" then return IsInRaid() end
    if channel == "PARTY" then return IsInGroup() end
    if channel == "INSTANCE_CHAT" then return LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
    return true
end

local ticker
local function refill()
    local now = GetTime()
    if lastRefill == 0 then lastRefill = now end
    local gained = math.floor((now - lastRefill) / RATE)
    if gained > 0 then
        tokens = math.min(BURST, tokens + gained)
        lastRefill = lastRefill + gained * RATE
    end
    if tokens >= BURST then lastRefill = now end
end

local function nextItem()
    for _, name in ipairs({ "alert", "normal", "bulk" }) do
        local q = queue[name]
        if #q > 0 then return q, q[1] end
    end
end

local function pump()
    if GetTime() < pausedUntil then return end
    if ns.CommsRestricted() then return end
    refill()
    while tokens >= 1 do
        local q, item = nextItem()
        if not item then
            if ticker then ticker:Cancel(); ticker = nil end
            return
        end
        if item.channel ~= "WHISPER" and not channelReady(item.channel) then
            table.remove(q, 1)
            stats.dropped = stats.dropped + 1
        elseif item.expires and GetTime() > item.expires then
            table.remove(q, 1)
            stats.dropped = stats.dropped + 1
        else
            local text = item.text
            if item.build then text = item.build() end
            if not text or (item.channel == "WHISPER" and Comm.TargetGone(item.target)) then
                table.remove(q, 1)
                if text then stats.dropped = stats.dropped + 1 end
            else
                local ok, result = pcall(C_ChatInfo.SendAddonMessage, item.prefix, text, item.channel, item.target)
                -- 3 = throttled, 8 = channel throttled (Enum.SendAddonMessageResult)
                if ok and (result == 3 or result == 8) then
                    pausedUntil = GetTime() + 2
                    return
                end
                table.remove(q, 1)
                tokens = tokens - 1
                stats.sent = stats.sent + 1
                if item.channel == "WHISPER" then Comm.NoteWhisper(item.target) end
            end
        end
    end
end

local function ensureTicker()
    if not ticker then ticker = C_Timer.NewTicker(0.2, ns.Guard(pump)) end
end

-- Low-level: queue one raw message (used for foreign prefixes as well).
-- opts: priority ("alert"|"normal"|"bulk"), target (whisper), expires (seconds), build (fn returning text)
function Comm.SendRaw(prefix, text, channel, opts)
    opts = opts or {}
    local q = queue[opts.priority or "normal"]
    q[#q + 1] = {
        prefix = prefix, text = text, build = opts.build, channel = channel, target = opts.target,
        expires = opts.expires and (GetTime() + opts.expires) or nil,
    }
    ensureTicker()
    pump()
end

-- Sends a table. data.k must be the message kind. channel: GUILD, RAID,
-- PARTY, INSTANCE_CHAT, WHISPER (opts.target), GROUP (current group) or
-- LOCAL (only delivered to ourselves; used by test modes).
-- opts.loopback also delivers the message to our own handlers.
function Comm.Send(kind, data, channel, opts)
    data = data or {}
    data.k = kind
    opts = opts or {}
    if channel == "LOCAL" then
        local me = ns.Names.Unit("player") or "me"
        local copy = ns.Serialize.Unpack(ns.Serialize.Pack(data))
        ns.After(0.05, function() dispatch(copy, me, "LOCAL") end)
        return true
    end
    if channel == "GROUP" then
        channel = ns.GroupChannel()
        if not channel then return false end
    end
    -- "BUND": the hidden channel shared with the partner guild
    if channel == "BUND" then
        local id = ns.CoGuild and ns.CoGuild.ChannelId and ns.CoGuild.ChannelId()
        if not id then return false end
        channel = "CHANNEL"
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.target = id
        opts = o
    end
    if channel == "WHISPER" and (not opts.target or Comm.TargetGone(opts.target)) then return false end
    if not channelReady(channel) then return false end
    if opts.loopback then
        -- our own messages are not echoed back to us; deliver a copy locally
        local me = ns.Names.Unit("player") or "me"
        local copy = ns.Serialize.Unpack(ns.Serialize.Pack(data))
        local resolved = channel
        ns.After(0.05, function() dispatch(copy, me, resolved) end)
    end
    local raw = ns.Serialize.Pack(data)
    local pieces = split(raw)
    local mid = newId()
    for i, piece in ipairs(pieces) do
        local head
        if #pieces == 1 then head = "S"
        elseif i == 1 then head = "B"
        elseif i == #pieces then head = "E"
        else head = "C" end
        Comm.SendRaw(Comm.PREFIX, head .. mid .. ns.Serialize.Escape(piece), channel, opts)
    end
    return true
end

function Comm.QueueSize()
    return #queue.alert + #queue.normal + #queue.bulk
end

---------------------------------------------------------------------------
-- Offline whisper targets: an addon whisper to someone who is offline makes
-- the game print "No player named 'X' is currently playing." once per
-- message piece. We hide those lines, drop the rest of the queue for that
-- player and skip him for a while (or until he is seen again).
---------------------------------------------------------------------------
local GONE_FOR = 600      -- seconds a player stays "offline" after the error
local OWN_WINDOW = 30     -- an error within this time after our whisper is ours
local whispered, gone, heard, wasOffline = {}, {}, {}, {}
Comm.gone = gone

function Comm.NoteWhisper(target)
    local key = ns.Names.Key(target)
    if key then whispered[key] = GetTime() end
end

function Comm.Heard(name)
    local key = ns.Names.Key(name)
    if not key then return end
    heard[key] = GetTime()
    gone[key] = nil
end

function Comm.TargetGone(target)
    local key = ns.Names.Key(target)
    if not key then return false end
    local now = GetTime()
    local m = ns.Guild and ns.Guild.Find and ns.Guild.Find(key)
    if m then
        -- roster went from offline to online since the error: logged back in
        if m.online == false then wasOffline[key] = true
        elseif m.online == true and wasOffline[key] then wasOffline[key] = nil; gone[key] = nil end
    end
    if gone[key] then
        if now < gone[key] then return true end
        gone[key] = nil
    end
    -- guild roster says offline (unless he just talked to us)
    if m and m.online == false and not (heard[key] and now - heard[key] < 120) then return true end
    return false
end

local function purge(key)
    for _, q in pairs(queue) do
        for i = #q, 1, -1 do
            if q[i].channel == "WHISPER" and ns.Names.Key(q[i].target) == key then
                table.remove(q, i)
                stats.dropped = stats.dropped + 1
            end
        end
    end
end

local notFound
local function notFoundName(msg)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return nil end
    if not notFound then
        local fmt = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S
            or "No player named '%s' is currently playing."
        local pat = fmt:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
        notFound = "^" .. pat .. "$"
    end
    return msg:match(notFound)
end
Comm.NotFoundName = notFoundName

-- /lg test offline
function Comm.OfflineReport()
    local list, now = {}, GetTime()
    for key, untilT in pairs(gone) do
        if untilT > now then list[#list + 1] = ("%s (%d min)"):format(ns.Names.Display(key), math.ceil((untilT - now) / 60)) end
    end
    table.sort(list)
    ns.Print(("Offline whisper targets: %s · dropped messages: %d"):format(#list > 0 and table.concat(list, ", ") or "none", stats.dropped))
end

-- true if the line is about one of our own addon whispers (then it is hidden)
function Comm.OwnNotFound(msg)
    local name = notFoundName(msg)
    local key = name and ns.Names.Key(name)
    if not key then return false end
    local t = whispered[key]
    if not t or GetTime() - t > OWN_WINDOW then return false end
    if not gone[key] then
        gone[key] = GetTime() + GONE_FOR
        wasOffline[key] = nil
        purge(key)
    end
    return true
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        local ok, own = pcall(Comm.OwnNotFound, msg)
        return ok and own or false
    end)
end
ns.On("CHAT_MSG_SYSTEM", function(_, msg) Comm.OwnNotFound(msg) end)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local foreign = {}
-- Lets modules listen to other addons' prefixes: fn(text, channel, sender)
function Comm.Listen(prefix, fn)
    foreign[prefix] = fn
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    end
end

local function receive(text, channel, sender)
    local head, mid, body = text:sub(1, 1), text:sub(2, 3), text:sub(4)
    body = ns.Serialize.Unescape(body)
    local id = sender .. "\1" .. channel .. "\1" .. mid
    if head == "S" then
        buffers[id] = nil
        dispatch(ns.Serialize.Unpack(body), sender, channel)
    elseif head == "B" then
        buffers[id] = { parts = { body }, t = GetTime() }
    elseif head == "C" or head == "E" then
        local buf = buffers[id]
        if not buf then return end
        buf.parts[#buf.parts + 1] = body
        buf.t = GetTime()
        if #buf.parts > 400 then buffers[id] = nil; return end
        if head == "E" then
            buffers[id] = nil
            dispatch(ns.Serialize.Unpack(table.concat(buf.parts)), sender, channel)
        end
    end
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if ns.IsSecret(prefix) or ns.IsSecret(text) or ns.IsSecret(sender) or ns.IsSecret(channel) then return end
    if type(sender) ~= "string" or type(text) ~= "string" then return end
    if prefix == Comm.PREFIX then
        if ns.Names.IsMe(sender) then return end
        stats.received = stats.received + 1
        Comm.Heard(sender)
        receive(text, channel, sender)
    elseif foreign[prefix] then
        ns.Safe(foreign[prefix], text, channel, sender)
    end
end)

ns.On("ADDON_LOADED", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
    end
end)

C_Timer.NewTicker(30, function()
    local now = GetTime()
    for id, buf in pairs(buffers) do
        if now - buf.t > BUFFER_TTL then buffers[id] = nil end
    end
    if Comm.QueueSize() > 0 then ensureTicker() end
end)

---------------------------------------------------------------------------
-- Elected replies: when many clients could answer a request, each waits a
-- random time and cancels if someone else answered first.
---------------------------------------------------------------------------
local pendingReplies = {}
function Comm.ReplyOnce(topic, minDelay, maxDelay, fn)
    if pendingReplies[topic] then return end
    local delay = minDelay + math.random() * (maxDelay - minDelay)
    pendingReplies[topic] = C_Timer.NewTimer(delay, function()
        pendingReplies[topic] = nil
        ns.Safe(fn)
    end)
end

function Comm.Answered(topic)
    local timer = pendingReplies[topic]
    if timer then timer:Cancel(); pendingReplies[topic] = nil end
end
