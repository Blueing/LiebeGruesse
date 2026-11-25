-- Automatic chat answers ("[LG] …" for !lg and !lfg) and what happens when the
-- game blocks them. Some clients may not post chat lines on their own: the call
-- fires ADDON_ACTION_BLOCKED and the line is gone. Then
--   * that client stays out of the answer election for a few days (per topic),
--     so another member answers;
--   * a question of its own player is shown to them in their chat window when
--     no answer showed up in guild chat, with a link "[Post in guild chat]":
--     a click is a hardware event, so the game lets that line go out.
local _, ns = ...
local AutoPost = {}
ns.AutoPost = AutoPost

local BLOCK_DAYS = 3     -- a blocked client stays out this long, then tries again
local WAIT = 4           -- seconds an own question waits for an answer in guild chat
AutoPost.BLOCK_DAYS = BLOCK_DAYS

local lastSend           -- { t = GetTime(), topic = "lfg" | "craft" }
local waiting            -- own question waiting for an "[LG]" line in guild chat

local function blocks()
    local c = ns.Database.Char()
    if type(c.autoPostBlocked) ~= "table" then c.autoPostBlocked = {} end
    return c.autoPostBlocked
end

-- true while the game blocked this client's answers of that topic lately
function AutoPost.Blocked(topic)
    local t = blocks()[topic]
    return type(t) == "number" and ns.Now() - t < BLOCK_DAYS * 86400
end

-- try again (all topics when none is given)
function AutoPost.Reset(topic)
    if topic then blocks()[topic] = nil else wipe(blocks()) end
end

-- sends an automatic answer (topic "lfg" or "craft")
function AutoPost.Send(topic, text, channel, target)
    lastSend = { t = GetTime(), topic = topic }
    ns.SendChatAuto(topic .. "-answer-" .. (target or channel), text, channel, target)
end

ns.On("ADDON_ACTION_BLOCKED", function(_, addon)
    if addon ~= ns.name or not lastSend or GetTime() - lastSend.t > 3 then return end
    local topic = lastSend.topic
    lastSend = nil
    local first = not AutoPost.Blocked(topic)
    blocks()[topic] = ns.Now()
    ns.Fire("LG_AUTOPOST_BLOCKED", topic)
    if first then ns.Print(ns.L.AUTOPOST_BLOCKED:format(topic == "lfg" and "!lfg" or "!lg", BLOCK_DAYS)) end
end)

---------------------------------------------------------------------------
-- Local answer with "[Post in guild chat]". Clickable chat links:
-- |Haddon:<type>:<data>|h…|h – the click arrives through EventRegistry
-- "SetItemRef" (hooksecurefunc on clients without it).
---------------------------------------------------------------------------
local LINK_TYPE = "LiebeGruesseLG"
local posts, postId = {}, 0

function AutoPost.ShowLocally(text)
    postId = postId + 1
    posts[postId] = text
    posts[postId - 20] = nil   -- only the last few stay clickable
    local L = ns.L
    local link = ("|cff66bbff|Haddon:%s:post:%d|h[%s]|h|r"):format(LINK_TYPE, postId, L.AUTOPOST_POST_LINK)
    ns.Print("%s |cff999999(%s)|r %s", text, L.AUTOPOST_ONLY_YOU, link)
end

local function onLink(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return end
    local id = tonumber(link:match("^addon:" .. LINK_TYPE .. ":post:(%d+)"))
    local text = id and posts[id]
    if not text then return end
    posts[id] = nil   -- each answer is posted once
    -- inside the click: the game lets this line through
    ns.SendChat(text, "GUILD")
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link) ns.Safe(onLink, link) end, AutoPost)
elseif hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link) ns.Safe(onLink, link) end)
end

-- Our own question: when no "[LG]" line shows up in guild chat within a few
-- seconds, build() is shown to us locally (with the post link).
function AutoPost.WatchOwn(build)
    local w = {}
    waiting = w
    C_Timer.After(WAIT, function()
        if waiting ~= w then return end
        waiting = nil
        local ok, text = pcall(build)
        if ok and type(text) == "string" and text ~= "" then AutoPost.ShowLocally(text) end
    end)
end

ns.On("CHAT_MSG_GUILD", function(_, text)
    if waiting and type(text) == "string" and not ns.IsSecret(text) and text:find("^%[LG%]") then waiting = nil end
end)
