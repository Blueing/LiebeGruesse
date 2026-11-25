-- "Trade expiration timers": a small movable list of the items in your bags
-- that can still be traded (loot from a group), with the time left as a
-- draining bar in the item's quality colour.
local _, ns = ...
local UI, Theme, L, Items = ns.UI, ns.Theme, ns.L, ns.Items
local TT = {}
ns.TradeTimers = TT

-- loot can be traded for two hours on classic; some servers allow longer, so
-- the bar's full length grows with the longest time seen
local TOTAL = 7200

function TT.Settings()
    local s = ns.Database.Settings()
    s.tradeTimers = s.tradeTimers or {}
    local o = s.tradeTimers
    local d = { enabled = true, onlyML = true, minQuality = 2, width = 250, rowHeight = 20, warn = true, warnMinutes = 10, scale = 1 }
    for k, v in pairs(d) do if o[k] == nil then o[k] = v end end
    return o
end

-- "1 hour 4 min", "1 Std. 4 Min.", "25 min", "45 sec" → seconds
local UNITS = { { "^h", 3600 }, { "^std", 3600 }, { "^hour", 3600 }, { "^stu", 3600 },
    { "^m", 60 }, { "^s", 1 } }
function TT.ParseTime(text)
    if type(text) ~= "string" then return nil end
    -- colour codes and textures would add digits of their own
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    -- clock format "1:02:03" / "2:03"
    local h, m, sec = text:match("(%d+):(%d%d):(%d%d)")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
    local m2, s2 = text:match("(%d+):(%d%d)")
    if m2 then return tonumber(m2) * 60 + tonumber(s2) end
    local total, any = 0, false
    for n, unit in text:lower():gmatch("(%d+)%s*([%a%.]+)") do
        for _, u in ipairs(UNITS) do
            if unit:find(u[1]) then total = total + tonumber(n) * u[2]; any = true; break end
        end
    end
    return any and total or nil
end

TT.items = {}   -- { s, link, icon, quality, expires (GetTime based) }
TT.test = nil

function TT.Scan()
    if not TT.Settings().enabled and not TT.test then TT.items = {}; TT.Layout(); return end
    local Queue = ns.CouncilQueue
    if not Queue or not Queue.ContainerAPI then return end
    local numSlots, itemLink = Queue.ContainerAPI()
    local pattern = Queue.TradePattern()
    if not numSlots or not itemLink or not pattern then return end
    local o = TT.Settings()
    local list, now = {}, GetTime()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.Call(numSlots, bag) or 0) do
            local link = ns.Call(itemLink, bag, slot)
            local s = Items.String(link)
            local info = s and Items.Info(s)
            if info and (info.quality or 0) >= o.minQuality then
                for _, text in ipairs(Queue.TooltipLines(bag, slot)) do
                    local rest = text:match(pattern)
                    if rest then
                        local left = TT.ParseTime(rest)
                        if left then
                            if left > TOTAL then TOTAL = math.min(left, 6 * 3600) end
                            list[#list + 1] = { s = s, link = info.link or link, icon = Items.Icon(s), quality = info.quality or 1,
                                name = info.name, expires = now + left, bag = bag, slot = slot, raw = rest, readAt = now }
                        end
                        break
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.expires < b.expires end)
    TT.items = list
    TT.Layout()
end

local function fmt(sec)
    sec = math.max(0, math.floor(sec))
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end
TT.Format = fmt

local frame
local function create()
    frame = UI.Panel(UIParent, "bg", "border")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    TT.frame = frame
    frame.title = UI.Text(frame, 12, "text")
    frame.title:SetPoint("TOPLEFT", 8, -6)
    frame.title:SetText(L.TT_TITLE)
    frame.gear = UI.IconButton(frame, "settings", 16, function()
        ns.Window.Show("council"); if ns.CouncilPage then ns.CouncilPage.ShowSetup() end
    end)
    -- close: hides the list until a new tradeable item appears
    frame.close = UI.IconButton(frame, "x", 16, function() TT.Dismiss() end)
    frame.close:SetPoint("TOPRIGHT", -4, -3)
    frame.close.tip = L.TT_CLOSE_TIP
    frame.gear:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)
    frame.gear.tip = L.MOVE_OPTIONS
    frame.lock = ns.Movers.LockButton("tradeTimers", frame, frame, 16)
    frame.lock:SetPoint("RIGHT", frame.gear, "LEFT", -4, 0)
    -- the title ends before the buttons (width set in Layout)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.rows = {}
    ns.Movers.Attach("tradeTimers", frame)
end

