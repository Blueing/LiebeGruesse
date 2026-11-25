-- Shopping list for recipes: a cart of recipes × crafts (every click adds one
-- craft); all their reagents (vendor reagents left out, nothing subtracted)
-- go to the Auction House addon you use:
--   * Auctionator: a shopping list "Liebe Grüße" (its public API), ready in its Shopping tab
--   * TradeSkillMaster: a search string to paste into its Shopping search
--   * neither: a plain list to copy
local _, ns = ...
local Shop = {}
ns.Shopping = Shop
local L, Items = ns.L, ns.Items

Shop.LIST_NAME = "Liebe Grüße"

-- reagents sold by trade goods vendors – nobody buys them at the Auction House
Shop.VENDOR = {
    [2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true,   -- threads
    [3371] = true, [3372] = true, [8925] = true, [18256] = true,                   -- vials
    [2880] = true, [3466] = true, [3857] = true,                                   -- flux, coal
    [2324] = true, [2604] = true, [2605] = true, [2325] = true, [4340] = true, [4341] = true,
    [4342] = true, [6260] = true, [6261] = true, [10290] = true,                   -- bleach, dyes
    [4289] = true, [4470] = true, [6217] = true, [4399] = true, [4400] = true,     -- salt, wood, copper rod, charges
    [159] = true, [2678] = true, [2692] = true, [3713] = true, [2596] = true,      -- water, spices, skin of dwarven stout
    [6530] = true, [17020] = true, [17194] = true, [17196] = true,                 -- nightcrawlers, arcane powder, holiday spices, wine
}

function Shop.IsVendor(id) return Shop.VENDOR[id] == true end

-- vendor materials: the merchant price (four times the sell price), nil when unknown
function Shop.VendorCost(id)
    if not Shop.IsVendor(id) then return nil end
    local sell = ns.Professions and ns.Professions.VendorPrice(id)
    return sell and sell * 4 or nil
end

local function itemName(id)
    local info = Items.Info(id)
    if info and info.name then return info.name end
    local cached = Items.names[id]
    return cached and cached[1] or nil
end

-- where the list goes: "auctionator", "tsm" or "text"
function Shop.Target()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.CreateShoppingList and api.ConvertToSearchString then return "auctionator" end
    if TSM_API then return "tsm" end
    return "text"
end
function Shop.HasTSM() return TSM_API ~= nil end

-- reagents of a recipe (guild catalog first, then own recipes)
function Shop.Reagents(id)
    local meta = ns.Crafts and ns.Crafts.Meta(id)
    if meta and meta.r and next(meta.r) then return meta.r, meta end
    local own = ns.db and ns.db.recipes and ns.db.recipes[id]
    if own and own.r and next(own.r) then return own.r, own end
    return nil
end

-- { { id, name, need, price } } for wanted = { [recipe] = crafts } – nothing is subtracted
function Shop.Needs(wanted)
    local total = {}
    for id, crafts in pairs(wanted) do
        for item, qty in pairs(Shop.Reagents(id) or {}) do
            total[item] = (total[item] or 0) + qty * crafts
        end
    end
    local out, vendor, unknown = {}, 0, 0
    for item, need in pairs(total) do
        if Shop.IsVendor(item) then
            vendor = vendor + 1
        else
            local name = itemName(item)
            if not name then unknown = unknown + 1 end
            out[#out + 1] = { id = item, name = name, need = need, buy = need,
                price = ns.Professions and ns.Professions.Price(item) }
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out, vendor, unknown
end

local function money(copper)
    if not copper then return "?" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g) end
    if s > 0 then return c > 0 and ("%ds %dc"):format(s, c) or ("%ds"):format(s) end
    return ("%dc"):format(c)
end
Shop.PlainMoney = money

---------------------------------------------------------------------------
-- The cart: recipes × crafts (per character). Every click on a cart adds
-- one craft; the Auctionator list follows the cart right away.
---------------------------------------------------------------------------
function Shop.Cart()
    local char = ns.Database.Char()
    char.shopCart = char.shopCart or {}
    return char.shopCart
