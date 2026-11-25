-- Armory: one member like a character sheet – gear left/right of the model,
-- stats, talents, professions, attunements, alts and where the data comes from.
-- Opened from the roster (click on a member); Back returns to the list.
local _, ns = ...
local UI, Theme, L, Names, Items = ns.UI, ns.Theme, ns.L, ns.Names, ns.Items
local Armory = {}
ns.Armory = Armory

local LEFT_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_SLOTS = { 16, 17, 18 }
local SLOT_KEY = {}
for _, s in ipairs(Items.SLOTS) do SLOT_KEY[s.id] = s.key end
for _, s in ipairs(Items.COSMETIC) do SLOT_KEY[s.id] = s.key end

-- talent tree names that mean "healer" / "caster" (English and German clients)
local HEALER = { holy = true, heilig = true, restoration = true, wiederherstellung = true, discipline = true, disziplin = true }
local CASTER = { balance = true, gleichgewicht = true, elemental = true, elementarkampf = true, elementar = true, shadow = true,
    schatten = true, arcane = true, arkan = true, fire = true, feuer = true, frost = true, affliction = true, gebrechen = true,
    demonology = true, ["dämonologie"] = true, destruction = true, ["zerstörung"] = true }
local CASTER_CLASS = { MAGE = true, WARLOCK = true, PRIEST = true }

