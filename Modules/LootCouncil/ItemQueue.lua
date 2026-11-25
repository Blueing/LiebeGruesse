-- Loot Council item queue: which items go into the next session.
-- Ways to add items (no chat command needed):
--   * "Add all": every tradeable loot in your bags (trade timer, like "/rc add all")
--     plus recently looted epics; BoE items optionally
--   * the loot window button / automatic queueing when you loot as loot master
--   * Alt-click an item in your bags or a chat link
--   * drag an item onto the council window
local _, ns = ...
local L, Items, Council = ns.L, ns.Items, ns.Council
local Queue = {}
ns.CouncilQueue = Queue

local function opts()
    local s = ns.Database.Settings()
    s.lcItems = s.lcItems or {}
    local o = s.lcItems
    if o.altClick == nil then o.altClick = true end
    if o.autoAdd == nil then o.autoAdd = false end
    if o.boe == nil then o.boe = false end
    return o
end
Queue.Options = opts

local function changed() ns.Fire("LG_COUNCIL") end

---------------------------------------------------------------------------
-- Queue
---------------------------------------------------------------------------
function Queue.Add(item, quiet)
    local s = Items.String(item) or (type(item) == "string" and item:match("^item:") and item)
    if not s then return false end
    table.insert(Council.pending, s)
    if not quiet then
        ns.Print(L.LC_QUEUED:format(Items.Link(s) or s, #Council.pending))
        changed()
    end
    return true
end

function Queue.Remove(index)
    if Council.pending[index] then table.remove(Council.pending, index); changed() end
end

function Queue.Clear()
    wipe(Council.pending)
    changed()
end

local function countIn(list, s)
    local n = 0
    for _, v in ipairs(list) do if v == s then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
-- Bag scan: tradeable loot (trade timer line in the tooltip)
---------------------------------------------------------------------------
local function escape(text) return (text:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")) end

local tradePattern
local function getTradePattern()
    if tradePattern ~= nil then return tradePattern end
    local t = BIND_TRADE_TIME_REMAINING
    tradePattern = false
    if type(t) == "string" then
        local a, b = t:match("^(.-)%%%d?%$?s(.*)$")
        if a then tradePattern = "^" .. escape(a) .. "(.+)" .. escape(b) end
    end
    return tradePattern
end

-- Two ways to read a bag item's tooltip. The rendered tooltip (hidden
-- GameTooltip + SetBagItem) shows the same text as the bag tooltip; the
-- C_TooltipInfo data can carry an older trade time, so it is only the fallback.
local scanTip
local function renderedLines(bag, slot)
    local lines = {}
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "LiebeGruesseScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    if not pcall(scanTip.SetBagItem, scanTip, bag, slot) then return lines end
    for i = 1, (scanTip:NumLines() or 0) do
        local fs = _G["LiebeGruesseScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if type(text) == "string" and not ns.IsSecret(text) then lines[#lines + 1] = text end
    end
    scanTip:Hide()
    return lines
end

local function dataLines(bag, slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = ns.Call(C_TooltipInfo.GetBagItem, bag, slot)
        if type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                if type(line) == "table" and type(line.leftText) == "string" then lines[#lines + 1] = line.leftText end
            end
        end
    end
    return lines
end

local function tooltipLines(bag, slot)
    local lines = renderedLines(bag, slot)
    if #lines > 0 then return lines end
    return dataLines(bag, slot)
end
Queue.RenderedLines, Queue.DataLines = renderedLines, dataLines

Queue.TooltipLines = tooltipLines
Queue.TradePattern = getTradePattern

local function containerAPI()
    local C = C_Container
    return (C and C.GetContainerNumSlots) or GetContainerNumSlots, (C and C.GetContainerItemLink) or GetContainerItemLink
end

-- { { s = itemString, link, bag, slot, why = "trade"|"recent"|"boe", left = seconds or nil } }
Queue.ContainerAPI = function() return containerAPI() end

function Queue.BagItems()
    local numSlots, itemLink = containerAPI()
    if not numSlots or not itemLink then return {} end
    local o = opts()
    local minQuality = Council.Config().quality or 4
    local pattern = getTradePattern()
    local recent = {}
    for _, r in ipairs(Council.recent or {}) do
        if ns.Now() - r.t < 7200 then recent[r.s] = math.max(recent[r.s] or 0, r.t) end
    end
    local found, seen = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.Call(numSlots, bag) or 0) do
            local link = ns.Call(itemLink, bag, slot)
            local s = Items.String(link)
            local info = s and Items.Info(s)
            if info and (info.quality or 0) >= minQuality and not Council.IsIgnored(s, info) then
                local why, left
                for _, text in ipairs(tooltipLines(bag, slot)) do
                    if pattern and text:match(pattern) then why = "trade"; break end
                    if text == ITEM_SOULBOUND then why = why or "bound" end
                end
                if why ~= "trade" and why ~= "bound" and recent[s] then why = "recent" end
                if not why and o.boe then
                    local bind = select(14, ns.Call((C_Item and C_Item.GetItemInfo) or GetItemInfo, s))
                    if bind == 2 then why = "boe" end
                end
                if why == "trade" or why == "recent" or why == "boe" then
                    if recent[s] then left = 7200 - (ns.Now() - recent[s]) end
                    seen[s] = (seen[s] or 0) + 1
                    found[#found + 1] = { s = s, link = info.link or link, bag = bag, slot = slot, why = why, left = left,
                        queued = seen[s] <= countIn(Council.pending, s) }
                end
            end
        end
    end
    return found
end

-- Adds every tradeable item from the bags that is not queued yet
function Queue.AddAll()
    local added = 0
    for _, item in ipairs(Queue.BagItems()) do
        if not item.queued then
            table.insert(Council.pending, item.s)
            added = added + 1
        end
    end
    ns.Print(L.LC_ADDED_ALL:format(added, #Council.pending))
    changed()
    return added
end
Council.AddRecent = Queue.AddAll

---------------------------------------------------------------------------
-- Drag & drop and Alt-click
---------------------------------------------------------------------------
function Queue.DropCursor()
    local kind, _, link = ns.Call(GetCursorInfo)
    if kind ~= "item" or type(link) ~= "string" then return false end
    ClearCursor()
    Queue.Add(link)
    if ns.CouncilWindow then ns.CouncilWindow.ShowQueue() end
    return true
end

local function mayQueue()
    return not IsInGroup() or Council.IAmLootMaster()
end

ns.On("LG_READY", function()
    if not hooksecurefunc or not HandleModifiedItemClick then return end
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not opts().altClick or ns.IsSecret(link) or type(link) ~= "string" then return end
        if not (IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()) then return end
        if not link:find("|Hitem:") or not mayQueue() then return end
        if ns.Database.Settings().modules.council == false then return end
        Queue.Add(link)
        if ns.CouncilWindow then ns.CouncilWindow.ShowQueue() end
    end)
end)

---------------------------------------------------------------------------
-- Automatic queueing of own loot as loot master
---------------------------------------------------------------------------
ns.On("CHAT_MSG_LOOT", function(_, text)
    if ns.IsSecret(text) or type(text) ~= "string" or not opts().autoAdd then return end
    if not IsInRaid() or not Council.IAmLootMaster() then return end
    local link = text:match("|H(item:[^|]+)|h")
    local self = LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(.-)%%s")
    if not link or not self or not text:find(self, 1, true) then return end
    local info = Items.Info(link)
    if info and (info.quality or 0) >= (Council.Config().quality or 4) and not Council.IsIgnored(link, info) then
        Queue.Add(link)
    end
end)
