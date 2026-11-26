-- Quick actions: a small bar of one-line prompts for "!lg" answers only
-- ("Salty Brown asked for [Lionheart Helm] – click to post"). A click is your
-- own action, so the game lets the chat line through – no automatic line needed.
-- Notifications (toasts), greetings and congratulations stay as they are.
-- Placed with "Move elements"; nothing runs while it is empty (one timer per
-- entry for its expiry, no OnUpdate).
local _, ns = ...
local UI, Theme, L = ns.UI, ns.Theme, ns.L

local QB = {}
ns.QuickBar = QB
local WIDTH, ROW_H, GAP = 320, 30, 3

QB.entries = {}   -- newest first: { key, icon, text, tip, send, onClick, group, timer, t }
local rows, holder = {}, nil

function QB.Settings()
    local s = ns.Database.Settings()
    s.quick = s.quick or {}
    local q = s.quick
    -- auto: "ask" = "!lg" answers for players without the addon wait here, "send" = sent by the addon
    local defaults = { enabled = true, auto = "ask", craft = true, craftLink = true, ttl = 15, max = 4, scale = 1 }
    for k, v in pairs(defaults) do if q[k] == nil then q[k] = v end end
    -- 1.0.82: lines stay 15 s by default (first builds had 90 s)
    if not q.ttl15 then q.ttl15 = true; if q.ttl == 90 then q.ttl = 15 end end
    return q
end

-- "!lg" answers for players without the addon: ask first (bar) instead of sending them
function QB.AskFirst()
    local q = QB.Settings()
    return q.enabled and q.auto == "ask"
end

local function remove(key)
    for i, e in ipairs(QB.entries) do
        if e.key == key then
            if e.timer then e.timer:Cancel() end
            table.remove(QB.entries, i)
            return true
        end
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function shrink(row, ttl)
    -- thin line at the bottom that runs empty until the prompt goes away
    row.drain:SetWidth(WIDTH - 2)
    if row.anim then row.anim:Stop() end
    if not (row.drainAnim and ttl and ttl > 0) then return end
    row.drainAnim:SetDuration(ttl)
    row.anim:Play()
end

