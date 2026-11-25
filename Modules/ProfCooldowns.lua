-- Guild profession cooldowns (Mooncloth, transmutes, Salt Shaker, …).
-- Every member reads their own cooldowns and shares the ready time with the
-- guild; the "Cooldowns" tab of the professions page lists all of them.
local _, ns = ...
local PCD = ns.NewModule and ns.NewModule("ProfCooldowns") or {}
ns.ProfCD = PCD
local UI, Theme, L, Names, Comm = ns.UI, ns.Theme, ns.L, ns.Names, ns.Comm

-- Every profession cooldown of Classic / Forever, one entry per spell or item.
--   kind "spell": a known recipe with a cooldown; kind "item": an item in the bags
--   family: rows of one member with the same ready time are shown as one line
--   (e.g. all transmutes, if the game lets them share a cooldown)
-- Keys: "s<spellID>" / "i<itemID>". Own IDs can be added (settings.profcdCustom).
PCD.LIST = {
    -- Tailoring
    { id = 18560, kind = "spell", prof = "tailoring", family = "mooncloth", n = "Mooncloth" },           -- Mooncloth
    -- Alchemy: transmutes
    { id = 17187, kind = "spell", prof = "alchemy", family = "transmute", n = "Arcanite" },             -- Arcanite
    { id = 11479, kind = "spell", prof = "alchemy", family = "transmute", n = "Iron to Gold" },             -- Iron to Gold
    { id = 11480, kind = "spell", prof = "alchemy", family = "transmute", n = "Mithril to Truesilver" },             -- Mithril to Truesilver
    { id = 17559, kind = "spell", prof = "alchemy", family = "transmute", n = "Air to Fire" },             -- Air to Fire
    { id = 17560, kind = "spell", prof = "alchemy", family = "transmute", n = "Fire to Earth" },             -- Fire to Earth
    { id = 17561, kind = "spell", prof = "alchemy", family = "transmute", n = "Earth to Water" },             -- Earth to Water
    { id = 17562, kind = "spell", prof = "alchemy", family = "transmute", n = "Water to Air" },             -- Water to Air
    { id = 17563, kind = "spell", prof = "alchemy", family = "transmute", n = "Undeath to Water" },             -- Undeath to Water
    { id = 17564, kind = "spell", prof = "alchemy", family = "transmute", n = "Water to Undeath" },             -- Water to Undeath
    { id = 17565, kind = "spell", prof = "alchemy", family = "transmute", n = "Life to Earth" },             -- Life to Earth
    { id = 17566, kind = "spell", prof = "alchemy", family = "transmute", n = "Earth to Life" },             -- Earth to Life
    { id = 25146, kind = "spell", prof = "alchemy", family = "transmute", n = "Elemental Fire" },             -- Elemental Fire
    -- Leatherworking: Salt Shaker (Refined Deeprock Salt)
    { id = 15846, kind = "item", prof = "leatherworking", family = "salt", n = "Salt Shaker" },
    -- Mining / smelting
    { id = 22967, kind = "spell", prof = "mining", family = "elementium", n = "Smelt Elementium" },             -- Smelt Elementium
    -- Engineering: teleporters and other long item cooldowns
    { id = 18984, kind = "item", prof = "engineering", family = "teleport", n = "Dimensional Ripper - Everlook" },           -- Dimensional Ripper - Everlook
    { id = 18986, kind = "item", prof = "engineering", family = "teleport", n = "Ultrasafe Transporter: Gadgetzan" },           -- Ultrasafe Transporter: Gadgetzan
    { id = 18587, kind = "item", prof = "engineering", family = "engi", n = "Goblin Jumper Cables XL" },               -- Goblin Jumper Cables XL
    { id = 7506, kind = "item", prof = "engineering", family = "engi", n = "Gnomish Universal Remote" },                -- Gnomish Universal Remote
    { id = 18634, kind = "item", prof = "engineering", family = "engi", n = "Gyrofreeze Ice Reflector" },               -- Gyrofreeze Ice Reflector
    { id = 18637, kind = "item", prof = "engineering", family = "engi", n = "Major Recombobulator" },               -- Major Recombobulator
    { id = 18638, kind = "item", prof = "engineering", family = "engi", n = "Hyper-Radiant Flame Reflector" },               -- Hyper-Radiant Flame Reflector
    { id = 18639, kind = "item", prof = "engineering", family = "engi", n = "Ultra-Flash Shadow Reflector" },               -- Ultra-Flash Shadow Reflector
    { id = 10725, kind = "item", prof = "engineering", family = "engi", n = "Gnomish Battle Chicken" },               -- Gnomish Battle Chicken
    { id = 10726, kind = "item", prof = "engineering", family = "engi", n = "Gnomish Mind Control Cap" },               -- Gnomish Mind Control Cap
}
PCD.FAMILIES = { "mooncloth", "transmute", "salt", "elementium", "teleport", "engi", "custom" }
local OLD_GROUPS = { mooncloth = "s18560", transmute = "s17187", salt = "i15846", elementium = "s22967" }

