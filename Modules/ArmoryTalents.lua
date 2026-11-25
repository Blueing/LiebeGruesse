-- Armory talents card: one row per tree (name, points, bar) with the icons of
-- the chosen talents below it (tooltip per icon). Hovering a tree row opens a
-- small talent tree next to the card: every talent at its place, chosen ones
-- lit with their rank, each with its spell tooltip.
local _, ns = ...
local UI, Theme, L = ns.UI, ns.Theme, ns.L
local AT = {}
ns.ArmoryTalents = AT

local ICON, GAP = 20, 3
local CELL, CELL_GAP = 34, 6

local function spellIcon(t)
    if t.spell and t.spell > 0 then
        local get = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
        local tex = get and ns.Call(get, t.spell)
        if tex then return tex end
    end
    if t.icon and t.icon > 0 then return t.icon end
    return 134400
end

local function talentTooltip(owner, t)
    ns.TipOwner(owner, "ANCHOR_RIGHT", true)
    local ok = t.spell and t.spell > 0 and pcall(GameTooltip.SetSpellByID, GameTooltip, t.spell)
    if not ok then GameTooltip:SetText(L.ARM_TALENT, 1, 1, 1) end
    local r, g, b = Theme.Color(t.rank >= t.max and t.max > 0 and "accent" or (t.rank > 0 and "good" or "muted"))
    GameTooltip:AddLine(L.ARM_RANK:format(t.rank, t.max), r, g, b)
    GameTooltip:Show()
end

-- "tree,row,col,rank,max,spell[,icon];…" -> [tree] = { {row,col,rank,max,spell,icon}, … }
function AT.Parse(text)
    local trees = {}
    for entry in tostring(text or ""):gmatch("[^;]+") do
        local v = {}
        for n in entry:gmatch("[^,]+") do v[#v + 1] = tonumber(n) end
        if v[1] and v[2] and v[3] then
            trees[v[1]] = trees[v[1]] or {}
            table.insert(trees[v[1]], { row = v[2], col = v[3], rank = v[4] or 0, max = v[5] or 0, spell = v[6] or 0, icon = v[7] })
        end
    end
    for _, list in pairs(trees) do
        table.sort(list, function(a, b) if a.row ~= b.row then return a.row < b.row end return a.col < b.col end)
    end
    return trees
end

---------------------------------------------------------------------------
-- Popup: the whole tree
---------------------------------------------------------------------------
local popup, popupAnchor

local function hideLater()
    ns.After(0.15, function()
        if not popup or not popup:IsShown() then return end
        if (popupAnchor and popupAnchor:IsVisible() and popupAnchor:IsMouseOver()) or popup:IsMouseOver() then return end
        popup:Hide()
    end)
end

local function makePopup()
    popup = UI.Panel(UIParent, "bg", "border")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()
    popup.title = UI.Text(popup, 12, "text")
    popup.title:SetPoint("TOPLEFT", 10, -9)
    popup.points = UI.Text(popup, 12, "accent", "RIGHT")
    popup.points:SetPoint("TOPRIGHT", -10, -9)
    popup.empty = UI.Text(popup, 11, "muted", "CENTER")
    popup.empty:SetPoint("CENTER", 0, -8)
    popup.cells = {}
    popup:SetScript("OnLeave", hideLater)
    return popup
end

local function cell(i)
    local c = popup.cells[i]
    if c then return c end
    c = CreateFrame("Button", nil, popup)
    c:SetSize(CELL, CELL)
    c.border = UI.Fill(c, "borderDim", "BACKGROUND")
    c.border:SetAllPoints()
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- rank on a dark plate with shadow, readable on any icon
    c.rank = UI.Text(c, 11, "text", "RIGHT")
    c.rank:SetPoint("BOTTOMRIGHT", -1, 1)
    c.rank:SetShadowOffset(1, -1)
    c.rank:SetShadowColor(0, 0, 0, 1)
    c.plate = c:CreateTexture(nil, "OVERLAY", nil, -1)
    c.plate:SetTexture(Theme.WHITE)
    c.plate:SetVertexColor(0, 0, 0, 0.85)
    c.plate:SetPoint("TOPLEFT", c.rank, "TOPLEFT", -2, 1)
    c.plate:SetPoint("BOTTOMRIGHT", c.rank, "BOTTOMRIGHT", 1, -1)
    c:SetScript("OnEnter", function(self) if self.t then talentTooltip(self, self.t) end end)
    c:SetScript("OnLeave", function() GameTooltip:Hide(); hideLater() end)
    popup.cells[i] = c
    return c
end

function AT.ShowTree(anchor, name, points, list)
    if not popup then makePopup() end
    popupAnchor = anchor
    local rows, cols = 7, 4
    for _, t in ipairs(list or {}) do rows = math.max(rows, t.row); cols = math.max(cols, t.col) end
    local hasList = list and #list > 0
    if not hasList then rows, cols = 2, 4 end
    popup:SetSize(cols * (CELL + CELL_GAP) - CELL_GAP + 20, rows * (CELL + CELL_GAP) - CELL_GAP + 42)
    popup.title:SetText(name or "")
    popup.points:SetText(tostring(points or 0))
    popup.empty:SetText(hasList and "" or L.ARM_TREE_UNKNOWN)
    for i, t in ipairs(list or {}) do
        local c = cell(i)
        c.t = t
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 10 + (t.col - 1) * (CELL + CELL_GAP), -32 - (t.row - 1) * (CELL + CELL_GAP))
        c.icon:SetTexture(spellIcon(t))
        local picked = t.rank > 0
        if c.icon.SetDesaturated then c.icon:SetDesaturated(not picked) end
        c.icon:SetAlpha(picked and 1 or 0.35)
        c.border:SetVertexColor(Theme.Color(picked and (t.rank >= t.max and "accent" or "good") or "borderDim"))
        local label = picked and t.max > 1 and ("%d/%d"):format(t.rank, t.max) or ""
        c.rank:SetText(label)
        c.rank:SetTextColor(Theme.Color(t.rank >= t.max and "accent" or "text"))
        c.plate:SetShown(label ~= "")
        c:Show()
    end
    for i = #(list or {}) + 1, #popup.cells do popup.cells[i]:Hide(); popup.cells[i].t = nil end
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 4)
    popup:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    popup:Show()
