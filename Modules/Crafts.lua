-- Guild crafting directory: who in the guild can craft what.
-- Data comes from the recipe lists every member's addon shares (m.rc) and a
-- small recipe catalog (output item, yield, reagents) that crafters share.
-- Also: favourites, item tooltips ("Guild crafters: ..."), whisper/guild post.
local _, ns = ...
local Crafts = ns.NewModule("crafts")
ns.Crafts = Crafts
local L, Names, Comm, Items, Theme = ns.L, ns.Names, ns.Comm, ns.Items, ns.Theme

---------------------------------------------------------------------------
-- Professions (names differ between client languages → canonical keys)
---------------------------------------------------------------------------
local PROFS = {
    { key = "alchemy", icon = 136240, names = { "Alchemy", "Alchimie" } },
    { key = "blacksmithing", icon = 136241, names = { "Blacksmithing", "Schmiedekunst" } },
    { key = "enchanting", icon = 136244, names = { "Enchanting", "Verzauberkunst" } },
    { key = "engineering", icon = 136243, names = { "Engineering", "Ingenieurskunst" } },
    { key = "jewelcrafting", icon = 134071, names = { "Jewelcrafting", "Juwelenschleifen", "Juwelierskunst" } },
    { key = "leatherworking", icon = 133611, names = { "Leatherworking", "Lederverarbeitung" } },
    { key = "tailoring", icon = 136249, names = { "Tailoring", "Schneiderei" } },
    { key = "inscription", icon = 237171, names = { "Inscription", "Inschriftenkunde" } },
    { key = "mining", icon = 136248, names = { "Mining", "Bergbau", "Smelting", "Verhüttung" }, gather = true },
    { key = "herbalism", icon = 136246, names = { "Herbalism", "Kräuterkunde" }, gather = true },
    { key = "skinning", icon = 134366, names = { "Skinning", "Kürschnerei" }, gather = true },
    { key = "cooking", icon = 133971, names = { "Cooking", "Kochkunst" } },
    { key = "firstaid", icon = 135966, names = { "First Aid", "Erste Hilfe" } },
    { key = "fishing", icon = 136245, names = { "Fishing", "Angeln" }, gather = true },
}
local BY_NAME, BY_KEY = {}, {}
for i, p in ipairs(PROFS) do
    p.order = i
    BY_KEY[p.key] = p
    for _, n in ipairs(p.names) do BY_NAME[n:lower()] = p end
end
Crafts.PROFS = PROFS

-- Not professions: hunters' pet training and rogues' poisons also use the craft window
local NOT_PROFESSIONS = { ["beast training"] = true, ["wildtierausbildung"] = true, ["tierausbildung"] = true,
    ["poisons"] = true, ["gifte"] = true }
Crafts.NOT_PROFESSIONS = NOT_PROFESSIONS

function Crafts.ProfKey(name)
    if type(name) ~= "string" then return nil end
    local lower = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if NOT_PROFESSIONS[lower] then return nil end
    -- older versions stored enchanting under an empty name (the craft window gave none)
    if lower == "" then return "enchanting" end
    local p = BY_NAME[lower]
    return p and p.key or lower
end
function Crafts.ProfInfo(key) return BY_KEY[key] end
-- a stored name that is no profession (e.g. "Poisons" from older versions)
function Crafts.NotProfession(name)
    return type(name) == "string" and NOT_PROFESSIONS[(name:gsub("^%s+", ""):gsub("%s+$", ""):lower())] == true
end
-- Display name in the player's language
function Crafts.ProfName(key)
    local p = BY_KEY[key]
    if not p then return key end
    return p.names[1] -- English only
end
-- Remember the name the client itself uses (from our own profile)
local function learnLocalNames()
    local me = ns.Database.Member(Names.Me())
    for _, pr in ipairs(me and me.pr or {}) do
        local p = BY_NAME[(pr.n or ""):lower()]
        if p then p.local_ = pr.n end
    end
end

---------------------------------------------------------------------------
-- Recipe catalog: ns.db.catalog[id] = { p = profKey, o = outputItem, y = yield, r = { [item] = qty } }
---------------------------------------------------------------------------
local function catalog()
    ns.db.catalog = ns.db.catalog or {}
    return ns.db.catalog
end

local dirty = true
local function changed()
    dirty = true
    ns.Debounce("crafts-changed", 1, function() ns.Fire("LG_CRAFTS") end)
end

