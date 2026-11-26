-- Chat messages the addon writes for you (congratulations, award announcements,
-- blessing whispers …) as editable templates with placeholders: {player},
-- {first}, {item} … An empty field means the default text.
local _, ns = ...
local Messages = {}
ns.Messages = Messages
local L = ns.L

-- key = { default locale key, placeholders }
Messages.DEFS = {
    gratzLevel = { "MSG_DEF_GRATZ_LEVEL", { "player", "first", "level" } },
    gratzLoot = { "MSG_DEF_GRATZ_LOOT", { "player", "first", "item" } },
    gratzProf = { "MSG_DEF_GRATZ_PROF", { "player", "first", "profession", "skill" } },
    welcome = { "MSG_DEF_WELCOME", { "player", "first" } },
    lcAward = { "MSG_DEF_LC_AWARD", { "item", "player", "first", "response" } },
    lcRoll = { "MSG_DEF_LC_ROLL", { "item" } },
    blessWhisper = { "MSG_DEF_BLESS_WHISPER", { "blessings", "player", "first" } },
}
local MAX = 200

local function store()
    local s = ns.Database.Settings()
    s.messages = s.messages or {}
    return s.messages
end

function Messages.Default(key)
    local def = Messages.DEFS[key]
    return def and L[def[1]] or ""
end

-- the template in use (own text or default)
function Messages.Get(key)
    local t = ns.db and store()[key]
    if type(t) == "string" and t ~= "" then return t end
    return Messages.Default(key)
end

-- own text: no escape codes, one line, ≤ 200 characters; empty or default = default
function Messages.Clean(text)
    text = tostring(text or ""):gsub("|", ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text > MAX then text = text:sub(1, MAX) end
    return text
end

function Messages.Set(key, text)
    text = Messages.Clean(text)
    if text == "" or text == Messages.Default(key) then text = nil end
    store()[key] = text
end

-- fills the placeholders; {first} comes from {player} when not given.
-- Unknown placeholders stay as they are.
function Messages.Fill(template, values)
    values = values or {}
    if values.player and not values.first then values.first = tostring(values.player):match("^(%S+)") end
    return (tostring(template or ""):gsub("{(%a+)}", function(k)
        local v = values[k]
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end))
end

function Messages.Format(key, values) return Messages.Fill(Messages.Get(key), values) end

-- "{player} {level}" for the tooltip / note under the field
function Messages.VarsText(key)
    local def = Messages.DEFS[key]
    local out = {}
    for _, v in ipairs(def and def[2] or {}) do out[#out + 1] = "{" .. v .. "}" end
    return table.concat(out, "  ")
end

-- /lg test messages: every text with sample values (only printed)
function Messages.Test()
    local me = ns.Names.Display(ns.Names.Me())
    local sample = { player = me, level = 60, item = "[Lionheart Helm]", profession = "Blacksmithing", skill = 300,
        response = "BiS", blessings = "Warrior: Might, Rogue: Might" }
    for _, key in ipairs({ "gratzLevel", "gratzLoot", "gratzProf", "welcome", "lcAward", "lcRoll", "blessWhisper" }) do
        ns.Print("%s %s: %s", L.TEST_TAG, L["MSG_" .. key] or key, Messages.Format(key, sample))
    end
end

-- form rows: one full-width field per message (placeholder = default text),
-- below it one chip per placeholder – a click puts it in at the cursor
local CHIP_H, ROW_H = 18, 62
local function chip(row, edit, key, token)
    local b = CreateFrame("Button", nil, row, "BackdropTemplate")
    ns.UI.Skin(b, "input", "borderDim")
    b:SetHeight(CHIP_H)
    b.text = ns.UI.Text(b, 10, "accent", "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(token)
    b:SetWidth(math.max(34, (b.text:GetStringWidth() or 40) + 12))
    b:SetScript("OnClick", function()
        if edit.SetFocus then edit:SetFocus() end
        if edit.Insert and edit.HasFocus and edit:HasFocus() then edit:Insert(token)
        else edit:SetText((edit:GetText() or "") .. token) end
        Messages.Set(key, edit:GetText())
    end)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ns.Theme.Color("accent"))
        ns.UI.Tooltip(self, token, { L["MSG_VAR_" .. token:sub(2, -2)] or "", L.MSG_CHIP_TIP })
    end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(ns.Theme.Color("borderDim")); GameTooltip:Hide() end)
    return b
end

function Messages.Rows(section, keys)
    for _, key in ipairs(keys) do
        local edit, row = section:Edit(L["MSG_" .. key] or key, function() return store()[key] or "" end,
            function(v) Messages.Set(key, v) end,
            { col = 0, width = 380, height = ROW_H, placeholder = Messages.Default(key),
              tip = L.MSG_TIP:format(Messages.VarsText(key), Messages.Default(key)) })
        if edit and edit.SetMaxLetters then edit:SetMaxLetters(MAX) end
        edit:ClearAllPoints()
        edit:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -8)
        -- placeholder chips under the field
        local prev
        row.chips = {}
        for _, v in ipairs(Messages.DEFS[key][2]) do
            local c = chip(row, edit, key, "{" .. v .. "}")
            row.chips[#row.chips + 1] = c
            if prev then c:SetPoint("LEFT", prev, "RIGHT", 4, 0) else c:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -5) end
            prev = c
        end
        -- the field grows with the card, but leaves room for its label
        if row and row.HookScript then
            row:HookScript("OnSizeChanged", function(r)
                local w = math.floor(math.max(200, math.min(420, (r:GetWidth() or 0) - 190)))
                edit:SetWidth(w)
                if r.label then r.label:SetPoint("RIGHT", r, "RIGHT", -(w + 24), 0) end
            end)
        end
    end
end
