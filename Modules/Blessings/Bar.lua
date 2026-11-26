-- Blessing bar for paladins: one row per class you bless (class, blessing,
-- buffed/total, minutes left). Left click: greater blessing on that class,
-- right click: single blessing on someone missing it. "Auto Assign":
-- left click casts the next missing blessing, right click fills in the
-- assignments. Every cast is one click (secure buttons, as the game requires).
local _, ns = ...
local UI, Theme, L = ns.UI, ns.Theme, ns.L
local B = ns.Blessings
local Bar = {}
ns.BlessingsBar = Bar

local WIDTH, ROW_H = 176, 28
local frame, auto, rows = nil, nil, {}

local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function inRange(spellName, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        local r = ns.Call(C_Spell.IsSpellInRange, spellName, unit)
        if r ~= nil then return r == true or r == 1 end
    end
    if IsSpellInRange then
        local r = ns.Call(IsSpellInRange, spellName, unit)
        if r ~= nil then return r == 1 end
    end
    return true
end
local function usable(unit)
    return ns.Call(UnitExists, unit) and not ns.Call(UnitIsDeadOrGhost, unit) and ns.Call(UnitIsConnected, unit) ~= false
end

-- a unit of that class to cast on: someone who misses it and is in range first
local function pickUnit(class, spellName, needList)
    for _, unit in ipairs(needList or {}) do
        if usable(unit) and inRange(spellName, unit) then return unit end
    end
    for _, unit in ipairs(B.classUnits[class] or {}) do
        if usable(unit) and inRange(spellName, unit) then return unit end
    end
    local list = B.classUnits[class]
    return list and list[1]
end

local function setSecure(button, attrs)
    if inCombat() then return false end
    if B.test then attrs = { type1 = false, type2 = false } end   -- test raiders: clicks cast nothing
    button.lgAttrs = button.lgAttrs or {}
    for k, v in pairs(attrs) do
        button:SetAttribute(k, v or nil)
        button.lgAttrs[k] = v or nil
    end
    return true
end
-- current value of a secure attribute (the combat snippet below can change unit1/unit2)
local function attr(button, key)
    local v = button:GetAttribute(key)
    if v == nil and button.lgAttrs then v = button.lgAttrs[key] end
    return v
end

-- after a click: remember whom the blessing went to (auras are hidden in combat)
local function noteClick(button, mouse)
    local which = (mouse == "RightButton") and "2" or "1"
    if attr(button, "type" .. which) ~= "spell" then return end
    local unit, spell = attr(button, "unit" .. which), attr(button, "spell" .. which)
    if unit and spell then B.NoteCastTarget(unit, spell) end
end

-- In combat the attributes are frozen, so a right-click would always hit the
-- same player (and nothing at all once he is dead). This secure snippet runs
-- before each click in combat: right-click steps through the class (players
-- missing the blessing first), left-click only skips a dead target. Outside
-- of combat it does nothing – the bar picks the target itself.
local ROTATE = [[
    if button ~= "LeftButton" and button ~= "RightButton" then return end
    if not SecureCmdOptionParse("[combat] 1") then return end
    local n = self:GetAttribute("lg-n") or 0
    if n == 0 then return end
    local which = (button == "RightButton") and "2" or "1"
    if not self:GetAttribute("spell" .. which) then return end
    local current = self:GetAttribute("unit" .. which)
    if which == "1" and current and SecureCmdOptionParse("[@" .. current .. ",help,nodead] 1") then return end
    local step = (which == "2") and (self:GetAttribute("lg-step") or 1) or 1
    for i = 0, n - 1 do
        local idx = (step - 1 + i) % n + 1
        local unit = self:GetAttribute("lg-u" .. idx)
        if unit and SecureCmdOptionParse("[@" .. unit .. ",help,nodead] 1") then
            self:SetAttribute("unit" .. which, unit)
            if which == "2" and not down then self:SetAttribute("lg-step", idx % n + 1) end
            return
        end
    end
]]
local header
local function wrapRotation(button)
    if not (SecureHandlerWrapScript and SecureCmdOptionParse) then return end
    if not header then
        local ok, f = pcall(CreateFrame, "Frame", "LiebeGruesseBlessHeader", UIParent, "SecureHandlerBaseTemplate")
        if not ok or not f then return end
        header = f
    end
    pcall(SecureHandlerWrapScript, button, "OnClick", header, ROTATE)
end
-- the order for the combat snippet: the chosen target, then whoever misses
-- the blessing, then the rest of the class
local function rotation(button, class, first, needList)
    local list, seen = {}, {}
    local function add(u) if u and not seen[u] then seen[u] = true; list[#list + 1] = u end end
    add(first)
    for _, u in ipairs(needList or {}) do add(u) end
    for _, u in ipairs(B.classUnits[class] or {}) do add(u) end
    local old = button.lgRotation or 0
    local attrs = { ["lg-n"] = #list, ["lg-step"] = 1 }
    for i = 1, math.max(#list, old) do attrs["lg-u" .. i] = list[i] or false end
    button.lgRotation = #list
    setSecure(button, attrs)
end

local function fmtLeft(sec)
    if not sec or sec == math.huge then return "" end
    if sec >= 60 then return ("%dm"):format(math.floor(sec / 60)) end
    return ("%ds"):format(math.max(0, math.floor(sec)))
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function makeRow(i)
    local r = CreateFrame("Button", "LiebeGruesseBlessRow" .. i, frame, "SecureActionButtonTemplate")
    r:SetSize(WIDTH - 8, ROW_H - 2)
    r:RegisterForClicks("AnyUp", "AnyDown")
    -- down and up: the cast follows the key-down setting, noting twice is harmless
    r:HookScript("PostClick", function(self, mouse) noteClick(self, mouse) end)
    wrapRotation(r)
    r.bg = UI.Fill(r, "rowAlt", "BACKGROUND"); r.bg:SetAllPoints()
    r.hl = UI.Fill(r, "hover", "HIGHLIGHT"); r.hl:SetAllPoints()
    r.mark = UI.Fill(r, "bad", "ARTWORK")
    r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); r.mark:SetWidth(2)
    r.class = r:CreateTexture(nil, "ARTWORK")
    r.class:SetSize(20, 20)
    r.class:SetPoint("LEFT", 6, 0)
    r.bless = r:CreateTexture(nil, "ARTWORK")
    r.bless:SetSize(20, 20)
    r.bless:SetPoint("LEFT", r.class, "RIGHT", 4, 0)
    r.bless:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.count = UI.Text(r, 13, "text")
    r.count:SetPoint("LEFT", r.bless, "RIGHT", 8, 0)
    r.left = UI.Text(r, 13, "good", "RIGHT")
    r.left:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnEnter", function(self)
        if not self.cls then return end
        ns.TipOwner(self, "ANCHOR_LEFT")
        local cname = ns.ClassName(self.cls)
        local cr, cg, cb = ns.ClassColor(self.cls)
        GameTooltip:AddLine(ns.ClassIcon(self.cls, 14) .. " " .. cname, cr, cg, cb)
        GameTooltip:AddLine(B.Name(self.blessing) or "", 1, 0.82, 0)
        if self.absent then GameTooltip:AddLine(L.BLESS_ROW_ABSENT, 0.6, 0.6, 0.6, true) end
        local st = B.status[self.cls]
        if st and st.estimated and not self.absent then
            GameTooltip:AddLine((ns.BlessNative and ns.BlessNative.Active()) and L.BLESS_ESTIMATED_LIVE or L.BLESS_ESTIMATED, 0.6, 0.6, 0.6, true)
        end
        for _, m in ipairs(B.missing) do
            if m.class == self.cls then
                for _, b in ipairs(m.list) do
                    if b == self.blessing then GameTooltip:AddLine(L.BLESS_TIP_MISSING:format(m.name), 1, 0.4, 0.4) end
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.BLESS_ROW_TIP, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- wheel: change the blessing for this class (secure attributes can only
    -- follow outside of combat, so it is blocked there)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(self, delta)
        if not self.cls then return end
        if inCombat() then ns.Print(L.BLESS_WHEEL_COMBAT); return end
        if B.Cycle(B.Me(), self.cls, delta, true) then
            self.blessing = B.Me().set[self.cls]
            if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
        end
    end)
    r:Hide()
    rows[i] = r
    return r
end

local function create()
    if frame or inCombat() then return frame end
    frame = UI.Panel(UIParent, "bg", "border")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetWidth(WIDTH)
    frame:Hide()

    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", 4, -4)
    head:SetPoint("TOPRIGHT", -4, -4)
    head:SetHeight(24)
    local open = UI.IconButton(head, "users", 22, function() ns.Window.Show("blessings") end)
    open:SetPoint("LEFT")
    open.tip = L.PAGE_BLESSINGS
    local gear = UI.IconButton(head, "settings", 22, function() ns.Window.Show("blessings") end)
    gear:SetPoint("LEFT", open, "RIGHT", 4, 0)
    gear.tip = L.MOVE_OPTIONS
    local lock = ns.Movers.LockButton("blessingsBar", frame, head, 22)
    lock:SetPoint("LEFT", gear, "RIGHT", 4, 0)
    frame.nextIcon = head:CreateTexture(nil, "ARTWORK")
    frame.nextIcon:SetSize(22, 22)
    frame.nextIcon:SetPoint("RIGHT")
    frame.nextIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.nextLabel = UI.Text(head, 10, "muted", "RIGHT")
    frame.nextLabel:SetPoint("RIGHT", frame.nextIcon, "LEFT", -6, 0)
    frame.nextLabel:SetText(L.BLESS_NEXT:upper())

    auto = CreateFrame("Button", "LiebeGruesseBlessAuto", frame, "SecureActionButtonTemplate, BackdropTemplate")
    auto:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    auto:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -4)
    auto:SetHeight(26)
    auto:RegisterForClicks("AnyUp", "AnyDown")
    UI.Skin(auto, "button", "border")
    auto.icon = UI.Icon(auto, "rotate-ccw", 14, "accent")
    auto.icon:SetPoint("LEFT", 10, 0)
    auto.label = UI.Text(auto, 13, "text", "CENTER")
    auto.label:SetPoint("CENTER", 8, 0)
    auto.label:SetText(L.BLESS_AUTO)
    -- registered for down and up (the cast follows the key-down setting):
    -- PostClick runs for both, the assignment only once on release
    auto:SetScript("PostClick", function(_, button, down)
        if button == "LeftButton" then noteClick(auto, button) end
        if down then return end
        if button == "RightButton" and not inCombat() then
            if B.Suggest() then ns.Print(L.BLESS_SUGGESTED) end
        end
    end)
    auto:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.Color("accent"))
        UI.Tooltip(self, L.BLESS_AUTO, { L.BLESS_AUTO_TIP })
    end)
    auto:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(Theme.Color("border")); GameTooltip:Hide() end)

    for i = 1, #B.CLASSES do makeRow(i) end
    frame.empty = UI.Text(frame, 11, "muted", "CENTER")
    frame.empty:SetWordWrap(true)
    frame.empty:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 2, -8)
    frame.empty:SetPoint("TOPRIGHT", auto, "BOTTOMRIGHT", -2, -8)
    frame.empty:SetText(L.BLESS_BAR_EMPTY)
    ns.Movers.Attach("blessingsBar", frame)
    -- the live strip lives outside the bar frame: hide it with the bar
    frame:HookScript("OnHide", function()
        if ns.BlessNative and not inCombat() then ns.Safe(ns.BlessNative.Layout, {}) end
    end)
    return frame
