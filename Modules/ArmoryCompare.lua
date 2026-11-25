-- Armory compare: two characters side by side – gear slot by slot with the
-- item level difference, stats, talents, professions and attunements.
-- Opened from the armory ("Compare" → searchable member list); Back returns.
local _, ns = ...
local UI, Theme, L, Names, Items = ns.UI, ns.Theme, ns.L, ns.Names, ns.Items
local Compare = {}
ns.ArmoryCompare = Compare

local view
local state = { a = nil, b = nil, onlyDiff = false, lastB = nil }
Compare.state = state
local ROW_H, SIDE_W = 40, 340

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function member(key)
    local g = ns.Guild.Find(key) or {}
    local m = (ns.Roster and ns.Roster.MemberAny(key)) or ns.Database.Member(key) or {}
    return g, m, g.class or m.c
end

local function className(class)
    return class and ns.ClassName(class) or ""
end

local function specOf(m) return ns.SpecName(m.sp or (m.insp and m.insp.sp), m.c, ns.SpecPoints(m)) end

-- everybody we could compare with: own guild members with gear data
local function candidates(exclude)
    local list = {}
    for key, g in pairs(ns.Guild.members) do
        if not Names.Same(key, exclude) then
            local m = ns.Database.Member(key) or {}
            local gear, ilvl = ns.Inspect.Gear(m)
            if gear then list[#list + 1] = { key = key, name = g.name or key, class = g.class or m.c, spec = specOf(m), ilvl = ilvl, m = m } end
        end
    end
    local me = Names.Me()
    if me and not Names.Same(me, exclude) and not ns.Guild.members[me] then
        local m = ns.Database.Member(me) or {}
        local gear, ilvl = ns.Inspect.Gear(m)
        if gear then list[#list + 1] = { key = me, name = Names.Display(me), class = m.c, spec = specOf(m), ilvl = ilvl, m = m } end
    end
    table.sort(list, function(x, y) return (x.ilvl or 0) > (y.ilvl or 0) end)
    return list
end

-- default partner: the last pick, else you, else the best of the same class and spec
local function defaultPartner(a)
    if state.lastB and not Names.Same(state.lastB, a) then return state.lastB end
    local me = Names.Me()
    if me and not Names.Same(me, a) then
        local m = ns.Database.Member(me)
        if m and ns.Inspect.Gear(m) then return me end
    end
    local _, ma, ca = member(a)
    local list = candidates(a)
    for _, c in ipairs(list) do if c.class == ca and c.spec and c.spec == specOf(ma) then return c.key end end
    for _, c in ipairs(list) do if c.class == ca then return c.key end end
    return list[1] and list[1].key
end

---------------------------------------------------------------------------
-- Search menu
---------------------------------------------------------------------------
local function entry(c, tag)
    return {
        value = c.key, tag = tag,
        text = ns.ColorName(c.name, c.class),
        right = (c.spec and Theme.HexColor("muted", c.spec) .. "   " or "") .. (c.ilvl and ("%.1f"):format(c.ilvl) or "–"),
        setIcon = function(tex) ns.SetSpecIcon(tex, c.class, ns.SpecPoints(c.m)) end,
    }
end

function Compare.Pick(anchor, a, onPicked)
    UI.SearchMenu(anchor, {
        width = 340, placeholder = L.CMP_SEARCH, hint = L.CMP_KEYS,
        build = function(q)
            local _, ma, ca = member(a)
            local list = candidates(a)
            local function match(c)
                if q == "" then return true end
                return (c.name or ""):lower():find(q, 1, true) or className(c.class):lower():find(q, 1, true)
                    or (c.spec or ""):lower():find(q, 1, true)
            end
            local out, used = {}, {}
            -- suggestions: you and the closest same-spec players
            local sug = {}
            local me = Names.Me()
            for _, c in ipairs(list) do
                if match(c) then
                    if Names.Same(c.key, me) then table.insert(sug, 1, entry(c, L.CMP_YOU)); used[c.key] = true
                    elseif c.class == ca and c.spec and c.spec == specOf(ma) and #sug < 3 then sug[#sug + 1] = entry(c, L.CMP_SAME_SPEC); used[c.key] = true end
                end
            end
            if #sug > 0 then
                out[#out + 1] = { head = L.CMP_SUGGEST }
                for _, e in ipairs(sug) do out[#out + 1] = e end
            end
            -- then by class: the own class first
            local byClass, classes = {}, {}
            for _, c in ipairs(list) do
                if match(c) and not used[c.key] and c.class then
                    if not byClass[c.class] then byClass[c.class] = {}; classes[#classes + 1] = c.class end
                    table.insert(byClass[c.class], c)
                end
            end
            table.sort(classes, function(x, y)
                if (x == ca) ~= (y == ca) then return x == ca end
                return className(x) < className(y)
            end)
            for _, class in ipairs(classes) do
                out[#out + 1] = { head = className(class) .. " · " .. #byClass[class] }
                for _, c in ipairs(byClass[class]) do out[#out + 1] = entry(c) end
            end
            if #out == 0 then out[1] = { head = L.CMP_NONE } end
            return out
        end,
        onPick = function(key)
            if onPicked then onPicked(key) else Compare.Open(a, key) end
        end,
    })
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
-- one gear side: icon, name, "iLvl 66 · verz."; mirrored on the right
local function gearSide(parent, mirrored)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_H)
    f.icon = UI.ItemIcon(f, 30)
    f.icon:SetPoint(mirrored and "RIGHT" or "LEFT", mirrored and -10 or 10, 0)
    f.empty = UI.Panel(f, "input", "borderDim")
    f.empty:SetSize(30, 30)
    f.empty:SetPoint(mirrored and "RIGHT" or "LEFT", mirrored and -10 or 10, 0)
    local just = mirrored and "RIGHT" or "LEFT"
    f.name = UI.Text(f, 13, "text", just)
    f.name:SetPoint("BOTTOM" .. just, f.icon, mirrored and "LEFT" or "RIGHT", mirrored and -8 or 8, 1)
    f.sub = UI.Text(f, 11, "muted", just)
    f.sub:SetPoint("TOP" .. just, f.icon, mirrored and "LEFT" or "RIGHT", mirrored and -8 or 8, -2)
    function f:Set(slotId, item, better, width)
        self.icon:SetItem(item)
        self.empty:SetShown(item == nil)
        self.name:SetWidth(math.max(40, width - 58))
        self.sub:SetWidth(math.max(40, width - 58))
        if not item then
            self.name:SetText(Theme.HexColor("muted", L.ARM_EMPTY))
            self.sub:SetText("")
            return
        end
        local info = Items.Info(item)
        local q = info and info.quality
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local name = info and info.name or ("item " .. (Items.ID(item) or "?"))
        self.name:SetText(c and (c.hex .. name .. "|r") or name)
        local parts = {}
        local level = Items.Level(item)
        if level then parts[#parts + 1] = "iLvl " .. Theme.HexColor(better and "good" or "textDim", tostring(level)) end
        if Items.Enchant(item) then parts[#parts + 1] = Theme.HexColor("good", L.CMP_ENCH)
        elseif Items.ShouldEnchant(slotId, item) then parts[#parts + 1] = Theme.HexColor("bad", L.CMP_NO_ENCH) end
        self.sub:SetText(table.concat(parts, Theme.HexColor("muted", " · ")))
    end
    return f
end

local function gearRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = UI.Fill(r, (i % 2 == 1) and "row" or "rowAlt", "BACKGROUND")
    r.bg:SetAllPoints()
    r.left = gearSide(r, false)
    r.right = gearSide(r, true)
    r.slot = UI.Text(r, 10, "muted", "CENTER", nil, true)
    r.slot:SetPoint("BOTTOM", r, "CENTER", 0, 1)
    r.diff = UI.Text(r, 13, "muted", "CENTER", nil, true)
    r.diff:SetPoint("TOP", r, "CENTER", 0, -1)
    -- the better side is tinted with a green edge, so the number in the middle has a clear owner
    for _, k in ipairs({ "winA", "winB" }) do
        local t = UI.Fill(r, "good", "BORDER"); t:SetAlpha(0.07); t:Hide(); r[k] = t
        local e = UI.Fill(r, "good", "ARTWORK"); e:SetWidth(2); e:Hide(); r[k .. "Edge"] = e
    end
    r.winA:SetPoint("TOPLEFT"); r.winA:SetPoint("BOTTOMRIGHT", r, "BOTTOM", 0, 0)
    r.winB:SetPoint("TOPLEFT", r, "TOP", 0, 0); r.winB:SetPoint("BOTTOMRIGHT")
    r.winAEdge:SetPoint("TOPLEFT"); r.winAEdge:SetPoint("BOTTOMLEFT")
    r.winBEdge:SetPoint("TOPRIGHT"); r.winBEdge:SetPoint("BOTTOMRIGHT")
    r.mid = CreateFrame("Frame", nil, r)
    r.mid:SetPoint("TOP"); r.mid:SetPoint("BOTTOM"); r.mid:SetWidth(96)
    r.mid:SetScript("OnEnter", function(self)
        if not r.tip then return end
        ns.TipOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(r.tip[1], Theme.Color("text"))
        for i = 2, #r.tip do GameTooltip:AddLine(r.tip[i], 0.75, 0.75, 0.75, true) end
        GameTooltip:Show()
    end)
    r.mid:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

-- two values mirrored around a label, bars grow from the middle outwards
local function mirrorRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(30)
    r.a = UI.Text(r, 13, "text", "LEFT", nil, true)
    r.a:SetPoint("TOPLEFT", 0, -2)
    r.b = UI.Text(r, 13, "text", "RIGHT", nil, true)
    r.b:SetPoint("TOPRIGHT", 0, -2)
    r.label = UI.Text(r, 10, "muted", "CENTER", nil, true)
    r.label:SetPoint("TOP", 0, -4)
    r.trackA = UI.Fill(r, "borderDim", "ARTWORK")
    r.trackB = UI.Fill(r, "borderDim", "ARTWORK")
    r.fillA = UI.Fill(r, "accent", "OVERLAY")
    r.fillB = UI.Fill(r, "accent", "OVERLAY")
    for _, t in ipairs({ r.trackA, r.trackB, r.fillA, r.fillB }) do t:SetHeight(3) end
    function r:Set(width, label, at, bt, av, bv)
        local half = math.floor((width - 4) / 2)
        self.label:SetText(ns.Upper(label))
        local better = (av or 0) ~= (bv or 0)
        self.a:SetText(Theme.HexColor(better and (av or 0) > (bv or 0) and "good" or "text", at or "–"))
        self.b:SetText(Theme.HexColor(better and (bv or 0) > (av or 0) and "good" or "text", bt or "–"))
        self.trackA:ClearAllPoints(); self.trackA:SetPoint("BOTTOMLEFT", 0, 2); self.trackA:SetWidth(half)
        self.trackB:ClearAllPoints(); self.trackB:SetPoint("BOTTOMRIGHT", 0, 2); self.trackB:SetWidth(half)
        local mx = math.max(av or 0, bv or 0)
        local wa = mx > 0 and math.max(1, half * (av or 0) / mx) or 1
        local wb = mx > 0 and math.max(1, half * (bv or 0) / mx) or 1
        self.fillA:ClearAllPoints(); self.fillA:SetPoint("BOTTOMRIGHT", self.trackA, "BOTTOMRIGHT"); self.fillA:SetWidth(wa)
        self.fillB:ClearAllPoints(); self.fillB:SetPoint("BOTTOMLEFT", self.trackB, "BOTTOMLEFT"); self.fillB:SetWidth(wb)
        self.fillA:SetVertexColor(Theme.Color((av or 0) >= (bv or 0) and "accent" or "textDim"))
        self.fillB:SetVertexColor(Theme.Color((bv or 0) >= (av or 0) and "accent" or "textDim"))
        self.fillA:SetShown((av or 0) > 0); self.fillB:SetShown((bv or 0) > 0)
    end
    return r
end

local function card(parent, title)
    local c = UI.Panel(parent, "panel", "borderDim")
    c.right = UI.Text(c, 10, "muted", "RIGHT")
    c.right:SetPoint("TOPRIGHT", -12, -10)
    c.title = UI.CardTitle(c, title, c.right)
    c.rows = {}
    return c
end

local function head(parent, mirrored)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(56)
    local side = mirrored and "RIGHT" or "LEFT"
    h.ring = h:CreateTexture(nil, "BORDER")
    h.ring:SetTexture(Theme.WHITE)
    h.ring:SetAlpha(0)   -- class icons without a border
    h.ring:SetSize(48, 48)
    h.ring:SetPoint(side, 0, 0)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetPoint("TOPLEFT", h.ring, "TOPLEFT", 0, 0)
    h.icon:SetPoint("BOTTOMRIGHT", h.ring, "BOTTOMRIGHT", 0, 0)
    h.name = UI.Text(h, 22, "text", side)
    h.name:SetPoint("BOTTOM" .. side, h.ring, mirrored and "LEFT" or "RIGHT", mirrored and -12 or 12, 2)
    h.sub = UI.Text(h, 12, "textDim", side)
    h.sub:SetPoint("TOP" .. side, h.ring, mirrored and "LEFT" or "RIGHT", mirrored and -12 or 12, -4)
    h.ilvlLabel = UI.Text(h, 10, "muted", "CENTER", nil, true)
    h.ilvlLabel:SetText(ns.Upper(L.COL_ILVL))
    h.ilvl = UI.Text(h, 24, "gold", "CENTER")
    h.ilvl:SetPoint(mirrored and "LEFT" or "RIGHT", h, mirrored and "LEFT" or "RIGHT", mirrored and 14 or -14, -6)
    h.ilvlLabel:SetPoint("BOTTOM", h.ilvl, "TOP", 0, 0)
    return h
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Compare.Build(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    if view.SetClipsChildren then view:SetClipsChildren(true) end

    -- top bar: back to the armory · partner picker · swap · only differences
    local back = UI.Button(view, "‹  " .. L.CMP_BACK, 150, 26, function() Compare.Close() end)
    back:SetPoint("TOPLEFT")
    local with = UI.Text(view, 11, "muted", "LEFT", nil, true)
    with:SetPoint("LEFT", back, "RIGHT", 18, 0)
    with:SetText(ns.Upper(L.CMP_WITH))
    view.picker = UI.Button(view, "", 230, 26, function(self)
        Compare.Pick(self, state.a, function(key) state.lastB = key; Compare.Open(state.a, key) end)
    end)
    view.picker:SetPoint("LEFT", with, "RIGHT", 10, 0)
    view.picker.label:ClearAllPoints()
    view.picker.label:SetPoint("LEFT", 32, 0)
    view.picker.label:SetJustifyH("LEFT")
    view.picker.label:SetWidth(170)
    view.picker.spec = view.picker:CreateTexture(nil, "OVERLAY")
    view.picker.spec:SetSize(16, 16)
    view.picker.spec:SetPoint("LEFT", 9, 0)
    view.picker.chev = UI.Icon(view.picker, "chevron-down", 11, "textDim")
    view.picker.chev:SetPoint("RIGHT", -9, 0)
    view.swap = UI.IconButton(view, "arrow-left-right", 26, function()
        if state.a and state.b then Compare.Open(state.b, state.a) end
    end)
    view.swap:SetPoint("LEFT", view.picker, "RIGHT", 8, 0)
    view.swap.tip = L.CMP_SWAP
    view.onlyDiff = UI.Check(view, L.CMP_ONLY_DIFF, function() return state.onlyDiff end,
        function(v) state.onlyDiff = v; Compare.Fill() end)
    view.onlyDiff:SetPoint("TOPRIGHT", -4 - ns.Window.SearchReserve(), -4)
    local line = UI.Divider(view)
    line:SetPoint("TOPLEFT", 0, -36)
    line:SetPoint("TOPRIGHT", 0, -36)

    -- heads: both characters mirrored, "VS" diamond with the item level difference
    view.heads = UI.Panel(view, "panel", "borderDim")
    view.heads:SetPoint("TOPLEFT", 0, -46)
    view.heads:SetPoint("TOPRIGHT", 0, -46)
    view.heads:SetHeight(72)
    local tint = UI.Gradient(view.heads, "bronze", 0.08, "BORDER")
    tint:SetPoint("TOPLEFT", 1, -1); tint:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.Corners(view.heads)
    view.headA = head(view.heads, false)
    view.headA:SetPoint("LEFT", 14, 0)
    view.headB = head(view.heads, true)
    view.headB:SetPoint("RIGHT", -14, 0)
    view.vs = view.heads:CreateTexture(nil, "ARTWORK")
    view.vs:SetTexture(Theme.WHITE)
    view.vs:SetSize(22, 22)
    view.vs:SetPoint("CENTER", 0, 8)
    view.vs:SetVertexColor(Theme.Color("bronzeDim"))
    if view.vs.SetRotation then view.vs:SetRotation(math.rad(45)) end
    view.vsText = UI.Text(view.heads, 10, "text", "CENTER", nil, true)
    view.vsText:SetPoint("CENTER", view.vs, "CENTER", 0, 0)
    view.vsText:SetText("VS")
    view.vsDiff = UI.Text(view.heads, 13, "good", "CENTER", nil, true)
    view.vsDiff:SetPoint("TOP", view.vs, "BOTTOM", 0, -6)

    -- body: gear table on the left, cards on the right (stacked when narrow)
    local scroll, body = UI.ScrollArea(view)
    scroll:SetPoint("TOPLEFT", 0, -128)
    scroll:SetPoint("BOTTOMRIGHT", -6, 0)
    view.scroll, view.body = scroll, body
    view.table = UI.Panel(body, "bg", "borderDim")
    view.tableHead = CreateFrame("Frame", nil, view.table)
    view.tableHead:SetPoint("TOPLEFT", 1, -1)
    view.tableHead:SetPoint("TOPRIGHT", -1, -1)
    view.tableHead:SetHeight(28)
    view.colA = UI.Text(view.tableHead, 11, "muted", "LEFT", nil, true)
    view.colA:SetPoint("LEFT", 12, 0)
    view.colB = UI.Text(view.tableHead, 11, "muted", "RIGHT", nil, true)
    view.colB:SetPoint("RIGHT", -12, 0)
    view.colSlot = UI.Text(view.tableHead, 11, "accent", "CENTER", nil, true)
    view.colSlot:SetPoint("CENTER")
    view.colSlot:SetText(ns.Upper(L.CMP_SLOT))
    local hl = UI.Fill(view.tableHead, "borderDim", "ARTWORK")
    hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT"); hl:SetHeight(1)
    view.rows = {}
    view.empty = UI.Text(view.table, 12, "muted", "CENTER")
    view.empty:SetPoint("TOP", 0, -50)

    view.stats = card(body, L.CMP_STATS)
    view.talents = card(body, L.ARM_TALENTS)
    view.misc = card(body, L.CMP_PROFS_ATT)
    for _, c in ipairs({ view.stats, view.talents }) do
        c.mrows = {}
        for i = 1, 5 do c.mrows[i] = mirrorRow(c) end
    end
    view.misc.lineA = UI.Text(view.misc, 12, "textDim")
    view.misc.lineB = UI.Text(view.misc, 12, "textDim")
    view.misc.lineA2 = UI.Text(view.misc, 12, "textDim")
    view.misc.lineB2 = UI.Text(view.misc, 12, "textDim")
    view.misc.sep = UI.Fill(view.misc, "borderDim", "ARTWORK")
    view.misc.sep:SetHeight(1)

    scroll:HookScript("OnSizeChanged", function() if view:IsShown() then ns.Debounce("compare-layout", 0.05, Compare.Fill) end end)
end

---------------------------------------------------------------------------
-- Fill
---------------------------------------------------------------------------
local function setHead(h, key)
    local g, m, class = member(key)
    ns.SetSpecIcon(h.icon, class, ns.SpecPoints(m))
    h.ring:SetVertexColor(ns.ClassColor(class))
    h.name:SetText(ns.ColorName(g.name or m.name or key, class))
    local r, gg, b = ns.ClassColor(class)
    local bits = { L.LEVEL .. " " .. (g.level or m.l or "?"), ns.Hex(r, gg, b, className(class)) }
    if specOf(m) then bits[#bits + 1] = Theme.HexColor("text", specOf(m)) end
    if g.rank then bits[#bits + 1] = g.rank end
    h.sub:SetText(table.concat(bits, Theme.HexColor("muted", "  ·  ")))
    local _, ilvl = ns.Inspect.Gear(m)
    h.ilvl:SetText(ilvl and ("%.1f"):format(ilvl) or "–")
    return g, m, class, ilvl
end

local function num(text) return tonumber(tostring(text or ""):match("[%d%.]+")) end

function Compare.Fill()
    if not view or not view:IsShown() or not state.a or not state.b then return end
    local ga, ma, ca, ia = setHead(view.headA, state.a)
    local gb, mb, cb, ib = setHead(view.headB, state.b)
    local W = math.max(520, (view.scroll:GetWidth() or 900) - 8)
    local headW = math.floor((W - 120) / 2)
    view.headA:SetWidth(headW); view.headB:SetWidth(headW)
    view.headA.name:SetWidth(headW - 140); view.headA.sub:SetWidth(headW - 70)
    view.headB.name:SetWidth(headW - 140); view.headB.sub:SetWidth(headW - 70)

    -- picker shows the partner
    view.picker:SetText(ns.ColorName(gb.name or mb.name or state.b, cb))
    ns.SetSpecIcon(view.picker.spec, cb, ns.SpecPoints(mb))

    local d = (ia or 0) - (ib or 0)
    if ia and ib and math.abs(d) >= 0.05 then
        view.vsDiff:SetText(Theme.HexColor("good", (d > 0 and "‹ " or "") .. ("+%.1f"):format(math.abs(d)) .. (d < 0 and " ›" or "")))
    else
        view.vsDiff:SetText(Theme.HexColor("muted", "="))
    end

    -- layout: table + cards side by side, stacked when narrow
    local stacked = W < 900
    local sideW = stacked and W or SIDE_W
    local tableW = stacked and W or (W - SIDE_W - 16)
    view.colA:SetText(ns.Upper(Names.Display(ga.name or state.a)))
    view.colB:SetText(ns.Upper(Names.Display(gb.name or state.b)))

    -- gear rows (all slots; "only differences" hides equal ones)
    local gearA = ns.Inspect.Gear(ma) or {}
    local gearB = ns.Inspect.Gear(mb) or {}
    local half = math.floor((tableW - 2 - 96) / 2)
    local n = 0
    for _, s in ipairs(Items.SLOTS) do
        local ia2, ib2 = gearA[s.id], gearB[s.id]
        local la, lb = ia2 and Items.Level(ia2) or 0, ib2 and Items.Level(ib2) or 0
        local same = (ia2 and Items.ID(ia2)) == (ib2 and Items.ID(ib2)) and la == lb
        if not (state.onlyDiff and same) and (ia2 or ib2) then
            n = n + 1
            local r = view.rows[n]
            if not r then r = gearRow(view.table, n); view.rows[n] = r end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -29 - (n - 1) * ROW_H)
            r:SetWidth(tableW - 2)
            r.left:ClearAllPoints(); r.left:SetPoint("LEFT"); r.left:SetWidth(half)
            r.right:ClearAllPoints(); r.right:SetPoint("RIGHT"); r.right:SetWidth(half)
            r.left:Set(s.id, ia2, la > lb, half)
            r.right:Set(s.id, ib2, lb > la, half)
            r.slot:SetText(ns.Upper(L["SLOT_" .. s.key] or s.key))
            local dd = la - lb
            local nameA, nameB = Names.Display(ga.name or state.a), Names.Display(gb.name or state.b)
            r.winA:SetShown(dd > 0); r.winAEdge:SetShown(dd > 0)
            r.winB:SetShown(dd < 0); r.winBEdge:SetShown(dd < 0)
            if dd == 0 then
                r.diff:SetText(Theme.HexColor("muted", L.CMP_EQUAL))
                r.tip = { ns.Upper(L["SLOT_" .. s.key] or s.key), same and L.CMP_SAME_ITEM or L.CMP_SAME_LEVEL:format(la) }
            else
                local who = dd > 0 and nameA or nameB
                r.diff:SetText(Theme.HexColor("good", (dd > 0 and "‹ " or "") .. L.CMP_ILVL_PLUS:format(math.abs(dd)) .. (dd < 0 and " ›" or "")))
                r.tip = { ns.Upper(L["SLOT_" .. s.key] or s.key), L.CMP_DIFF_TIP:format(who, math.abs(dd)),
                    ("%s %s · %s %s"):format(nameA, la > 0 and la or "–", nameB, lb > 0 and lb or "–") }
            end
            r:Show()
        end
    end
    for i = n + 1, #view.rows do view.rows[i]:Hide() end
    view.empty:SetText(n == 0 and (state.onlyDiff and L.CMP_SAME or L.CMP_NO_GEAR) or "")
    view.table:ClearAllPoints()
    view.table:SetPoint("TOPLEFT", view.body, "TOPLEFT", 0, 0)
    view.table:SetWidth(tableW)
    local tableH = 30 + math.max(1, n) * ROW_H + (n == 0 and 60 or 0)
    view.table:SetHeight(tableH)

    -- stats
    local sa = ns.Armory.StatSet(ma, ca) or {}
    local sb = ns.Armory.StatSet(mb, cb) or {}
    local inner = sideW - 24
    local rows = {}
    for i = 1, 3 do
        if sa[i] or sb[i] then
            rows[#rows + 1] = { (sa[i] or sb[i])[1], sa[i] and tostring(sa[i][2]) or "–", sb[i] and tostring(sb[i][2]) or "–",
                num(sa[i] and sa[i][2]), num(sb[i] and sb[i][2]) }
        end
    end
    local ea = Items.EnchantStatus(gearA) or { done = 0, needed = 0 }
    local eb = Items.EnchantStatus(gearB) or { done = 0, needed = 0 }
    rows[#rows + 1] = { L.CMP_ENCHANTS, ea.done .. "/" .. ea.needed, eb.done .. "/" .. eb.needed, ea.done, eb.done }
    local function fillMirror(c, list)
        local y = -38
        for i, row in ipairs(list) do
            local mr = c.mrows[i]
            mr:ClearAllPoints()
            mr:SetPoint("TOPLEFT", 12, y)
            mr:SetWidth(inner)
            mr:Set(inner, row[1], row[2], row[3], row[4], row[5])
            mr:Show()
            y = y - 34
        end
        for i = #list + 1, #c.mrows do c.mrows[i]:Hide() end
        c:SetHeight(-y + 8)
        return -y + 8
    end
    -- talents: points per tree
    local function points(m)
        local out = {}
        for p in tostring(ns.SpecPoints(m) or ""):gmatch("%d+") do out[#out + 1] = tonumber(p) end
        return out
    end
    local function treeNames(m)
        return ns.TreeNames(m.c, m.tn or (m.insp and m.insp.tn))
    end
    local pa, pb = points(ma), points(mb)
    local names = ca == cb and treeNames(ma) or {}
    local trows = {}
    for i = 1, math.max(#pa, #pb, 0) do
        trows[#trows + 1] = { names[i] or ("#" .. i), pa[i] and tostring(pa[i]) or "–", pb[i] and tostring(pb[i]) or "–", pa[i], pb[i] }
    end
    view.talents.right:SetText(ca ~= cb and Theme.HexColor("muted", L.CMP_OTHER_CLASS) or "")

    -- professions and attunements: one line per character
    local function profLine(m)
        local parts = {}
        for _, p in ipairs(m.pr or {}) do
            local pk = ns.Crafts and ns.Crafts.ProfKey(p.n)
            local info = pk and ns.Crafts.ProfInfo(pk)
            if info and pk ~= "cooking" and pk ~= "firstaid" and pk ~= "fishing" then
                parts[#parts + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(info.icon, Theme.HexColor("textDim", p.s or "?"))
            end
        end
        return #parts > 0 and table.concat(parts, "   ") or Theme.HexColor("muted", "–")
    end
    local function attLine(m)
        local at = ns.Attune and ns.Attune.Parse(m.at)
        if not at then return Theme.HexColor("muted", L.ATT_NO_ADDON) end
        local out = {}
        for _, e in ipairs(ns.Attune.LIST) do
            if e.kind == "attune" then
                out[#out + 1] = (at[e.key] and UI.Glyph("badge-check", "good", 11) .. " " .. Theme.HexColor("good", e.short))
                    or Theme.HexColor("muted", "× " .. e.short)
            end
        end
        return table.concat(out, "   ")
    end
    local who = function(g, m, key, class) return ns.ColorName(g.name or m.name or key, class) end
    local misc = view.misc
    local x, y = 12, -38
    misc.lineA:ClearAllPoints(); misc.lineA:SetPoint("TOPLEFT", x, y); misc.lineA:SetWidth(inner)
    misc.lineA:SetText(who(ga, ma, state.a, ca) .. "   " .. profLine(ma))
    misc.lineA2:ClearAllPoints(); misc.lineA2:SetPoint("TOPLEFT", x, y - 18); misc.lineA2:SetWidth(inner)
    misc.lineA2:SetText(attLine(ma))
    misc.sep:ClearAllPoints(); misc.sep:SetPoint("TOPLEFT", x, y - 40); misc.sep:SetWidth(inner)
    misc.lineB:ClearAllPoints(); misc.lineB:SetPoint("TOPLEFT", x, y - 48); misc.lineB:SetWidth(inner)
    misc.lineB:SetText(who(gb, mb, state.b, cb) .. "   " .. profLine(mb))
    misc.lineB2:ClearAllPoints(); misc.lineB2:SetPoint("TOPLEFT", x, y - 66); misc.lineB2:SetWidth(inner)
    misc.lineB2:SetText(attLine(mb))
    misc:SetHeight(38 + 66 + 26)

    -- place the cards
    local cx = stacked and 0 or (tableW + 16)
    local cy = stacked and (tableH + 12) or 0
    for _, c in ipairs({ view.stats, view.talents, view.misc }) do
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", view.body, "TOPLEFT", cx, -cy)
        c:SetWidth(sideW)
    end
    cy = cy + fillMirror(view.stats, rows) + 10
    view.talents:ClearAllPoints(); view.talents:SetPoint("TOPLEFT", view.body, "TOPLEFT", cx, -cy)
    cy = cy + fillMirror(view.talents, trows) + 10
    view.misc:ClearAllPoints(); view.misc:SetPoint("TOPLEFT", view.body, "TOPLEFT", cx, -cy)
    cy = cy + view.misc:GetHeight() + 10
    view.body:SetHeight(math.max(stacked and cy or math.max(tableH, cy), 10) + 12)
    view.scroll.UpdateBar()
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
function Compare.Open(a, b)
    if not view or not a then return end
    b = b or defaultPartner(a)
    if not b then ns.Print(L.CMP_NONE); return end
    state.a, state.b = a, b
    if ns.Armory and ns.Armory.Suspend then ns.Armory.Suspend() end
    view:Show()
    view.onlyDiff:Refresh()
    view.scroll:SetVerticalScroll(0)
    Compare.Fill()
end

function Compare.Close()
    if not view then return end
    view:Hide()
    local back = state.a
    state.a, state.b = nil, nil
    if ns.Armory and ns.Armory.Resume and back then ns.Armory.Resume() end
end

function Compare.IsOpen() return view ~= nil and view:IsShown() end

ns.On("LG_PROFILE", function() if Compare.IsOpen() then ns.Debounce("compare-fill", 0.5, Compare.Fill) end end)
ns.On("LG_ITEMS", function() if Compare.IsOpen() then ns.Debounce("compare-fill", 0.5, Compare.Fill) end end)
