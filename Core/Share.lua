-- Import / export of settings as a copyable text ("LG1:...")
local _, ns = ...
local Share = {}
ns.Share = Share

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end

function Share.Encode(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = 4 - ((b and 0 or 1) + (c and 0 or 1))
        for k = 1, 4 do
            local idx = math.floor(v / 64 ^ (4 - k)) % 64
            out[#out + 1] = k <= chars and B64:sub(idx + 1, idx + 1) or "="
        end
    end
    return table.concat(out)
end

function Share.Decode(s)
    s = s:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #s, 4 do
        local v, pad = 0, 0
        for k = 0, 3 do
            local ch = s:byte(i + k)
            local d = ch and DEC[ch]
            if not d then pad = pad + 1; d = 0 end
            v = v * 64 + d
        end
        local bytes = { math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256 }
        for k = 1, 3 - pad do out[#out + 1] = string.char(bytes[k]) end
    end
    return table.concat(out)
end

local function copy(t) return ns.Serialize.Unpack(ns.Serialize.Pack(t)) end

-- Parts that can be shared
Share.PARTS = {
    cooldowns = {
        get = function() return copy(ns.Database.Settings().cd) end,
        set = function(v)
            local cd = ns.Database.Settings().cd
            for k, val in pairs(v) do cd[k] = val end
            ns.CooldownSpells.Rebuild()
            ns.Fire("LG_COOLDOWNS")
        end,
    },
    council = {
        get = function() return copy(ns.Council.Config()) end,
        set = function(v)
            v.t = ns.Now()
            ns.Database.Guild().lc = v
        end,
    },
    look = {
        get = function() return copy(ns.Database.Settings().theme) end,
        set = function(v)
            local theme = ns.Database.Settings().theme
            for k, val in pairs(v) do theme[k] = val end
            ns.Theme.Apply()
        end,
    },
    general = {
        get = function()
            local s = ns.Database.Settings()
            return copy({ minimap = s.minimap, toasts = s.toasts, tooltips = s.tooltips, enchantSlots = s.enchantSlots,
                modules = s.modules, ahCut = s.ahCut, craft = s.craft, community = s.community })
        end,
        set = function(v)
            local s = ns.Database.Settings()
            for k, val in pairs(v) do s[k] = val end
            ns.UI.UpdateMinimap()
            ns.Window.BuildNav()
        end,
    },
}
Share.ORDER = { "cooldowns", "council", "look", "general" }

function Share.Export(parts)
    local data = { v = 1, by = ns.Names.Unit("player"), parts = {} }
    if not parts then
        parts = {}
        for key in pairs(Share.PARTS) do parts[#parts + 1] = key end
        table.sort(parts)
    end
    for _, key in ipairs(parts) do
        local part = Share.PARTS[key]
        if part then data.parts[key] = part.get() end
    end
    return "LG1:" .. Share.Encode(ns.Serialize.Pack(data))
end

-- Returns the decoded table or nil, error
function Share.Read(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local body = text:match("^LG1:(.+)$")
    if not body then return nil, ns.L.SHARE_BAD end
    local data = ns.Serialize.Unpack(Share.Decode(body))
    if type(data) ~= "table" or type(data.parts) ~= "table" then return nil, ns.L.SHARE_BAD end
    return data
end

function Share.Import(text)
    local data, err = Share.Read(text)
    if not data then return false, err end
    local names = {}
    for key, value in pairs(data.parts) do
        local part = Share.PARTS[key]
        if part and type(value) == "table" then
            ns.Safe(part.set, value)
            names[#names + 1] = ns.L["SHARE_PART_" .. key]
        end
    end
    return true, table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Dialog with a multi-line text box
---------------------------------------------------------------------------
local dialog
local function create()
    local UI, L = ns.UI, ns.L
    dialog = UI.Panel(UIParent, "bg", "border")
    if dialog.SetClipsChildren then dialog:SetClipsChildren(true) end
    dialog:SetSize(560, 360)
    dialog.defaultSize = { 560, 360 }
    dialog:SetPoint("CENTER")
    ns.UI.Float(dialog)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    tinsert(UISpecialFrames, "LiebeGruesseShareDialog")
    _G.LiebeGruesseShareDialog = dialog
    dialog.title = UI.Text(dialog, 15, "text")
    dialog.title:SetPoint("TOPLEFT", 16, -14)
    dialog.hint = UI.Text(dialog, 11, "muted")
    dialog.hint:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -6)
    local close = UI.IconButton(dialog, "x", 24, function() dialog:Hide() end, true)
    close:SetPoint("TOPRIGHT", -10, -10)
    local box = UI.Panel(dialog, "input", "border")
    box:SetPoint("TOPLEFT", 16, -60)
    box:SetPoint("BOTTOMRIGHT", -16, 56)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    ns.Theme.SetFont(edit, ns.Theme.Font(), 11, "")
    edit:SetTextColor(ns.Theme.Color("text"))
    edit:SetWidth(500)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, self:GetVerticalScroll() - delta * 30))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    dialog.edit = edit
    -- resizable; the text box follows the width
    UI.Resizable(dialog, "share", 420, 260, 1600, 1200, function() edit:SetWidth(math.max(100, (scroll:GetWidth() or 500) - 4)) end)
    scroll:HookScript("OnSizeChanged", function(self, w) if w and w > 0 then edit:SetWidth(w - 4) end end)
    dialog.action = UI.Button(dialog, "", 160, 28, function() if dialog.onAction then dialog.onAction(edit:GetText()) end end)
    dialog.action:SetPoint("BOTTOMRIGHT", -16, 16)
    dialog.select = UI.Button(dialog, L.SHARE_SELECT_ALL, 140, 28, function() edit:SetFocus(); edit:HighlightText() end)
    dialog.select:SetPoint("RIGHT", dialog.action, "LEFT", -8, 0)
end

function Share.ShowExport(parts)
    if not dialog then create() end
    local L = ns.L
    dialog.title:SetText(L.SHARE_EXPORT_TITLE)
    dialog.hint:SetText(L.SHARE_EXPORT_HINT)
    dialog.edit:SetText(Share.Export(parts))
    dialog.action:SetText(L.CLOSE)
    dialog.onAction = function() dialog:Hide() end
    dialog:Show()
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
end

-- Shows any text to copy (e.g. a loot history export)
function Share.ShowText(title, hint, text)
    if not dialog then create() end
    dialog.title:SetText(title)
    dialog.hint:SetText(hint or ns.L.SHARE_EXPORT_HINT)
    dialog.edit:SetText(text or "")
    dialog.action:SetText(ns.L.CLOSE)
    dialog.onAction = function() dialog:Hide() end
    dialog:Show()
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
end

function Share.ShowImport()
    if not dialog then create() end
    local L = ns.L
    dialog.title:SetText(L.SHARE_IMPORT_TITLE)
    dialog.hint:SetText(L.SHARE_IMPORT_HINT)
    dialog.edit:SetText("")
    dialog.action:SetText(L.SHARE_IMPORT)
    dialog.onAction = function(text)
        local ok, info = Share.Import(text)
        if ok then
            ns.Print(L.SHARE_IMPORTED:format(info))
            dialog:Hide()
            ns.Window.Refresh()
        else
            ns.Print(info)
        end
    end
    dialog:Show()
    dialog.edit:SetFocus()
end