local function customList()
    local st = ns.Database.Settings()
    st.profcdCustom = st.profcdCustom or {}
    return st.profcdCustom
end
PCD.Custom = customList

local BY_KEY
local function entries()
    local list = {}
    for _, e in ipairs(PCD.LIST) do list[#list + 1] = e end
    for _, c in ipairs(customList()) do
        list[#list + 1] = { id = c.id, kind = c.kind, prof = c.prof or "custom", family = "custom", custom = true }
    end
    BY_KEY = {}
    for _, e in ipairs(list) do
        e.key = (e.kind == "item" and "i" or "s") .. e.id
        BY_KEY[e.key] = e
    end
    return list
end
PCD.Entries = entries

function PCD.Entry(key)
    if not BY_KEY then entries() end
    key = OLD_GROUPS[key] or key
    return BY_KEY[key]
end

local function store()
    local g = ns.Database.Guild()
    g.profcd = g.profcd or {}
    return g.profcd
end
PCD.Store = store

-- name of a cooldown: the spell or item name in the client's language
function PCD.Name(key)
    key = OLD_GROUPS[key] or key
    local kind, id = key:match("^([si])(%d+)$")
    id = tonumber(id)
    if not id then return L["PCD_" .. key:upper()] or key end
    local e = PCD.Entry(key)
    local fallback = e and e.n
    if kind == "i" then
        local name = (C_Item and C_Item.GetItemNameByID and ns.Call(C_Item.GetItemNameByID, id)) or (GetItemInfo and ns.Call(GetItemInfo, id))
        if type(name) ~= "string" and C_Item and C_Item.RequestLoadItemDataByID then ns.Call(C_Item.RequestLoadItemDataByID, id) end
        return type(name) == "string" and name or fallback or ("Item " .. id)
    end
    local name
    if C_Spell and C_Spell.GetSpellName then name = ns.Call(C_Spell.GetSpellName, id)
    elseif GetSpellInfo then name = ns.Call(GetSpellInfo, id) end
    return type(name) == "string" and name or fallback or ("Spell " .. id)
end
-- item names arrive later from the server: redraw once they are there
ns.On("GET_ITEM_INFO_RECEIVED", function() ns.Debounce("profcd-names", 1, function() ns.Fire("LG_PROFCD") end) end)

function PCD.FamilyName(family) return L["PCD_FAM_" .. (family or "custom"):upper()] or family end
function PCD.GroupName(key) return PCD.Name(key) end
function PCD.ProfOf(key)
    local e = PCD.Entry(key)
    return e and e.prof or "custom"
end
function PCD.FamilyOf(key)
    local e = PCD.Entry(key)
    return e and e.family or "custom"
end

local function known(entry)
    if entry.kind == "item" then
        local count = ns.Call(GetItemCount, entry.id)
        return ns.Num(count) and count > 0 or false
    end
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, entry.id)
        if ok and v then return true end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, entry.id)
        if ok and v then return true end
    end
    return false
end