local function row(i)
    local r = frame.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, frame)
    r.bg = UI.Fill(r, "rowAlt", "BACKGROUND"); r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetTexture(Theme.WHITE)
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT"); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.time = UI.Text(r, 12, "text", "RIGHT")
    r.time:SetPoint("RIGHT", -5, 0)
    r.name = UI.Text(r, 12, "text")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetPoint("RIGHT", r.time, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", function(self)
        if not self.item then return end
        Items.ShowTooltip(self, self.item.link, "ANCHOR_LEFT")
        if self.item.raw then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.TT_SOURCE:format(self.item.raw, ns.Duration(GetTime() - (self.item.readAt or GetTime()))), 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end
        -- hovering re-reads the time from the bag tooltip
        ns.Debounce("tt-scan", 0.2, TT.Scan)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        local item = self.item
        if not item then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(item.link); return end
        if button == "RightButton" then
            UI.ContextMenu({ { title = item.name or "" },
                { text = L.TT_ADD_LC, func = function() ns.CouncilQueue.Add(item.s) end },
                { text = L.TT_LINK_RAID, func = function() ns.SendChat(L.TT_LINK_TEXT:format(item.link, fmt(item.expires - GetTime())), IsInRaid() and "RAID" or "PARTY") end,
                  disabled = not IsInGroup() },
            })
        else
            ns.CouncilQueue.Add(item.s)
        end
    end)
    frame.rows[i] = r
    return r
end

local warned = {}
function TT.Layout()
    local o = TT.Settings()
    local list = TT.test or TT.items
    -- closed: stays hidden until an item shows up that was not in the list when it was closed
    if TT.hidden and not TT.test then
        local new = false
        for _, item in ipairs(list) do
            if not TT.hidden[(item.s or "") .. ":" .. (item.bag or 0) .. ":" .. (item.slot or 0)] then new = true end
        end
        if new then TT.hidden = nil end
    end
    -- only for the master looter (option), except in tests and move mode
    local forMe = not o.onlyML or TT.test or ns.Movers.active or (ns.Council and ns.Council.IsMasterLooter())
    local show = o.enabled and forMe and ns.Database.Settings().modules.council ~= false and (#list > 0 or ns.Movers.active)
        and (not TT.hidden or ns.Movers.active)
    if not show then
        if frame then frame:Hide() end
        TT.ticker:Hide()
        if ns.CouncilBar then ns.Debounce("lc-bar", 0.1, ns.CouncilBar.Layout) end
        return
    end
    if not frame then create() end
    local h = o.rowHeight
    local now = GetTime()
    local n = 0
    for _, item in ipairs(list) do
        local left = item.expires - now
        if left > 0 then
            n = n + 1
            local r = row(n)
            r.item = item
            r:SetSize(o.width - 8, h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 4, -22 - (n - 1) * (h + 1))
            r.icon:SetSize(h, h)
            r.icon:SetTexture(item.icon or 134400)
            local qr, qg, qb = 0.6, 0.6, 0.6
            if GetItemQualityColor then
                local ok, a, b, c = pcall(GetItemQualityColor, item.quality)
                if ok and type(a) == "number" then qr, qg, qb = a, b, c end
            end
            r.bar:SetVertexColor(qr * 0.55, qg * 0.55, qb * 0.55, 0.9)
            r.barMax = o.width - 8
            r.bar:SetWidth(math.max(1, r.barMax * math.min(1, left / TOTAL)))
            r.name:SetText(("|cff%02x%02x%02x[%s]|r"):format(qr * 255, qg * 255, qb * 255, item.name or "?"))
            r.time:SetText(fmt(left))
            r:Show()
            if o.warn and left < o.warnMinutes * 60 and not warned[item.s .. (item.bag or 0) .. (item.slot or 0)] and not TT.test then
                warned[item.s .. (item.bag or 0) .. (item.slot or 0)] = true
                UI.Toast(L.TT_TITLE, L.TT_WARN:format(item.link or item.name or "?", math.ceil(left / 60)), item.icon)
            end
        end
    end
    for i = n + 1, #frame.rows do frame.rows[i]:Hide() end
    frame:SetSize(o.width, 26 + math.max(1, n) * (h + 1))
    frame.title:SetWidth(math.max(20, o.width - 8 - 3 * 20 - 8))
    frame:SetScale(o.scale)
    frame:SetShown(n > 0 or ns.Movers.active)
    TT.ticker:SetShown(n > 0)
    if ns.CouncilBar then ns.Debounce("lc-bar", 0.1, ns.CouncilBar.Layout) end
end

-- smooth countdown between scans
-- runs only while the list is visible (an OnUpdate costs nothing on a hidden frame)
local acc, rescanAcc = 0, 0
local ticker = CreateFrame("Frame")
ticker:Hide()
TT.ticker = ticker
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 1 then return end
    acc = 0
    rescanAcc = rescanAcc + 1
    if rescanAcc >= 60 and not TT.test then rescanAcc = 0; ns.Debounce("tt-scan", 0.1, TT.Scan) end
    if frame and frame:IsShown() then
        local now = GetTime()
        for _, r in ipairs(frame.rows) do
            if r:IsShown() and r.item then
                local left = r.item.expires - now
                if left <= 0 then ns.Debounce("tt-layout", 0.1, TT.Layout) end
                r.time:SetText(fmt(left))
                r.bar:SetWidth(math.max(1, (r.barMax or 200) * math.min(1, math.max(0, left) / TOTAL)))
            end
        end
    end
end)

