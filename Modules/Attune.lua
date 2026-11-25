-- Attunements and dungeon keys: who may enter which raid, who carries which key.
-- Each member reads their own status (a handful of quest/item checks, only when
-- quests are turned in or bags change) and shares it with the profile – no
-- timers, no scanning of other players.
local _, ns = ...
local UI, Theme, L, Names = ns.UI, ns.Theme, ns.L, ns.Names
local Attune = ns.NewModule("attune")
ns.Attune = Attune

-- kind "attune": raid access; kind "key": dungeon key / item
-- quests: any of them completed counts; items: any of them owned (bags, bank, keyring)
Attune.LIST = {
    { key = "mc", kind = "attune", short = "MC", name = "Molten Core", quests = { 7848 },
      how = "Quest “Attunement to the Core” (Blackrock Depths)" },
    { key = "ony", kind = "attune", short = "Ony", name = "Onyxia's Lair", quests = { 6502, 6602 }, items = { 16309 },
      how = "Drakefire Amulet (quest chain)" },
    { key = "bwl", kind = "attune", short = "BWL", name = "Blackwing Lair", quests = { 7761 },
      how = "Quest “Blackhand's Command” (UBRS)" },
    { key = "naxx", kind = "attune", short = "Naxx", name = "Naxxramas", quests = { 9121, 9122, 9123 },
      how = "Quest “The Dread Citadel – Naxxramas” (Light's Hope)" },
    { key = "ubrs", kind = "key", short = "UBRS", name = "Seal of Ascension", items = { 12344 } },
    { key = "scholo", kind = "key", short = "Scholo", name = "Skeleton Key", items = { 13704 } },
    { key = "strat", kind = "key", short = "Strat", name = "Key to the City", items = { 12382 } },
    { key = "dm", kind = "key", short = "DM", name = "Crescent Key", items = { 18249 } },
    { key = "brd", kind = "key", short = "BRD", name = "Shadowforge Key", items = { 11000 } },
    { key = "gnomer", kind = "key", short = "Gnome", name = "Workshop Key", items = { 6893 } },
    { key = "sm", kind = "key", short = "SM", name = "Scarlet Key", items = { 7146 } },
    { key = "zf", kind = "key", short = "ZF", name = "Mallet of Zul'Farrak", items = { 9240 } },
    { key = "quint", kind = "key", short = "Quint", name = "Quintessence (MC runes)", items = { 17333, 22754 } },
}
Attune.BY_KEY = {}
for _, e in ipairs(Attune.LIST) do Attune.BY_KEY[e.key] = e end

