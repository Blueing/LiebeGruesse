-- Professions: own recipes with reagents, auction prices, profit and shopping
-- lists, plus the guild's crafters. Prices come from auction searches the
-- player runs; if PriceGraph Forever is installed its saved prices are used too.
local _, ns = ...
local Professions = ns.NewModule("professions")
ns.Professions = Professions
local UI, Theme, L, Names, Items = ns.UI, ns.Theme, ns.L, ns.Names, ns.Items

local PRICE_TTL = 7 * 86400

local function db()
    ns.db.recipes = ns.db.recipes or {}
    ns.db.prices = ns.db.prices or {}
    return ns.db
end

local function charKey() return Names.Me() or "?" end

---------------------------------------------------------------------------
-- Recipe capture (called from the profession scan in Profile.lua)
---------------------------------------------------------------------------
local function store(id, prof, name, output, yield, reagents)
    if ns.Crafts then ns.Crafts.Learn(id, prof, name, output, yield, reagents) end
    if not id or not next(reagents) then return end
    local r = db().recipes[id] or { by = {} }
    r.n, r.p, r.o, r.y, r.r, r.t = name or r.n, prof or r.p, output or r.o, yield or r.y or 1, reagents, ns.Now()
    r.by = r.by or {}
    r.by[charKey()] = true
    db().recipes[id] = r
end

function Professions.CaptureModern(id, prof, name)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return end
    local schema = ns.Call(T.GetRecipeSchematic, id, false)
    if type(schema) ~= "table" or type(schema.reagentSlotSchematics) ~= "table" then return end
    local reagents = {}
    for _, slot in ipairs(schema.reagentSlotSchematics) do
        if type(slot) == "table" and slot.required == true and type(slot.reagents) == "table" and #slot.reagents == 1 then
            local item = slot.reagents[1].itemID
            local qty = slot.quantityRequired
            if type(item) == "number" and type(qty) == "number" and qty > 0 then reagents[item] = (reagents[item] or 0) + qty end
        end
    end
    store(id, prof, name, schema.outputItemID, schema.quantityMin, reagents)
end

function Professions.CaptureClassic(id, prof, index)
    local name = ns.Call(GetTradeSkillInfo, index)
    local output = Items.ID(Items.String(ns.Call(GetTradeSkillItemLink, index)))
    local yield = ns.Call(GetTradeSkillNumMade, index)
    local reagents = {}
    for j = 1, (ns.Call(GetTradeSkillNumReagents, index) or 0) do
        local _, _, count = ns.Call(GetTradeSkillReagentInfo, index, j)
        local item = Items.ID(Items.String(ns.Call(GetTradeSkillReagentItemLink, index, j)))
        if item and count then reagents[item] = (reagents[item] or 0) + count end
    end
    store(id, prof, name, output, yield, reagents)
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
local function remember(itemID, unit)
    if type(itemID) ~= "number" or type(unit) ~= "number" or unit < 1 then return end
    local p = db().prices[itemID]
    local now = ns.Now()
    -- several results in one search: keep the cheapest
    if p and now - p.t < 60 and p.p <= unit then return end
    db().prices[itemID] = { p = math.floor(unit), t = now }
    ns.Debounce("prof-prices", 1, function() ns.Fire("LG_PRICES") end)
end

