-- Names, colors, time, items and group helpers
local _, ns = ...

---------------------------------------------------------------------------
-- Names. Forever characters have a first name and a surname. Keys are
-- lowercase, single-spaced; "First-Surname" without a space is a surname,
-- a "-Suffix" after a spaced name is dropped.
---------------------------------------------------------------------------
local Names = {}
ns.Names = Names

local function trim(text) return (text:gsub("%s+", " "):match("^%s*(.-)%s*$")) end

function Names.Strip(name)
    if type(name) ~= "string" or ns.IsSecret(name) then return nil end
    name = trim(name)
    if name:find(" ", 1, true) then
        return trim(name:match("^([^%-]+)%-") or name)
    end
    local first, second = name:match("^([^%-]+)%-([^%-]+)")
    if first then return first .. " " .. second end
    return name
end

function Names.Key(name)
    local stripped = Names.Strip(name)
    if not stripped or stripped == "" then return nil end
    return stripped:lower()
end

function Names.First(name)
    local key = Names.Key(name)
    return key and key:match("^(%S+)")
end

function Names.Display(name)
    local key = Names.Key(name)
    if not key then return "?" end
    return (key:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b end))
end

-- Full name of a unit (first name plus surname when the client returns one)
function Names.Unit(unit)
    local first, surname = ns.Call(UnitName, unit)
    if type(first) ~= "string" or first == "" then return nil end
    if type(surname) == "string" and surname ~= "" then
        local suffix = " " .. surname
        if first:sub(-#suffix) ~= suffix then first = first .. suffix end
    end
    return first
end

local meKey
function Names.Me()
    if not meKey then
        local name = Names.Unit("player")
        meKey = name and Names.Key(name)
    end
    return meKey
end

function Names.IsMe(name)
    local key = Names.Key(name)
    return key ~= nil and key == Names.Me()
end

-- Two keys refer to the same character if equal, or if one side lacks a
-- surname and the first names match.
function Names.Same(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local fa, fb = a:match("^(%S+)"), b:match("^(%S+)")
    if fa ~= fb then return false end
    return not a:find(" ", 1, true) or not b:find(" ", 1, true)
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
function ns.ClassColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

function ns.ClassHex(classFile)
    local r, g, b = ns.ClassColor(classFile)
    return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Round class icon: on a texture (ns.SetClassIcon) or inline in text (ns.ClassIcon)
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
function ns.SetClassIcon(texture, classFile)
    local c = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
    if c then
        texture:SetTexture(CLASS_CIRCLES)
        texture:SetTexCoord(c[1], c[2], c[3], c[4])
        return true
    end
    texture:SetTexture(nil)
    return false
end
-- Spec icons: the game's own talent-tree icons, in tree order per class
local SPEC_ICONS = {
    WARRIOR = { "Ability_Rogue_Eviscerate", "Ability_Warrior_InnerRage", "INV_Shield_06" },
    PALADIN = { "Spell_Holy_HolyBolt", "Spell_Holy_DevotionAura", "Spell_Holy_AuraOfLight" },
    HUNTER = { "Ability_Hunter_BeastTaming", "Ability_Marksmanship", "Ability_Hunter_SwiftStrike" },
    ROGUE = { "Ability_Rogue_Eviscerate", "Ability_BackStab", "Ability_Stealth" },
    PRIEST = { "Spell_Holy_WordFortitude", "Spell_Holy_HolyBolt", "Spell_Shadow_ShadowWordPain" },
    SHAMAN = { "Spell_Nature_Lightning", "Spell_Nature_LightningShield", "Spell_Nature_MagicImmunity" },
    MAGE = { "Spell_Holy_MagicalSentry", "Spell_Fire_FireBolt02", "Spell_Frost_FrostBolt02" },
    WARLOCK = { "Spell_Shadow_DeathCoil", "Spell_Shadow_Metamorphosis", "Spell_Shadow_RainOfFire" },
    DRUID = { "Spell_Nature_StarFall", "Ability_Racial_BearForm", "Spell_Nature_HealingTouch" },
}
-- English class and tree names (the UI is English only; clients report their own language)
local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid", DEATHKNIGHT = "Death Knight" }
local SPEC_NAMES = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}
-- German tree names → English (data from deDE clients without points)
local SPEC_DE = {
    ["waffen"] = "Arms", ["furor"] = "Fury", ["schutz"] = "Protection", ["heilig"] = "Holy", ["vergeltung"] = "Retribution",
    ["tierherrschaft"] = "Beast Mastery", ["tierbeherrschung"] = "Beast Mastery", ["treffsicherheit"] = "Marksmanship",
    ["überleben"] = "Survival", ["meucheln"] = "Assassination", ["kampf"] = "Combat", ["täuschung"] = "Subtlety",
    ["disziplin"] = "Discipline", ["schatten"] = "Shadow", ["schattenmagie"] = "Shadow", ["elementar"] = "Elemental",
    ["elementarkampf"] = "Elemental", ["verstärkung"] = "Enhancement", ["wiederherstellung"] = "Restoration",
    ["arkan"] = "Arcane", ["feuer"] = "Fire", ["frost"] = "Frost", ["gebrechen"] = "Affliction",
    ["dämonologie"] = "Demonology", ["zerstörung"] = "Destruction", ["gleichgewicht"] = "Balance",
    ["wilder kampf"] = "Feral Combat", ["wildheit"] = "Feral Combat", ["wächter"] = "Guardian",
}
function ns.ClassName(classFile)
    if not classFile then return "" end
    return CLASS_NAMES[classFile] or (classFile:sub(1, 1) .. classFile:sub(2):lower())
end
-- English spec name: from class + points when known, else the stored name translated
function ns.SpecName(name, classFile, points)
    local tree = ns.SpecTree(points)
    local list = classFile and SPEC_NAMES[classFile]
    if tree and list and list[tree] then return list[tree] end
    if type(name) ~= "string" or name == "" then return nil end
    return SPEC_DE[name:lower()] or name
end
-- English tree names of a class as a list, else the stored "A,B,C" translated
function ns.TreeNames(classFile, tn)
    local list = classFile and SPEC_NAMES[classFile]
    if list then return { list[1], list[2], list[3] } end
    local out = {}
    for t in tostring(tn or ""):gmatch("[^,]+") do out[#out + 1] = SPEC_DE[t:lower()] or t end
    return out
end
-- tree with the most points from "a/b/c"; nil without points
function ns.SpecTree(points)
    if type(points) ~= "string" then return nil end
    local best, bestN, i = nil, 0, 0
    for n in points:gmatch("%d+") do
        i = i + 1
        n = tonumber(n)
        if n > bestN then best, bestN = i, n end
    end
    return best
end
-- talent points of a member record: own profile, else the last inspect
function ns.SpecPoints(m)
    if type(m) ~= "table" then return nil end
    if tostring(m.tp or ""):find("[1-9]") then return m.tp end
    return m.insp and m.insp.tp or nil
end
-- texture path of the spec icon, or nil when the spec is unknown
function ns.SpecIcon(classFile, points)
    local tree = ns.SpecTree(points)
    local list = classFile and SPEC_ICONS[classFile]
    return tree and list and list[tree] and ("Interface\\Icons\\" .. list[tree]) or nil
end
-- sets a texture to the spec icon, falling back to the class icon
function ns.SetSpecIcon(texture, classFile, points)
    local icon = ns.SpecIcon(classFile, points)
    if icon then
        texture:SetTexture(icon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return true
    end
    return ns.SetClassIcon(texture, classFile)
end

function ns.ClassIcon(classFile, size)
    local c = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
    if not c then return "" end
    size = size or 14
    return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t"):format(CLASS_CIRCLES, size, size, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

function ns.ColorName(name, classFile)
    return ("|c%s%s|r"):format(ns.ClassHex(classFile), Names.Display(name))
end

function ns.Hex(r, g, b, text)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

---------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------
-- Copy of data received from other players: only strings, numbers, booleans
-- and tables (limited depth); "|" is removed so nobody can inject links,
-- textures or colors into our UI; strings are capped.
local CLEAN_MAX = 200
local function clean(v, depth)
    local t = type(v)
    if t == "string" then
        v = v:gsub("|", "")
        if #v > CLEAN_MAX then v = v:sub(1, CLEAN_MAX) end
        return v
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return v
    elseif t == "boolean" then
        return v
    elseif t == "table" and depth > 0 then
        local out, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 60 then break end
            local tk = type(k)
            if tk == "string" or tk == "number" then
                local ck = tk == "string" and clean(k, 0) or k
                if ck ~= nil then out[ck] = clean(x, depth - 1) end
            end
        end
        return out
    end
    return nil
end
function ns.Clean(v, depth) return clean(v, depth or 3) end

function ns.Now()
    return GetServerTime and GetServerTime() or time()
end

function ns.Ago(ts)
    if not ts then return "–" end
    local d = ns.Now() - ts
    local L = ns.L
    if d < 90 then return L.JUST_NOW end
    if d < 3600 then return L.MINUTES_AGO:format(math.floor(d / 60)) end
    if d < 86400 then return L.HOURS_AGO:format(math.floor(d / 3600)) end
    return L.DAYS_AGO:format(math.floor(d / 86400))
end

function ns.Date(ts)
    return date("%d.%m.%y %H:%M", ts or ns.Now())
end

-- text without colour codes, links and textures (for searching)
function ns.PlainText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text
end

-- true when at least one word of the query appears in the text
function ns.SearchAny(text, query)
    query = (query or ""):lower()
    local hay
    for word in query:gmatch("%S+") do
        hay = hay or ns.PlainText(text):lower()
        if hay:find(word, 1, true) then return true end
    end
    return false
end

-- true when every word of the query appears in the text (case-insensitive)
function ns.SearchMatch(text, query)
    query = (query or ""):lower()
    if query:find("^%s*$") then return true end
    local hay = ns.PlainText(text):lower()
    for word in query:gmatch("%S+") do
        if not hay:find(word, 1, true) then return false end
    end
    return true
end

-- marks every occurrence of the query words in a text (colour role, default
-- accent). Colour codes, links and textures of the text stay intact; inside
-- links and textures nothing is marked.
function ns.Highlight(text, query, role)
    if type(text) ~= "string" or text == "" or type(query) ~= "string" then return text end
    local words = {}
    for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return text end
    -- tokens: { plain = char } or { code = "|c…" / "|r" / opaque link/texture }
    local tokens, plain, i, n = {}, {}, 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c == "|" and i < n then
            local nx = text:sub(i + 1, i + 1)
            local j
            if nx == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
                tokens[#tokens + 1] = { code = text:sub(i, i + 9), kind = "color" }; i = i + 10
            elseif nx == "r" then
                tokens[#tokens + 1] = { code = "|r", kind = "reset" }; i = i + 2
            elseif nx == "H" then
                -- |Hdata|h[text]|h – kept whole
                local a = text:find("|h", i + 2, true)
                local b = a and text:find("|h", a + 2, true)
                j = b and (b + 1) or n
                tokens[#tokens + 1] = { code = text:sub(i, j), kind = "opaque" }; i = j + 1
            elseif nx == "T" or nx == "A" then
                local close = text:find(nx == "T" and "|t" or "|a", i + 2, true)
                j = close and (close + 1) or n
                tokens[#tokens + 1] = { code = text:sub(i, j), kind = "opaque" }; i = j + 1
            else
                tokens[#tokens + 1] = { code = text:sub(i, i + 1), kind = "opaque" }; i = i + 2
            end
        else
            tokens[#tokens + 1] = { char = c, at = #plain + 1 }
            plain[#plain + 1] = c
            i = i + 1
        end
    end
    local hay = table.concat(plain):lower()
    local mark, any = {}, false
    for _, w in ipairs(words) do
        local from = 1
        while true do
            local a, b = hay:find(w, from, true)
            if not a then break end
            for k = a, b do mark[k] = true end
            any = true
            from = b + 1
        end
    end
    if not any then return text end
    local open = ns.HighlightCode and ns.HighlightCode(role) or "|cffff9933"
    local out, inHL, color, extra = {}, false, nil, 0
    local function close()
        if not inHL then return end
        out[#out + 1] = "|r"
        inHL = false
        -- old clients reset to white: put the outer colour back (counted, see reset)
        if color then out[#out + 1] = color; extra = extra + 1 end
    end
    for _, t in ipairs(tokens) do
        if t.char then
            if mark[t.at] and not inHL then out[#out + 1] = open; inHL = true
            elseif not mark[t.at] and inHL then close() end
            out[#out + 1] = t.char
        else
            close()
            if t.kind == "color" then color = t.code; extra = 0
            elseif t.kind == "reset" then
                -- one extra |r per colour we put back, so colour stacks stay balanced
                for _ = 1, extra do out[#out + 1] = "|r" end
                color, extra = nil, 0
            end
            out[#out + 1] = t.code
        end
    end
    close()
    return table.concat(out)
end

function ns.Duration(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds >= 3600 then return ("%dh%02d"):format(seconds / 3600, (seconds % 3600) / 60) end
    if seconds >= 60 then return ("%d:%02d"):format(seconds / 60, seconds % 60) end
    if seconds >= 10 then return ("%d"):format(seconds) end
    return ("%.1f"):format(seconds)
end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------
-- upper case that keeps German umlauts intact (string.upper works byte-wise)
function ns.Upper(text)
    return (tostring(text or ""):upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

function ns.CompareVersions(a, b)
    if a == b then return 0 end
    if not a then return -1 end
    if not b then return 1 end
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local Items = {}
ns.Items = Items

-- "item:1234:..." from a full link, trailing empty fields removed
function Items.String(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return nil end
    local s = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)")
    if not s then return nil end
    return (s:gsub(":+$", ""))
end

function Items.ID(itemString)
    return itemString and tonumber(tostring(itemString):match("item:(%d+)"))
end

function Items.Info(item)
    if not item then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, quality, level, _, _, _, _, equipLoc, icon = ns.Call(getInfo, item)
    if not name then
        local id = Items.ID(item) or tonumber(item)
        if id and C_Item and C_Item.RequestLoadItemDataByID then ns.Call(C_Item.RequestLoadItemDataByID, id) end
        return nil
    end
    local id = Items.ID(item) or tonumber(item)
    if id then Items.names[id] = { name, quality } end
    return { name = name, link = link, quality = quality, level = level, equipLoc = equipLoc, icon = icon }
end
Items.names = {}   -- item id -> { name, quality } seen this session

function Items.Level(item)
    if not item then return nil end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local level = ns.Call(C_Item.GetDetailedItemLevelInfo, item)
        if type(level) == "number" and level > 0 then return level end
    end
    if GetDetailedItemLevelInfo then
        local level = ns.Call(GetDetailedItemLevelInfo, item)
        if type(level) == "number" and level > 0 then return level end
    end
    local info = Items.Info(item)
    return info and info.level
end

function Items.Icon(item)
    local id = Items.ID(item) or tonumber(item)
    if id and C_Item and C_Item.GetItemIconByID then
        local icon = ns.Call(C_Item.GetItemIconByID, id)
        if icon then return icon end
    end
    local info = Items.Info(item)
    return info and info.icon or 134400
end

-- A link for text: the real one when the item is cached, otherwise one built from
-- a known name (or "Item 123") – never the raw item string. The real link follows
-- once the client has loaded the item (GET_ITEM_INFO_RECEIVED).
function Items.Link(item, name, quality)
    local info = Items.Info(item)
    if info and info.link then return info.link end
    if type(item) == "string" and item:find("|H") then return item end
    local id = Items.ID(item) or tonumber(item)
    if not id then return item end
    local known = Items.names[id]
    name, quality = name or (known and known[1]), quality or (known and known[2])
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local itemString = type(item) == "string" and item:match("item:[%-%d:]+") or ("item:" .. id)
    return ("%s|H%s|h[%s]|h|r"):format(c and c.hex or "|cffffffff", itemString, name or ("Item " .. id))
end

-- Equipment slots (inventory slot ids) and their labels
Items.SLOTS = {
    { id = 1, key = "HEAD" }, { id = 2, key = "NECK" }, { id = 3, key = "SHOULDER" },
    { id = 15, key = "BACK" }, { id = 5, key = "CHEST" }, { id = 9, key = "WRIST" },
    { id = 10, key = "HANDS" }, { id = 6, key = "WAIST" }, { id = 7, key = "LEGS" },
    { id = 8, key = "FEET" }, { id = 11, key = "FINGER1" }, { id = 12, key = "FINGER2" },
    { id = 13, key = "TRINKET1" }, { id = 14, key = "TRINKET2" }, { id = 16, key = "MAINHAND" },
    { id = 17, key = "OFFHAND" }, { id = 18, key = "RANGED" },
}

-- Cosmetic slots: only read for the armory view (no item level, no enchants)
Items.COSMETIC = { { id = 4, key = "SHIRT" }, { id = 19, key = "TABARD" } }

-- Which inventory slots an equip location can go into
Items.EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18, 16 }, INVTYPE_RANGEDRIGHT = { 18, 16 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

---------------------------------------------------------------------------
-- Enchants
---------------------------------------------------------------------------
-- Permanent enchant id of an item string (0/nil = none)
function Items.Enchant(itemString)
    if not itemString then return nil end
    local enchant = tostring(itemString):match("^item:%d+:(%d*)")
    enchant = tonumber(enchant)
    return enchant and enchant > 0 and enchant or nil
end

local OFFHAND_ENCHANTABLE = { INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local RANGED_ENCHANTABLE = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }

-- Can the item in this slot carry an enchant (per the guild's slot list)?
function Items.ShouldEnchant(slot, itemString)
    if not itemString then return false end
    local slots = ns.db and ns.db.settings.enchantSlots or {}
    if not slots[slot] then return false end
    if slot == 17 or slot == 18 then
        local info = Items.Info(itemString)
        if not info then return true end
        if slot == 17 then return OFFHAND_ENCHANTABLE[info.equipLoc] == true end
        if not RANGED_ENCHANTABLE[info.equipLoc] then return false end
        -- wands (weapon subclass 19) take no scope
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local _, _, _, _, _, classID, subclassID = ns.Call(instant, itemString)
        return not (classID == 2 and subclassID == 19)
    end
    return true
end

-- { done = n, needed = n, missing = { slotId, ... } }
function Items.EnchantStatus(gear)
    local status = { done = 0, needed = 0, missing = {} }
    if not gear then return status end
    for _, slot in ipairs(Items.SLOTS) do
        local item = gear[slot.id]
        if Items.ShouldEnchant(slot.id, item) then
            status.needed = status.needed + 1
            if Items.Enchant(item) then status.done = status.done + 1
            else status.missing[#status.missing + 1] = slot.id end
        end
    end
    return status
end

local enchantNames = {}
-- Enchant description from the item tooltip, when the client can tell
function Items.EnchantText(itemString)
    local id = Items.Enchant(itemString)
    if not id then return nil end
    if enchantNames[id] ~= nil then return enchantNames[id] or nil end
    local text
    local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink and lineType then
        local data = ns.Call(C_TooltipInfo.GetHyperlink, itemString)
        for _, line in ipairs(type(data) == "table" and data.lines or {}) do
            if line.type == lineType and type(line.leftText) == "string" and not ns.IsSecret(line.leftText) then
                text = line.leftText
                break
            end
        end
    end
    if text and ENCHANTED_TOOLTIP_LINE then
        local pattern = "^" .. ENCHANTED_TOOLTIP_LINE:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
        text = text:match(pattern) or text
    end
    enchantNames[id] = text or false
    return text
end

-- Tooltip anchor for the whole addon: at the mouse cursor (setting, default on),
-- otherwise next to the element. fixed = true keeps the element anchor (used
-- where the cursor position makes no sense, e.g. the talent tree popup).
-- Addon tooltips get the window look: flat dark card, 1px border, bronze
-- corners. Drawn on the tooltip's own background frame and removed again as
-- soon as anything else uses the tooltip.
local tipSkin
local function tipBackground()
    return GameTooltip.NineSlice or GameTooltip
end
local function skinTooltip(on)
    local Theme = ns.Theme
    local host = tipBackground()
    if on and not tipSkin then
        tipSkin = {}
        local function fill(layer, sub)
            local t = host:CreateTexture(nil, layer, nil, sub)
            t:SetTexture(Theme.WHITE)
            tipSkin[#tipSkin + 1] = t
            return t
        end
        local bg = fill("BACKGROUND", 7)
        bg:SetPoint("TOPLEFT", GameTooltip, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", 0, 0)
        tipSkin.bg = bg
        tipSkin.edges = {}
        for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
            local t = fill("BORDER", 7)
            t:SetPoint(e[1], GameTooltip, e[1]); t:SetPoint(e[2], GameTooltip, e[2])
            if e[3] then t:SetWidth(1) else t:SetHeight(1) end
            tipSkin.edges[#tipSkin.edges + 1] = t
        end
        tipSkin.corners = {}
        for _, c in ipairs({ { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }) do
            local h = fill("ARTWORK", 7); h:SetSize(7, 1); h:SetPoint(c[1], GameTooltip, c[1], c[2], c[3])
            local v = fill("ARTWORK", 7); v:SetSize(1, 7); v:SetPoint(c[1], GameTooltip, c[1], c[2], c[3])
            tipSkin.corners[#tipSkin.corners + 1] = h
            tipSkin.corners[#tipSkin.corners + 1] = v
        end
    end
    if not tipSkin then return end
    for _, t in ipairs(tipSkin) do t:SetShown(on) end
    local ns9 = GameTooltip.NineSlice
    if on then
        local r, g, b = Theme.Color("panel")
        tipSkin.bg:SetVertexColor(r, g, b, 0.97)
        for _, t in ipairs(tipSkin.edges) do t:SetVertexColor(Theme.Color("borderDim")) end
        for _, t in ipairs(tipSkin.corners) do t:SetVertexColor(Theme.Color("bronze")) end
        if ns9 and ns9.SetCenterColor then ns9:SetCenterColor(0, 0, 0, 0); ns9:SetBorderColor(0, 0, 0, 0) end
        tipSkin.active = true
    elseif tipSkin.active then
        tipSkin.active = false
        if ns9 and ns9.SetCenterColor then
            local bgc, bc = TOOLTIP_DEFAULT_BACKGROUND_COLOR, TOOLTIP_DEFAULT_COLOR
            if bgc then ns9:SetCenterColor(bgc.r, bgc.g, bgc.b, 1) else ns9:SetCenterColor(0.09, 0.09, 0.19, 1) end
            if bc then ns9:SetBorderColor(bc.r, bc.g, bc.b, 1) else ns9:SetBorderColor(1, 1, 1, 1) end
        end
    end
end
local tipHooked
local function hookTooltip()
    if tipHooked then return end
    tipHooked = true
    GameTooltip:HookScript("OnHide", function() skinTooltip(false) end)
    hooksecurefunc(GameTooltip, "SetOwner", function() skinTooltip(false) end)
end

function ns.TipOwner(owner, anchor, fixed)
    hookTooltip()
    local tips = ns.Database.Settings().tooltips
    if not fixed and (not tips or tips.cursor ~= false) then
        if not pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_CURSOR_RIGHT", 18, -6) then
            GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        end
    else
        GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    end
    ns.Safe(skinTooltip, true)
end

function Items.ShowTooltip(owner, item, anchor)
    if not item then return end
    ns.TipOwner(owner, anchor)
    local link = Items.Link(item)
    if type(link) == "string" and link:find("item:", 1, true) then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link:match("|H(item:[^|]+)|h") or link)
        if not ok then GameTooltip:SetText(tostring(item)) end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Group helpers
---------------------------------------------------------------------------
function ns.GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Iterates group units: for unit, key in ns.GroupUnits() do ... end
function ns.GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, GetNumSubgroupMembers and GetNumSubgroupMembers() or 4 do units[#units + 1] = "party" .. i end
    end
    local i = 0
    return function()
        while true do
            i = i + 1
            local unit = units[i]
            if not unit then return nil end
            if UnitExists(unit) then
                local name = Names.Unit(unit)
                if name then return unit, Names.Key(name), name end
            end
        end
    end
end

function ns.UnitForKey(key)
    if not key then return nil end
    if Names.Same(key, Names.Me()) then return "player" end
    for unit, k in ns.GroupUnits() do
        if Names.Same(k, key) then return unit end
    end
end

-- Leader or assistant in the current group
function ns.IsGroupLead(unit)
    unit = unit or "player"
    if ns.Call(UnitIsGroupLeader, unit) then return true end
    if IsInRaid() and ns.Call(UnitIsGroupAssistant, unit) then return true end
    return false
end
