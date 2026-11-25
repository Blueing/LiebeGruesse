-- Guild chat craft lookup: "!lg brawlers leather" (or an item link) is
-- answered by exactly one addon user in guild chat.
--   * fuzzy search: apostrophes, case, plural and small typos do not matter
--   * answers stay short: best match plus "+N more", recipe families in one line
--   * nothing found: "Did you mean …?"
--   * the answering client is elected: clients out of combat and with recipe
--     data win; nobody answers from combat (the game may block chat there)
--   * answers are English only: clients in another language never answer
--     (their recipe names would be in that language), and current versions
--     always win the election against older ones
local _, ns = ...
local Craft = {}
ns.CraftQuery = Craft
local L, Names, Comm, Crafts = ns.L, ns.Names, ns.Comm, ns.Crafts

local recent = {}       -- [query] = time of the last answer
local pending = {}      -- [query] = { token, timer }
local claims = {}       -- [query] = lowest token seen
local REPEAT = 30
local MAX_CHAT = 250

local function settings() return ns.Database.Settings().craft end

-- only English clients answer: recipe and item names come from the client
local function englishClient()
    local locale = GetLocale and ns.Call(GetLocale)
    return locale == nil or locale == "enUS" or locale == "enGB"
end
Craft.EnglishClient = englishClient
-- claims below every older version's token (those are 1 or higher)
local CLAIM_BASE = -10000000