function Crafts.Learn(id, prof, name, output, yield, reagents)
    if type(id) ~= "number" then return end
    local c = catalog()
    local e = c[id] or {}
    local pk = Crafts.ProfKey(prof)
    if pk and not (pk == "enchanting" and e.p and e.p ~= "enchanting") then e.p = pk end
    if type(output) == "number" and output > 0 then e.o = output end
    if type(yield) == "number" and yield > 0 then e.y = yield end
    if type(reagents) == "table" and next(reagents) then e.r = reagents end
    if type(name) == "string" then e.n = name end
    c[id] = e
    changed()
end

function Crafts.Meta(id) return catalog()[id] end

local nameCache = {}
function Crafts.Name(id)
    local n = nameCache[id]
    if n then return n end
    n = ns.Profile.RecipeName(id)
    if not n then
        -- the client's own item name first; the stored name is the scanner's language
        local e = catalog()[id]
        if e and e.o then local info = Items.Info(e.o); n = info and info.name end
        if not n then n = e and e.n end
        if not n then return "#" .. id end
        return n
    end
    nameCache[id] = n
    return n
end

-- Item quality of the crafted item (nil for enchants and unknown outputs)
function Crafts.Quality(id)
    local e = catalog()[id]
    local info = e and e.o and Items.Info(e.o)
    return info and info.quality
end