local view       -- the armory frame (child of the roster content)
local state = { key = nil, rows = nil, index = nil, onBack = nil }
Armory.state = state

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function parseStats(text)
    if type(text) ~= "string" then return nil end
    local v = {}
    for part in (text .. ","):gmatch("([^,]*),") do v[#v + 1] = tonumber(part) end
    return { hit = v[1], crit = v[2], ap = v[3], sp = v[4], heal = v[5], scrit = v[6], shit = v[7], rap = v[8], rcrit = v[9], rhit = v[10] }
end

-- the three numbers that matter for this character
local function statSet(m, class, live)
    local st = parseStats(live or m.st)
    if not st then return nil end
    local spec = tostring(m.sp or ""):lower()
    local pct = function(x) return x and (("%.1f %%"):format(x)) or "–" end
    if HEALER[spec] and class ~= "WARRIOR" and class ~= "ROGUE" then
        return { { L.ARM_SPELL_CRIT, pct(st.scrit) }, { L.ARM_HEALING, st.heal or "–" }, { L.ARM_SPELL_POWER, st.sp or "–" } }
    end
    if CASTER[spec] or (CASTER_CLASS[class] and not HEALER[spec]) then
        return { { L.ARM_SPELL_HIT, pct(st.shit) }, { L.ARM_SPELL_CRIT, pct(st.scrit) }, { L.ARM_SPELL_POWER, st.sp or "–" } }
    end
    if class == "HUNTER" then
        return { { L.ARM_HIT, pct(st.rhit or st.hit) }, { L.ARM_CRIT, pct(st.rcrit or st.crit) }, { L.ARM_RAP, st.rap or "–" } }
    end
    return { { L.ARM_HIT, pct(st.hit) }, { L.ARM_CRIT, pct(st.crit) }, { L.ARM_AP, st.ap or "–" } }
end

Armory.StatSet = statSet
Armory.SLOT_KEY = SLOT_KEY

local function sourceText(source)
    return source == "inspect" and L.ARM_FROM_INSPECT or L.ARM_FROM_ADDON
end

---------------------------------------------------------------------------
-- Gear slot: icon + name + "iLvl · enchant"; right column mirrored
---------------------------------------------------------------------------
local function makeSlot(parent, mirrored)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(40)
    f.icon = UI.ItemIcon(f, 36)
    f.empty = UI.Panel(f, "input", "borderDim")
    f.empty:SetSize(36, 36)
    f.name = UI.Text(f, 12, "text", mirrored and "RIGHT" or "LEFT")
    f.sub = UI.Text(f, 11, "muted", mirrored and "RIGHT" or "LEFT")
    -- icon size follows the row height; name above, details below the middle
    function f:Size(h)
        local sz = math.floor(math.max(36, math.min(54, h - 4)))
        self:SetHeight(sz + 4)
        self.icon:SetSize(sz, sz); self.empty:SetSize(sz, sz)
        local off = sz + 8
        self.icon:ClearAllPoints(); self.empty:ClearAllPoints()
        self.name:ClearAllPoints(); self.sub:ClearAllPoints()
        local side = mirrored and "RIGHT" or "LEFT"
        local d = mirrored and -off or off
        self.icon:SetPoint(side); self.empty:SetPoint(side)
        self.name:SetPoint("BOTTOM" .. side, self, side, d, 1)
        self.name:SetPoint("BOTTOM" .. (mirrored and "LEFT" or "RIGHT"), self, mirrored and "LEFT" or "RIGHT", 0, 1)
        self.sub:SetPoint("TOP" .. side, self, side, d, -2)
        self.sub:SetPoint("TOP" .. (mirrored and "LEFT" or "RIGHT"), self, mirrored and "LEFT" or "RIGHT", 0, -2)
    end
    f:Size(40)
    function f:Set(slotId, item)
        self.icon:SetItem(item)
        self.empty:SetShown(item == nil)
        if not item then
            self.name:SetText(Theme.HexColor("muted", L["SLOT_" .. (SLOT_KEY[slotId] or "")] or ""))
            self.sub:SetText(Theme.HexColor("borderDim", L.ARM_EMPTY))
            return
        end
        local info = Items.Info(item)
        local q = info and info.quality
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local name = info and info.name or ("item " .. (Items.ID(item) or "?"))
        self.name:SetText(c and (c.hex .. name .. "|r") or name)
        local parts = {}
        local level = Items.Level(item)
        if level and slotId ~= 4 and slotId ~= 19 then parts[#parts + 1] = L.ARM_ILVL:format(level) end
        if Items.Enchant(item) then
            parts[#parts + 1] = Theme.HexColor("good", Items.EnchantText(item) or L.ENCHANTED)
        elseif Items.ShouldEnchant(slotId, item) then
            parts[#parts + 1] = Theme.HexColor("bad", L.ENCHANT_MISSING)
        end
        self.sub:SetText(table.concat(parts, Theme.HexColor("muted", " · ")))
    end
    return f
end

---------------------------------------------------------------------------
-- Model: the real character when it is in sight (group, target, mouseover,
-- focus); otherwise race and gender from the synced profile with the
-- member's gear. Never your own character for someone else; without race
-- data (very old profiles) the box stays empty with a hint.
---------------------------------------------------------------------------
-- race file -> race id (the profile also sends the id as "ri")
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8,
    Goblin = 9, BloodElf = 10, Draenei = 11 }
function Armory.RaceID(m)
    if not m then return nil end
    local id = tonumber(m.ri)
    if id and id > 0 then return id end
    return m.rf and RACE_IDS[m.rf] or nil
end
-- UnitSex: 2 = male, 3 = female; the model wants 0 = male, 1 = female
function Armory.ModelSex(m)
    local sx = m and tonumber(m.sx)
    if sx == 3 then return 1 end
    if sx == 2 then return 0 end
    return nil
end

-- a unit token for the member, only if the game can draw it right now
local function visibleUnit(key)
    local unit = ns.UnitForKey(key)
    if unit and ns.Call(UnitIsVisible, unit) then return unit end
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        if ns.Call(UnitIsPlayer, u) and ns.Call(UnitIsVisible, u) then
            local name = Names.Unit(u)
            if name and Names.Same(Names.Key(name), key) then return u end
        end
    end
end
Armory.VisibleUnit = visibleUnit

local function makeModel(parent)
    local box = UI.Panel(parent, "input", "borderDim")
    local ok, model = pcall(CreateFrame, "DressUpModel", nil, box)
    if not ok or not model then return box end
    model:SetPoint("TOPLEFT", 1, -1)
    model:SetPoint("BOTTOMRIGHT", -1, 1)
    box.model = model
    box.hint = UI.Text(box, 10, "muted", "CENTER")
    box.hint:SetPoint("BOTTOMLEFT", 4, 6)
    box.hint:SetPoint("BOTTOMRIGHT", -4, 6)
    box.hint:SetWordWrap(true)
    -- empty state (race unknown): the guild logo, faint
    box.empty = box:CreateTexture(nil, "ARTWORK")
    box.empty:SetTexture(ns.media .. "logo")
    box.empty:SetSize(96, 96)
    box.empty:SetPoint("CENTER", 0, 12)
    box.empty:SetAlpha(0.12)
    box.empty:Hide()
    -- drag to turn (the update script only runs while dragging)
    model:EnableMouse(true)
    local rot = 0
    model:SetScript("OnMouseDown", function(self)
        local x0 = GetCursorPosition()
        local r0 = rot
        self:SetScript("OnUpdate", function(m)
            local x = GetCursorPosition()
            rot = r0 + (x - x0) / 80
            if m.SetFacing then m:SetFacing(rot) end
        end)
    end)
    model:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    -- the model is only rebuilt when member, gear, race or "real/preview"
    -- change; refills (item info arriving, profile syncs, resizing) leave it alone
    local loaded
    function box:Load(key, gear, force, m)
        local unit = visibleUnit(key)
        local real = unit ~= nil
        local race, sex = Armory.RaceID(m), Armory.ModelSex(m)
        local parts = { tostring(key), tostring(real), tostring(unit) }
        if not real then
            parts[#parts + 1] = tostring(race) .. "/" .. tostring(sex)
            for slot = 1, 19 do parts[#parts + 1] = gear and gear[slot] and tostring(gear[slot]) or "" end
        end
        local sig = table.concat(parts, ";")
        if sig == loaded and not force then return end
        loaded = sig
        rot = 0
        box.gear, box.tries = (not real) and gear or nil, 0
        box.unit = unit
        box.pendingRace, box.reveal = nil, nil
        pcall(function()
            if real then
                box.race = nil
                box.Reveal(true)
                model:SetUnit(unit)
                if model.Dress then model:Dress() end
                box.hint:SetText("")
                box.mode = "real"
            elseif race and model.SetCustomRace then
                -- the member's race, gender and gear (the face/hair of others
                -- is only known to the game while they are in sight). Never
                -- your own character: it is not who you clicked.
                box.race, box.sex, box.raceTries = race, sex or 0, 0
                if model.ClearModel then model:ClearModel() end
                local ok = pcall(model.SetCustomRace, model, race, sex or 0)
                if ok then
                    box.Reveal(true)
                    box:TryGear()
                    box.mode = "race"
                else
                    -- some clients need a loaded model before the race can be
                    -- set: load a base model hidden, set the race once it has
                    -- loaded and only then show it (OnModelLoaded)
                    box.Reveal(false)
                    box.pendingRace = true
                    model:SetUnit("player")
                    box.mode = "race-late"
                end
                box.hint:SetText(L.ARM_MODEL_RACE)
            else
                box.Empty()
            end
            if model.SetFacing then model:SetFacing(0) end
        end)
    end
    -- no race known (profile from a very old version): no model at all
    function box.Empty()
        box.race, box.pendingRace, box.gear = nil, nil, nil
        if model.ClearModel then pcall(model.ClearModel, model) end
        box.Reveal(false)
        box.hint:SetText(L.ARM_MODEL_NONE)
        box.mode = "none"
    end
    function box.Reveal(on)
        model:SetAlpha(on and 1 or 0)
        box.empty:SetShown(not on)
        box.reveal = nil
    end
    -- the preview: undress and put the member's gear on; repeated when the
    -- model has loaded (right after SetUnit/SetCustomRace the items do not stick)
    function box:TryGear()
        if not box.gear then return end
        if model.Undress then model:Undress() end
        for _, item in pairs(box.gear) do
            -- the plain item string works without cached item info
            local s = type(item) == "string" and item:match("item:[%-%d:]+")
            local link = s or Items.Link(item)
            if type(link) == "string" and model.TryOn then pcall(model.TryOn, model, link) end
        end
    end
    model:SetScript("OnModelLoaded", function()
        -- the hidden base model has loaded: now set the member's race
        if box.pendingRace then
            box.pendingRace = nil
            if not pcall(model.SetCustomRace, model, box.race, box.sex or 0) then box.Empty(); return end
            box.raceTries = 1
            pcall(box.TryGear, box)
            -- show it with the next load (race change) or shortly after
            box.reveal = true
            local sig = loaded
            ns.After(0.4, function() if box.reveal and loaded == sig then box.Reveal(true) end end)
            return
        end
        if box.reveal then box.Reveal(true) end
        -- some clients drop the custom race when the first model load ends: set it once more
        if box.race and (box.raceTries or 0) < 1 then
            box.raceTries = (box.raceTries or 0) + 1
            pcall(model.SetCustomRace, model, box.race, box.sex or 0)
        end
        if box.gear and (box.tries or 0) < 3 then box.tries = (box.tries or 0) + 1; pcall(box.TryGear, box) end
    end)
    return box
end

---------------------------------------------------------------------------
-- Right column cards
---------------------------------------------------------------------------
local function card(parent, title)
    local c = UI.Panel(parent, "panel", "borderDim")
    c.right = UI.Text(c, 10, "muted", "RIGHT")
    c.right:SetPoint("TOPRIGHT", -12, -10)
    c.title = UI.CardTitle(c, title, c.right)
    c.rows = {}
    return c
end

-- a row with optional icon, label, value and a thin bar below
local function cardRow(c, i)
    local r = c.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, c)
    r:SetHeight(26)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 0, 2)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.label = UI.Text(r, 12, "text")
    r.value = UI.Text(r, 12, "textDim", "RIGHT")
    r.value:SetPoint("RIGHT", 0, 2)
    r.track = UI.Fill(r, "borderDim", "ARTWORK")
    r.track:SetPoint("BOTTOMLEFT", 0, 0)
    r.track:SetPoint("BOTTOMRIGHT", 0, 0)
    r.track:SetHeight(2)
    r.fill = UI.Fill(r, "accent", "OVERLAY")
    r.fill:SetPoint("BOTTOMLEFT", 0, 0)
    r.fill:SetHeight(2)
    c.rows[i] = r
    return r
end

local function fillRows(c, entries, width)
    local y = -38
    for i, e in ipairs(entries) do
        local r = cardRow(c, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 12, y)
        r:SetPoint("TOPRIGHT", -12, y)
        if e.icon then r.icon:SetTexture(e.icon); r.icon:Show() else r.icon:Hide() end
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", e.icon and 26 or 0, 2)
        r.label:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
        r.label:SetText(e.label or "")
        r.value:SetText(e.value or "")
        local bar = e.bar ~= nil
        r.track:SetShown(bar)
        r.fill:SetShown(bar and e.bar > 0)
        if bar then
            r.fill:SetWidth(math.max(1, (width - 24) * math.min(1, e.bar)))
            r.fill:SetVertexColor(Theme.Color(e.highlight and "accent" or "textDim"))
        end
        r:SetHeight(bar and 28 or 22)
        r:Show()
        y = y - (bar and 32 or 24)
    end
    for i = #entries + 1, #c.rows do c.rows[i]:Hide() end
    if c.extra then
        c.extra:ClearAllPoints()
        c.extra:SetPoint("TOPLEFT", 12, y - 2)
        c.extra:SetWidth(width - 24)
        local h = c.extra:GetStringHeight() or 0
        if (c.extra:GetText() or "") ~= "" then y = y - h - 4 end
    end
    c:SetHeight(-y + 12)
    return -y + 12
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Armory.Build(parent)
    if ns.ArmoryCompare then ns.ArmoryCompare.Build(parent) end
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    if view.SetClipsChildren then view:SetClipsChildren(true) end

    -- top bar: back · name of the list position · prev/next · actions
    local back = UI.Button(view, "‹  " .. L.BACK, 96, 26, function() Armory.Close() end)
    back:SetPoint("TOPLEFT")
    view.back = back
    local nextBtn = UI.IconButton(view, "chevron-right", 26, function() Armory.Step(1) end)
    -- the top right corner belongs to the page search
    nextBtn:SetPoint("TOPRIGHT", -ns.Window.SearchReserve(), 0)
    nextBtn.tip = L.ARM_NEXT
    local pos = UI.Text(view, 12, "textDim", "CENTER")
    pos:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
    pos:SetWidth(54)
    local prevBtn = UI.IconButton(view, "chevron-right", 26, function() Armory.Step(-1) end)
    prevBtn:SetPoint("RIGHT", pos, "LEFT", -6, 0)
    prevBtn.icon:SetTexCoord(1, 0, 0, 1)
    prevBtn.tip = L.ARM_PREV
    view.pos = pos
    view.inspect = UI.Button(view, L.INSPECT, 100, 26, function()
        local unit = ns.UnitForKey(state.key)
        if unit and ns.Inspect.Request(unit, true) then ns.Print(L.INSPECTING, Names.Display(state.key))
        else ns.Print(L.INSPECT_UNAVAILABLE) end
    end)
    view.inspect:SetPoint("RIGHT", prevBtn, "LEFT", -12, 0)
    view.life = UI.Button(view, L.LIFE_STATS_BUTTON, 110, 26, function()
        if state.key and ns.LifeWindow then ns.LifeWindow.Show(state.key) end
    end, "badge-check")
    view.life:SetPoint("RIGHT", view.inspect, "LEFT", -8, 0)
    view.whisper = UI.Button(view, L.WHISPER, 100, 26, function()
        local g = ns.Guild.Find(state.key)
        if ChatFrame_SendTell then ChatFrame_SendTell((g and g.name) or Names.Display(state.key)) end
    end, "message-circle")
    view.whisper:SetPoint("RIGHT", view.life, "LEFT", -8, 0)
    -- compare: searchable member list, then the side-by-side view
    view.compare = UI.Button(view, L.CMP_COMPARE, 120, 26, function(self)
        if ns.ArmoryCompare then ns.ArmoryCompare.Pick(self, state.key) end
    end, "scale")
    view.compare.tip = { L.CMP_TIP }
    view.compare:SetPoint("RIGHT", view.inspect, "LEFT", -8, 0)
    view.life:ClearAllPoints()
    view.life:SetPoint("RIGHT", view.compare, "LEFT", -8, 0)

    local line = UI.Divider(view)
    line:SetPoint("TOPLEFT", 0, -36)
    line:SetPoint("TOPRIGHT", 0, -36)

    local scroll, body = UI.ScrollArea(view)
    scroll:SetPoint("TOPLEFT", 0, -44)
    scroll:SetPoint("BOTTOMRIGHT", -6, 0)
    view.scroll, view.body = scroll, body

    -- header: portrait, name, facts; stat block on the right
    local portrait = CreateFrame("Frame", nil, body)
    portrait:SetSize(84, 84)
    portrait:SetPoint("TOPLEFT", 4, -6)
    -- spec icon in a class-colored frame, bronze corners outside
    portrait.ring = portrait:CreateTexture(nil, "BORDER")
    portrait.ring:SetTexture(Theme.WHITE)
    portrait.ring:SetAlpha(0)   -- class icons without a border
    portrait.ring:SetPoint("TOPLEFT", 6, -6)
    portrait.ring:SetPoint("BOTTOMRIGHT", -6, 6)
    portrait.icon = portrait:CreateTexture(nil, "ARTWORK")
    portrait.icon:SetPoint("TOPLEFT", portrait.ring, "TOPLEFT", 0, 0)
    portrait.icon:SetPoint("BOTTOMRIGHT", portrait.ring, "BOTTOMRIGHT", 0, 0)
    UI.Corners(portrait, 10)
    view.portrait = portrait
    view.name = UI.Text(body, 26, "text")
    view.name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 14, -6)
    view.facts = UI.Text(body, 13, "textDim")
    view.facts:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -6)
    view.status = UI.Text(body, 12, "muted")
    view.status:SetPoint("TOPLEFT", view.facts, "BOTTOMLEFT", 0, -6)
    view.status:SetWidth(420)

    view.stats = {}
    for i = 1, 4 do
        local s = CreateFrame("Frame", nil, body)
        s:SetSize(104, 62)
        s.label = UI.Text(s, 11, "muted", "CENTER", nil, true)
        s.label:SetPoint("TOP", 0, -4)
        s.value = UI.Text(s, i == 4 and 26 or 24, i == 4 and "gold" or "text", "CENTER")
        s.value:SetPoint("TOP", s.label, "BOTTOM", 0, -6)
        s.sub = UI.Text(s, 10, "muted", "CENTER")
        s.sub:SetPoint("TOP", s.value, "BOTTOM", 0, -4)
        view.stats[i] = s
    end

    -- gear
    view.left, view.right, view.bottom = {}, {}, {}
    for i = 1, #LEFT_SLOTS do view.left[i] = makeSlot(body, false) end
    for i = 1, #RIGHT_SLOTS do view.right[i] = makeSlot(body, true) end
    for i = 1, #BOTTOM_SLOTS do view.bottom[i] = makeSlot(body, i == 3) end
    view.model = makeModel(body)
    view.enchants = UI.Text(body, 11, "muted", "CENTER")

    -- right column
    view.talents = card(body, L.ARM_TALENTS)
    view.talents.extra = UI.Text(view.talents, 12, "muted")
    view.talents.extra:SetWordWrap(true)
    view.talents.extra:SetJustifyH("LEFT")
    view.profs = card(body, L.COL_PROFESSIONS)
    view.attunes = card(body, L.ATT_ATTUNES)
    view.attunes.extra = UI.Text(view.attunes, 12, "textDim")
    view.attunes.extra:SetWordWrap(true)
    view.attunes.extra:SetJustifyH("LEFT")
    view.attunes.extra:SetSpacing(5)
    view.badges = card(body, L.BADGES)
    view.char = card(body, L.ARM_CHARACTER)
    view.char.extra = UI.Text(view.char, 12, "textDim")
    view.char.extra:SetWordWrap(true)
    view.char.extra:SetJustifyH("LEFT")
    view.char.extra:SetSpacing(5)
    view.data = card(body, L.ARM_DATA)
    view.data.extra = UI.Text(view.data, 11, "muted")
    view.data.extra:SetWordWrap(true)
    view.data.extra:SetJustifyH("LEFT")
    view.data.extra:SetSpacing(3)

    view:SetScript("OnHide", function() ns.ArmoryTalents.Hide() end)
    view:SetScript("OnSizeChanged", function() if view:IsShown() then ns.Debounce("armory-layout", 0.05, Armory.Fill) end end)
    Armory.view = view
    return view