function TT.Dismiss()
    TT.hidden = {}
    for _, item in ipairs(TT.items) do TT.hidden[(item.s or "") .. ":" .. (item.bag or 0) .. ":" .. (item.slot or 0)] = true end
    if TT.test then TT.test = nil end
    TT.Layout()
end

-- /lg test trade raw: the tooltip lines the timers are read from
function TT.Debug()
    local Queue = ns.CouncilQueue
    local numSlots, itemLink = Queue.ContainerAPI()
    local pattern = Queue.TradePattern()
    ns.Print(L.TEST_TAG .. " BIND_TRADE_TIME_REMAINING = " .. tostring(BIND_TRADE_TIME_REMAINING) .. "  ·  pattern: " .. tostring(pattern))
    local found = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.Call(numSlots, bag) or 0) do
            local link = ns.Call(itemLink, bag, slot)
            if link then
                -- both sources, to see which one carries the right time
                for _, src in ipairs({ { "tooltip", Queue.RenderedLines }, { "data", Queue.DataLines } }) do
                    for _, text in ipairs(src[2](bag, slot)) do
                        local rest = pattern and text:match(pattern)
                        if rest then
                            found = found + 1
                            ns.Print(("%s [%s]  \"%s\"  ->  %s"):format(link, src[1], rest, fmt(TT.ParseTime(rest) or 0)))
                        end
                    end
                end
            end
        end
    end
    if found == 0 then ns.Print(L.TEST_TAG .. " " .. L.TT_DEBUG_NONE) end
end

function TT.Test()
    local now = GetTime()
    TT.test = {
        { s = "item:19019", name = "Bladeangel's Money Belt", quality = 4, icon = 132492, expires = now + 25 * 60 + 53, link = "item:19019" },
        { s = "item:19137", name = "Shadowtooth Trollskin Cuirass", quality = 4, icon = 132631, expires = now + 3893, link = "item:19137" },
        { s = "item:18646", name = "Heartless", quality = 2, icon = 135274, expires = now + 5273, link = "item:18646" },
        { s = "item:17064", name = "Brooch of Nature's Mercy", quality = 3, icon = 133292, expires = now + 7133, link = "item:17064" },
    }
    TT.Layout()
    ns.After(60, function() TT.test = nil; TT.Layout() end)
end

ns.On("BAG_UPDATE_DELAYED", function()
    if not TT.Settings().enabled or ns.Database.Settings().modules.council == false then return end
    ns.Debounce("tt-scan", 2, TT.Scan)
end)
ns.On("LG_MOVERS", function() TT.Layout() end)
-- master looter changes: show or hide the list
for _, e in ipairs({ "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    ns.On(e, function() ns.Debounce("tt-ml", 0.5, function() TT.Layout() end) end)
end
ns.On("LG_READY", function()
    ns.Movers.Anchor("tradeTimers", L.TT_TITLE, { "RIGHT", "RIGHT", -260, 80 }, 250, 110, nil, { icon = "timer",
        onFollow = function() if ns.CouncilBar then ns.CouncilBar.Layout() end end,
        settings = function() ns.Window.Show("council"); if ns.CouncilPage then ns.CouncilPage.ShowSetup() end end,
        sizes = {
            { label = L.CD_SCALE, min = 0.5, max = 2, step = 0.05, pct = true, get = function() return TT.Settings().scale end,
              set = function(v) TT.Settings().scale = v; TT.Layout() end },
            { label = L.TT_WIDTH, min = 160, max = 420, step = 2, get = function() return TT.Settings().width end,
              set = function(v) TT.Settings().width = v; TT.Layout() end },
            { label = L.TT_ROW_HEIGHT, min = 14, max = 32, step = 1, get = function() return TT.Settings().rowHeight end,
              set = function(v) TT.Settings().rowHeight = v; TT.Layout() end },
        } })
    -- bags are read only when they change (BAG_UPDATE_DELAYED) or after looting; the countdown needs no rescans.
    -- Right after login the client can still show an old trade time (the timer also runs while offline),
    -- so the list is read again a few times – one-shot timers, nothing periodic.
    ns.After(5, TT.Scan)
    ns.After(30, TT.Scan)
    ns.After(120, TT.Scan)
end)