function Crafts.ColoredName(id)
    local name = Crafts.Name(id)
    local q = Crafts.Quality(id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex .. name .. "|r" end
    return Theme.HexColor("text", name)
end

function Crafts.Icon(id)
    local e = catalog()[id]
    if e and e.o then return Items.Icon(e.o) end
    local tex = C_Spell and C_Spell.GetSpellTexture and ns.Call(C_Spell.GetSpellTexture, id)
    if not tex and GetSpellTexture then tex = ns.Call(GetSpellTexture, id) end
    if tex then return tex end
    local p = e and BY_KEY[e.p]
    return p and p.icon or 134400
end

-- Insertable chat link for a recipe (crafted item, else the spell)
function Crafts.Link(id)
    local e = catalog()[id]
    local info = e and e.o and Items.Info(e.o)
    if info and info.link then return info.link end
    if GetSpellLink then
        local link = ns.Call(GetSpellLink, id)
        if link then return link end
    end
    if C_Spell and C_Spell.GetSpellLink then return ns.Call(C_Spell.GetSpellLink, id) end
    return Crafts.Name(id)
end

-- Recipe link (the profession link: its tooltip lists the reagents).
-- Only links the game builds itself – a hand-made link with a wrong text
-- would make the server drop the whole chat message:
--   1. the profession API, 2. a link seen while scanning your own
--   professions, 3. the spell link of the recipe.
function Crafts.RememberLink(id, link)
    if type(id) ~= "number" or type(link) ~= "string" or not link:find("|H") then return end
    local s = ns.Database.Settings()
    s.recipeLinks = s.recipeLinks or {}
    s.recipeLinks[id] = link
end

function Crafts.RecipeLink(id)
    if type(id) ~= "number" then return nil end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then
        local link = ns.Call(C_TradeSkillUI.GetRecipeLink, id)
        if type(link) == "string" and link:find("|H") then return link end
    end
    local saved = ns.Database.Settings().recipeLinks
    if saved and saved[id] then return saved[id] end
    local link
    if C_Spell and C_Spell.GetSpellLink then link = ns.Call(C_Spell.GetSpellLink, id) end
    if not link and GetSpellLink then link = ns.Call(GetSpellLink, id) end
    if type(link) == "string" and link:find("|H") then return link end
end

-- Item link of the crafted item (nil for enchants)
function Crafts.ItemLink(id)
    local e = catalog()[id]
    local info = e and e.o and Items.Info(e.o)
    return info and info.link
end

-- pack/unpack for the network: "id:out:yield:item*qty/item*qty"
local function packEntry(id, e)
    local r = {}
    for item, qty in pairs(e.r or {}) do r[#r + 1] = item .. "*" .. qty end
    table.sort(r)
    return ("%d:%d:%d:%s"):format(id, e.o or 0, e.y or 1, table.concat(r, "/"))
end

local function unpackInto(text, prof)
    local n = 0
    for entry in text:gmatch("[^;]+") do
        local id, out, yield, rest = entry:match("^(%d+):(%d+):(%d+):(.*)$")
        id = tonumber(id)
        if id then
            local reagents = {}
            for item, qty in rest:gmatch("(%d+)%*(%d+)") do reagents[tonumber(item)] = tonumber(qty) end
            local e = catalog()[id] or {}
            e.p = e.p or prof
            if tonumber(out) > 0 then e.o = tonumber(out) end
            e.y = tonumber(yield)
            if next(reagents) then e.r = reagents end
            catalog()[id] = e
            n = n + 1
        end
    end
    if n > 0 then changed() end
    return n
end

local function packFor(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        local e = catalog()[id]
        if e and (e.o or e.r) then parts[#parts + 1] = packEntry(id, e) end
    end
    return table.concat(parts, ";")
end

---------------------------------------------------------------------------
-- Guild index (rebuilt lazily)
--   profs[key] = { key, members = { [memberKey] = { s, m, x, t } }, recipes = { [id] = { memberKey, ... } } }
---------------------------------------------------------------------------
local index
local byOutput, byName

local function guildMembers()
    local result = {}
    local roster = next(ns.Guild.members) ~= nil
    for key, m in pairs(ns.Database.Guild().members) do
        if not roster or ns.Guild.IsMember(key) or Names.Same(key, Names.Me()) then result[key] = m end
    end
    return result
end

function Crafts.Index()
    if index and not dirty then return index end
    learnLocalNames()
    index = { profs = {}, recipes = {} }
    byOutput, byName = nil, nil
    for key, m in pairs(guildMembers()) do
        for _, pr in ipairs(m.pr or {}) do
            local pk = Crafts.ProfKey(pr.n)
            if pk then
                local p = index.profs[pk] or { key = pk, members = {}, recipes = {}, count = 0, recipeCount = 0 }
                p.members[key] = { s = pr.s or 0, m = pr.m, x = pr.x }
                index.profs[pk] = p
            end
        end
        -- recipes this member has in another profession never count as enchanting
        -- (older versions filed them there, see Profile.CleanEnchanting)
        local other = {}
        for profName, ids in pairs(m.rc or {}) do
            if type(ids) == "string" and Crafts.ProfKey(profName) ~= "enchanting" then
                for raw in ids:gmatch("%d+") do other[raw] = true end
            end
        end
        for profName, ids in pairs(m.rc or {}) do
            local pk = Crafts.ProfKey(profName)
            if pk == "enchanting" and type(ids) == "string" then
                local keep = {}
                for raw in ids:gmatch("%d+") do if not other[raw] then keep[#keep + 1] = raw end end
                ids = table.concat(keep, ",")
            end
            if pk and type(ids) == "string" then
            local p = index.profs[pk] or { key = pk, members = {}, recipes = {}, count = 0, recipeCount = 0 }
            index.profs[pk] = p
            local mem = p.members[key] or { s = 0 }
            p.members[key] = mem
            -- two stored names can mean the same profession (e.g. an old empty name): merge them
            local t = m.rct and m.rct[profName]
            if t and (not mem.t or t > mem.t) then mem.t = t end
            mem.ids = mem.ids and (mem.ids .. "," .. ids) or ids
            for raw in ids:gmatch("%d+") do
                local id = tonumber(raw)
                local list = p.recipes[id]
                if not list then list = {}; p.recipes[id] = list; p.recipeCount = p.recipeCount + 1 end
                local already = false
                for _, k in ipairs(list) do if k == key then already = true; break end end
                if not already then list[#list + 1] = key end
                index.recipes[id] = index.recipes[id] or { prof = pk, crafters = list }
                local e = catalog()[id]
                -- repair: a recipe filed as enchanting by mistake gets its real profession back
                if e and (not e.p or (e.p == "enchanting" and pk ~= "enchanting")) then e.p = pk end
            end
            end
        end
    end
    for _, p in pairs(index.profs) do
        for _ in pairs(p.members) do p.count = p.count + 1 end
    end
    dirty = false
    return index
end

local function online(key)
    local g = ns.Guild.Find(key)
    return g and g.online or Names.Same(key, Names.Me())
end
Crafts.Online = online

local function sortCrafters(list)
    table.sort(list, function(a, b)
        local oa, ob = online(a) and 1 or 0, online(b) and 1 or 0
        if oa ~= ob then return oa > ob end
        return a < b
    end)
    return list
end

-- crafters of a recipe, online first
function Crafts.Crafters(id)
    local r = Crafts.Index().recipes[id]
    if not r then return {} end
    local copy = {}
    for i, k in ipairs(r.crafters) do copy[i] = k end
    return sortCrafters(copy)
end

function Crafts.RecipeProf(id)
    local r = Crafts.Index().recipes[id]
    return r and r.prof or (catalog()[id] and catalog()[id].p)
end

function Crafts.DisplayName(key)
    local g = ns.Guild.Find(key)
    local m = ns.Database.Member(key)
    return Names.Display(g and g.name or (m and m.name) or key), g and g.class or (m and m.c)
end

function Crafts.ColoredMember(key, withStatus)
    local name, class = Crafts.DisplayName(key)
    local text = ns.ColorName(name, class)
    if withStatus then
        text = (online(key) and ns.UI.Glyph("dot", "good", 10) or ns.UI.Glyph("ring", "muted", 10)) .. " " .. text
    end
    return text
end

-- recipe IDs for a crafted item
function Crafts.ForItem(itemID)
    if not byOutput then
        -- build the index first: rebuilding it clears this cache
        local recipes = Crafts.Index().recipes
        local map = {}
        for id in pairs(recipes) do
            local e = catalog()[id]
            if e and e.o then
                map[e.o] = map[e.o] or {}
                table.insert(map[e.o], id)
            end
        end
        byOutput = map
    end
    return byOutput[itemID]
end

-- recipe ID for a recipe item ("Pattern: Netherweave Bag" → Netherweave Bag)
function Crafts.ForRecipeName(name)
    if type(name) ~= "string" then return nil end
    if not byName then
        local recipes = Crafts.Index().recipes
        local map = {}
        for id in pairs(recipes) do
            local n = Crafts.Name(id)
            if n then map[n:lower()] = id end
        end
        byName = map
    end
    local stripped = name:match("^[^:]+:%s*(.+)$")
    return stripped and byName[stripped:lower()]
end

---------------------------------------------------------------------------
-- Favourites
---------------------------------------------------------------------------
local function favs()
    ns.db.favorites = ns.db.favorites or {}
    local f = ns.db.favorites
    f.recipes, f.members = f.recipes or {}, f.members or {}
    return f
end
function Crafts.IsFav(kind, key) return favs()[kind][key] == true end
function Crafts.ToggleFav(kind, key)
    local f = favs()[kind]
    f[key] = (not f[key]) or nil
    ns.Fire("LG_CRAFTS")
end
function Crafts.Favs(kind) return favs()[kind] end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function Crafts.Whisper(key, id)
    local name = Crafts.DisplayName(key)
    local target = ns.Guild.Find(key) and ns.Guild.Find(key).name or name
    if ChatFrame_SendTell then
        ChatFrame_SendTell(target)
        if id and ChatEdit_GetActiveWindow then
            local box = ChatEdit_GetActiveWindow()
            if box and box.Insert then box:Insert(Crafts.Link(id) .. " ") end
        end
    end
end

local lastPost = {}
local POST_COOLDOWN = 30
function Crafts.PostToGuild(id)
    if not IsInGuild() then return end
    local now = GetTime()
    if lastPost[id] and now - lastPost[id] < POST_COOLDOWN then
        ns.Print(L.CRAFT_POST_WAIT:format(math.ceil(POST_COOLDOWN - (now - lastPost[id]))))
        return
    end
    local crafters = Crafts.Crafters(id)
    if #crafters == 0 then return end
    local names = {}
    for i, key in ipairs(crafters) do
        if i > 6 then names[#names + 1] = L.CRAFT_MORE:format(#crafters - 6); break end
        local n = Crafts.DisplayName(key)
        names[#names + 1] = n .. (online(key) and "*" or "")
    end
    lastPost[id] = now
    ns.SendChat(("[LG] %s: %s"):format(Crafts.Link(id), table.concat(names, ", ")), "GUILD")
end

function Crafts.InsertLink(id)
    local link = Crafts.Link(id)
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

---------------------------------------------------------------------------
-- Network: share the catalog for one's own recipes
---------------------------------------------------------------------------
-- called by Profile when our recipe list for a profession changed
function Crafts.ShareOwn(profName, ids)
    local list = {}
    for raw in tostring(ids):gmatch("%d+") do list[#list + 1] = tonumber(raw) end
    local packed = packFor(list)
    if packed ~= "" and IsInGuild() then
        Comm.Send("RM", { p = Crafts.ProfKey(profName), m = packed }, "GUILD", { priority = "bulk" })
    end
end

Comm.Register("RM", function(data, sender)
    if type(data.m) ~= "string" or Names.Same(sender, Names.Me()) then return end
    unpackInto(data.m, type(data.p) == "string" and data.p or nil)
end)

-- missing catalog entries are asked from whoever sent the recipe list
local wanted = {}   -- [raw sender] = { [id] = true }
function Crafts.Missing(ids, raw)
    local need = wanted[raw] or {}
    local any = false
    for rawId in tostring(ids):gmatch("%d+") do
        local id = tonumber(rawId)
        local e = catalog()[id]
        if not e or (not e.o and not e.r) then need[id] = true; any = true end
    end
    if not any then return end
    wanted[raw] = need
    ns.Debounce("crafts-mq-" .. raw, 20, function()
        local list = {}
        for id in pairs(wanted[raw] or {}) do
            local e = catalog()[id]
            if (not e or (not e.o and not e.r)) and #list < 400 then list[#list + 1] = id end
        end
        wanted[raw] = nil
        if #list > 0 then Comm.Send("MQ", { ids = table.concat(list, ",") }, "WHISPER", { target = raw, priority = "bulk" }) end
    end)
end

Comm.Register("MQ", function(data, _, _, raw)
    if type(data.ids) ~= "string" then return end
    local list = {}
    for rawId in data.ids:gmatch("%d+") do
        list[#list + 1] = tonumber(rawId)
        if #list >= 400 then break end
    end
    local packed = packFor(list)
    if packed ~= "" then Comm.Send("RM", { m = packed }, "WHISPER", { target = raw, priority = "bulk" }) end
end)

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------
local MAX_TIP = 5
local function tipNames(list)
    local parts = {}
    for i, key in ipairs(list) do
        if i > MAX_TIP then parts[#parts + 1] = Theme.HexColor("muted", L.CRAFT_MORE:format(#list - MAX_TIP)); break end
        parts[#parts + 1] = Crafts.ColoredMember(key, true)
    end
    return parts
end

local function addItemLines(tooltip, link)
    local s = ns.Database.Settings().tooltips
    if s.crafters == false or type(link) ~= "string" then return end
    local itemID = Items.ID(Items.String(link))
    if not itemID then return end
    local ids = Crafts.ForItem(itemID)
    local r, g, b = Theme.Color("gold")
    if ids then
        local seen, list = {}, {}
        for _, id in ipairs(ids) do
            for _, key in ipairs(Crafts.Crafters(id)) do
                if not seen[key] then seen[key] = true; list[#list + 1] = key end
            end
        end
        sortCrafters(list)
        if #list > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(L.TIP_CRAFTERS, r, g, b)
            for _, line in ipairs(tipNames(list)) do tooltip:AddLine("  " .. line) end
            -- price to craft (materials at current prices)
            local P = ns.Professions
            for _, id in ipairs(ids) do
                local meta = catalog()[id]
                if P and meta and meta.r and next(meta.r) then
                    local total, missing = P.ReagentCost(meta.r)
                    if total > 0 then
                        local per = total / math.max(1, meta.y or 1)
                        tooltip:AddDoubleLine("  " .. L.TIP_PTC .. (missing > 0 and (" " .. L.TIP_PTC_PARTIAL) or ""),
                            (missing > 0 and "~" or "") .. P.Money(per), 0.8, 0.8, 0.8, 1, 1, 1)
                    end
                    break
                end
            end
            tooltip:Show()
        end
        return
    end
    -- recipe items: who already knows it
    local info = Items.Info(itemID)
    local id = info and Crafts.ForRecipeName(info.name)
    if id then
        local list = Crafts.Crafters(id)
        if #list > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(L.TIP_KNOWN_BY, r, g, b)
            for _, line in ipairs(tipNames(list)) do tooltip:AddLine("  " .. line) end
            tooltip:Show()
        end
    end
end

local function onItem(tooltip)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    if ns.IsSecret(link) then return end
    ns.Safe(addItemLines, tooltip, link)
end
Crafts.TooltipLines = addItemLines

ns.On("LG_READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tip and tip:HasScript("OnTooltipSetItem") then tip:HookScript("OnTooltipSetItem", onItem) end
        end
    end
end)

ns.On("LG_PROFILE", changed)
ns.On("GUILD_ROSTER_UPDATE", function() dirty = true end)
ns.On("LG_ITEMS", function() byName = nil end)

---------------------------------------------------------------------------
-- Fuzzy recipe search (used by "!lg" in guild chat and the crafting page)
--   * case, apostrophes, punctuation and accents do not matter
--     ("brawlers leather" finds "Brawler's Leather Armor")
--   * every word of the query must match a word of the name: equal, as the
--     start of a word ("lionh" > "Lionheart") or with one typo (5+ letters)
--   * only names from this client are searched (recipe and crafted item)
---------------------------------------------------------------------------
-- The folding must stay exactly like in older versions: "!lg" keys are built
-- with it, and clients of every version have to agree on the same key.
local ACCENTS = { ["\195\164"] = "a", ["\195\182"] = "o", ["\195\188"] = "u", ["\195\132"] = "a", ["\195\150"] = "o",
    ["\195\156"] = "u", ["\195\159"] = "ss", ["é"] = "e", ["è"] = "e", ["à"] = "a", ["ç"] = "c" }

function Crafts.Normalize(text)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]+|h", ""):gsub("|h", "")
    for from, to in pairs(ACCENTS) do text = text:gsub(from, to) end
    text = text:lower():gsub("['`´’]", "")
    text = text:gsub("[^%w\128-\255]+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function words(text)
    local list = {}
    for w in Crafts.Normalize(text):gmatch("%S+") do list[#list + 1] = w end
    return list
end
Crafts.Words = words

-- at most one edit (insert, delete, replace, swap)
local function oneEdit(a, b)
    local la, lb = #a, #b
    if math.abs(la - lb) > 1 then return false end
    if la == lb then
        local diff, first = 0, nil
        for i = 1, la do
            if a:sub(i, i) ~= b:sub(i, i) then
                diff = diff + 1
                if diff == 1 then first = i
                elseif diff == 2 then
                    -- swapped neighbours count as one
                    if not (i == first + 1 and a:sub(first, first) == b:sub(i, i) and a:sub(i, i) == b:sub(first, first)) then return false end
                else return false end
            end
        end
        return true
    end
    if la > lb then a, b = b, a end
    local i, j, skipped = 1, 1, false
    while i <= #a and j <= #b do
        if a:sub(i, i) == b:sub(j, j) then i, j = i + 1, j + 1
        elseif skipped then return false
        else skipped = true; j = j + 1 end
    end
    return true
end

-- points for one query word against one name word
local function wordScore(q, w)
    if q == w then return 4 end
    if #q >= 3 and w:sub(1, #q) == q then return 3 end
    -- "brawlers" vs "brawler", "potions" vs "potion"
    if #q >= 4 and (q:sub(1, -2) == w or w:sub(1, -2) == q) then return 3 end
    if #q >= 5 and oneEdit(q, w) then return 2 end
    if #q >= 5 and #w > #q and oneEdit(q, w:sub(1, #q)) then return 1 end
    return 0
end

local function nameScore(qWords, name)
    local nWords = words(name)
    if #nWords == 0 then return 0 end
    local total = 0
    for _, q in ipairs(qWords) do
        local best = 0
        for _, w in ipairs(nWords) do
            local s = wordScore(q, w)
            if s > best then best = s end
        end
        if best == 0 then return 0 end
        total = total + best
    end
    -- exact name, and fewer extra words, rank higher
    if #nWords == #qWords and total == 4 * #qWords then total = total + 10 end
    return total - (#nWords - #qWords) * 0.25
end

local function namesOf(id)
    local list = { Crafts.Name(id) }
    local e = catalog()[id]
    if e and e.o then
        local info = Items.Info(e.o)
        if info and info.name then list[#list + 1] = info.name end
    end
    return list
end

-- { { id, score, name }, ... } best first; partial = matches of at least half the words
function Crafts.Search(query, partial)
    local qWords = words(query)
    local hits, near = {}, {}
    if #qWords == 0 then return hits end
    for id in pairs(Crafts.Index().recipes) do
        local best = 0
        for _, name in ipairs(namesOf(id)) do best = math.max(best, nameScore(qWords, name)) end
        if best > 0 then
            hits[#hits + 1] = { id = id, score = best, name = Crafts.Name(id) }
        elseif partial and #qWords >= 2 then
            local name = Crafts.Name(id)
            local nWords, got = words(name), 0
            for _, q in ipairs(qWords) do
                for _, w in ipairs(nWords) do if wordScore(q, w) > 0 then got = got + 1; break end end
            end
            if got >= math.ceil(#qWords / 2) then near[#near + 1] = { id = id, score = got, name = name } end
        end
    end
    local function sort(list)
        table.sort(list, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if #a.name ~= #b.name then return #a.name < #b.name end
            return a.name < b.name
        end)
    end
    sort(hits); sort(near)
    return hits, near
end