local function crafterText(list, max)
    local parts = {}
    for i, key in ipairs(list) do
        if i > max then parts[#parts + 1] = L.CRAFT_MORE:format(#list - max); break end
        local name = Crafts.DisplayName(key)
        parts[#parts + 1] = name .. (Crafts.Online(key) and " (online)" or "")
    end
    return table.concat(parts, ", ")
end

-- longest common word prefix of several names ("Brawler's Leather")
local function commonPrefix(names)
    local first = {}
    for w in names[1]:gmatch("%S+") do first[#first + 1] = w end
    local n = #first
    for i = 2, #names do
        local j = 0
        for w in names[i]:gmatch("%S+") do
            j = j + 1
            if j > n or w ~= first[j] then j = j - 1; break end
        end
        n = math.min(n, j)
    end
    if n <= 0 then return nil end
    return table.concat(first, " ", 1, n)
end

local function trim(text)
    if #text <= MAX_CHAT then return text end
    return text:sub(1, MAX_CHAT - 3) .. "..."
end

-- "Enchanting: Enchant Cloak - Agility", "Formula: …" → "Enchant Cloak - Agility"
local RECIPE_WORDS = { formula = true, pattern = true, plans = true, recipe = true, schematic = true, manual = true }
local function stripPrefix(text)
    local head, rest = tostring(text or ""):match("^%s*([^:]+):%s*(.+)$")
    if head and (Crafts.ProfKey(head) or RECIPE_WORDS[head:lower()]) then return rest end
    return text
end
Craft.StripPrefix = stripPrefix

-- exact recipe name (after the prefix) → id
local function byExactName(name)
    name = stripPrefix(name)
    local id = Crafts.ForRecipeName("x: " .. name)
    if id then return id end
    local key = Crafts.Normalize(name)
    for rid in pairs(Crafts.Index().recipes) do
        if Crafts.Normalize(Crafts.Name(rid)) == key then return rid end
    end
end

-- recipe ids for a link in the query: crafted item, recipe item, or the
-- recipe itself (enchant, spell and profession links from the recipe window)
local function idsFromLink(raw)
    raw = tostring(raw or "")
    local recipes = Crafts.Index().recipes
    local itemID = tonumber(raw:match("|Hitem:(%d+)"))
    if itemID then
        local ids = Crafts.ForItem(itemID)
        if ids and #ids > 0 then return ids end
        local info = ns.Items.Info(itemID)
        local id = info and Crafts.ForRecipeName(info.name)
        if id then return { id } end
    end
    for kind, data in raw:gmatch("|H(%a+):([^|]+)|h") do
        if kind == "enchant" or kind == "spell" or kind == "trade" then
            for num in data:gmatch("%d+") do
                local id = tonumber(num)
                if id and recipes[id] then return { id } end
            end
        end
    end
    -- unknown id (other client, other rank): the link's text
    for text in raw:gmatch("|h%[(.-)%]|h") do
        local id = byExactName(text)
        if id then return { id } end
    end
    return nil
end

-- Answers stay short (one chat line, no walls of text): at most two crafters,
-- several matches become the best one plus "+N more".
local COMPACT = 180

-- One recipe: "[Arcanite Rod]: crafters · Recipe: [Arcanite Rod]" – the item
-- and the recipe as links (the recipe's tooltip lists the reagents).
-- Links must never be cut, so the crafter list and extras shrink instead.
local function single(hit, suffix)
    suffix = suffix or ""
    local list = Crafts.Crafters(hit.id)
    local item = Crafts.ItemLink(hit.id)
    local recipe = Crafts.RecipeLink(hit.id)
    local tries = {
        { item or recipe or hit.name, (item and recipe) and L.CRAFT_ANSWER_RECIPE:format(recipe) or "" },
        { item or recipe or hit.name, "" },
        { hit.name, "" },
    }
    -- the material cost, short, at the very end (" · mats ~64g")
    local price = Craft.ShortPrice and Craft.ShortPrice(hit.id) or ""
    for _, limit in ipairs({ COMPACT, MAX_CHAT }) do
        for _, withPrice in ipairs({ true, false }) do
            for _, t in ipairs(tries) do
                for max = 2, 1, -1 do
                    local text = L.CRAFT_ANSWER_LIST:format(t[1], crafterText(list, max)) .. t[2] .. suffix .. (withPrice and price or "")
                    if #text <= limit then return text end
                end
            end
        end
    end
    return trim(L.CRAFT_ANSWER_LIST:format(hit.name, crafterText(list, 1)) .. suffix)
end

-- hits for a query: { { id, name, score } }, plus near misses
function Craft.Lookup(query, raw)
    local ids = raw and idsFromLink(raw)
    if ids then
        local hits = {}
        for _, id in ipairs(ids) do hits[#hits + 1] = { id = id, name = Crafts.Name(id), score = 99 } end
        return hits
    end
    local text = stripPrefix(query)
    local exact = byExactName(text)
    if exact then return { { id = exact, name = Crafts.Name(exact), score = 99 } } end
    local hits, near = Crafts.Search(text, true)
    -- an exact name wins over longer names
    if hits[1] and hits[1].score >= 10 then hits = { hits[1] } end
    return hits, near
end

local function sameCrafters(a, b)
    if #a ~= #b then return false end
    local set = {}
    for _, k in ipairs(a) do set[k] = true end
    for _, k in ipairs(b) do if not set[k] then return false end end
    return true
end

-- Builds the answer text for a query (raw text may contain an item link)
function Craft.Answer(query, raw)
    local hits, near = Craft.Lookup(query, raw)
    if #hits == 0 then
        if near and #near > 0 then
            local names = {}
            for i = 1, math.min(2, #near) do names[i] = near[i].name end
            return trim(L.CRAFT_DID_YOU_MEAN:format(query, table.concat(names, ", ")))
        end
        return L.CRAFT_NONE:format(query)
    end
    if #hits == 1 then return single(hits[1]) end
    if #hits > 8 then
        return trim(L.CRAFT_TOO_MANY:format(#hits, query, hits[1].name .. ", " .. hits[2].name))
    end
    -- all matches made by the same people: one short line for the family
    -- ("5 recipes – Brawler's Leather (Armor, Belt, …): Other Person")
    local crafters = Crafts.Crafters(hits[1].id)
    local same = true
    for i = 2, #hits do
        if not sameCrafters(crafters, Crafts.Crafters(hits[i].id)) then same = false; break end
    end
    if same then
        local names = {}
        for i, h in ipairs(hits) do names[i] = h.name end
        table.sort(names)
        local prefix = commonPrefix(names)
        if prefix then
            local tails = {}
            for i, n in ipairs(names) do
                local tail = n:sub(#prefix + 2)
                tails[i] = tail ~= "" and tail or n
            end
            local text = L.CRAFT_ANSWER_GROUP:format(#hits, prefix .. " (" .. table.concat(tails, ", ") .. ")",
                crafterText(crafters, 2))
            if #text <= COMPACT then return text end
        end
    end
    -- different crafters: the best match, the rest only counted
    return single(hits[1], " · " .. L.CRAFT_MORE_MATCHES:format(#hits - 1))
end

-- old name kept for other modules
function Craft.Find(query)
    local hits = Crafts.Search(query)
    if not hits[1] then return nil end
    return { name = hits[1].name, crafters = Crafts.Crafters(hits[1].id), matches = #hits }
end

local function clean(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]+|h", ""):gsub("|h", "")
    text = text:gsub("[%[%]]", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------------------
-- Price to craft: "!lg price <item>", "!lg cost <item>", "!lg mats <item>"
-- (or the word at the end). The election key stays the whole question, so
-- older versions compete for the same question and lose as always.
---------------------------------------------------------------------------
local PRICE_WORDS = { price = true, prices = true, cost = true, costs = true, mats = true, materials = true }
Craft.PRICE_WORDS = PRICE_WORDS

-- returns isPrice, query without the word, raw without the word
function Craft.ParsePrice(query, raw)
    query, raw = tostring(query or ""), tostring(raw or query or "")
    local first, rest = query:match("^(%S+)%s+(.+)$")
    if first and PRICE_WORDS[first:lower()] then
        local r = raw:match("^%s*%S+%s+(.+)$") or rest
        return true, rest, r
    end
    local head, last = query:match("^(.+)%s+(%S+)$")
    if last and PRICE_WORDS[last:lower()] then
        local r = raw:match("^(.-)%s+%S+%s*$") or head
        return true, head, r
    end
    return false, query, raw
end

local function plainMoney(copper) return ns.Shopping.PlainMoney(copper) end

local function itemName(id)
    local info = ns.Items.Info(id)
    if info and info.name then return info.name end
    local c = ns.Items.names[id]
    return c and c[1] or ("item " .. id)
end

-- price facts for a recipe: cost, missing, value, mats { {name, qty, cost} } or nil
function Craft.PriceInfo(id)
    local reagents = ns.Shopping.Reagents(id)
    if not reagents then return nil end
    local P = ns.Professions
    local info = { cost = 0, missing = 0, mats = {} }
    for item, qty in pairs(reagents) do
        local price = P.Price(item) or ns.Shopping.VendorCost(item)
        if price then info.cost = info.cost + price * qty
        elseif not ns.Shopping.IsVendor(item) then info.missing = info.missing + 1 end
        info.mats[#info.mats + 1] = { name = itemName(item), qty = qty, cost = price and price * qty or -1 }
    end
    table.sort(info.mats, function(a, b) if a.cost ~= b.cost then return a.cost > b.cost end return a.name < b.name end)
    local meta = ns.Crafts.Meta(id) or {}
    local out = meta.o and P.Price(meta.o)
    if out then info.value = out * (meta.y or 1) end
    info.priced = info.cost > 0
    return info
end

-- " · mats ~64g" (or "" without prices) for normal answers
function Craft.ShortPrice(id)
    local ok, p = pcall(Craft.PriceInfo, id)
    if not ok or not p or not p.priced then return "" end
    return " · " .. L.CRAFT_PRICE_MATS:format(plainMoney(p.cost)) .. (p.missing > 0 and "+" or "")
end

-- "[Lionheart Helm]: mats ~120g 40s (2x Arcanite Bar, …) · AH ~300g · Ben Lienert (online)"
local function priceLine(hit, suffix)
    suffix = suffix or ""
    local item = Crafts.ItemLink(hit.id)
    local p = Craft.PriceInfo(hit.id)
    if not p then return trim(L.CRAFT_PRICE_NO_REAGENTS:format(item or hit.name)) end
    if not p.priced then return trim(L.CRAFT_PRICE_NONE:format(item or hit.name)) end
    local head = L.CRAFT_PRICE_MATS:format(plainMoney(p.cost)) .. (p.missing > 0 and L.CRAFT_PRICE_UNPRICED:format(p.missing) or "")
    local sells = p.value and (" · " .. L.CRAFT_PRICE_SELLS:format(plainMoney(p.value))) or ""
    local list = Crafts.Crafters(hit.id)
    -- shrink step by step: mats list, crafters, AH value, link → name
    for _, name in ipairs({ item or hit.name, hit.name }) do
        for _, withSells in ipairs({ true, false }) do
            -- the price matters most: crafters go before the materials do
            for maxMats = math.min(4, #p.mats), 0, -1 do
                for maxCrafters = 2, 0, -1 do
                    local mats = {}
                    for i = 1, maxMats do mats[i] = ("%dx %s"):format(p.mats[i].qty, p.mats[i].name) end
                    if maxMats > 0 and maxMats < #p.mats then mats[#mats + 1] = L.CRAFT_MORE:format(#p.mats - maxMats) end
                    local text = name .. ": " .. head .. (#mats > 0 and (" (" .. table.concat(mats, ", ") .. ")") or "")
                        .. (withSells and sells or "")
                        .. (maxCrafters > 0 and #list > 0 and (" · " .. crafterText(list, maxCrafters)) or "")
                        .. suffix
                    if #text <= COMPACT or (maxMats == 0 and maxCrafters == 0 and not withSells and #text <= MAX_CHAT) then return text end
                end
            end
        end
    end
    return trim(hit.name .. ": " .. head .. suffix)
end

-- answer to a price question (query already without the word)
function Craft.PriceAnswer(query, raw)
    local hits = Craft.Lookup(query, raw)
    if #hits == 0 then return Craft.Answer(query, raw) end
    if #hits > 1 then return priceLine(hits[1], " · " .. L.CRAFT_MORE_MATCHES:format(#hits - 1)) end
    return priceLine(hits[1])
end

-- a dungeon name ("!lg ubrs") is answered by the dungeon interest module
local function dungeonQuestion(query)
    return ns.Dungeons and ns.Dungeons.ChatQuery and ns.Dungeons.ChatQuery(query) ~= nil
end

-- any question: dungeon questions get who wants to go, price questions the price line
function Craft.Reply(query, raw)
    local dungeon = ns.Dungeons and ns.Dungeons.ChatAnswer and ns.Dungeons.ChatAnswer(query)
    if dungeon then return dungeon end
    local isPrice, q, r = Craft.ParsePrice(query, raw)
    if isPrice and #q >= 3 then return Craft.PriceAnswer(q, r) end
    return Craft.Answer(query, raw)
end

-- why "!lg" questions would (not) be answered by this client: for /lg test lfgask
function Craft.Status()
    local blocked, why = ns.ChatBlocked()
    local locale = GetLocale and ns.Call(GetLocale) or "?"
    return { answer = settings().answer and true or false, prefix = settings().prefix or "!lg", locale = locale,
        english = englishClient(), blocked = blocked and true or false, why = why }
end

-- /lg test price <item>: the answer only in your chat window
function Craft.TestPrice(text)
    text = tostring(text or "")
    if #text < 3 then ns.Print(L.CRAFT_TEST_PRICE_USAGE); return end
    ns.Print("[Test] [LG] %s", Craft.Reply("price " .. text))
end

local function say(text, channel, target)
    text = "[LG] " .. text
    -- automatic answers never go out from combat or a chat lockdown: the game blocks them
    ns.SendChatAuto("craft-answer-" .. (target or channel), text, channel, target)
end

-- election token: lower wins. Out of combat and with recipe data first.
-- Returns the claim (always below older versions' claims) and the delay.
local function drawToken(query, raw)
    local token = math.random(1, 100000)
    if ns.ChatBlocked() then token = token + 2000000 end
    -- dungeon questions: every client knows the same, so only combat counts. The claim
    -- lies below every crafting claim, so a version without dungeon answers (which
    -- would say "no recipe found") always loses
    if dungeonQuestion(query) then
        return CLAIM_BASE - 10000000 + token, 0.05 + (token % 100000) / 100000 * 0.5 + math.floor(token / 1000000) * 0.15
    end
    -- the client that knows the recipe answers (others may miss a profile)
    local isPrice, q, r = Craft.ParsePrice(query, raw)
    local ok, hits = pcall(Craft.Lookup, q, r)
    if not ok or not hits or #hits == 0 then token = token + 1000000
    elseif not isPrice then
        -- normal questions end with the price: a client with prices first
        local okP, p = pcall(Craft.PriceInfo, hits[1].id)
        if not okP or not p or not p.priced then token = token + 500000 end
    elseif isPrice then
        -- price questions: a client with prices for every material first
        local okP, p = pcall(Craft.PriceInfo, hits[1].id)
        if not okP or not p or not p.priced then token = token + 1000000
        elseif p.missing > 0 then token = token + 500000 end
    end
    -- every claim goes out within 1 s – older versions answer 1.4 s at the earliest,
    -- so this version always wins; better tokens claim sooner
    local delay = 0.05 + (token % 100000) / 100000 * 0.5 + math.floor(token / 1000000) * 0.15
    return CLAIM_BASE + token, delay
end

local function parseQuery(text)
    local prefix = settings().prefix or "!lg"
    local raw = text:match("^%s*" .. prefix:gsub("%p", "%%%0") .. "%s+(.+)$")
    if not raw then return nil end
    return clean(raw), raw
end

ns.On("CHAT_MSG_GUILD", function(_, text, sender)
    if ns.IsSecret(text) or type(text) ~= "string" or not settings().answer then return end
    local query, raw = parseQuery(text)
    if not query then return end
    -- dungeon names are the same in every client language and may be short ("!lg zf")
    local dungeon = dungeonQuestion(query)
    if not dungeon and (#query < 3 or not englishClient()) then return end
    local key = Crafts.Normalize(query)
    if recent[key] and GetTime() - recent[key] < REPEAT then return end
    if pending[key] then return end
    local token, delay = drawToken(query, raw)
    pending[key] = { token = token }
    pending[key].timer = C_Timer.NewTimer(delay, function()
        local p = pending[key]
        if not p then return end
        if claims[key] and claims[key] < p.token then pending[key] = nil; return end
        Comm.Send("CQ", { q = key, n = p.token }, "GUILD", { priority = "alert" })
        C_Timer.After(1.2, function()
            local still = pending[key]
            pending[key] = nil
            if not still or (claims[key] and claims[key] < still.token) then return end
            recent[key] = GetTime()
            say(Craft.Reply(query, raw), "GUILD")
        end)
    end)
end)

Comm.Register("CQ", function(data)
    if type(data.q) ~= "string" or type(data.n) ~= "number" then return end
    if not claims[data.q] or data.n < claims[data.q] then claims[data.q] = data.n end
    recent[data.q] = GetTime()
    local p = pending[data.q]
    if p and data.n < p.token then
        if p.timer then p.timer:Cancel() end
        pending[data.q] = nil
    end
    C_Timer.After(REPEAT, function() claims[data.q] = nil end)
end)

-- Whispered queries are answered directly
ns.On("CHAT_MSG_WHISPER", function(_, text, sender)
    if ns.IsSecret(text) or type(text) ~= "string" or not settings().answer then return end
    local query, raw = parseQuery(text)
    if not query then return end
    if dungeonQuestion(query) or (#query >= 3 and englishClient()) then say(Craft.Reply(query, raw), "WHISPER", sender) end
end)