local function questDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return ns.Call(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false end
    if IsQuestFlaggedCompleted then return ns.Call(IsQuestFlaggedCompleted, id) and true or false end
    return false
end

local function owned(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return false end
    local n = ns.Call(fn, id, true)
    return ns.Num(n) and n > 0 or false
end

-- own status as a short string: keys that are done, e.g. "mc,ony,ubrs"
function Attune.ReadOwn()
    local done = {}
    for _, e in ipairs(Attune.LIST) do
        local ok = false
        for _, q in ipairs(e.quests or {}) do if questDone(q) then ok = true; break end end
        if not ok then for _, i in ipairs(e.items or {}) do if owned(i) then ok = true; break end end end
        if ok then done[#done + 1] = e.key end
    end
    return table.concat(done, ",")
end

-- /lg test attune: what the addon reads for you right now (nothing is sent)
function Attune.Test()
    local done = Attune.Parse(Attune.ReadOwn()) or {}
    local have, miss = {}, {}
    for _, e in ipairs(Attune.LIST) do
        local t = e.short or e.key
        if done[e.key] then have[#have + 1] = t else miss[#miss + 1] = t end
    end
    ns.Print(ns.L.TEST_TAG .. " " .. ns.L.ATT_TEST:format(#have > 0 and table.concat(have, ", ") or "–",
        #miss > 0 and table.concat(miss, ", ") or "–"))
    ns.Window.Show("attune")
end

function Attune.Parse(text)
    if type(text) ~= "string" then return nil end
    local set = {}
    for k in text:gmatch("[^,]+") do set[k] = true end
    return set
end

-- re-read only when something relevant happened; the profile sends it on if it changed
local function changed() ns.Debounce("attune-read", 5, function() if ns.Profile then ns.Profile.Update(false) end end) end
ns.On("QUEST_TURNED_IN", changed)
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("attune-bags", 30, changed) end)

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local state = { filter = "all", show = "both", search = "" }
Attune.state = state

local function columnsFor()
    local list = {}
    for _, e in ipairs(Attune.LIST) do
        if state.show == "both" or state.show == e.kind then list[#list + 1] = e end
    end
    return list
end

function Attune.Rows()
    local rows = {}
    local search = state.search:lower()
    for key, g in pairs(ns.Guild.members) do
        local m = ns.Database.Member(key) or {}
        local keep = true
        if state.filter == "online" and not g.online then keep = false end
        if state.filter == "max" and (g.level or 0) < 60 then keep = false end
        if keep then
            rows[#rows + 1] = { key = key, name = g.name, class = g.class or m.c, level = g.level or m.l, online = g.online,
                at = Attune.Parse(m.at), main = m.m }
        end
    end
    return rows
end

local function cell(e)
    return function(r)
        if not r.at then return Theme.HexColor("muted", "?") end
        if r.at[e.key] then return UI.Glyph("badge-check", "good", 13) end
        return UI.Glyph("x", e.kind == "attune" and "bad" or "muted", 11)
    end
end

UI.AddPage("attune", L.PAGE_ATTUNE, 45, function(content, page)
    local list
    -- the name search sits in the page header
    page.searchHint = L.ATT_SEARCH
    page.Search = function(text)
        state.search = text or ""
        page.OnShow()
        return list and list:ShowFirstHit(state.search) or 0
    end
    local filter = UI.Segmented(content, 260, { { value = "all", text = L.ATT_ALL }, { value = "online", text = L.ONLINE },
        { value = "max", text = L.ATT_MAX } }, function() return state.filter end, function(v) state.filter = v; page.OnShow() end)
    filter:SetPoint("TOPLEFT", 0, 0)
    local show = UI.Segmented(content, 300, { { value = "both", text = L.ATT_BOTH }, { value = "attune", text = L.ATT_ATTUNES },
        { value = "key", text = L.ATT_KEYS } }, function() return state.show end, function(v) state.show = v; page.Rebuild() end)
    show:SetPoint("LEFT", filter, "RIGHT", 12, 0)
    local summary = UI.Text(content, 11, "textDim")
    summary:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 2, -10)
    summary:SetPoint("RIGHT", content, "RIGHT")
    summary:SetHeight(14)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    -- narrow page: both switches get slimmer, then the second one moves into its own row
    local listTop = -64
    local function fitTop()
        local w = content:GetWidth() or 900
        local room = w - ns.Window.SearchReserve()
        filter:ClearAllPoints(); show:ClearAllPoints(); summary:ClearAllPoints()
        filter:SetPoint("TOPLEFT", 0, 0)
        if room >= 260 + 12 + 300 then
            filter:SetWidth(260); show:SetWidth(300)
            show:SetPoint("LEFT", filter, "RIGHT", 12, 0)
            summary:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 2, -10)
            listTop = -64
        elseif room >= 220 + 10 + 250 then
            filter:SetWidth(220); show:SetWidth(250)
            show:SetPoint("LEFT", filter, "RIGHT", 10, 0)
            summary:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 2, -10)
            listTop = -64
        else
            filter:SetWidth(math.min(260, room)); show:SetWidth(math.min(300, w))
            show:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 0, -6)
            summary:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 2, -10)
            listTop = -94
        end
        summary:SetPoint("RIGHT", content, "RIGHT")
        if filter.Layout then filter:Layout() end
        if show.Layout then show:Layout() end
        if list then list:ClearAllPoints(); list:SetPoint("TOPLEFT", 0, listTop); list:SetPoint("BOTTOMRIGHT", 0, 34) end
    end
    content:HookScript("OnSizeChanged", fitTop)

    function page.Rebuild()
        if list then list:Hide() end
        local cols = {
            { key = "name", title = L.COL_NAME, flex = 1, minWidth = 120,
              text = function(r)
                  local dot = r.online and UI.Glyph("dot", "good", 9) .. " " or ""
                  local alt = r.main and not Names.Same(r.main, r.key) and Theme.HexColor("muted", " (" .. L.ALT .. ")") or ""
                  return dot .. ns.ColorName(r.name, r.class) .. alt
              end, sort = function(r) return r.key end },
            { key = "level", title = L.COL_LEVEL, width = 40, align = "CENTER", text = function(r) return tostring(r.level or "") end,
              sort = function(r) return r.level or 0 end, defaultDesc = true },
        }
        for i, e in ipairs(columnsFor()) do
            cols[#cols + 1] = { key = e.key, title = e.short, width = 54, align = "CENTER", text = cell(e), optional = 100 - i,
                sort = function(r) return r.at and (r.at[e.key] and 2 or 1) or 0 end, defaultDesc = true }
        end
        list = UI.List(content, {
            sortKey = "level", sortDesc = true, columns = cols,
            onClick = function(row, button)
                if button == "RightButton" and ChatFrame_SendTell then ChatFrame_SendTell(row.name) end
            end,
            onEnter = function(frame, row)
                ns.TipOwner(frame, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.ColorName(row.name, row.class))
                if not row.at then
                    GameTooltip:AddLine(L.ATT_NO_ADDON, 0.6, 0.6, 0.6, true)
                else
                    for _, e in ipairs(Attune.LIST) do
                        local ok = row.at[e.key]
                        GameTooltip:AddDoubleLine(e.name, ok and L.ATT_YES or L.ATT_NO, 0.8, 0.8, 0.8,
                            ok and 0.3 or 0.6, ok and 0.85 or 0.6, ok and 0.4 or 0.6)
                    end
                end
                GameTooltip:Show()
            end,
        })
        list.page = "attune"
        fitTop()
        list:SetPoint("TOPLEFT", 0, listTop)
        list:SetPoint("BOTTOMRIGHT", 0, 34)
        list:SetEmptyText(L.ROSTER_EMPTY)
        page.OnShow()
    end

    local legend = UI.Text(content, 10, "muted")
    legend:SetPoint("BOTTOMLEFT", 2, 2)
    legend:SetPoint("BOTTOMRIGHT")
    legend:SetHeight(28)
    legend:SetJustifyH("LEFT")
    legend:SetJustifyV("BOTTOM")
    legend:SetWordWrap(true)
    local parts = {}
    for _, e in ipairs(Attune.LIST) do parts[#parts + 1] = e.short .. " = " .. e.name end
    legend:SetText(table.concat(parts, "  ·  "))

    page.OnShow = function()
        if not list then return end
        filter:Refresh(); show:Refresh()
        local rows = Attune.Rows()
        list:SetRows(rows)
        -- per column: how many of those with the addon have it
        local known, counts = 0, {}
        for _, r in ipairs(rows) do
            if r.at then
                known = known + 1
                for k in pairs(r.at) do counts[k] = (counts[k] or 0) + 1 end
            end
        end
        local sum = {}
        for _, e in ipairs(columnsFor()) do
            sum[#sum + 1] = ("%s %s"):format(Theme.HexColor("text", e.short), Theme.HexColor("accent", (counts[e.key] or 0) .. "/" .. known))
        end
        summary:SetText(L.ATT_SUMMARY:format(known, #rows) .. "   " .. table.concat(sum, "  ·  "))
    end
    page.Rebuild()
end, { section = "raid", icon = "shield" })

ns.On("LG_PROFILE", function() ns.Debounce("attune-redraw", 1, function() ns.Window.Refresh("attune") end) end)