local function makeRow(i)
    local r = CreateFrame("Button", nil, holder, "BackdropTemplate")
    UI.Skin(r, "bg", "borderDim")
    r:SetSize(WIDTH, ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.accent = UI.Fill(r, "accent", "ARTWORK")
    r.accent:SetPoint("TOPLEFT", 1, -1); r.accent:SetPoint("BOTTOMLEFT", 1, 1); r.accent:SetWidth(2)
    r.hl = UI.Fill(r, "hover", "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 10, 0)
    r.close = UI.IconButton(r, "x", 18, function() QB.Remove(r.key) end)
    r.close:SetPoint("RIGHT", -5, 0)
    r.close.tip = L.QB_DISMISS
    r.text = UI.Text(r, 12, "text")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", r.close, "LEFT", -6, 0)
    r.drain = UI.Fill(r, "accent", "OVERLAY")
    r.drain:SetPoint("BOTTOMLEFT", 1, 1)
    r.drain:SetHeight(1)
    r.drain:SetAlpha(0.7)
    r.anim = r.drain:CreateAnimationGroup()
    local a = r.anim:CreateAnimation("Scale")
    if a.SetScaleFrom then a:SetScaleFrom(1, 1); a:SetScaleTo(0.001, 1); r.drainAnim = a
    elseif a.SetFromScale then a:SetFromScale(1, 1); a:SetToScale(0.001, 1); r.drainAnim = a end
    if a.SetOrigin then a:SetOrigin("LEFT", 0, 0) end
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then QB.Remove(self.key) else QB.Run(self.key) end
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        local lines = {}
        for _, l in ipairs(e.tip or {}) do lines[#lines + 1] = l end
        if e.send then lines[#lines + 1] = Theme.HexColor("muted", L.QB_WILL_SEND) .. " " .. e.send[1] end
        lines[#lines + 1] = Theme.HexColor("muted", e.hint or (e.send and L.QB_CLICK_SEND or L.QB_CLICK_OPEN))
        UI.Tooltip(self, e.title or e.text, lines)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function sample()
    return { key = "sample", icon = "message-circle", text = L.QB_SAMPLE, tip = { L.QB_SAMPLE_TIP } }
end

function QB.Layout()
    if not holder then return end
    local q = QB.Settings()
    holder:SetScale(q.scale or 1)
    local list = QB.entries
    -- while placing the elements: one sample line shows where the bar is
    if (#list == 0) and ns.Movers.active then list = { sample() } end
    local shown = q.enabled and math.min(#list, q.max or 4) or 0
    for i = 1, shown do
        local e = list[i]
        local r = rows[i] or makeRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * (ROW_H + GAP))
        r.key, r.entry = e.key, e
        if type(e.icon) == "number" then r.icon:SetTexture(e.icon); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); r.icon:SetVertexColor(1, 1, 1)
        else Theme.SetIcon(r.icon, e.icon or "message-circle"); r.icon:SetVertexColor(Theme.Color("accent")) end
        r.text:SetText(e.text or "")
        if r.shownFor ~= e then
            r.shownFor = e
            shrink(r, e.expires and (e.expires - GetTime()) or nil)
        end
        r:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide(); rows[i].shownFor = nil end
    -- more than fit: the last line says so
    if q.enabled and #list > shown and shown > 0 then
        local r = rows[shown]
        r.text:SetText(r.entry.text .. "  " .. Theme.HexColor("muted", L.QB_MORE:format(#list - shown)))
    end
    holder:SetShown(shown > 0)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- e = { key, icon (Lucide name or texture id), text, title, tip = { lines },
--       send = { text, chatType, target }, check = fn() -> ok, reason,
--       onClick = fn() (return false to keep the line), group, ttl }
-- Same key replaces the older line. Returns true when it is shown.
function QB.Add(e)
    local q = QB.Settings()
    if not q.enabled or not e or not e.key then return false end
    remove(e.key)
    local ttl = e.ttl or q.ttl or 15
    e.expires = GetTime() + ttl
    e.timer = C_Timer.NewTimer(ttl, function() if remove(e.key) then QB.Layout() end end)
    table.insert(QB.entries, 1, e)
    -- keep the list short (the oldest go)
    while #QB.entries > 20 do
        local old = table.remove(QB.entries)
        if old.timer then old.timer:Cancel() end
    end
    QB.Layout()
    return true
end

function QB.Remove(key)
    if remove(key) then QB.Layout() end
end

function QB.RemoveGroup(group)
    local any = false
    for i = #QB.entries, 1, -1 do
        local e = QB.entries[i]
        if e.group == group then
            if e.timer then e.timer:Cancel() end
            table.remove(QB.entries, i)
            any = true
        end
    end
    if any then QB.Layout() end
end

function QB.Clear()
    for _, e in ipairs(QB.entries) do if e.timer then e.timer:Cancel() end end
    wipe(QB.entries)
    QB.Layout()
end

function QB.Get(key)
    for _, e in ipairs(QB.entries) do if e.key == key then return e end end
end

-- a click: send the line (or run the action) and remove it
function QB.Run(key)
    local e = QB.Get(key)
    if not e then return end
    if e.check then
        local ok, reason = e.check()
        if not ok then
            if reason then ns.Print(reason) end
            QB.Remove(key)
            return
        end
    end
    local done = true
    if e.send then
        if e.test then ns.Print("%s %s", L.TEST_TAG, e.send[1])
        else done = ns.SendChat(e.send[1], e.send[2], e.send[3]) == true end
    end
    if e.onClick then
        local r = ns.Try(e.onClick, e, done)
        if r == false then done = false end
    end
    if done then QB.Remove(key) end
end

-- /lg test quick: sample "!lg" lines (a click only prints, nothing is sent)
function QB.Test()
    local me = ns.Names.Display(ns.Names.Me())
    local answer = "[LG] [Lionheart Helm]: " .. me .. " (online) · mats ~64g"
    QB.Add({ key = "test-craft", icon = "hammer", test = true, text = L.QB_CRAFT_ASKED:format("Salty Brown", "[Lionheart Helm]"),
        tip = { answer, L.QB_CRAFT_POST_TIP }, send = { answer, "GUILD" }, ttl = 120 })
    QB.Add({ key = "test-whisper", icon = "hammer", test = true, text = L.QB_CRAFT_WHISPERED:format("Mar Cha", "[Arcanite Rod]"),
        send = { "[LG] [Arcanite Rod]: " .. me .. " (online)", "WHISPER", "Mar Cha" }, ttl = 120 })
    ns.Print(L.QB_TEST_DONE)
end

---------------------------------------------------------------------------
-- Anchor and settings
---------------------------------------------------------------------------
ns.On("LG_READY", function()
    holder = ns.Movers.Anchor("quickBar", L.QB_TITLE, { "TOP", "TOP", 0, -330 }, WIDTH, ROW_H * 2 + GAP, nil, {
        icon = "zap",
        settings = function() ns.Window.ShowSettings("professions") end,
        sizes = { { label = L.CD_SCALE, min = 0.6, max = 1.6, step = 0.05, pct = true,
            get = function() return QB.Settings().scale end, set = function(v) QB.Settings().scale = v; QB.Layout() end } },
    })
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
end)
ns.On("LG_MOVERS", function() QB.Layout() end)
ns.On("LG_THEME", function() QB.Layout() end)

-- card on the Notifications page
function QB.SettingsCard(form)
    local q = QB.Settings
    local s = form:Section(L.QB_TITLE)
    s:Note(L.QB_HINT, { col = 0, height = 44 })
    s:Toggle(L.QB_ENABLED, function() return q().enabled end, function(v) q().enabled = v; QB.Layout() end)
    s:Segment(L.QB_AUTO, { { value = "ask", text = L.QB_AUTO_ASK }, { value = "send", text = L.QB_AUTO_SEND } },
        function() return q().auto end, function(v) q().auto = v end,
        { width = 220, tip = L.QB_AUTO_TIP, show = function() return q().enabled end })
    s:Toggle(L.QB_CRAFT, function() return q().craft end, function(v) q().craft = v end,
        { tip = L.QB_CRAFT_TIP, show = function() return q().enabled end })
    s:Toggle(L.QB_CRAFT_LINK, function() return q().craftLink end, function(v) q().craftLink = v end, { col = 2, tip = L.QB_CRAFT_LINK_TIP })
    s:Slider(L.QB_TTL, 10, 120, 5, function() return q().ttl end, function(v) q().ttl = v end,
        { col = 2, fmt = function(v) return ("%d s"):format(v) end, show = function() return q().enabled end })
    s:Buttons({ { L.NOTIFY_TEST, function() QB.Test() end, width = 140, icon = "sparkles" },
        { L.MOVE_ELEMENTS, function() ns.Window.ToggleMovers() end, width = 170, icon = "move" } }, { col = 0 })
    return s
end
