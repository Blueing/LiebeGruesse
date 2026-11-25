-- "Guild crafting" tab of the professions page: professions on the left,
-- recipes (expandable: materials and every crafter) or members on the right.
local _, ns = ...
local UI, Theme, L, Items = ns.UI, ns.Theme, ns.L, ns.Items
local Crafts = ns.Crafts
local Page = {}
ns.CraftsPage = Page

local FAV = "__fav"
local ICON_PATH = "Interface\\AddOns\\LiebeGruesse\\Media\\Icons\\"

local state = { prof = nil, mode = "recipes", search = "", onlineOnly = false, expanded = {}, member = nil }
Page.state = state

local function glyph(name, role, size) return UI.Glyph(name, role, size) end

local function matches(text, query)
    return query == "" or (text or ""):lower():find(query, 1, true) ~= nil
end

local function anyOnline(list)
    for _, key in ipairs(list) do if Crafts.Online(key) then return true end end
    return false
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function crafterSummary(list)
    if #list == 0 then return Theme.HexColor("muted", "–") end
    local parts = {}
    for i = 1, math.min(2, #list) do parts[i] = Crafts.ColoredMember(list[i], true) end
    local text = table.concat(parts, Theme.HexColor("muted", ", "))
    if #list > 2 then text = text .. Theme.HexColor("muted", "  " .. L.CRAFT_MORE:format(#list - 2)) end
    return text
end

local function memberSkill(prof, key)
    local idx = Crafts.Index()
    local p = idx.profs[prof]
    local m = p and p.members[key]
    if not m then return "" end
    local text = m.m and ("%d/%d"):format(m.s or 0, m.m) or tostring(m.s or "?")
    if m.x then text = text .. Theme.HexColor("muted", "  " .. m.x) end
    return text
end

local function view()
    local st = ns.Database.Settings()
    st.craftView = st.craftView or {}
    local v = st.craftView
    if v.mats == nil then v.mats = true end
    if v.crafters == nil then v.crafters = true end
    if v.cost == nil then v.cost = true end
    return v
end
Page.View = view

local function isOpen(key)
    local e = state.expanded[key]
    if e ~= nil then return e end
    return state.expandAll or false
end

-- Adds a recipe row plus, when expanded, its materials and crafters
local function addRecipe(rows, id, prefix)
    local crafters = Crafts.Crafters(id)
    if state.onlineOnly and not anyOnline(crafters) then return end
    local key = (prefix or "") .. id
    local v = view()
    local open = isOpen(key) and (v.mats or v.crafters)
    rows[#rows + 1] = { kind = "recipe", key = key, id = id, crafters = crafters, open = open }
    if not open then return end
    local meta = Crafts.Meta(id)
    local reagents = {}
    for item, qty in pairs(meta and meta.r or {}) do reagents[#reagents + 1] = { item = item, qty = qty } end
    table.sort(reagents, function(a, b) return a.item < b.item end)
    if v.mats then
        if #reagents == 0 then
            rows[#rows + 1] = { kind = "note", key = key .. ":n", id = id, text = L.CRAFT_NO_REAGENTS }
        end
        for _, r in ipairs(reagents) do
            rows[#rows + 1] = { kind = "reagent", key = key .. ":r" .. r.item, id = id, item = r.item, qty = r.qty }
        end
    end
    local prof = Crafts.RecipeProf(id)
    for _, c in ipairs(crafters) do
        if v.crafters and (not state.onlineOnly or Crafts.Online(c)) then
            rows[#rows + 1] = { kind = "crafter", key = key .. ":c" .. c, id = id, member = c, prof = prof }
        end
    end
end

local function sortedIds(ids)
    local list = {}
    for id in pairs(ids) do list[#list + 1] = { id = id, name = Crafts.Name(id):lower() } end
    table.sort(list, function(a, b) if a.name == b.name then return a.id < b.id end return a.name < b.name end)
    return list
end

-- grouped by profession with header rows
local function groupedRows(ids)
    local byProf = {}
    for id in pairs(ids) do
        local p = Crafts.RecipeProf(id) or "?"
        byProf[p] = byProf[p] or {}
        byProf[p][id] = true
    end
    local profs = {}
    for p in pairs(byProf) do profs[#profs + 1] = p end
    table.sort(profs, function(a, b)
        local ia, ib = Crafts.ProfInfo(a), Crafts.ProfInfo(b)
        return (ia and ia.order or 99) < (ib and ib.order or 99)
    end)
    local rows = {}
    for _, p in ipairs(profs) do
        local start = #rows + 1
        rows[#rows + 1] = { kind = "head", key = "h:" .. p, prof = p }
        for _, e in ipairs(sortedIds(byProf[p])) do addRecipe(rows, e.id) end
        if #rows == start then rows[start] = nil end
    end
    return rows
end

local function recipeRowsFor(prof, query)
    local idx = Crafts.Index()
    if query ~= "" or prof == FAV then
        local ids = {}
        if query ~= "" then
            for _, h in ipairs(Crafts.Search(query)) do ids[h.id] = true end
        else
            for id in pairs(Crafts.Favs("recipes")) do if idx.recipes[id] then ids[id] = true end end
        end
        return groupedRows(ids)
    end
    local p = idx.profs[prof]
    local rows = {}
    if not p then return rows end
    for _, e in ipairs(sortedIds(p.recipes)) do addRecipe(rows, e.id) end
    return rows
end

local function memberRecipes(prof, key)
    local p = Crafts.Index().profs[prof]
    local m = p and p.members[key]
    local rows = {}
    if not (m and m.ids) then return rows end
    local ids = {}
    for raw in m.ids:gmatch("%d+") do ids[tonumber(raw)] = true end
    local saved = state.onlineOnly
    state.onlineOnly = false
    for _, e in ipairs(sortedIds(ids)) do addRecipe(rows, e.id, "m:") end
    state.onlineOnly = saved
    return rows
end

---------------------------------------------------------------------------
-- Columns of the recipe tree
---------------------------------------------------------------------------
local function whisperMenu(row, anchor)
    local list = row.member and { row.member } or row.crafters or {}
    if #list == 0 then return end
    if #list == 1 then Crafts.Whisper(list[1], row.id); return end
    local items = {}
    for _, key in ipairs(list) do
        items[#items + 1] = { value = key, text = Crafts.ColoredMember(key, true) }
    end
    UI.OpenMenu(anchor, items, function(key) Crafts.Whisper(key, row.id) end, 220)
end

local function treeColumns(refresh, compact)
    return {
        { key = "fav", width = 26, align = "CENTER",
          text = function(row)
              if row.kind ~= "recipe" then return "" end
              local on = Crafts.IsFav("recipes", row.id)
              return glyph(on and "star-filled" or "star", on and "gold" or "borderDim", 13)
          end,
          onClick = function(row) if row.kind == "recipe" then Crafts.ToggleFav("recipes", row.id); refresh() end end,
          tip = function(row) if row.kind == "recipe" then return L.CRAFT_FAV_TIP end end },
        { key = "name", flex = true,
          icon = function(row)
              if row.kind == "recipe" then return Crafts.Icon(row.id) end
              if row.kind == "reagent" then return Items.Icon(row.item) end
              if row.kind == "head" then local p = Crafts.ProfInfo(row.prof); return p and p.icon end
          end,
          text = function(row)
              if row.kind == "head" then return Theme.HexColor("gold", Crafts.ProfName(row.prof)) end
              if row.kind == "recipe" then
                  return Theme.HexColor("muted", row.open and "–  " or "+  ") .. Crafts.ColoredName(row.id)
              end
              if row.kind == "reagent" then
                  local info = Items.Info(row.item)
                  local have = ns.Call(GetItemCount, row.item, true) or 0
                  return ("     %s %s%s"):format(Theme.HexColor("text", row.qty .. "×"),
                      info and info.link or ("item " .. row.item),
                      have > 0 and Theme.HexColor("muted", "  (" .. L.CRAFT_HAVE:format(have) .. ")") or "")
              end
              if row.kind == "crafter" then
                  return "     " .. Crafts.ColoredMember(row.member, true) .. "   " .. Theme.HexColor("textDim", memberSkill(row.prof, row.member))
              end
              if row.kind == "note" then return "     " .. Theme.HexColor("muted", row.text) end
              return ""
          end },
        { key = "crafters", width = compact and 110 or 230, align = compact and "RIGHT" or "LEFT",
          text = function(row)
              if row.kind ~= "recipe" then return "" end
              if compact then return Theme.HexColor("muted", L.CRAFT_N_CRAFTERS:format(#row.crafters)) end
              return crafterSummary(row.crafters)
          end,
          -- hover: every crafter right here; click: whisper (one crafter) or pick from the list below the cell
          tip = function(row)
              if row.kind ~= "recipe" or #row.crafters == 0 then return end
              local lines = {}
              local prof = Crafts.RecipeProf(row.id)
              for _, key in ipairs(row.crafters) do
                  lines[#lines + 1] = Crafts.ColoredMember(key, true) .. "   " .. Theme.HexColor("muted", prof and memberSkill(prof, key) or "")
              end
              lines[#lines + 1] = " "
              lines[#lines + 1] = Theme.HexColor("muted", #row.crafters == 1 and L.CRAFT_CLICK_WHISPER or L.CRAFT_CLICK_PICK)
              return L.CRAFT_CRAFTERS_TIP:format(#row.crafters), lines
          end,
          onClick = function(row, _, cell) if row.kind == "recipe" then whisperMenu(row, cell) end end },
        { key = "cost", width = 96, align = "RIGHT",
          text = function(row)
              if not view().cost then return "" end
              local P = ns.Professions
              if row.kind == "recipe" then
                  local meta = Crafts.Meta(row.id)
                  if not meta or not meta.r then return "" end
                  local total, missing = P.ReagentCost(meta.r)
                  if total == 0 and missing > 0 then return Theme.HexColor("muted", "?") end
                  return (missing > 0 and Theme.HexColor("muted", "~") or "") .. P.Money(total)
              elseif row.kind == "reagent" then
                  local price = P.Price(row.item)
                  return price and Theme.HexColor("muted", P.Money(price * row.qty)) or Theme.HexColor("muted", "?")
              end
              return ""
          end,
          tip = function(row)
              if row.kind ~= "recipe" then return end
              local meta = Crafts.Meta(row.id)
              local P = ns.Professions
              local lines = {}
              for item, qty in pairs(meta and meta.r or {}) do
                  local info = Items.Info(item)
                  local price = P.Price(item)
                  lines[#lines + 1] = ("%dx %s: %s"):format(qty, info and info.name or ("item " .. item), price and P.Money(price * qty) or "?")
              end
              local out = meta and meta.o and P.Price(meta.o)
              if out then lines[#lines + 1] = L.CRAFT_VALUE:format(P.Money(out * (meta.y or 1))) end
              local _, _, src = P.Price(next(meta and meta.r or {}) or 0)
              if src then lines[#lines + 1] = L.CRAFT_PRICE_FROM:format(L["PRICE_SRC_" .. src] or src) end
              return L.CRAFT_COST, lines
          end,
          onClick = function(row, button) if Page.click then Page.click(row, button) end end },
        { key = "whisper", width = 30, align = "CENTER",
          text = function(row)
              if row.kind == "recipe" or row.kind == "crafter" then return glyph("message-circle", "textDim", 13) end
              return ""
          end,
          onClick = function(row, _, cell) if row.kind == "recipe" or row.kind == "crafter" then whisperMenu(row, cell) end end,
          tip = function(row)
              if row.kind == "recipe" then return L.CRAFT_WHISPER, { L.CRAFT_WHISPER_TIP } end
              if row.kind == "crafter" then return L.CRAFT_WHISPER end
          end },
        { key = "post", width = 30, align = "CENTER",
          text = function(row) return row.kind == "recipe" and glyph("megaphone", "textDim", 13) or "" end,
          onClick = function(row) if row.kind == "recipe" then Crafts.PostToGuild(row.id) end end,
          tip = function(row) if row.kind == "recipe" then return L.CRAFT_POST, { L.CRAFT_POST_TIP } end end },
    }
end

local function recipeTooltip(frame, row)
    ns.TipOwner(frame, "ANCHOR_RIGHT")
    if row.kind == "reagent" then
        GameTooltip:SetHyperlink("item:" .. row.item)
    elseif row.kind == "recipe" then
        local meta = Crafts.Meta(row.id)
        local ok = meta and meta.o and pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. meta.o)
        if not ok and not pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. row.id) then
            GameTooltip:SetText(Crafts.Name(row.id))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.CRAFT_ROW_TIP, 0.6, 0.6, 0.6, true)
    elseif row.kind == "crafter" then
        GameTooltip:SetText((Crafts.DisplayName(row.member)))
        GameTooltip:AddLine(L.CRAFT_CLICK_WHISPER, 0.6, 0.6, 0.6)
    else
        GameTooltip:Hide()
        return
    end
    GameTooltip:Show()
end

local function treeClick(refresh)
    return function(row, button, frame)
        if row.kind == "recipe" then
            if IsShiftKeyDown and IsShiftKeyDown() then Crafts.InsertLink(row.id); return end
            if button == "RightButton" then
                -- the list opens right below the crafters, not at the row's left edge
                local anchor = frame and frame.cells and frame.cells[3] or frame
                whisperMenu(row, anchor)
                return
            end
            state.expanded[row.key] = not isOpen(row.key)
            refresh()
        elseif row.kind == "crafter" then
            Crafts.Whisper(row.member, row.id)
        elseif row.kind == "reagent" and IsShiftKeyDown and IsShiftKeyDown() then
            local info = Items.Info(row.item)
            if info and info.link and ChatEdit_InsertLink then ChatEdit_InsertLink(info.link) end
        end
    end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Page.Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    local refresh = function() f.Refresh() end
    Page.click = function(row, button) treeClick(refresh)(row, button) end

    -- top bar
    -- the search sits in the page header (Professions page); /lg craft fills it
    Page.Search = function(text)
        state.mode = "recipes"
        if ns.Window.SetPageSearch and ns.Window.IsShown("professions") then
            ns.Window.SetPageSearch(text or "")
        else
            f.Filter(text)
        end
    end
    local mode = UI.Segmented(f, 210, { { value = "recipes", text = L.RECIPES }, { value = "members", text = L.CRAFT_MEMBERS } },
        function() return state.mode end, function(v) state.mode = v; f.Refresh() end)
    mode:SetPoint("TOPLEFT", 0, -1)
    local onlineCheck = UI.Check(f, L.CRAFT_ONLINE_ONLY, function() return state.onlineOnly end,
        function(v) state.onlineOnly = v; f.Refresh() end, L.CRAFT_ONLINE_ONLY_TIP)
    onlineCheck:SetPoint("LEFT", mode, "RIGHT", 14, 0)
    local stats = UI.Text(f, 11, "muted", "RIGHT")
    stats:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -7)
    stats:SetPoint("LEFT", onlineCheck, "RIGHT", 10, 0)

    -- view toggles (second row)
    local viewBar = CreateFrame("Frame", nil, f)
    viewBar:SetPoint("TOPLEFT", 0, -34)
    viewBar:SetPoint("TOPRIGHT", 0, -34)
    viewBar:SetHeight(22)
    local showLabel = UI.Text(viewBar, 11, "muted")
    showLabel:SetPoint("LEFT", 2, 0)
    showLabel:SetText(L.CRAFT_SHOW)
    local x = (showLabel:GetStringWidth() or 50) + 14
    local checks = {}
    for _, def in ipairs({ { "mats", L.CRAFT_SHOW_MATS }, { "crafters", L.CRAFT_SHOW_CRAFTERS }, { "cost", L.CRAFT_SHOW_COST } }) do
        local c = UI.Check(viewBar, def[2], function() return view()[def[1]] end,
            function(v) view()[def[1]] = v; f.Refresh() end)
        c:SetPoint("LEFT", x, 0)
        x = x + c:GetWidth() + 18
        checks[#checks + 1] = c
    end
    local expandAll = UI.Button(viewBar, "", 150, 22, function()
        state.expandAll = not state.expandAll
        wipe(state.expanded)
        f.Refresh()
    end)
    expandAll:SetPoint("LEFT", x + 6, 0)

    -- professions
    local profList = UI.List(f, {
        noHeader = true, rowHeight = 28,
        columns = {
            { key = "name", flex = true, icon = function(r) return r.icon end, noHighlight = true,
              text = function(r) return r.key == FAV and Theme.HexColor("gold", r.name) or r.name end },
            { key = "count", width = 44, align = "RIGHT", noHighlight = true, text = function(r) return Theme.HexColor("muted", r.countText or "") end },
        },
        onClick = function(row) state.prof = row.key; state.member = nil; f.Refresh() end,
        isSelected = function(row) return row.key == state.prof end,
        onEnter = function(frame, row)
            if row.tip then UI.Tooltip(frame, row.name, { row.tip }) end
        end,
    })
    profList:SetPoint("TOPLEFT", 0, -66)
    profList:SetPoint("BOTTOMLEFT")
    profList:SetWidth(220)
    profList:SetEmptyText(L.NO_PROFESSIONS)

    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", profList, "TOPRIGHT", 14, 0)
    right:SetPoint("BOTTOMRIGHT")

    -- recipes mode
    local recipes = CreateFrame("Frame", nil, right)
    recipes:SetAllPoints()
    local title = UI.Text(recipes, 15, "gold")
    title:SetPoint("TOPLEFT", 4, -4)
    local sub = UI.Text(recipes, 11, "muted", "RIGHT")
    sub:SetPoint("TOPRIGHT", recipes, "TOPRIGHT", -4, -7)
    local tree = UI.List(recipes, {
        noHeader = true, rowHeight = 24, columns = treeColumns(refresh), keepEmptyText = true,
        onClick = treeClick(refresh), onEnter = recipeTooltip,
    })
    tree:SetPoint("TOPLEFT", 0, -30)
    tree:SetPoint("BOTTOMRIGHT")

    -- members mode
    local members = CreateFrame("Frame", nil, right)
    members:SetAllPoints()
    local memberList = UI.List(members, {
        noHeader = true, rowHeight = 26,
        columns = {
            { key = "fav", width = 24, align = "CENTER",
              text = function(r)
                  local on = Crafts.IsFav("members", r.member)
                  return glyph(on and "star-filled" or "star", on and "gold" or "borderDim", 12)
              end,
              onClick = function(r) Crafts.ToggleFav("members", r.member); f.Refresh() end,
              tip = function() return L.CRAFT_FAV_MEMBER_TIP end },
            { key = "name", flex = true, text = function(r) return Crafts.ColoredMember(r.member, true) end },
            { key = "skill", width = 92, align = "RIGHT", text = function(r) return r.skillText end },
        },
        onClick = function(r, button)
            if button == "RightButton" then Crafts.Whisper(r.member); return end
            state.member = r.key; f.Refresh()
        end,
        isSelected = function(r) return r.key == state.member end,
        onEnter = function(frame, r)
            local lines = {}
            if r.spec then lines[#lines + 1] = r.spec end
            lines[#lines + 1] = L.CRAFT_MEMBER_TIP
            UI.Tooltip(frame, Crafts.DisplayName(r.member), lines)
        end,
    })
    memberList:SetPoint("TOPLEFT")
    memberList:SetPoint("BOTTOMLEFT")
    memberList:SetWidth(250)
    local detail = CreateFrame("Frame", nil, members)
    detail:SetPoint("TOPLEFT", memberList, "TOPRIGHT", 14, 0)
    detail:SetPoint("BOTTOMRIGHT")
    local dTitle = UI.Text(detail, 15, "gold")
    dTitle:SetPoint("TOPLEFT", 4, -4)
    dTitle:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -4, -4)
    local dSub = UI.Text(detail, 11, "muted")
    dSub:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -4)
    dSub:SetPoint("TOPRIGHT", dTitle, "BOTTOMRIGHT", 0, -4)
    local dTree = UI.List(detail, {
        noHeader = true, rowHeight = 24, columns = treeColumns(refresh, true),
        onClick = treeClick(refresh), onEnter = recipeTooltip,
    })
    dTree:SetPoint("TOPLEFT", 0, -46)
    dTree:SetPoint("BOTTOMRIGHT")
    local dEmpty = UI.Text(detail, 12, "muted", "CENTER")
    dEmpty:SetPoint("TOP", 0, -60)
    dEmpty:SetWidth(320)
    dEmpty:SetWordWrap(true)

    -- page search: hits per profession (recipe names; in "Members" the crafter names)
    local function hitsByProf(idx)
        local out, q = {}, state.search
        if q == "" then return out end
        if state.mode == "members" then
            for prof, p in pairs(idx.profs) do
                local n = 0
                for key in pairs(p.members) do if ns.SearchAny(Crafts.DisplayName(key), q) then n = n + 1 end end
                out[prof] = n
            end
            return out
        end
        for _, h in ipairs(Crafts.Search(q)) do
            for prof, p in pairs(idx.profs) do
                if p.recipes[h.id] then out[prof] = (out[prof] or 0) + 1 end
            end
        end
        return out
    end
    f.hitsByProf = hitsByProf

    local function profRows(idx)
        local rows = {}
        local favCount = 0
        for _ in pairs(Crafts.Favs("recipes")) do favCount = favCount + 1 end
        local favMembers = 0
        for _ in pairs(Crafts.Favs("members")) do favMembers = favMembers + 1 end
        rows[1] = { key = FAV, name = L.CRAFT_FAVORITES, icon = ICON_PATH .. "star-filled.tga",
            countText = tostring(state.mode == "members" and favMembers or favCount), order = 0, tip = L.CRAFT_FAV_LIST_TIP }
        local list = {}
        for key, p in pairs(idx.profs) do
            local info = Crafts.ProfInfo(key)
            list[#list + 1] = { key = key, name = Crafts.ProfName(key), icon = info and info.icon or 134400,
                order = (info and info.order or 50) + (info and info.gather and 100 or 0),
                countText = state.mode == "members" and tostring(p.count) or (p.recipeCount > 0 and tostring(p.recipeCount) or tostring(p.count)),
                tip = L.CRAFT_PROF_TIP:format(p.count, p.recipeCount) }
        end
        table.sort(list, function(a, b) return a.order < b.order end)
        for _, r in ipairs(list) do rows[#rows + 1] = r end
        return rows
    end

    local function refreshRecipes(idx)
        -- a search lists the hits of every profession, grouped by profession (as before 1.0.58)
        local rows = recipeRowsFor(state.prof, state.search)
        tree:SetRows(rows)
        local count = 0
        for _, r in ipairs(rows) do if r.kind == "recipe" then count = count + 1 end end
        if state.search ~= "" then
            title:SetText(L.CRAFT_SEARCH_TITLE:format(state.search))
        elseif state.prof == FAV then
            title:SetText(L.CRAFT_FAVORITES)
        else
            title:SetText(Crafts.ProfName(state.prof))
        end
        sub:SetText(L.CRAFT_COUNT:format(count))
        if state.search ~= "" then tree:SetEmptyText(L.CRAFT_NOTHING_FOUND:format(ns.Database.Settings().craft.prefix or "!lg"))
        elseif state.prof == FAV then tree:SetEmptyText(L.CRAFT_NO_FAVS)
        elseif Crafts.ProfInfo(state.prof) and Crafts.ProfInfo(state.prof).gather then tree:SetEmptyText(L.CRAFT_GATHER_ONLY)
        else tree:SetEmptyText(L.CRAFT_NO_RECIPES_PROF) end
    end

    local function refreshMembers(idx)
        local rows = {}
        local favs = Crafts.Favs("members")
        local function add(prof, key, m)
            if state.onlineOnly and not Crafts.Online(key) then return end
            if state.search ~= "" and not matches(Crafts.DisplayName(key), state.search) then return end
            local skill = m.m and ("%d/%d"):format(m.s or 0, m.m) or tostring(m.s or "?")
            rows[#rows + 1] = { key = prof .. "|" .. key, prof = prof, member = key, skill = m.s or 0, spec = m.x,
                skillText = Theme.HexColor("textDim", skill), sortName = Crafts.DisplayName(key):lower() }
        end
        for prof, p in pairs(idx.profs) do
            if state.search ~= "" or state.prof == FAV or prof == state.prof then
                for key, m in pairs(p.members) do
                    if state.prof ~= FAV or favs[key] then add(prof, key, m) end
                end
            end
        end
        local multi = state.search ~= "" or state.prof == FAV
        for _, r in ipairs(rows) do
            if multi then r.skillText = Theme.HexColor("muted", Crafts.ProfName(r.prof):sub(1, 10) .. " ") .. r.skillText end
        end
        table.sort(rows, function(a, b)
            local oa, ob = Crafts.Online(a.member) and 1 or 0, Crafts.Online(b.member) and 1 or 0
            if a.skill ~= b.skill and not multi then return a.skill > b.skill end
            if oa ~= ob then return oa > ob end
            if a.sortName ~= b.sortName then return a.sortName < b.sortName end
            return a.prof < b.prof
        end)
        memberList:SetRows(rows)
        memberList:SetEmptyText(state.prof == FAV and L.CRAFT_NO_FAV_MEMBERS or L.CRAFT_NO_MEMBERS)
        local sel
        for _, r in ipairs(rows) do if r.key == state.member then sel = r end end
        if not sel then sel = rows[1]; state.member = sel and sel.key end
        dTree:SetShown(sel ~= nil)
        dTitle:SetShown(sel ~= nil)
        dSub:SetShown(sel ~= nil)
        if not sel then dEmpty:SetText(L.CRAFT_PICK_MEMBER); dEmpty:Show(); return end
        local p = idx.profs[sel.prof]
        local m = p.members[sel.member]
        dTitle:SetText(("%s  %s  %s"):format(Crafts.ColoredMember(sel.member), Theme.HexColor("muted", "—"),
            Theme.HexColor("gold", Crafts.ProfName(sel.prof) .. " " .. (m.m and ("%d/%d"):format(m.s or 0, m.m) or tostring(m.s or "")))))
        local parts = {}
        if m.x then parts[#parts + 1] = Theme.HexColor("text", m.x) end
        parts[#parts + 1] = m.t and L.CRAFT_SCANNED:format(ns.Ago(m.t)) or L.CRAFT_NOT_SCANNED
        parts[#parts + 1] = Crafts.Online(sel.member) and Theme.HexColor("good", L.CRAFT_ONLINE) or Theme.HexColor("muted", L.CRAFT_OFFLINE)
        dSub:SetText(table.concat(parts, "  ·  "))
        local recipeRows = memberRecipes(sel.prof, sel.member)
        dTree:SetRows(recipeRows)
        local info = Crafts.ProfInfo(sel.prof)
        dEmpty:SetText(info and info.gather and L.CRAFT_GATHER_ONLY or L.CRAFT_MEMBER_NO_RECIPES)
        dEmpty:SetShown(#recipeRows == 0)
    end

    function f.Refresh()
        for _, c in ipairs(checks) do c:Refresh() end
        expandAll:SetText(state.expandAll and L.CRAFT_COLLAPSE_ALL or L.CRAFT_EXPAND_ALL)
        local idx = Crafts.Index()
        if not state.prof or (state.prof ~= FAV and not idx.profs[state.prof]) then
            local best, order
            for key in pairs(idx.profs) do
                local info = Crafts.ProfInfo(key)
                local o = info and (info.order + (info.gather and 100 or 0)) or 50
                if not order or o < order then best, order = key, o end
            end
            state.prof = best or FAV
        end
        profList:SetRows(profRows(idx))
        mode:Refresh()
        onlineCheck:Refresh()
        recipes:SetShown(state.mode == "recipes")
        members:SetShown(state.mode == "members")
        if state.mode == "recipes" then refreshRecipes(idx) else refreshMembers(idx) end
        local crafters, total, on = 0, 0, 0
        local seen = {}
        for _, p in pairs(idx.profs) do
            for key, m in pairs(p.members) do
                if m.ids and not seen[key] then seen[key] = true; crafters = crafters + 1; if Crafts.Online(key) then on = on + 1 end end
            end
        end
        for _ in pairs(idx.recipes) do total = total + 1 end
        stats:SetText(L.CRAFT_STATS:format(total, crafters, on))
    end
    -- the page search: recipes (or members) of all professions that match, grouped by profession
    function f.Filter(text)
        state.search = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        f.Refresh()
        if state.search == "" then return 0 end
        if state.mode == "members" then return #memberList.rows end
        local n = 0
        for _, r in ipairs(tree.rows) do if r.kind == "recipe" then n = n + 1 end end
        return n
    end
    return f
end

ns.On("LG_CRAFTS", function() ns.Debounce("crafts-page", 0.5, function() ns.Window.Refresh("professions") end) end)