end

function AT.Hide() if popup then popup:Hide() end end

---------------------------------------------------------------------------
-- Card content
---------------------------------------------------------------------------
local function treeRow(c, i)
    c.trees = c.trees or {}
    local r = c.trees[i]
    if r then return r end
    r = CreateFrame("Button", nil, c)
    r:SetHeight(26)
    r.label = UI.Text(r, 12, "text")
    r.label:SetPoint("LEFT", 0, 2)
    r.value = UI.Text(r, 12, "textDim", "RIGHT")
    r.value:SetPoint("RIGHT", 0, 2)
    r.label:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.track = UI.Fill(r, "borderDim", "ARTWORK")
    r.track:SetPoint("BOTTOMLEFT"); r.track:SetPoint("BOTTOMRIGHT"); r.track:SetHeight(2)
    r.fill = UI.Fill(r, "accent", "OVERLAY")
    r.fill:SetPoint("BOTTOMLEFT"); r.fill:SetHeight(2)
    r.hl = UI.Fill(r, "hover", "HIGHLIGHT"); r.hl:SetAllPoints()
    r.icons = {}
    r:SetScript("OnEnter", function(self)
        if self.tree then AT.ShowTree(self, self.tree.name, self.tree.points, self.tree.talents) end
    end)
    r:SetScript("OnLeave", hideLater)
    c.trees[i] = r
    return r
end

local function icon(r, j)
    local b = r.icons[j]
    if b then return b end
    b = CreateFrame("Button", nil, r:GetParent())
    b:SetSize(ICON, ICON)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", function(self) if self.t then talentTooltip(self, self.t) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.icons[j] = b
    return b
end

-- trees = { { name, points, highlight, talents = { … } } }; returns the height
function AT.Fill(c, trees, width)
    local y = -32
    local inner = width - 24
    local perLine = math.max(1, math.floor((inner + GAP) / (ICON + GAP)))
    for i, tree in ipairs(trees) do
        local r = treeRow(c, i)
        r.tree = tree
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", c, "TOPLEFT", 12, y)
        r:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, y)
        r.label:SetText(tree.name)
        r.label:SetTextColor(Theme.Color(tree.highlight and "accent" or "text"))
        r.value:SetText(tostring(tree.points))
        r.fill:SetShown(tree.points > 0)
        r.fill:SetWidth(math.max(1, inner * math.min(1, tree.points / 51)))
        r.fill:SetVertexColor(Theme.Color(tree.highlight and "accent" or "textDim"))
        r:Show()
        y = y - 30
        local n = 0
        for _, t in ipairs(tree.talents or {}) do
            if t.rank > 0 then
                n = n + 1
                local b = icon(r, n)
                b.t = t
                b.tex:SetTexture(spellIcon(t))
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + ((n - 1) % perLine) * (ICON + GAP), y - math.floor((n - 1) / perLine) * (ICON + GAP))
                b:Show()
            end
        end
        for j = n + 1, #r.icons do r.icons[j]:Hide(); r.icons[j].t = nil end
        if n > 0 then y = y - math.ceil(n / perLine) * (ICON + GAP) - 4 end
        y = y - 4
    end
    for i = #trees + 1, #(c.trees or {}) do
        local r = c.trees[i]
        r:Hide(); r.tree = nil
        for _, b in ipairs(r.icons) do b:Hide() end
    end
    if c.extra then
        c.extra:ClearAllPoints()
        c.extra:SetPoint("TOPLEFT", 12, y - 2)
        c.extra:SetWidth(inner)
        if (c.extra:GetText() or "") ~= "" then y = y - (c.extra:GetStringHeight() or 0) - 8 end
    end
    c:SetHeight(-y + 8)
    return -y + 8
end