end
function Shop.InCart(id) return Shop.Cart()[id] or 0 end
function Shop.CartCount()
    local n = 0
    for _ in pairs(Shop.Cart()) do n = n + 1 end
    return n
end

-- Auctionator: one list "Liebe Grüße", replaced with the whole cart
local function toAuctionator(rows)
    local api = Auctionator.API.v1
    local terms = {}
    for _, r in ipairs(rows) do
        if r.name then
            local ok, str = pcall(api.ConvertToSearchString, "LiebeGruesse", { searchString = r.name, isExact = true, quantity = r.need })
            if not ok then ok, str = pcall(api.ConvertToSearchString, "LiebeGruesse", { searchString = r.name, isExact = true }) end
            if ok and type(str) == "string" then terms[#terms + 1] = str end
        end
    end
    if api.DeleteShoppingList then pcall(api.DeleteShoppingList, "LiebeGruesse", Shop.LIST_NAME) end
    if #terms == 0 then return 0 end
    local ok, err = pcall(api.CreateShoppingList, "LiebeGruesse", Shop.LIST_NAME, terms)
    if not ok then ns.Print(L.SHOP_FAILED, tostring(err)); return nil end
    return #terms
end

-- TSM shopping search: "Name/exact;Name/exact"
function Shop.TSMString(rows)
    local parts = {}
    for _, r in ipairs(rows) do
        if r.name then parts[#parts + 1] = r.name .. "/exact" end
    end
    return table.concat(parts, ";")
end

function Shop.PlainText(rows, title)
    local lines = { title }
    local sum = 0
    for _, r in ipairs(rows) do
        lines[#lines + 1] = ("%dx %s%s"):format(r.need, r.name or ("item " .. r.id), r.price and ("  (" .. money(r.price * r.need) .. ")") or "")
        if r.price then sum = sum + r.price * r.need end
    end
    if sum > 0 then lines[#lines + 1] = L.SHOP_TOTAL_PLAIN:format(money(sum)) end
    return table.concat(lines, "\n")
end

-- "3x Lionheart Helm, 1x Arcanite Bar"
function Shop.CartTitle()
    local parts = {}
    for id, n in pairs(Shop.Cart()) do parts[#parts + 1] = ("%dx %s"):format(n, ns.Crafts.Name(id) or ("#" .. id)) end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- pushes the cart to the AH addon (Auctionator right away; TSM/text open a copy box)
-- quiet: no chat line. Returns { rows, vendor, sum, text }
function Shop.Sync(target, quiet, test)
    target = target or Shop.Target()
    local rows, vendor, unknown = Shop.Needs(Shop.Cart())
    -- item names load lazily: once more when they arrived
    if unknown > 0 and not test then
        ns.Debounce("shop-names", 1, function() Shop.Sync(target, quiet, true) end)
    end
    local sum, missing = 0, 0
    for _, r in ipairs(rows) do if r.price then sum = sum + r.price * r.need else missing = missing + 1 end end
    local result = { rows = rows, vendor = vendor, sum = sum, target = target }
    if target == "auctionator" then
        local n = toAuctionator(rows)
        if n and not quiet then
            if n == 0 then ns.Print(L.SHOP_EMPTY_DONE)
            else
                local notes = {}
                if sum > 0 then notes[#notes + 1] = L.SHOP_COST:format(money(sum) .. (missing > 0 and "+" or "")) end
                if vendor > 0 then notes[#notes + 1] = L.SHOP_VENDOR_LEFT:format(vendor) end
                ns.Print(L.SHOP_DONE_AUCTIONATOR:format(Shop.LIST_NAME, n, Shop.CartTitle(),
                    #notes > 0 and (" (" .. table.concat(notes, "; ") .. ")") or ""))
            end
        end
    elseif target == "tsm" then
        result.text = Shop.TSMString(rows)
        if not quiet then ns.Share.ShowText(L.SHOP_TSM_TITLE:format(Shop.CartTitle()), L.SHOP_TSM_HINT, result.text) end
    else
        result.text = Shop.PlainText(rows, Shop.CartTitle())
        if not quiet then ns.Share.ShowText(L.SHOP_TEXT_TITLE:format(Shop.CartTitle()), L.SHOP_TEXT_HINT, result.text) end
    end
    return result
end

local function changed(id)
    ns.Fire("LG_SHOPPING")
    -- Auctionator follows every change; TSM / text only on request (copy box)
    if Shop.Target() == "auctionator" then Shop.Sync("auctionator", true) end
    local name = ns.Crafts.Name(id) or ("#" .. id)
    local n = Shop.InCart(id)
    local where = Shop.Target() == "auctionator" and L.SHOP_WHERE_AUCTIONATOR or L.SHOP_WHERE_OTHER
    -- several quick clicks: one chat line with the final state
    ns.Debounce("shop-chat", 0.8, function()
        if n > 0 then ns.Print(L.SHOP_ADDED:format(name, Shop.InCart(id), Shop.CartCount(), where))
        else ns.Print(L.SHOP_REMOVED:format(name, Shop.CartCount(), where)) end
    end)
end

-- one more craft of a recipe (n crafts at once with n)
function Shop.Add(id, n)
    if not Shop.Reagents(id) then ns.Print(L.SHOP_NO_REAGENTS); return false end
    local cart = Shop.Cart()
    cart[id] = (cart[id] or 0) + (n or 1)
    changed(id)
    return true
end
function Shop.Remove(id, n)
    local cart = Shop.Cart()
    if not cart[id] then return end
    cart[id] = n and (cart[id] - n) or 0
    if cart[id] <= 0 then cart[id] = nil end
    changed(id)
end
function Shop.Clear()
    wipe(Shop.Cart())
    ns.Fire("LG_SHOPPING")
    if Shop.Target() == "auctionator" then Shop.Sync("auctionator", true) end
    ns.Print(L.SHOP_CLEARED)
end

-- cart button: left click +1, right click -1
function Shop.CartClick(id, button)
    if button == "RightButton" then Shop.Remove(id, 1) else Shop.Add(id, 1) end
end

-- the cart menu (button on the Professions page)
function Shop.Menu(anchor)
    local entries = { { title = L.SHOP_MENU_TITLE } }
    local ids = {}
    for id in pairs(Shop.Cart()) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (ns.Crafts.Name(a) or "") < (ns.Crafts.Name(b) or "") end)
    if #ids == 0 then entries[#entries + 1] = { text = L.SHOP_CART_EMPTY, disabled = true } end
    for _, id in ipairs(ids) do
        local name = ns.Crafts.Name(id) or ("#" .. id)
        entries[#entries + 1] = { text = ("%dx %s"):format(Shop.InCart(id), name), submenu = {
            { text = L.SHOP_ONE_MORE, func = function() Shop.Add(id, 1); ns.UI.CloseContextMenu() end },
            { text = L.SHOP_ONE_LESS, func = function() Shop.Remove(id, 1); ns.UI.CloseContextMenu() end },
            { text = L.SHOP_REMOVE, func = function() Shop.Remove(id); ns.UI.CloseContextMenu() end },
        } }
    end
    local empty = #ids == 0
    entries[#entries + 1] = { divider = true }
    if Shop.Target() == "auctionator" then
        entries[#entries + 1] = { text = L.SHOP_SEND_AUCTIONATOR, tip = L.SHOP_TIP_auctionator, disabled = empty,
            func = function() ns.UI.CloseContextMenu(); Shop.Sync("auctionator") end }
    end
    if Shop.HasTSM() then
        entries[#entries + 1] = { text = L.SHOP_SEND_TSM, tip = L.SHOP_TIP_tsm, disabled = empty,
            func = function() ns.UI.CloseContextMenu(); Shop.Sync("tsm") end }
    end
    entries[#entries + 1] = { text = L.SHOP_COPY_TEXT, disabled = empty, func = function() ns.UI.CloseContextMenu(); Shop.Sync("text") end }
    entries[#entries + 1] = { text = L.SHOP_CLEAR, disabled = empty, color = "bad", func = function() ns.UI.CloseContextMenu(); Shop.Clear() end }
    ns.UI.ContextMenu(entries)
end

-- tooltip lines for a recipe's cart button
function Shop.CartTip(id)
    if not Shop.Reagents(id) then return L.SHOP_BUTTON, { L.SHOP_NO_REAGENTS } end
    local lines = {}
    local n = Shop.InCart(id)
    if n > 0 then lines[#lines + 1] = L.SHOP_IN_CART:format(n) end
    lines[#lines + 1] = L.SHOP_CART_HINT
    lines[#lines + 1] = L["SHOP_TIP_" .. Shop.Target()]
    return L.SHOP_BUTTON, lines
end

-- /lg test shopping [recipe]: the list as text for a known recipe (cart untouched, nothing goes to an AH addon)
function Shop.Test(query)
    local id
    if query and query ~= "" and ns.CraftQuery then
        local hits = ns.CraftQuery.Lookup(query)
        id = hits and hits[1] and hits[1].id
    end
    if not id then
        for rid, meta in pairs(ns.db.catalog or {}) do
            if type(meta) == "table" and meta.r and next(meta.r) then id = rid; break end
        end
    end
    if not id then ns.Print(L.SHOP_TEST_NONE); return end
    local name = ns.Crafts.Name(id) or ("#" .. id)
    ns.Print(L.SHOP_TEST:format(name, L["SHOP_TIP_" .. Shop.Target()]))
    local rows = Shop.Needs({ [id] = 2 })
    ns.Share.ShowText(L.SHOP_TEXT_TITLE:format("[Test] 2x " .. name), L.SHOP_TEXT_HINT, Shop.PlainText(rows, "[Test] 2x " .. name))
end

---------------------------------------------------------------------------
-- Tab "Shopping list" on the Professions page: recipes in the cart (with
-- −/+ and remove) on the left, all materials with price on the right,
-- actions on top (Auctionator, TSM, copy, empty).
---------------------------------------------------------------------------
function Shop.Build(parent)
    local UI, Theme = ns.UI, ns.Theme
    local P = ns.Professions
    local f = CreateFrame("Frame", nil, parent)

    local summary = UI.Text(f, 12, "textDim", "LEFT")
    summary:SetPoint("TOPLEFT", 0, -6)
    summary:SetWordWrap(false)

    local bar = UI.Toolbar(f, {
        { text = L.SHOP_SEND_AUCTIONATOR, width = 190, icon = "shopping-cart", tip = L.SHOP_TIP_auctionator,
          onClick = function() Shop.Sync("auctionator") end },
        { text = L.SHOP_SEND_TSM, width = 170, icon = "search", tip = L.SHOP_TIP_tsm_tab, onClick = function() Shop.Sync("tsm") end },
        { text = L.SHOP_COPY_TEXT, width = 120, icon = "scroll-text", tip = L.SHOP_COPY_TIP, onClick = function() Shop.Sync("text") end },
        { text = L.SHOP_CLEAR, width = 130, icon = "x", tip = L.SHOP_CLEAR_TIP, onClick = function() Shop.Clear() end },
    })
    bar:SetPoint("TOPRIGHT", 0, 0)
    f.bar = bar

    -- recipes in the cart
    local recipes = UI.List(f, {
        sortKey = "name", rowHeight = 26,
        columns = {
            { key = "name", title = L.RECIPE, flex = true, minWidth = 120,
              icon = function(r) return ns.Crafts.Icon(r.id) end,
              text = function(r) return ns.Crafts.ColoredName(r.id) end, sort = function(r) return r.name end },
            { key = "less", width = 26, align = "CENTER", noHighlight = true,
              text = function() return Theme.HexColor("textDim", "–") end,
              onClick = function(r) Shop.Remove(r.id, 1) end, tip = function() return L.SHOP_ONE_LESS end },
            { key = "n", title = L.SHOP_COL_CRAFTS, width = 44, align = "CENTER",
              text = function(r) return Theme.HexColor("accent", r.n .. "×") end, sort = function(r) return r.n end },
            { key = "more", width = 26, align = "CENTER", noHighlight = true,
              text = function() return Theme.HexColor("textDim", "+") end,
              onClick = function(r) Shop.Add(r.id, 1) end, tip = function() return L.SHOP_ONE_MORE end },
            { key = "cost", title = L.PROF_COST, width = 90, align = "RIGHT", optional = 1,
              text = function(r) return r.cost and P.Money(r.cost) or Theme.HexColor("muted", "?") end,
              sort = function(r) return r.cost or -1 end },
            { key = "del", width = 26, align = "CENTER", noHighlight = true,
              text = function() return UI.Glyph("x", "muted", 12) end,
              onClick = function(r) Shop.Remove(r.id) end, tip = function() return L.SHOP_REMOVE end },
        },
    })
    recipes:SetEmptyText(L.SHOP_CART_EMPTY, L.SHOP_EMPTY_HINT, "shopping-cart")

    -- all materials of the cart
    local mats = UI.List(f, {
        sortKey = "name", rowHeight = 24,
        columns = {
            { key = "name", title = L.PROF_REAGENT, flex = true, minWidth = 130,
              icon = function(r) return Items.Icon(r.id) end,
              text = function(r)
                  local info = Items.Info(r.id)
                  local name = info and info.link or r.name or ("item " .. r.id)
                  return r.vendor and (name .. Theme.HexColor("muted", "  " .. L.SHOP_VENDOR)) or name
              end, sort = function(r) return r.name or "" end },
            { key = "need", title = L.SHOP_COL_NEED, width = 60, align = "CENTER",
              text = function(r) return Theme.HexColor(r.vendor and "muted" or "text", tostring(r.need)) end,
              sort = function(r) return r.need end },
            { key = "have", title = L.SHOP_COL_HAVE, width = 70, align = "CENTER", optional = 2,
              text = function(r) return Theme.HexColor("muted", tostring(r.have)) end,
              tip = function() return L.SHOP_COL_HAVE, { L.SHOP_HAVE_TIP } end },
            { key = "price", title = L.PROF_PRICE, width = 80, align = "RIGHT", optional = 1,
              text = function(r) return P.Money(r.price) end, sort = function(r) return r.price or -1 end },
            { key = "total", title = L.SHOP_COL_TOTAL, width = 90, align = "RIGHT",
              text = function(r) return r.price and P.Money(r.price * r.need) or Theme.HexColor("muted", "?") end,
              sort = function(r) return r.price and r.price * r.need or -1 end, defaultDesc = true },
        },
        onEnter = function(frame, r) Items.ShowTooltip(frame, "item:" .. r.id) end,
    })
    mats:SetEmptyText(L.SHOP_MATS_EMPTY)
    local total = UI.Text(f, 12, "text", "RIGHT")
    total:SetPoint("BOTTOMRIGHT", -4, 4)

    -- side by side; narrow windows: recipes on top, materials below
    local function layout()
        local W = f:GetWidth() or 0
        if W <= 0 then W = 900 end
        local H = f:GetHeight() or 0
        if H <= 0 then H = 500 end
        recipes:ClearAllPoints(); mats:ClearAllPoints()
        if W >= 760 then
            local lw = math.max(300, math.floor(W * 0.42))
            recipes:SetPoint("TOPLEFT", 0, -36); recipes:SetPoint("BOTTOMLEFT", 0, 0); recipes:SetWidth(lw)
            mats:SetPoint("TOPLEFT", recipes, "TOPRIGHT", 14, 0); mats:SetPoint("BOTTOMRIGHT", 0, 26)
        else
            local rh = math.max(120, math.floor((H - 36) * 0.38))
            recipes:SetPoint("TOPLEFT", 0, -36); recipes:SetPoint("TOPRIGHT", 0, -36); recipes:SetHeight(rh)
            mats:SetPoint("TOPLEFT", recipes, "BOTTOMLEFT", 0, -12); mats:SetPoint("BOTTOMRIGHT", 0, 26)
        end
        -- summary ends before the buttons
        bar:SetWidth(math.max(140, math.min(640, W - 260)))
        bar:Fit()
        summary:SetWidth(math.max(60, W - (bar:GetWidth() or 0) - 16))
    end
    f:SetScript("OnSizeChanged", function() ns.Debounce("shop-layout", 0.02, layout) end)

    function f.Refresh()
        layout()
        local cart = Shop.Cart()
        local rrows = {}
        for id, n in pairs(cart) do
            local cost, missing = P.ReagentCost(Shop.Reagents(id) or {})
            rrows[#rrows + 1] = { key = id, id = id, n = n, name = ns.Crafts.Name(id) or ("#" .. id),
                cost = (missing == 0 or cost > 0) and cost * n or nil }
        end
        recipes:SetRows(rrows)
        -- materials incl. vendor ones (marked; they never go to the AH list)
        local need = {}
        for id, n in pairs(cart) do
            for item, qty in pairs(Shop.Reagents(id) or {}) do need[item] = (need[item] or 0) + qty * n end
        end
        local mrows, sum, missing, ah = {}, 0, 0, 0
        for item, n in pairs(need) do
            local vendor = Shop.IsVendor(item)
            local price = vendor and Shop.VendorCost(item) or P.Price(item)
            mrows[#mrows + 1] = { key = item, id = item, need = n, have = ns.Call(GetItemCount, item, true) or 0,
                price = price, vendor = vendor, name = itemName(item) }
            if price then sum = sum + price * n elseif not vendor then missing = missing + 1 end
            if not vendor then ah = ah + 1 end
        end
        mats:SetRows(mrows)
        total:SetText(#mrows > 0 and (L.SHOP_TOTAL:format(P.Money(sum)) .. (missing > 0 and Theme.HexColor("muted", "  " .. L.SHOP_TOTAL_MISSING:format(missing)) or "")) or "")
        local nr = 0
        for _ in pairs(cart) do nr = nr + 1 end
        summary:SetText(nr == 0 and Theme.HexColor("muted", L.SHOP_CART_EMPTY)
            or L.SHOP_SUMMARY:format(nr, ah, Shop.Target() == "auctionator" and L.SHOP_SUMMARY_AUCTIONATOR or ""))
        -- buttons: only what is installed, never silently off
        local empty = nr == 0
        local btn = bar.buttons
        btn[1]:SetShown(Shop.Target() == "auctionator")
        btn[2]:SetShown(Shop.HasTSM())
        for i, b in ipairs(btn) do
            b:SetEnabled(not empty)
            local base = ({ L.SHOP_TIP_auctionator, L.SHOP_TIP_tsm_tab, L.SHOP_COPY_TIP, L.SHOP_CLEAR_TIP })[i]
            b.tip = empty and { base, L.SHOP_CART_EMPTY } or { base }
        end
        bar:Fit()
    end
    -- buttons that are hidden take no room
    local fit = bar.Fit
    function bar:Fit()
        local shown = {}
        for _, b in ipairs(self.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
        local all = self.buttons
        self.buttons = shown
        fit(self)
        self.buttons = all
        -- right aligned
        local used = 0
        for _, b in ipairs(shown) do used = used + b:GetWidth() + 8 end
        local x = (self:GetWidth() or 0) - used + 8
        for _, b in ipairs(shown) do b:ClearAllPoints(); b:SetPoint("LEFT", math.max(0, x), 0); x = x + b:GetWidth() + 8 end
    end

    -- page search: recipes and materials
    f.SearchHits = function(q) f.Refresh(); return recipes:SearchHits(q) + mats:SearchHits(q) end
    f.SearchApply = function(q) if recipes:SearchHits(q) > 0 then recipes:ShowFirstHit(q) else mats:ShowFirstHit(q) end end
    f.recipes, f.mats = recipes, mats
    return f
end
