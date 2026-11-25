-- Minimap button with the guild crest
local _, ns = ...
local UI = ns.UI
local L = ns.L

local button

local function place()
    local settings = ns.Database.Settings().minimap
    local angle = math.rad(settings.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function create()
    button = CreateFrame("Button", "LiebeGruesseMinimapButton", Minimap)
    button:SetSize(34, 34)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.media .. "icon")
    icon:SetAllPoints()
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(ns.media .. "icon")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.Window.Show("general") else ns.Window.Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            ns.Database.Settings().minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self) UI.Tooltip(self, ns.title, { L.MINIMAP_TIP }) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
end

function UI.UpdateMinimap()
    if not button then create() end
    button:SetShown(not ns.Database.Settings().minimap.hide)
end

ns.On("LG_READY", function() UI.UpdateMinimap() end)