-- seconds left on a cooldown (0 = ready) or nil when unreadable
local function left(entry)
    local start, duration
    if entry.kind == "item" then
        local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if not fn then return nil end
        start, duration = ns.Call(fn, entry.id)
    else
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = ns.Call(C_Spell.GetSpellCooldown, entry.id)
            if type(info) == "table" then start, duration = info.startTime, info.duration end
        elseif GetSpellCooldown then
            start, duration = ns.Call(GetSpellCooldown, entry.id)
        end
    end
    if not ns.Num(start) or not ns.Num(duration) then return nil end
    if start <= 0 or duration <= 1.5 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- Reads own cooldowns: { [group] = readyAt (epoch seconds) }
function PCD.ReadOwn()
    local out = {}
    for _, entry in ipairs(entries()) do
        if known(entry) then
            local l = left(entry)
            if l then
                out[entry.key] = l > 0 and math.floor(ns.Now() + l) or 0
            end
        end
    end
    return out
end

local function same(a, b)
    if not a then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

function PCD.Capture(force)
    local cds = PCD.ReadOwn()
    local me = Names.Me()
    local old = store()[me]
    local changed = not old or not same(old.c, cds)
    if not changed and not force then return end
    if next(cds) == nil and not old then return end
    store()[me] = { t = ns.Now(), c = cds }
    ns.Fire("LG_PROFCD")
    if IsInGuild() then Comm.Send("PC", { o = me, c = cds, t = ns.Now() }, "GUILD", { priority = "bulk" }) end
end

local function accept(owner, data)
    if type(data.c) ~= "table" then return end
    local old = store()[owner]
    if old and (old.t or 0) > (data.t or 0) then return end
    local c = {}
    for group, at in pairs(data.c) do
        -- spell/item keys (also ones we do not track ourselves) and old group names
        if type(group) == "string" and (group:match("^[si]%d+$") or OLD_GROUPS[group]) and tonumber(at) then
            c[OLD_GROUPS[group] or group] = tonumber(at)
        end
    end
    store()[owner] = { t = tonumber(data.t) or ns.Now(), c = c }
    ns.Debounce("profcd-redraw", 0.5, function() ns.Fire("LG_PROFCD") end)
end

Comm.Register("PC", function(data, sender)
    local owner = Names.Key(data.o or sender) or sender
    if Names.Same(owner, Names.Me()) then return end
    accept(owner, data)
end)