end

---------------------------------------------------------------------------
-- Update: texts every time, secure attributes only out of combat
---------------------------------------------------------------------------
local function shouldShow()
    if B.test then return true end
    if not B.Enabled() or not B.IsPaladin() then return false end
    if ns.Movers.active then return true end
    local o = B.Settings()
    if not o.bar then return false end
    if not IsInGroup() then return o.solo end
    if o.raidOnly then return IsInRaid() end
    return true
end

-- texts of one row (class, blessing, buffed/total, time left); safe in combat
local function paintRow(r)
    local class, blessing, present = r.cls, r.blessing, not r.absent
    local units = B.classUnits[class] or {}
    local st = B.status[class] or { total = #units, have = {}, left = {}, need = {} }
    local have, total = st.have[blessing] or 0, st.total > 0 and st.total or #units
    ns.SetClassIcon(r.class, class)
    r.bless:SetTexture(B.Icon(blessing))
    local left = st.left[blessing]
    if present then
        -- "~": aura data hidden (combat), the numbers are the last known state
        r.count:SetText(Theme.HexColor(have >= total and "good" or "bad", ((st.estimated and "~" or "") .. "%d/%d"):format(have, total)))
        r.left:SetText(fmtLeft(left))
        r.left:SetTextColor(Theme.Color(left and left < 300 and "warn" or "good"))
    else
        r.count:SetText(Theme.HexColor("muted", "—"))
        r.left:SetText("")
    end
    r.mark:SetShown(present and have < total)
    r:SetAlpha(present and 1 or 0.55)
    return st, have, total, left
end

-- In combat the secure rows can't move, change their spell/unit or show/hide.
-- So the layout stays exactly as it was when combat started: every row keeps
-- its class and only its numbers are refreshed (nothing jumps around).
local function combatRefresh()
    for _, r in ipairs(rows) do
        if r:IsShown() and r.cls and r.blessing then paintRow(r) end
    end
end

function Bar.Update()
    if frame and inCombat() then
        if frame:IsShown() then combatRefresh() end
        return
    end
    if not shouldShow() then
        if frame and frame:IsShown() and not inCombat() then frame:Hide() end
        return
    end
    if not create() then return end
    if not B.Me() then B.Rebuild() end
    local me = B.Me()
    -- first time on this character: fill in your own blessings right away,
    -- so the bar works without a right-click on Auto Assign
    local char = ns.Database.Char()
    -- (done once something was assigned: right after login the spells can be unknown yet)
    if me and not B.test and not char.blessingsAuto and not Bar.autoRunning and not inCombat() and not next(me.set or {}) then
        me.can = B.OwnSkills()
        local any = false
        for _, v in pairs(me.can) do if v > 0 then any = true end end
        Bar.autoRunning = true   -- Suggest calls Update again
        local ok = any and B.Suggest(true)
        Bar.autoRunning = false
        if ok and next(me.set or {}) then
            char.blessingsAuto = true
            ns.Print(L.BLESS_AUTO_FIRST)
            return   -- Suggest has updated the bar
        end
    end
    local set = me and me.set or {}
    local combat = inCombat()
    -- solo every assigned class gets a row, so you can see and change your plan
    local solo = not IsInGroup() and not B.test
    local n = 0
    local nextCast
    for _, class in ipairs(B.CLASSES) do
        local blessing = set[class]
        local units = B.classUnits[class]
        local present = units and #units > 0
        if blessing and (present or solo) then
            n = n + 1
            local r = rows[n]
            units = units or {}
            r.cls, r.blessing, r.absent = class, blessing, not present
            local st, have, total, left = paintRow(r)
            if not combat and not present then
                setSecure(r, { type1 = false, spell1 = false, unit1 = false, type2 = false, spell2 = false, unit2 = false })
            elseif not combat then
                local greater = B.SpellName(B.SpellFor(blessing, "greater"))
                local single = B.SpellName(B.SpellFor(blessing, "single"))
                local need = st.need and st.need[blessing]
                local gUnit = greater and pickUnit(class, greater, need)
                local sUnit = single and pickUnit(class, single, need)
                setSecure(r, {
                    type1 = (greater or single) and "spell" or nil, spell1 = greater or single, unit1 = greater and gUnit or sUnit,
                    type2 = single and "spell" or nil, spell2 = single, unit2 = sUnit,
                })
                rotation(r, class, sUnit, need)
                -- the next cast: the class with the fewest buffed, then the shortest time left
                if (have < total or (left and left < 300)) and (greater or single) then
                    local score = (total - have) * 10000 - (left or 0)
                    if not nextCast or score > nextCast.score then
                        nextCast = { score = score, spell = greater or single, unit = greater and gUnit or sUnit, blessing = blessing }
                    end
                end
            end
            if not combat then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -4 - (n - 1) * ROW_H)
                r:SetWidth(WIDTH - 8)
                r:Show()
            end
        end
    end
    if not combat then
        for i = n + 1, #rows do rows[i]:Hide() end
        -- live status strip (drawn by the game, also in combat); prepared here
        if ns.BlessNative then
            local live = {}
            if not B.test then
                for i = 1, n do
                    local r = rows[i]
                    if not r.absent then live[#live + 1] = { row = r, units = B.classUnits[r.cls] or {}, blessing = r.blessing } end
                end
            end
            ns.Safe(ns.BlessNative.Layout, live)
        end
        setSecure(auto, { type1 = nextCast and "spell" or nil, spell1 = nextCast and nextCast.spell, unit1 = nextCast and nextCast.unit })
        frame.empty:SetShown(n == 0)
        frame:SetHeight(4 + 24 + 4 + 26 + 6 + math.max(n * ROW_H, n == 0 and 34 or 0) + 4)
        frame:Show()
    end
    frame.nextIcon:SetTexture(nextCast and B.Icon(nextCast.blessing) or nil)
    frame.nextIcon:SetShown(nextCast ~= nil)
end

function Bar.Shown() return frame ~= nil and frame:IsShown() end

ns.On("LG_BLESSINGS", function() Bar.Update() end)
ns.On("LG_MOVERS", function() ns.AfterCombat("bless-bar", Bar.Update) end)
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(0.5, Bar.Update) end)
ns.On("LG_READY", function()
    ns.Movers.Anchor("blessingsBar", L.BLESS_BAR, { "RIGHT", "RIGHT", -40, 120 }, WIDTH, 120, nil, { icon = "sparkles", scalable = true,
        settings = function() ns.Window.Show("blessings") end })
    if B.IsPaladin() then ns.After(5, Bar.Update) end
end)
