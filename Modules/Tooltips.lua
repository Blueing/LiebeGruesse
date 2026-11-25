-- Extra tooltip lines for guild members (and partner guild members with the
-- addon): item level, enchants, spec, talents, professions, main/alts,
-- attunements, note, version. Every part can be switched on/off on the
-- settings page "Tooltips", which also shows a live preview.
local _, ns = ...
local UI, L, Names, Theme = ns.UI, ns.L, ns.Names, ns.Theme
local Tips = {}
ns.Tooltips = Tips

local DEFAULTS = {
    unit = true, ilvl = true, enchants = true, spec = true, talents = false, profs = true, secondary = false,
    skill = true, alt = true, alts = false, attune = false, note = false, version = false, partner = true,
    layout = "compact", shift = false, cursor = true, crafters = true,
}

function Tips.Settings()
    local s = ns.Database.Settings()
    s.tooltips = s.tooltips or {}
    local o = s.tooltips
    for k, v in pairs(DEFAULTS) do if o[k] == nil then o[k] = v end end
    return o
end

local SECONDARY = { cooking = true, firstaid = true, fishing = true }

local function className(class)
    return class and ns.ClassName(class) or ""
end

-- The lines for member m (key, guild roster entry g): { { text, r, g, b }, … }
function Tips.Lines(m, key, g, o)
    o = o or Tips.Settings()
    local out = {}
    local compact = o.layout ~= "lines"
    local gold = { Theme.Color("gold") }
    local function add(text, color)
        local c = color or { 0.85, 0.85, 0.85 }
        out[#out + 1] = { text, c[1], c[2], c[3] }
    end
    local function labeled(label, value, color)
        if compact then return value end
        add(Theme.HexColor("muted", label .. ": ") .. value, color)
    end

    -- item level · enchants · spec · talents
    local first = {}
    local gear, ilvl = ns.Inspect.Gear(m)
    if o.ilvl and ilvl then
        if compact then first[#first + 1] = L.TIP_ILVL:format(ilvl) else labeled(L.COL_ILVL, ("%.1f"):format(ilvl), gold) end
    end
    local e = gear and ns.Items.EnchantStatus(gear)
    if o.enchants and e and e.needed > 0 then
        local text = Theme.HexColor(#e.missing == 0 and "good" or "bad", ("%d/%d"):format(e.done, e.needed))
        if compact then first[#first + 1] = Theme.HexColor(#e.missing == 0 and "good" or "bad", L.TIP_ENCHANTS:format(e.done, e.needed))
        else labeled(L.COL_ENCHANTS_LONG, text) end
    end
    local spec = ns.SpecName(m.sp or (m.insp and m.insp.sp), (g and g.class) or m.c, ns.SpecPoints(m))
    if o.spec and spec then
        if compact then first[#first + 1] = spec else labeled(L.COL_SPEC, spec, gold) end
    end
    local tp = m.tp or (m.insp and m.insp.tp)
    if o.talents and tp and tostring(tp):find("[1-9]") then
        if compact then first[#first + 1] = tp else labeled(L.ARM_TALENTS, tp, gold) end
    end
    if compact and #first > 0 then add(table.concat(first, "  ·  "), gold) end

    -- professions
    if o.profs then
        local profs = {}
        for _, p in ipairs(m.pr or {}) do
            local pk = ns.Crafts and ns.Crafts.ProfKey(p.n)
            if o.secondary or not (pk and SECONDARY[pk]) then
                local name = (pk and ns.Crafts.ProfName and ns.Crafts.ProfName(pk)) or p.n
                profs[#profs + 1] = o.skill and ("%s %s"):format(name, p.s or "?") or name
            end
        end
        if #profs > 0 then
            if compact then add(table.concat(profs, "  ·  ")) else labeled(L.COL_PROFESSIONS, table.concat(profs, ", ")) end
        end
    end

    -- main / alts
    local isAlt = m.m and not Names.Same(m.m, key)
    if o.alt and isAlt then add(L.ALT_OF:format(Names.Display(m.m)), { 0.6, 0.75, 1 }) end
    if o.alts and not isAlt then
        local alts = {}
        for k, other in pairs(ns.Database.Guild().members or {}) do
            if other.m and Names.Same(other.m, key) and not Names.Same(k, key) then alts[#alts + 1] = ns.ColorName(other.name or k, other.c) end
        end
        for _, a in ipairs(ns.Account and ns.Account.Unpack(m.a) or {}) do alts[#alts + 1] = ns.ColorName(a.name, a.c) end
        if #alts > 0 then
            table.sort(alts)
            if #alts > 6 then alts = { unpack(alts, 1, 6) }; alts[7] = "…" end
            add(Theme.HexColor("muted", L.ALTS .. ": ") .. table.concat(alts, ", "))
        end
    end

    -- attunements
    if o.attune and ns.Attune then
        local at = ns.Attune.Parse(m.at)
        if at then
            local parts = {}
            for _, a in ipairs(ns.Attune.LIST) do
                if a.kind == "attune" then
                    parts[#parts + 1] = at[a.key] and (UI.Glyph("badge-check", "good", 10) .. " " .. Theme.HexColor("good", a.short))
                        or Theme.HexColor("muted", a.short)
                end
            end
            if #parts > 0 then add((compact and "" or Theme.HexColor("muted", L.ATT_ATTUNES .. ": ")) .. table.concat(parts, "  ")) end
        end
    end

    if o.note and g and g.note and g.note ~= "" then add(Theme.HexColor("muted", L.NOTE .. ": ") .. g.note) end
    if o.version then add(Theme.HexColor("muted", m.v and ("Liebe Grüße v" .. m.v) or L.ARM_NO_ADDON)) end
    return out
end

---------------------------------------------------------------------------
-- Unit tooltip hook
---------------------------------------------------------------------------
local function addLines(tooltip, unit)
    local o = Tips.Settings()
    if not o.unit then return end
    if o.shift and not IsShiftKeyDown() then return end
    if not unit or not UnitIsPlayer(unit) then return end
    local name = Names.Unit(unit)
    local key = name and Names.Key(name)
    if not key then return end
    local m
    if ns.Guild.IsMember(key) then
        m = ns.Database.Member(key)
    elseif o.partner and ns.Roster and ns.Roster.MemberAny then
        m = ns.Roster.MemberAny(key)
        if m and not m.v then m = nil end   -- only partner members with the addon
    end
    if not m then return end
    for _, l in ipairs(Tips.Lines(m, key, ns.Guild.Find(key), o)) do tooltip:AddLine(l[1], l[2], l[3], l[4]) end
    tooltip:Show()
end

local function onUnit(tooltip)
    if tooltip ~= GameTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local _, unit = tooltip:GetUnit()
    if ns.IsSecret(unit) then return end
    unit = unit or "mouseover"
    ns.Safe(addLines, tooltip, unit)
end

ns.On("LG_READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", onUnit)
    end
end)

-- "only with Shift": pressing/releasing Shift redraws the unit tooltip
ns.On("MODIFIER_STATE_CHANGED", function(_, key)
    if not Tips.Settings().shift or not tostring(key):find("SHIFT") then return end
    if GameTooltip:IsShown() and ns.Call(UnitExists, "mouseover") and GameTooltip:GetUnit() then
        ns.Call(GameTooltip.SetUnit, GameTooltip, "mouseover")
    end
end)

-- /lg test tooltip: your own (or sample) tooltip lines at the cursor for 8 s
function Tips.Test()
    local me = Names.Me()
    local m = me and ns.Database.Member(me)
    local key, g = me, me and ns.Guild.Find(me)
    if not (m and m.c) then m, key, g = Tips.SAMPLE, "revo lock", { note = "Raid main" } end
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetText(ns.ColorName(m.name or Names.Display(key), m.c))
    for _, l in ipairs(Tips.Lines(m, key, g)) do GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
    GameTooltip:Show()
    ns.After(8, function() if GameTooltip:GetOwner() == UIParent then GameTooltip:Hide() end end)
end

---------------------------------------------------------------------------
-- Settings page with live preview
---------------------------------------------------------------------------
local SAMPLE = {
    name = "Revo Lock", c = "WARLOCK", l = 60, r = "Human", sp = "Destruction", tp = "7/13/31", v = "1.0.7",
    pr = { { n = "Tailoring", s = 285, m = 300 }, { n = "Enchanting", s = 300, m = 300 }, { n = "First Aid", s = 240, m = 300 },
        { n = "Cooking", s = 300, m = 300 } },
    at = nil, m = nil,
}
Tips.SAMPLE = SAMPLE

local function previewMember()
    local me = Names.Me()
    local m = me and ns.Database.Member(me)
    if m and m.c and (m.g or m.pr) then return m, me, ns.Guild.Find(me), false end
    return SAMPLE, "revo lock", { rank = "Member", note = "Raid main" }, true
end

UI.AddPage("tooltips", L.PAGE_TOOLTIPS, 92, function(content, page)
    local preview = UI.Panel(content, "panel", "borderDim")
    preview:SetWidth(320)
    preview.kicker = UI.CardTitle(preview, L.TIPS_PREVIEW)
    preview.box = UI.Panel(preview, "bg", "borderDim")
    preview.box:SetPoint("TOPLEFT", 12, -30)
    preview.box:SetPoint("TOPRIGHT", -12, -30)
    preview.note = UI.Text(preview, 10, "muted")
    preview.note:SetWordWrap(true)
    preview.lines = {}

    local form = UI.Form(content)
    page.Search = function(text) return form:Filter(text) end
    page.SearchEnter = function() form:JumpFirst() end
    page.head = L.HEAD_TOOLTIPS
    local o = Tips.Settings
    local function get(k) return function() return o()[k] end end
    local function set(k) return function(v) o()[k] = v; page.Preview() end end
    local function on() return o().unit end

    local s = form:Section(L.TIPS_UNIT)
    s:Toggle(L.TIPS_ENABLED, get("unit"), set("unit"), { tip = L.SET_TOOLTIPS_TIP })
    s:Segment(L.TIPS_LAYOUT, { { value = "compact", text = L.TIPS_COMPACT }, { value = "lines", text = L.TIPS_LINES } },
        get("layout"), set("layout"), { width = 200, show = on })
    s:Toggle(L.TIPS_SHIFT, get("shift"), set("shift"), { tip = L.TIPS_SHIFT_TIP, show = on })
    s:Toggle(L.TIPS_PARTNER, get("partner"), set("partner"), { tip = L.TIPS_PARTNER_TIP, show = on })

    local w = form:Section(L.TIPS_WHAT)
    for _, def in ipairs({
        { "ilvl", L.COL_ILVL }, { "enchants", L.COL_ENCHANTS_LONG }, { "spec", L.COL_SPEC }, { "talents", L.TIPS_TALENTS },
        { "profs", L.COL_PROFESSIONS }, { "skill", L.TIPS_SKILL, "profs" }, { "secondary", L.TIPS_SECONDARY, "profs" },
        { "alt", L.TIPS_ALT }, { "alts", L.TIPS_ALTS }, { "attune", L.ATT_ATTUNES }, { "note", L.NOTE }, { "version", L.TIPS_VERSION },
    }) do
        local dep = def[3]
        w:Toggle(def[2], get(def[1]), set(def[1]), { show = function() return on() and (not dep or o()[dep]) end })
    end

    local other = form:Section(L.TIPS_OTHER)
    other:Toggle(L.SET_TIP_CURSOR, get("cursor"), set("cursor"), { tip = L.SET_TIP_CURSOR_TIP })
    other:Toggle(L.SET_TIP_CRAFTERS, get("crafters"), set("crafters"), { tip = L.SET_TIP_CRAFTERS_TIP })

    local function line(i)
        local fs = preview.lines[i]
        if not fs then
            fs = UI.Text(preview.box, i == 1 and 14 or 12, "text")
            fs:SetWordWrap(false)
            preview.lines[i] = fs
        end
        return fs
    end

    function page.Preview()
        local m, key, g, sample = previewMember()
        local class = m.c
        local r, gg, b = ns.ClassColor(class)
        -- the game's own lines first (grey), then the addon's
        local rows = {
            { ns.Hex(r, gg, b, m.name or Names.Display(key)), 1, 1, 1 },
            { ("%s [%s]"):format((not sample and ns.Call(GetGuildInfo, "player")) or "Liebe Grüße", (g and g.rank) or "Member"), 1, 1, 1 },
            { ("%s %s %s"):format(L.LEVEL, m.l or "?", m.r or ""), 1, 1, 1 },
            { className(class), 1, 1, 1 },
        }
        if o().unit then
            for _, l in ipairs(Tips.Lines(m, key, g, o())) do rows[#rows + 1] = l end
        end
        local y = -8
        for i, row in ipairs(rows) do
            local fs = line(i)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 10, y)
            fs:SetPoint("TOPRIGHT", -10, y)
            fs:SetText(row[1])
            fs:SetTextColor(row[2], row[3], row[4])
            fs:Show()
            y = y - (i == 1 and 18 or 15)
        end
        for i = #rows + 1, #preview.lines do preview.lines[i]:Hide() end
        preview.box:SetHeight(-y + 6)
        preview.note:ClearAllPoints()
        preview.note:SetPoint("TOPLEFT", preview.box, "BOTTOMLEFT", 0, -8)
        preview.note:SetPoint("TOPRIGHT", preview.box, "BOTTOMRIGHT", 0, -8)
        preview.note:SetText(sample and L.TIPS_PREVIEW_SAMPLE or L.TIPS_PREVIEW_OWN)
        preview:SetHeight(-y + 6 + 30 + 40)
        form:Refresh()
    end

    -- responsive: preview to the right, or above the settings when narrow
    local function layout()
        local W = content:GetWidth() or 900
        preview:ClearAllPoints()
        form.scroll:ClearAllPoints()
        if W >= 760 then
            preview:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            preview:SetWidth(320)
            form.scroll:SetPoint("TOPLEFT")
            form.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -340, 0)
        else
            preview:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            preview:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            form.scroll:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -10)
            form.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 0)
        end
    end
    content:HookScript("OnSizeChanged", function() ns.Debounce("tips-layout", 0.05, layout) end)
    layout()
    page.OnShow = function() layout(); page.Preview() end
end, { section = "settings", icon = "message-circle" })