-- Late joiners ask once; one member answers with everything newer
Comm.Register("PCQ", function(data, sender, _, raw)
    if not IsInGuild() then return end
    local since = tonumber(data.since) or 0
    local list = {}
    for key, v in pairs(store()) do
        if (v.t or 0) > since and not Names.Same(key, sender) then list[#list + 1] = key end
    end
    if #list == 0 then return end
    Comm.ReplyOnce("profcd:" .. sender, 3, 12, function()
        Comm.Send("PA", { to = sender }, "GUILD", { priority = "alert" })
        for i, key in ipairs(list) do
            if i > 100 then break end
            local v = store()[key]
            Comm.Send("PC", { o = key, c = v.c, t = v.t }, "WHISPER", { target = raw, priority = "bulk" })
        end
    end)
end)
Comm.Register("PA", function(data) if data.to then Comm.Answered("profcd:" .. data.to) end end)

-- Rows for the list: one per member and cooldown group
function PCD.Rows(filter)
    local rows, now = {}, ns.Now()
    for member, v in pairs(store()) do
        local merged = {}
        for key, at in pairs(v.c or {}) do
            key = OLD_GROUPS[key] or key
            local family = PCD.FamilyOf(key)
            if not filter or filter == "all" or filter == family or (filter == "ready" and at <= now) then
                -- one line per family and ready time (shared cooldowns like transmutes)
                local id = family .. ":" .. (at <= now and 0 or at)
                local r = merged[id]
                if r then
                    r.count = r.count + 1
                    r.keys[#r.keys + 1] = key
                else
                    r = { key = member, group = key, family = family, keys = { key }, count = 1, at = at, left = math.max(0, at - now), t = v.t }
                    merged[id] = r
                    rows[#rows + 1] = r
                end
            end
        end
    end
    return rows
end

-- label of a row: the cooldown, or the family with a count when several share it
function PCD.RowLabel(r)
    if r.count > 1 then return ("%s (%d)"):format(PCD.FamilyName(r.family), r.count) end
    return PCD.Name(r.group)
end

function PCD.FormatLeft(sec)
    if sec <= 0 then return Theme.HexColor("good", L.PCD_READY) end
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(math.max(1, m))
end

-- Toast when one of your own cooldowns becomes ready
local announced = {}
local function checkReady()
    local mine = store()[Names.Me()]
    local s = ns.Notify and ns.Notify.Settings()
    if not mine or not s or not s.profcd then return end
    local now = ns.Now()
    for group, at in pairs(mine.c or {}) do
        if at > 0 and at <= now and not announced[group .. at] then
            announced[group .. at] = true
            if now - at < 3600 then
                UI.Toast(L.PCD_TOAST_TITLE, L.PCD_TOAST:format(PCD.Name(group)), 136249)
            end
        end
    end
end
PCD.CheckReady = checkReady

function PCD.Test()
    local me = Names.Me()
    local t = ns.Now()
    store()[me] = { t = t, c = { s18560 = t - 5, s17187 = t + 3 * 3600, s17559 = t + 3 * 3600, s17560 = t + 3 * 3600 } }
    store()["testcrafter"] = { t = t, c = { i15846 = t + 50000, i18984 = 0, i18587 = t + 900 } }
    ns.Fire("LG_PROFCD")
    UI.Toast(L.PCD_TOAST_TITLE, L.PCD_TOAST:format(PCD.Name("s18560")), 136249)
end

function PCD:OnLogin()
    ns.After(12, function() PCD.Capture(true) end)
    ns.After(50, function()
        if not IsInGuild() then return end
        local newest = 0
        for key, v in pairs(store()) do
            if not Names.Same(key, Names.Me()) then newest = math.max(newest, v.t or 0) end
        end
        Comm.Send("PCQ", { since = newest }, "GUILD", { priority = "bulk" })
    end)
    C_Timer.NewTicker(60, function() checkReady(); ns.Fire("LG_PROFCD_TICK") end)
end

-- a craft that starts a cooldown, or opening the profession window
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if unit ~= "player" then return end
    if not ns.Num(spellID) then return end
    local id = spellID
    for _, entry in ipairs(entries()) do
        if entry.kind == "spell" and entry.id == id then ns.Debounce("profcd-capture", 2, function() PCD.Capture(false) end) return end
    end
end)
ns.On("TRADE_SKILL_SHOW", function() ns.Debounce("profcd-capture", 2, function() PCD.Capture(false) end) end)
ns.On("BAG_UPDATE_COOLDOWN", function() ns.Debounce("profcd-capture", 3, function() PCD.Capture(false) end) end)

---------------------------------------------------------------------------
-- Tab on the professions page
---------------------------------------------------------------------------
function PCD.Build(parent)
    local tab = CreateFrame("Frame", nil, parent)
    local state = { filter = "all" }
    local head = UI.Text(tab, 11, "muted")
    head:SetPoint("TOPLEFT", 0, -4)
    head:SetText(L.PCD_HINT)

    local items = { { value = "all", text = L.PCD_ALL }, { value = "ready", text = L.PCD_ONLY_READY } }
    for _, f in ipairs(PCD.FAMILIES) do items[#items + 1] = { value = f, text = PCD.FamilyName(f) } end
    local filter = UI.Dropdown(tab, 200, function() return items end, function() return state.filter end,
        function(v) state.filter = v; tab.Refresh() end)
    filter:SetPoint("TOPLEFT", 0, -24)
    local refresh = UI.Button(tab, L.PCD_REFRESH, 140, 26, function() PCD.Capture(true); tab.Refresh() end)
    refresh:SetPoint("LEFT", filter, "RIGHT", 8, 0)
    local post = UI.Button(tab, L.PCD_POST, 170, 26, function()
        local ready = {}
        for _, r in ipairs(PCD.Rows("ready")) do
            ready[#ready + 1] = ("%s (%s)"):format(Names.Display((ns.Crafts.DisplayName(r.key))) or r.key, PCD.RowLabel(r))
        end
        if #ready == 0 then ns.Print(L.PCD_NONE_READY) return end
        ns.SendChat(L.PCD_POST_TEXT:format(table.concat(ready, ", ")), "GUILD")
    end)
    post:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    post.tip = { L.PCD_POST_TIP }

    -- own cooldowns (e.g. new Forever recipes): spell or item ID
    local idBox = UI.EditBox(tab, 90, 26, L.PCD_ID_PH)
    local kind = UI.Segmented(tab, 120, { { value = "spell", text = L.PCD_SPELL }, { value = "item", text = L.PCD_ITEM } },
        function() return state.kind or "spell" end, function(v) state.kind = v end)
    local add = UI.Button(tab, L.PCD_ADD, 110, 26, function()
        local id = tonumber((idBox:GetText() or ""):match("%d+"))
        if not id then ns.Print(L.PCD_ADD_HINT); return end
        local k = state.kind or "spell"
        for _, c in ipairs(customList()) do if c.id == id and c.kind == k then return end end
        table.insert(customList(), { id = id, kind = k })
        idBox:SetText("")
        entries()
        PCD.Capture(true)
        ns.Print(L.PCD_ADDED:format(PCD.Name((k == "item" and "i" or "s") .. id)))
        tab.Refresh()
    end)
    add:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -24)
    kind:ClearAllPoints(); kind:SetPoint("RIGHT", add, "LEFT", -6, 0)
    idBox:ClearAllPoints(); idBox:SetPoint("RIGHT", kind, "LEFT", -6, 0)
    add.tip = { L.PCD_ADD_TIP }

    local list = UI.List(tab, {
        onClick = function(r, button)
            if button ~= "RightButton" then return end
            local e = PCD.Entry(r.group)
            if not (e and e.custom) then return end
            UI.ContextMenu({ { title = PCD.Name(r.group) },
                { text = L.PCD_REMOVE, func = function()
                    for i, c in ipairs(customList()) do
                        if (c.kind == "item" and "i" or "s") .. c.id == e.key then table.remove(customList(), i); break end
                    end
                    entries()
                    tab.Refresh()
                end } })
        end,
        sortKey = "left", columns = {
            { key = "name", title = L.COL_NAME, flex = 1, text = function(r) return ns.Crafts.ColoredMember(r.key, true) end,
              sort = function(r) return r.key end },
            { key = "group", title = L.PCD_COOLDOWN, flex = 1.2, minWidth = 180, text = function(r)
                return UI.Glyph("hammer", "muted", 12) .. " " .. PCD.RowLabel(r) end, sort = function(r) return PCD.RowLabel(r) end,
              tip = function(r)
                  local names = {}
                  for _, k in ipairs(r.keys) do names[#names + 1] = PCD.Name(k) end
                  return table.concat(names, "\n")
              end },
            { key = "prof", title = L.PROFESSION, width = 150, text = function(r)
                local prof = PCD.ProfOf(r.group)
                return Theme.HexColor("textDim", prof == "custom" and PCD.FamilyName("custom") or (ns.Crafts.ProfName(prof) or prof)) end,
              sort = function(r) return PCD.ProfOf(r.group) end },
            { key = "left", title = L.PCD_STATUS, width = 120, align = "RIGHT", text = function(r) return PCD.FormatLeft(r.left) end,
              sort = function(r) return r.left end },
            { key = "seen", title = L.PCD_UPDATED, width = 120, align = "RIGHT", text = function(r)
                return Theme.HexColor("muted", ns.Ago(r.t)) end, sort = function(r) return -(r.t or 0) end },
        },
    })
    list:SetPoint("TOPLEFT", 0, -60)
    list:SetPoint("BOTTOMRIGHT")
    list:SetEmptyText(L.PCD_EMPTY)

    function tab.Refresh()
        filter:Refresh()
        list:SetRows(PCD.Rows(state.filter))
    end
    ns.On("LG_PROFCD", function() if tab:IsVisible() then tab.Refresh() end end)
    ns.On("LG_PROFCD_TICK", function() if tab:IsVisible() then tab.Refresh() end end)
    return tab
end