-- PriceGraph Forever keeps its latest price per item at
-- PriceGraphForeverDB.realms["<realm>-<faction>"].items[id] = { p = price, t = time }
local function priceGraph(itemID)
    local pg = type(PriceGraphForeverDB) == "table" and type(PriceGraphForeverDB.realms) == "table" and PriceGraphForeverDB.realms
    if not pg then return nil end
    local faction = ns.Call(UnitFactionGroup, "player") or ""
    local realm = (ns.Call(GetRealmName) or "") .. "-" .. faction
    local best
    for key, r in pairs(pg) do
        if (key == realm or key:sub(-#faction - 1) == "-" .. faction) and type(r) == "table" and type(r.items) == "table" then
            local it = r.items[itemID]
            if type(it) == "table" and type(it.p) == "number" and type(it.t) == "number" and (not best or it.t > best.t) then
                best = it
            end
        end
    end
    return best
end

-- External price addons (only read, never bundled)
local function tsmPrice(itemID)
    if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
    for _, source in ipairs({ "dbmarket", "dbminbuyout", "dbrecent" }) do
        local ok, v = pcall(TSM_API.GetCustomPriceValue, source, "i:" .. itemID)
        if ok and type(v) == "number" and not ns.IsSecret(v) and v > 0 then return v end
    end
end

local function auctionatorPrice(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, v = pcall(api.GetAuctionPriceByItemID, "LiebeGruesse", itemID)
    if ok and type(v) == "number" and not ns.IsSecret(v) and v > 0 then
        local age
        if api.GetAuctionAgeByItemID then
            local ok2, days = pcall(api.GetAuctionAgeByItemID, "LiebeGruesse", itemID)
            if ok2 and type(days) == "number" then age = days end
        end
        return v, age
    end
end

Professions.SOURCES = { "auto", "tsm", "auctionator", "pricegraph", "own" }
function Professions.SourceAvailable(src)
    if src == "auto" or src == "own" then return true end
    if src == "tsm" then return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil end
    if src == "auctionator" then return Auctionator ~= nil and Auctionator.API ~= nil end
    if src == "pricegraph" then return type(PriceGraphForeverDB) == "table" end
    return false
end
function Professions.HasPrices()
    for _, src in ipairs({ "tsm", "auctionator", "pricegraph" }) do if Professions.SourceAvailable(src) then return true end end
    return next(db().prices) ~= nil
end

local function ownPrice(itemID)
    local own = db().prices[itemID]
    if own and ns.Now() - own.t < PRICE_TTL then return own.p, own.t end
end
local function graphPrice(itemID)
    local g = priceGraph(itemID)
    if g and ns.Now() - g.t < PRICE_TTL then return g.p, g.t end
end

-- price (copper), time, source ("tsm" / "auctionator" / "pricegraph" / "own")
function Professions.Price(itemID)
    if not itemID then return nil end
    local want = ns.Database.Settings().priceSource or "auto"
    if want == "tsm" then local p = tsmPrice(itemID); if p then return p, ns.Now(), "tsm" end return nil end
    if want == "auctionator" then
        local p, age = auctionatorPrice(itemID)
        if p then return p, ns.Now() - (age or 0) * 86400, "auctionator" end
        return nil
    end
    if want == "pricegraph" then local p, t = graphPrice(itemID); if p then return p, t, "pricegraph" end return nil end
    if want == "own" then local p, t = ownPrice(itemID); if p then return p, t, "own" end return nil end
    -- auto: TSM, then Auctionator, then the newest of PriceGraph and own searches
    local p = tsmPrice(itemID)
    if p then return p, ns.Now(), "tsm" end
    local a, age = auctionatorPrice(itemID)
    if a then return a, ns.Now() - (age or 0) * 86400, "auctionator" end
    local gp, gt = graphPrice(itemID)
    local op, ot = ownPrice(itemID)
    if gp and (not op or gt > ot) then return gp, gt, "pricegraph" end
    if op then return op, ot, "own" end
end

-- Material cost of a recipe from its reagents { [item] = qty }: total, missing prices
function Professions.ReagentCost(reagents)
    local total, missing = 0, 0
    for item, qty in pairs(reagents or {}) do
        local p = Professions.Price(item)
        if p then total = total + p * qty else missing = missing + 1 end
    end
    return total, missing
end

function Professions.VendorPrice(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local sell = select(11, ns.Call(getInfo, itemID))
    return type(sell) == "number" and sell > 0 and sell or nil
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
    local info = C_AuctionHouse and ns.Call(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
    if type(info) == "table" then remember(itemID, info.unitPrice) end
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
    if type(itemKey) ~= "table" then return end
    local info = C_AuctionHouse and ns.Call(C_AuctionHouse.GetItemSearchResultInfo, itemKey, 1)
    if type(info) == "table" and info.buyoutAmount then remember(itemKey.itemID, info.buyoutAmount) end
end)
ns.On("AUCTION_ITEM_LIST_UPDATE", function()
    local count = ns.Call(GetNumAuctionItems, "list") or 0
    for i = 1, math.min(count, 200) do
        local _, _, stack, _, _, _, _, _, _, buyout = ns.Call(GetAuctionItemInfo, "list", i)
        local id = Items.ID(Items.String(ns.Call(GetAuctionItemLink, "list", i)))
        if id and type(buyout) == "number" and buyout > 0 and (stack or 0) > 0 then remember(id, buyout / stack) end
    end
end)

---------------------------------------------------------------------------
-- Calculations
---------------------------------------------------------------------------
function Professions.Cut() return (ns.Database.Settings().ahCut or 5) / 100 end

-- { cost, missingPrices, value, profit, buyCost, reagents = { {id, qty, have, price} } }
function Professions.Calc(recipe)
    local out = { cost = 0, buyCost = 0, missing = 0, reagents = {} }
    for item, qty in pairs(recipe.r or {}) do
        local price = Professions.Price(item)
        local have = ns.Call(GetItemCount, item, true) or 0
        out.reagents[#out.reagents + 1] = { id = item, qty = qty, have = have, price = price }
        if price then
            out.cost = out.cost + price * qty
            out.buyCost = out.buyCost + price * math.max(0, qty - have)
        else
            out.missing = out.missing + 1
        end
    end
    table.sort(out.reagents, function(a, b) return a.id < b.id end)
    local outPrice = recipe.o and Professions.Price(recipe.o)
    if outPrice then out.value = outPrice * (recipe.y or 1) * (1 - Professions.Cut()) end
    if out.value and out.missing == 0 then out.profit = out.value - out.cost end
    return out
end

function Professions.Money(copper, colored)
    if not copper then return Theme.HexColor("muted", "–") end
    local neg = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local text
    if g > 0 then text = ("%d|cffffd700g|r %02d|cffc7c7cfs|r"):format(g, s)
    elseif s > 0 then text = ("%d|cffc7c7cfs|r %02d|cffeda55fc|r"):format(s, c)
    else text = ("%d|cffeda55fc|r"):format(c) end
    if colored then return Theme.HexColor(neg and "bad" or "good", neg and "-" or "+") .. text end
    return (neg and "-" or "") .. text
end

-- My professions (skill) from the profile
local function myProfessions()
    local m = ns.Database.Member(Names.Me())
    return m and m.pr or {}
end

local function myRecipes(prof)
    local list = {}
    for id, r in pairs(db().recipes) do
        if r.by and r.by[charKey()] and (not prof or r.p == prof) then list[#list + 1] = { key = id, id = id, r = r } end
    end
    return list
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local nameCache = {}
local function recipeName(id)
    local n = nameCache[id]
    if n == nil then
        n = (db().recipes[id] and db().recipes[id].n) or ns.Profile.RecipeName(id) or false
        nameCache[id] = n
    end
    return n or nil
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local state = { prof = nil, recipe = nil }

local function recipeIcon(row)
    local r = row.r
    if r and r.o then return Items.Icon(r.o) end
    local tex = C_Spell and C_Spell.GetSpellTexture and ns.Call(C_Spell.GetSpellTexture, row.id)
    return tex or 134400
end

local function recipeColumns(withProf)
    local cols = {
        { key = "name", title = L.RECIPE, flex = true, text = function(row) return row.r.n or recipeName(row.id) or ("#" .. row.id) end,
          icon = recipeIcon, sort = function(row) return row.r.n or "" end },
    }
    if withProf then cols[#cols + 1] = { key = "prof", title = L.PROFESSION, width = 110, text = function(row) return row.r.p or "" end } end
    cols[#cols + 1] = { key = "cost", title = L.PROF_COST, width = 95, align = "RIGHT",
        text = function(row) local c = row.calc; return c.missing > 0 and Theme.HexColor("muted", "?") or Professions.Money(c.cost) end,
        sort = function(row) return row.calc.cost end }
    cols[#cols + 1] = { key = "value", title = L.PROF_VALUE, width = 95, align = "RIGHT",
        text = function(row) return Professions.Money(row.calc.value) end, sort = function(row) return row.calc.value or -1 end, defaultDesc = true }
    cols[#cols + 1] = { key = "profit", title = L.PROF_PROFIT, width = 105, align = "RIGHT",
        text = function(row) return row.calc.profit and Professions.Money(row.calc.profit, true) or Theme.HexColor("muted", "–") end,
        sort = function(row) return row.calc.profit or -1e12 end, defaultDesc = true }
    return cols
end

local function withCalc(rows)
    for _, row in ipairs(rows) do row.calc = Professions.Calc(row.r) end
    return rows
end

-- shopping list panel for one recipe
local function buildShopping(parent)
    local panel = CreateFrame("Frame", nil, parent)
    local head = CreateFrame("Frame", nil, panel)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(56)
    local hbg = UI.Fill(head, "panel"); hbg:SetAllPoints()
    local bar = UI.Fill(head, "accent", "ARTWORK"); bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(2)
    panel.icon = UI.ItemIcon(head, 36)
    panel.icon:SetPoint("LEFT", 12, 0)
    panel.title = UI.Text(head, 14, "text")
    panel.title:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 10, -2)
    panel.title:SetPoint("TOPRIGHT", head, "TOPRIGHT", -10, -12)
    panel.sub = UI.Text(head, 11, "muted")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    panel.list = UI.List(panel, {
        sortKey = "name",
        columns = {
            { key = "name", title = L.PROF_REAGENT, flex = true,
              text = function(row) local info = Items.Info(row.id); return info and info.link or ("item " .. row.id) end,
              icon = function(row) return Items.Icon(row.id) end },
            { key = "need", title = L.PROF_NEED, width = 70, align = "CENTER",
              text = function(row)
                  local ok = row.have >= row.qty
                  return Theme.HexColor(ok and "good" or "text", ("%d/%d"):format(math.min(row.have, row.qty), row.qty))
              end },
            { key = "price", title = L.PROF_PRICE, width = 90, align = "RIGHT", text = function(row) return Professions.Money(row.price) end },
        },
        onEnter = function(frame, row) Items.ShowTooltip(frame, "item:" .. row.id) end,
    })
    panel.list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
    panel.list:SetPoint("BOTTOMRIGHT", 0, 70)
    panel.total = UI.Text(panel, 12, "text")
    panel.total:SetPoint("BOTTOMLEFT", 4, 40)
    panel.total:SetPoint("BOTTOMRIGHT", -4, 40)
    panel.total:SetWordWrap(true)
    panel.empty = UI.Text(panel, 12, "muted", "CENTER")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetText(L.PROF_PICK_RECIPE)
    function panel:Show_(id)
        local r = id and db().recipes[id]
        for _, region in ipairs({ head, self.list, self.total }) do region:SetShown(r ~= nil) end
        self.empty:SetShown(r == nil)
        if not r then return end
        local calc = Professions.Calc(r)
        self.icon:SetItem(r.o and ("item:" .. r.o) or nil)
        self.title:SetText(r.n or recipeName(id) or ("#" .. id))
        self.sub:SetText(("%s · %s %d"):format(r.p or "", L.PROF_YIELD, r.y or 1))
        local rows = {}
        for _, g in ipairs(calc.reagents) do g.key = g.id; rows[#rows + 1] = g end
        self.list:SetRows(rows)
        self.total:SetText(("%s: %s   ·   %s: %s   ·   %s: %s"):format(L.PROF_COST, Professions.Money(calc.missing > 0 and nil or calc.cost),
            L.PROF_BUY, Professions.Money(calc.buyCost), L.PROF_PROFIT, calc.profit and Professions.Money(calc.profit, true) or "–")
            .. (calc.missing > 0 and ("\n" .. Theme.HexColor("muted", L.PROF_MISSING_PRICES:format(calc.missing))) or ""))
    end
    return panel
end

UI.AddPage("professions", L.PAGE_PROFESSIONS, 60, function(content, page)
    local tabs = {}
    local toolbar = CreateFrame("Frame", nil, content)
    toolbar:SetSize(260, 26)
    toolbar:SetPoint("TOPRIGHT", 0, -1)
    toolbar:SetFrameLevel(content:GetFrameLevel() + 5)
    local cutLabel = UI.Text(toolbar, 11, "muted", "RIGHT")
    local cut = UI.Segmented(toolbar, 120, { { value = 5, text = "5%" }, { value = 15, text = "15%" } },
        function() return ns.Database.Settings().ahCut or 5 end,
        function(v) ns.Database.Settings().ahCut = v; page.OnShow() end)
    cut:SetPoint("RIGHT")
    cutLabel:SetPoint("RIGHT", cut, "LEFT", -8, 0)
    cutLabel:SetText(L.PROF_AH_CUT)
    local source = UI.Dropdown(content, 150, function()
        local items = {}
        for _, src in ipairs(Professions.SOURCES) do
            local name = L["PRICE_SRC_" .. src]
            if not Professions.SourceAvailable(src) then name = name .. " " .. Theme.HexColor("muted", L.PRICE_SRC_MISSING) end
            items[#items + 1] = { value = src, text = name }
        end
        return items
    end, function() return ns.Database.Settings().priceSource or "auto" end,
    function(v) ns.Database.Settings().priceSource = v; ns.Fire("LG_PRICES") end)
    -- left of the page search (top right corner)
    source:SetPoint("TOPRIGHT", -ns.Window.SearchReserve(), -1)
    source:SetFrameLevel(content:GetFrameLevel() + 5)
    local sourceLabel = UI.Text(content, 11, "muted", "RIGHT")
    sourceLabel:SetPoint("RIGHT", source, "LEFT", -8, 0)
    sourceLabel:SetText(L.PRICE_SOURCE)

    local holder = CreateFrame("Frame", nil, content)
    holder:SetPoint("TOPLEFT", 0, -40)
    holder:SetPoint("BOTTOMRIGHT")

    -------------------------------------------------------------------
    -- My professions
    -------------------------------------------------------------------
    local mine = CreateFrame("Frame", nil, holder)
    mine:SetAllPoints()
    local cards = CreateFrame("Frame", nil, mine)
    cards:SetPoint("TOPLEFT"); cards:SetPoint("TOPRIGHT"); cards:SetHeight(58)
    -- AH cut: top right of "My professions", above the shopping list
    toolbar:SetParent(mine)
    toolbar:ClearAllPoints()
    toolbar:SetPoint("TOPRIGHT", mine, "TOPRIGHT", 0, -2)
    cards.items = {}
    local shopping = buildShopping(mine)
    shopping:SetPoint("TOPRIGHT", 0, -70)
    shopping:SetPoint("BOTTOMRIGHT")
    shopping:SetWidth(360)
    local myList = UI.List(mine, {
        sortKey = "profit", sortDesc = true, columns = recipeColumns(false),
        onClick = function(row) state.recipe = row.id; mine.Refresh() end,
        isSelected = function(row) return row.id == state.recipe end,
    })
    myList:SetPoint("TOPLEFT", 0, -70)
    myList:SetPoint("BOTTOMRIGHT", shopping, "BOTTOMLEFT", -16, 0)
    myList:SetEmptyText(L.PROF_NO_RECIPES)
    function mine.Refresh()
        local profs = myProfessions()
        if not state.prof and profs[1] then state.prof = profs[1].n end
        for _, c in ipairs(cards.items) do c:Hide() end
        local w = 220
        for i, p in ipairs(profs) do
            local c = cards.items[i]
            if not c then
                c = CreateFrame("Button", nil, cards)
                c:SetSize(w, 54)
                c.bg = UI.Fill(c, "panel"); c.bg:SetAllPoints()
                c.sel = UI.Fill(c, "accent", "ARTWORK"); c.sel:SetPoint("TOPLEFT"); c.sel:SetPoint("BOTTOMLEFT"); c.sel:SetWidth(2)
                c.name = UI.Text(c, 13, "text"); c.name:SetPoint("TOPLEFT", 12, -9)
                c.skill = UI.Text(c, 11, "textDim", "RIGHT"); c.skill:SetPoint("TOPRIGHT", -12, -10)
                c.track = UI.Fill(c, "borderDim", "ARTWORK"); c.track:SetHeight(3)
                c.track:SetPoint("BOTTOMLEFT", 12, 12); c.track:SetPoint("BOTTOMRIGHT", -12, 12)
                c.fill = UI.Fill(c, "accent", "OVERLAY"); c.fill:SetHeight(3); c.fill:SetPoint("BOTTOMLEFT", 12, 12)
                cards.items[i] = c
            end
            c:SetPoint("TOPLEFT", (i - 1) * (w + 8), 0)
            c.name:SetText(p.n)
            c.skill:SetText(("%d / %d"):format(p.s or 0, p.m or 0))
            c.fill:SetWidth(math.max(1, (w - 24) * (p.s or 0) / math.max(1, p.m or 1)))
            c.sel:SetShown(state.prof == p.n)
            c.name:SetTextColor(Theme.Color(state.prof == p.n and "text" or "textDim"))
            c:SetScript("OnClick", function() state.prof = p.n; state.recipe = nil; mine.Refresh() end)
            c:Show()
        end
        myList:SetRows(withCalc(myRecipes(state.prof)))
        shopping:Show_(state.recipe)
    end
    tabs.mine = mine

    -------------------------------------------------------------------
    -- Guild crafting directory (Modules/CraftsPage.lua)
    -------------------------------------------------------------------
    local guild = ns.CraftsPage.Build(holder)
    guild:SetAllPoints()
    tabs.guild = guild

    local cds = ns.ProfCD.Build(holder)
    cds:SetAllPoints()
    tabs.cds = cds

    local bar = UI.SubTabs(content, {
        { key = "guild", title = L.PROF_TAB_GUILD }, { key = "mine", title = L.PROF_TAB_MINE },
        { key = "cds", title = L.PCD_TAB },
    }, function(key)
        for k, t in pairs(tabs) do t:SetShown(k == key) end
        toolbar:SetShown(key == "mine")
        source:SetShown(key ~= "cds"); sourceLabel:SetShown(key ~= "cds" and not source.compact)
        tabs[key].Refresh()
    end)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    -- price source between the tabs and the page search: full, without label, or only an icon
    local function fitSource()
        local tabsW = 0
        for _, b in ipairs(bar.buttons) do tabsW = tabsW + (b:GetWidth() or 80) + 6 end
        local free = (content:GetWidth() or 900) - ns.Window.SearchReserve() - tabsW - 12
        local lw = (sourceLabel.GetUnboundedStringWidth and sourceLabel:GetUnboundedStringWidth()) or sourceLabel:GetStringWidth() or 40
        source.compact = nil
        source.label:Show()
        source.arrow:ClearAllPoints(); source.arrow:SetPoint("RIGHT", -8, 0)
        source.menuWidth = 200
        source.tip = nil
        if free >= 150 + 8 + lw then
            source:SetWidth(150)
        elseif free >= 110 then
            source:SetWidth(math.min(150, free))
            source.compact = "small"
        else
            -- icon only: the current source shows in the tooltip
            source:SetWidth(30)
            source.label:Hide()
            source.arrow:ClearAllPoints(); source.arrow:SetPoint("CENTER")
            source.compact = "icon"
        end
        sourceLabel:SetShown(source:IsShown() and not source.compact)
    end
    source:HookScript("OnEnter", function(self)
        if self.compact then UI.Tooltip(self, L.PRICE_SOURCE, { self.label:GetText() or "" }) end
    end)
    source:HookScript("OnLeave", function() GameTooltip:Hide() end)
    content:HookScript("OnSizeChanged", fitSource)
    bar:Select("guild")
    fitSource()
    Professions.ShowTab = function(key) bar:Select(key) end
    -- header search: guild crafting (recipes, members) or your own recipes
    page.searchHint = L.CRAFT_SEARCH
    -- guild crafting and your own recipes are searched; the tab with hits opens
    guild.SearchHits = function(q)
        local n = 0
        for _, c in pairs(guild.hitsByProf(ns.Crafts.Index())) do n = n + c end
        return n
    end
    guild.SearchApply = function(q) guild.Filter(q) end
    mine.SearchHits = function(q) mine.Refresh(); return myList:SearchHits(q) end
    mine.SearchApply = function(q) myList:ShowFirstHit(q) end
    page.Search = function(text)
        state.query = text or ""
        guild.Filter(state.query)
        return UI.TabSearch(bar, tabs, state.query)
    end
    page.OnShow = function()
        fitSource()
        cut:Refresh()
        source:Refresh()
        tabs[bar.current].Refresh()
    end
end, { section = "forever", icon = "scroll-text", module = "professions" })

ns.On("LG_PRICES", function() ns.Window.Refresh("professions") end)
ns.On("LG_PROFILE", function() ns.Debounce("prof-page", 1, function() ns.Window.Refresh("professions") end) end)
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("prof-bags", 1, function() ns.Window.Refresh("professions") end) end)
ns.On("LG_ITEMS", function() ns.Window.Refresh("professions") end)