end

---------------------------------------------------------------------------
-- Fill + layout
---------------------------------------------------------------------------
local function placeColumn(slots, ids, x, y, w, gear, pitch)
    pitch = pitch or 46
    for i, f in ipairs(slots) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", view.body, "TOPLEFT", x, -(y + (i - 1) * pitch))
        f:SetWidth(w)
        f:Size(pitch - 6)
        f:Set(ids[i], gear and gear[ids[i]])
        f:Show()
    end
    return y + #slots * pitch
end

function Armory.Fill()
    if not view or not view:IsShown() or not state.key then return end
    local key = state.key
    local g = ns.Guild.Find(key) or {}
    local m = (ns.Roster and ns.Roster.MemberAny(key)) or ns.Database.Member(key) or {}
    local class = g.class or m.c
    local gear, ilvl, source, gearT = ns.Inspect.Gear(m)

    -- top bar
    if state.rows and state.index then view.pos:SetText(("%d/%d"):format(state.index, #state.rows)) else view.pos:SetText("") end
    view.inspect:SetEnabled(ns.UnitForKey(key) ~= nil and not Names.Same(key, Names.Me()))

    -- header
    if not ns.SetSpecIcon(view.portrait.icon, class, ns.SpecPoints(m)) then view.portrait.icon:SetTexture(nil) end
    local r, gg, b = ns.ClassColor(class)
    view.portrait.ring:SetVertexColor(r, gg, b)
    view.name:SetText(ns.ColorName(g.name or m.name or key, class))
    local className = class and ns.ClassName(class) or ""
    local facts = { L.LEVEL .. " " .. (g.level or m.l or "?") }
    if m.r and m.r ~= "" then facts[#facts + 1] = m.r end
    facts[#facts + 1] = ns.Hex(r, gg, b, className)
    local spec = ns.SpecName(m.sp or (m.insp and m.insp.sp), class, ns.SpecPoints(m))
    if spec then facts[#facts + 1] = Theme.HexColor("text", spec) end
    view.facts:SetText(table.concat(facts, Theme.HexColor("muted", "  ·  ")))
    local status = {}
    if g.rank then status[#status + 1] = (g.rankIndex == 0 and UI.Glyph("crown", "gold", 12) .. " " or "") .. g.rank end
    if g.online then
        status[#status + 1] = UI.Glyph("dot", "good", 10) .. " " .. Theme.HexColor("good", L.ONLINE) .. (g.zone and g.zone ~= "" and Theme.HexColor("muted", " · " .. g.zone) or "")
    elseif g.offlineHours then
        status[#status + 1] = L.LAST_SEEN_AGO:format(ns.Ago(ns.Now() - g.offlineHours * 3600))
    end
    if m.m and not Names.Same(m.m, key) then status[#status + 1] = L.ALT_OF:format(Names.Display(m.m)) end
    view.status:SetText(table.concat(status, Theme.HexColor("muted", "   ")))

    -- stat block (own character: read live, the stored values may be old)
    local own = Names.Same(key, Names.Me())
    -- (not in combat: the game hides some values there)
    local live = own and not ns.InCombat() and ns.Profile and ns.Profile.ReadStats and ns.Profile.ReadStats() or nil
    if live and not live:find("[1-9]") then live = nil end
    local set = statSet(m, class, live) or { { L.ARM_HIT, "–" }, { L.ARM_CRIT, "–" }, { L.ARM_AP, "–" } }
    for i = 1, 3 do
        view.stats[i].label:SetText(set[i][1]:upper())
        view.stats[i].value:SetText(tostring(set[i][2]))
        view.stats[i].sub:SetText("")
    end
    view.stats[4].label:SetText(L.COL_ILVL:upper())
    view.stats[4].value:SetText(ilvl and ("%.1f"):format(ilvl) or "–")
    view.stats[4].sub:SetText(gearT and L.ARM_AS_OF:format(ns.Ago(gearT)) or "")

    -- layout: right column cards, gear + model on the left
    -- responsive: the cards take about a third (300–620), the gear block the
    -- rest; the model grows with it, the columns get what is left
    local W = math.max(560, (view.scroll:GetWidth() or 900) - 8)
    local cardW = math.floor(math.max(300, math.min(620, W * 0.36)))
    local stacked = W - cardW - 20 < 520
    local leftW = stacked and W or (W - cardW - 20)
    if stacked then cardW = W end
    local modelW = leftW >= 520 and math.floor(math.max(140, math.min(340, leftW * 0.3))) or 0
    local colW = math.floor((leftW - modelW - (modelW > 0 and 24 or 12)) / 2)
    local gx = 0
    for i = 4, 1, -1 do
        local s = view.stats[i]
        s:ClearAllPoints()
        if i == 4 then s:SetPoint("TOPRIGHT", view.body, "TOPRIGHT", -4, -12)
        else s:SetPoint("RIGHT", view.stats[i + 1], "LEFT", -6, 0) end
        s:SetShown(W >= 700 or i == 4)
    end

    local top = 112
    -- rows spread over the visible height (gear, weapons and the enchant line fill the view)
    local viewH = view.scroll:GetHeight() or 0
    local pitch = math.floor(math.max(46, math.min(72, (viewH - top - 8 - 30) / 9)))
    local yL = placeColumn(view.left, LEFT_SLOTS, gx, top, colW, gear, pitch)
    placeColumn(view.right, RIGHT_SLOTS, gx + leftW - colW, top, colW, gear, pitch)
    view.model:ClearAllPoints()
    if modelW > 0 then
        view.model:SetPoint("TOPLEFT", view.body, "TOPLEFT", gx + colW + 12, -top)
        view.model:SetSize(modelW, yL - top - 6)
        view.model:Show()
        if view.model.Load then view.model:Load(key, gear, state.forceModel, m); state.forceModel = nil end
    else
        view.model:Hide()
    end
    -- weapons centred under the gear
    local wW = math.floor(math.min(colW, (leftW - 24) / 3))
    local startX = gx + math.floor((leftW - (wW * 3 + 24)) / 2)
    for i, f in ipairs(view.bottom) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", view.body, "TOPLEFT", startX + (i - 1) * (wW + 12), -(yL + 8))
        f:SetWidth(wW)
        f:Size(pitch - 6)
        f:Set(BOTTOM_SLOTS[i], gear and gear[BOTTOM_SLOTS[i]])
    end
    local gearBottom = yL + 8 + pitch
    if gear then
        local e = Items.EnchantStatus(gear)
        view.enchants:SetText(e.needed > 0 and (L.COL_ENCHANTS_LONG .. ": " .. Theme.HexColor(#e.missing == 0 and "good" or "bad", e.done .. "/" .. e.needed)) or "")
    else
        view.enchants:SetText(Theme.HexColor("muted", L.ARM_NO_GEAR))
    end
    view.enchants:ClearAllPoints()
    view.enchants:SetPoint("TOPLEFT", view.body, "TOPLEFT", gx, -(gearBottom + 4))
    view.enchants:SetWidth(leftW)
    gearBottom = gearBottom + 22

    -- talents: points per tree, the chosen talents as icons, the tree on hover
    local insp = m.insp or {}
    local useInsp = not tostring(m.tp or ""):find("[1-9]") and insp.tp ~= nil
    local tp, tn, tk = useInsp and insp.tp or m.tp, useInsp and insp.tn or m.tn, useInsp and insp.tk or m.tk
    -- own character: read live, the stored profile may be from before the talents loaded
    if Names.Same(key, Names.Me()) and ns.Profile and ns.Profile.ReadTalents then
        local _, ltp, ltn, most, ltk = ns.Profile.ReadTalents(false, true)
        if most and most > 0 then tp, tn, tk, useInsp = ltp, ltn, ltk or tk, false end
    end
    local points = {}
    for p in tostring(tp or ""):gmatch("%d+") do points[#points + 1] = tonumber(p) end
    local names = ns.TreeNames(g.class or m.c, tn)
    local best = 0
    for _, p in ipairs(points) do best = math.max(best, p) end
    if best == 0 then points = {} end
    local layout = ns.ArmoryTalents.Parse(tk)
    local trees = {}
    for i, p in ipairs(points) do
        trees[#trees + 1] = { name = names[i] or ("#" .. i), points = p, highlight = p == best and p > 0, talents = layout[i] or {} }
    end
    local head = #points > 0 and table.concat(points, "/") or ""
    if not useInsp and m.tp2 and m.tp2:find("[1-9]") then
        head = head .. Theme.HexColor("muted", "  ·  " .. L.ARM_DUAL_SPEC .. " " .. m.tp2)
    end
    view.talents.right:SetText(head)
    -- no points: a wrapped hint below the title instead of a (clipped) row
    view.talents.extra:SetText(#trees == 0 and (spec and Theme.HexColor("text", spec) .. "\n" or "")
        .. Theme.HexColor("muted", m.v and L.ARM_NO_TALENTS_YET or L.ARM_NO_TALENTS) or "")

    local x = stacked and 0 or (gx * 2 + leftW + 20)
    local y = stacked and gearBottom + 8 or top - 4
    local function place(c, list)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", view.body, "TOPLEFT", x, -y)
        c:SetWidth(cardW)
        local h = fillRows(c, list, cardW)
        y = y + h + 10
    end
    view.talents:ClearAllPoints()
    view.talents:SetPoint("TOPLEFT", view.body, "TOPLEFT", x, -y)
    view.talents:SetWidth(cardW)
    y = y + ns.ArmoryTalents.Fill(view.talents, trees, cardW) + 10

    -- professions (main first, then secondary)
    local profs = {}
    for _, p in ipairs(m.pr or {}) do
        local pk = ns.Crafts and ns.Crafts.ProfKey(p.n)
        local info = pk and ns.Crafts.ProfInfo(pk)
        profs[#profs + 1] = { icon = info and info.icon, label = (pk and ns.Crafts.ProfName(pk)) or p.n,
            value = ("%s/%s"):format(p.s or "?", p.m or "?"), bar = (p.s or 0) / math.max(1, p.m or 300),
            highlight = (p.s or 0) >= (p.m or 300), order = info and (info.gather and 50 or 0) + (info.order or 0) or 99,
            secondary = pk == "cooking" or pk == "firstaid" or pk == "fishing" }
    end
    table.sort(profs, function(a, b2)
        if a.secondary ~= b2.secondary then return not a.secondary end
        return a.order < b2.order
    end)
    if #profs == 0 then profs[1] = { label = Theme.HexColor("muted", L.ARM_NO_DATA) } end
    place(view.profs, profs)

    -- attunements and keys as one line each
    local at = ns.Attune and ns.Attune.Parse(m.at)
    if at then
        local raids, keys = {}, {}
        for _, e in ipairs(ns.Attune.LIST) do
            local t = (at[e.key] and UI.Glyph("badge-check", "good", 11) .. " " or "") .. Theme.HexColor(at[e.key] and "good" or "muted", e.short)
            if e.kind == "attune" then raids[#raids + 1] = t elseif at[e.key] then keys[#keys + 1] = Theme.HexColor("text", e.short) end
        end
        -- raids on the first line, keys below with their own label
        view.attunes.extra:SetText(table.concat(raids, "    ") .. "\n" .. Theme.HexColor("muted", ns.Upper(L.ATT_KEYS)) .. "   "
            .. (#keys > 0 and table.concat(keys, Theme.HexColor("muted", "  ·  ")) or Theme.HexColor("muted", "–")))
    else
        view.attunes.extra:SetText(Theme.HexColor("muted", L.ATT_NO_ADDON))
    end
    place(view.attunes, {})

    -- guild badges (Modules/Badges.lua)
    if ns.Badges and ns.Database.Settings().modules.community ~= false then
        view.badges:ClearAllPoints()
        view.badges:SetPoint("TOPLEFT", view.body, "TOPLEFT", x, -y)
        view.badges:SetWidth(cardW)
        y = y + ns.Badges.FillCard(view.badges, key, cardW) + 10
        view.badges:Show()
    else
        view.badges:Hide()
    end

    -- character: alts, note, version
    local lines = {}
    local alts = {}
    if not (m.m and not Names.Same(m.m, key)) then
        for k, other in pairs(ns.Database.Guild().members) do
            if other.m and Names.Same(other.m, key) and not Names.Same(k, key) then alts[#alts + 1] = ns.ColorName(other.name or k, other.c) end
        end
        for _, a in ipairs(ns.Account.Unpack(m.a)) do alts[#alts + 1] = ns.ColorName(a.name, a.c) .. (a.l and Theme.HexColor("muted", " " .. a.l) or "") end
    end
    -- muted label, value in text color
    local function line(label, value) lines[#lines + 1] = Theme.HexColor("muted", ns.Upper(label)) .. "   " .. value end
    if #alts > 0 then table.sort(alts); line(L.ALTS, table.concat(alts, ", ")) end
    if g.note and g.note ~= "" then line(L.NOTE, Theme.HexColor("text", g.note)) end
    if g.officerNote and g.officerNote ~= "" then line(L.ARM_OFFICER_NOTE, Theme.HexColor("text", g.officerNote)) end
    if m.v then line("Addon", Theme.HexColor("text", "v" .. m.v)) else lines[#lines + 1] = Theme.HexColor("muted", L.ARM_NO_ADDON) end
    view.char.extra:SetText(table.concat(lines, "\n"))
    place(view.char, {})

    -- where the data comes from
    local data = {}
    if gear then data[#data + 1] = ("%s · %s · %s"):format(L.GEAR, ns.Ago(gearT), sourceText(source)) end
    if not useInsp and m.tp and m.t then data[#data + 1] = ("%s · %s · %s"):format(L.ARM_TALENTS, ns.Ago(m.t), L.ARM_FROM_ADDON)
    elseif m.insp and (m.insp.tp or m.insp.sp) then data[#data + 1] = ("%s · %s · %s"):format(L.ARM_TALENTS, ns.Ago(m.insp.t), L.ARM_FROM_INSPECT) end
    if m.pr and #m.pr > 0 and m.t then data[#data + 1] = ("%s · %s · %s"):format(L.COL_PROFESSIONS, ns.Ago(m.t), L.ARM_FROM_ADDON) end
    if live then data[#data + 1] = ("%s · %s"):format(L.ARM_STATS, L.ARM_LIVE)
    elseif m.st and m.stt then data[#data + 1] = ("%s · %s"):format(L.ARM_STATS, ns.Ago(m.stt)) end
    view.data.extra:SetText(#data > 0 and table.concat(data, "\n") or L.ARM_NO_DATA)
    place(view.data, {})

    view.body:SetHeight(math.max(gearBottom, y) + 12)
    view.scroll.UpdateBar()
end

---------------------------------------------------------------------------
-- Open / close / step
---------------------------------------------------------------------------
function Armory.Open(key, rows, onBack)
    if not view then return end
    state.key, state.rows, state.onBack = key, rows, onBack
    state.index = nil
    for i, row in ipairs(rows or {}) do if Names.Same(row.key, key) then state.index = i end end
    state.forceModel = true
    view:Show()
    view.scroll:SetVerticalScroll(0)
    Armory.Fill()
    -- members without the addon: inspect them when possible
    local unit = ns.UnitForKey(key)
    local m = ns.Database.Member(key)
    if unit and not (m and m.v) and not Names.Same(key, Names.Me()) then ns.Inspect.Request(unit, false) end
end

function Armory.Step(delta)
    if not state.rows or not state.index or #state.rows == 0 then return end
    local i = ((state.index - 1 + delta) % #state.rows) + 1
    Armory.Open(state.rows[i].key, state.rows, state.onBack)
end

function Armory.Close()
    if not view then return end
    view:Hide()
    state.key = nil
    if state.onBack then ns.Safe(state.onBack) end
end

function Armory.IsOpen() return view ~= nil and view:IsShown() end
function Armory.Key() return state.key end

-- the compare view takes the armory's place and gives it back
function Armory.Suspend() if view then view:Hide() end end
function Armory.Resume()
    if not view or not state.key then return end
    view:Show()
    Armory.Fill()
end

-- /lg test model: what the armory knows about the open member's look
function Armory.ModelReport()
    local key = state.key
    if not key or not Armory.IsOpen() then ns.Print(L.TEST_TAG .. " " .. L.ARM_TEST_MODEL_OPEN); return end
    local m = ns.Database.Member(key) or {}
    local box = view and view.model
    local model = box and box.model
    ns.Print(L.TEST_TAG .. (" %s: version %s, profile %s"):format(Names.Display(key), tostring(m.v), m.t and ns.Ago(m.t) or "-"))
    ns.Print(L.TEST_TAG .. (" race file %s, race id %s, sex %s -> model race %s, gender %s"):format(tostring(m.rf), tostring(m.ri),
        tostring(m.sx), tostring(Armory.RaceID(m)), tostring(Armory.ModelSex(m))))
    ns.Print(L.TEST_TAG .. (" in sight: %s, mode: %s, SetCustomRace: %s, ClearModel: %s"):format(tostring((visibleUnit(key))),
        tostring(box and box.mode), tostring(model and model.SetCustomRace ~= nil), tostring(model and model.ClearModel ~= nil)))
end

-- the member became your target/focus: show the real model
local function sightChanged()
    if Armory.IsOpen() and state.key and visibleUnit(state.key) then ns.Debounce("armory-fill", 0.3, Armory.Fill) end
end
ns.On("PLAYER_TARGET_CHANGED", sightChanged)
ns.On("PLAYER_FOCUS_CHANGED", sightChanged)
ns.On("LG_PROFILE", function() if Armory.IsOpen() then ns.Debounce("armory-fill", 0.5, Armory.Fill) end end)
ns.On("LG_ITEMS", function() if Armory.IsOpen() then ns.Debounce("armory-fill", 0.5, Armory.Fill) end end)
