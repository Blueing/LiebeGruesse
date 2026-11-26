-- Main window: brand and grouped navigation on the left, page header with
-- opacity/scale controls, page area and a footer with Reload UI / Close.
local _, ns = ...
local UI, Theme = ns.UI, ns.Theme
local L = ns.L

local Window = {}
ns.Window = Window
local pages, pageList = {}, {}
local frame, current

local SIDEBAR_W, HEADER_H, FOOTER_H = 200, 72, 50
local SEARCH_STRIP_H = 44
local HEADER_SLIDER_W = 96
-- page search: top right of the page area; pages keep this corner free
Window.SEARCH_W, Window.SEARCH_H = 220, 26
Window.SEARCH_RESERVE = 220 + 14

Window.SECTIONS = {
    { key = "guild", title = "SECTION_GUILD" },
    { key = "raid", title = "SECTION_RAID" },
    { key = "forever", title = "SECTION_FOREVER" },
    { key = "me", title = "SECTION_ME" },
    { key = "settings", title = "SECTION_SETTINGS" },
}

-- builder(content, page) runs the first time the page is shown; page.OnShow()
-- runs every time. opts: section, icon
function UI.AddPage(key, title, order, builder, opts)
    opts = opts or {}
    local page = { key = key, title = title, order = order or 50, builder = builder,
        section = opts.section or "guild", icon = opts.icon or "sparkles", hidden = opts.hidden, module = opts.module,
        visible = opts.visible, badge = opts.badge }
    pages[key] = page
    pageList[#pageList + 1] = page
    table.sort(pageList, function(a, b) return a.order < b.order end)
    if frame then Window.BuildNav() end
    return page
end

function Window.Page(key) return pages[key] end

-- newer addon version confirmed (nil: none): chip next to the version
local pendingUpdate
function Window.SetUpdate(v)
    pendingUpdate = v
    if not frame or not frame.updChip then return end
    local chip = frame.updChip
    chip.v = v
    if v then
        chip.text:SetText(v)
        chip:SetWidth(4 + 10 + 3 + math.max(20, chip.text:GetStringWidth() or 30) + 5)
    end
    chip:SetShown(v ~= nil and not frame.compact)
    frame.updDot:SetShown(v ~= nil and frame.compact == true)
end

function UI.RemovePage(key)
    pages[key] = nil
    for i, p in ipairs(pageList) do if p.key == key then table.remove(pageList, i) break end end
end

local function settings() return ns.Database.Settings() end

-- Pages can be switched off in the settings (modules) or limited by a rule
function Window.PageVisible(page)
    if page.hidden then return false end
    if page.module and ns.db and settings().modules[page.module] == false then return false end
    if page.visible and not page.visible() then return false end
    return true
end

local function applyLook()
    if not frame then return end
    local theme = settings().theme
    frame:SetScale(theme.windowScale or 1)
    frame:SetAlpha(theme.windowAlpha or 1)
end

local function create()
    local win = settings().window
    frame = UI.Panel(UIParent, "bg", "bronzeDim")
    UI.Corners(frame, 12)
    frame:SetSize(win.w or 1160, win.h or 760)
    frame:SetPoint(win.point or "CENTER", UIParent, win.point or "CENTER", win.x or 0, win.y or 0)
    -- above most HUD elements; addon popups (DIALOG) still open on top
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(760, 480, 1900, 1300) end
    frame:Hide()
    tinsert(UISpecialFrames, "LiebeGruesseMainWindow")
    _G.LiebeGruesseMainWindow = frame
    applyLook()

    local function save()
        local point, _, _, x, y = frame:GetPoint()
        win.point, win.x, win.y = point, x, y
        if not frame.collapsed then win.w, win.h = frame:GetWidth(), frame:GetHeight() end
    end
    local function drag(region)
        region:EnableMouse(true)
        region:RegisterForDrag("LeftButton")
        region:SetScript("OnDragStart", function() frame:StartMoving() end)
        region:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); save() end)
    end

    -------------------------------------------------------------------
    -- sidebar
    -------------------------------------------------------------------
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 1, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR_W)
    local sbg = UI.Fill(side, "sidebar")
    sbg:SetAllPoints()
    local sline = UI.Fill(side, "borderDim", "ARTWORK")
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)
    frame.side = side

    local brand = CreateFrame("Frame", nil, side)
    brand:SetPoint("TOPLEFT")
    brand:SetPoint("TOPRIGHT", -1, 0)
    brand:SetHeight(HEADER_H + 6)
    drag(brand)
    -- faint lapis light from the top, like the logo's center stone
    local glow = UI.VGradient(brand, { 0.090, 0.129, 0.192, 1 }, { 0.090, 0.129, 0.192, 0 })
    glow:SetAllPoints()
    local crest = brand:CreateTexture(nil, "OVERLAY")
    crest:SetTexture(ns.media .. "logo")
    crest:SetSize(52, 52)
    crest:SetPoint("LEFT", 14, 0)
    frame.crest = crest
    -- name block centered next to the crest: "Liebe" / "Grüße" stacked tight, version below
    local name1 = UI.Text(brand, 22, "text", "LEFT")
    name1:SetPoint("TOPLEFT", crest, "TOPRIGHT", 10, 5)
    name1:SetText("Liebe")
    local name2 = UI.Text(brand, 22, "gold", "LEFT")
    name2:SetPoint("TOPLEFT", name1, "BOTTOMLEFT", 0, 1)
    name2:SetText("Grüße")
    local ver = UI.Text(brand, 11, "muted")
    ver:SetPoint("TOPLEFT", name2, "BOTTOMLEFT", 0, 0)
    ver:SetText("v" .. ns.version)
    frame.brandTexts = { name1, name2, ver }
    -- small "update available" chip next to the version (Window.SetUpdate)
    local upd = CreateFrame("Button", nil, brand, "BackdropTemplate")
    UI.Skin(upd, "selected", "accent")
    upd:SetHeight(15)
    upd:SetPoint("LEFT", ver, "RIGHT", 6, 0)
    upd.icon = UI.Icon(upd, "circle-arrow-up", 10, "accent")
    upd.icon:SetPoint("LEFT", 4, 0)
    upd.text = UI.Text(upd, 11, "accent", "LEFT", nil, true)
    upd.text:SetPoint("LEFT", upd.icon, "RIGHT", 3, 0)
    upd:SetScript("OnClick", function() Window.Show("versions") end)
    upd:SetScript("OnEnter", function(self) if self.v then UI.Tooltip(self, ns.L.UPDATE_KICKER, { ns.L.UPDATE_CHIP_TIP:format(self.v, ns.version) }) end end)
    upd:SetScript("OnLeave", function() GameTooltip:Hide() end)
    upd:Hide()
    frame.updChip = upd
    -- compact sidebar: a small dot on the crest instead
    local updDot = UI.Icon(brand, "dot", 9, "accent", "OVERLAY")
    updDot:SetPoint("TOPRIGHT", crest, "TOPRIGHT", 2, 2)
    updDot:Hide()
    frame.updDot = updDot
    local bline = UI.Fill(brand, "bronzeDim", "ARTWORK")
    bline:SetPoint("BOTTOMLEFT"); bline:SetPoint("BOTTOMRIGHT"); bline:SetHeight(1)
    -- light flash that keeps running along the line while the window is open
    local flashClip = CreateFrame("Frame", nil, brand)
    flashClip:SetPoint("BOTTOMLEFT"); flashClip:SetPoint("BOTTOMRIGHT"); flashClip:SetHeight(1)
    if flashClip.SetClipsChildren then flashClip:SetClipsChildren(true) end
    local spark = CreateFrame("Frame", nil, flashClip)
    spark:SetSize(80, 1)
    spark:SetPoint("RIGHT", flashClip, "LEFT", 0, 0)
    for i, a in ipairs({ { 0, 1 }, { 1, 0 } }) do
        local t = spark:CreateTexture(nil, "OVERLAY")
        t:SetTexture(Theme.WHITE)
        t:SetSize(40, 1)
        t:SetPoint("LEFT", (i - 1) * 40, 0)
        if t.SetGradient and CreateColor then
            t:SetGradient("HORIZONTAL", CreateColor(1, 0.89, 0.76, a[1]), CreateColor(1, 0.89, 0.76, a[2]))
        else
            t:SetVertexColor(1, 0.89, 0.76, 0.6)
        end
    end
    local flash = spark:CreateAnimationGroup()
    local move = flash:CreateAnimation("Translation")
    move:SetOffset(SIDEBAR_W + 80, 0)
    move:SetDuration(1.6)
    move:SetStartDelay(1.8)
    if move.SetSmoothing then move:SetSmoothing("IN_OUT") end
    flash:SetLooping("REPEAT")
    frame.flashAnim = flash

    -- status buttons: guild online, partner guild, new feed entries
    local status = CreateFrame("Frame", nil, side)
    status:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, 0)
    status:SetPoint("TOPRIGHT", brand, "BOTTOMRIGHT", 0, 0)
    status:SetHeight(40)
    frame.status = status
    local function chip(icon, role, onClick)
        local b = UI.Button(status, "", 56, 22, onClick, icon)
        UI.Skin(b, "bg", "borderDim")
        b:HookScript("OnLeave", function(self) self:SetBackdropColor(Theme.Color("bg")); self:SetBackdropBorderColor(Theme.Color("borderDim")) end)
        Theme.SetFont(b.label, Theme.Font(), Theme.FontSize(11), "")
        Theme.RegisterText(b.label, 11, "textDim")
        b.label:SetTextColor(Theme.Color("textDim"))
        b.icon:SetSize(11, 11)
        b.icon:SetVertexColor(Theme.Color(role))
        Theme.RegisterFill(b.icon, role)
        return b
    end
    frame.chips = {
        chip("users", "good", function() Window.Show("roster") end),
        chip("link", "lapis", function() Window.Show("coguild") end),
        chip("newspaper", "accent", function() Window.Show("feed") end),
    }
    -- online share of the guild as a thin bar; fills once when the window opens
    local rail = UI.Fill(side, "borderDim", "ARTWORK")
    rail:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    rail:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, 0)
    rail:SetHeight(2)
    local railFill = UI.Fill(side, "accent", "OVERLAY")
    railFill:SetPoint("TOPLEFT", rail, "TOPLEFT")
    railFill:SetHeight(2)
    railFill:SetWidth(1)
    local grow = railFill:CreateAnimationGroup()
    local scaleAnim = grow:CreateAnimation("Scale")
    if scaleAnim.SetScaleFrom then scaleAnim:SetScaleFrom(0.01, 1); scaleAnim:SetScaleTo(1, 1)
    elseif scaleAnim.SetFromScale then scaleAnim:SetFromScale(0.01, 1); scaleAnim:SetToScale(1, 1) end
    if scaleAnim.SetOrigin then scaleAnim:SetOrigin("LEFT", 0, 0) end
    scaleAnim:SetDuration(1.0)
    if scaleAnim.SetSmoothing then scaleAnim:SetSmoothing("OUT") end
    frame.rail, frame.railFill, frame.railGrow = rail, railFill, grow
    -- shine that keeps running to the right through the filled part
    local glintClip = CreateFrame("Frame", nil, side)
    glintClip:SetPoint("TOPLEFT", railFill, "TOPLEFT")
    glintClip:SetPoint("BOTTOMRIGHT", railFill, "BOTTOMRIGHT")
    if glintClip.SetClipsChildren then glintClip:SetClipsChildren(true) end
    glintClip:SetFrameLevel(side:GetFrameLevel() + 5)
    local glint = CreateFrame("Frame", nil, glintClip)
    glint:SetSize(40, 2)
    glint:SetPoint("RIGHT", glintClip, "LEFT", 0, 0)
    for i, a in ipairs({ { 0, 0.9 }, { 0.9, 0 } }) do
        local t = glint:CreateTexture(nil, "OVERLAY")
        t:SetTexture(Theme.WHITE)
        t:SetSize(20, 2)
        t:SetPoint("LEFT", (i - 1) * 20, 0)
        if t.SetGradient and CreateColor then
            t:SetGradient("HORIZONTAL", CreateColor(1, 0.89, 0.76, a[1]), CreateColor(1, 0.89, 0.76, a[2]))
        else
            t:SetVertexColor(1, 0.89, 0.76, 0.5)
        end
    end
    local shine = glint:CreateAnimationGroup()
    local shineMove = shine:CreateAnimation("Translation")
    shineMove:SetDuration(1.4)
    shineMove:SetStartDelay(1.2)
    shineMove:SetOffset(SIDEBAR_W, 0)
    shine:SetLooping("REPEAT")
    frame.shineAnim, frame.shineMove = shine, shineMove

    -- search everything (pages, settings, guide, commands, members, recipes):
    -- below the online bar, above the page list
    local searchStrip = CreateFrame("Frame", nil, side)
    searchStrip:SetPoint("TOPLEFT", rail, "BOTTOMLEFT", 0, 0)
    searchStrip:SetPoint("TOPRIGHT", rail, "BOTTOMRIGHT", 0, 0)
    searchStrip:SetHeight(SEARCH_STRIP_H)
    frame.searchStrip = searchStrip
    local gs = CreateFrame("Button", nil, searchStrip, "BackdropTemplate")
    UI.Skin(gs, "input", "borderDim")
    gs:SetHeight(26)
    gs.icon = UI.Icon(gs, "search", 12, "textDim")
    gs.icon:SetPoint("LEFT", 9, 0)
    gs.text = UI.Text(gs, 12, "muted", "LEFT")
    gs.text:SetPoint("LEFT", gs.icon, "RIGHT", 7, 0)
    gs.text:SetPoint("RIGHT", -8, 0)
    gs.text:SetText(L.SEARCH_ALL)
    gs:SetScript("OnClick", function() Window.OpenSearch() end)
    gs:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.Color("accent"))
        UI.Tooltip(self, L.SEARCH_ALL_TITLE, { L.SEARCH_ALL_TIP })
    end)
    gs:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(Theme.Color("borderDim")); GameTooltip:Hide() end)
    frame.globalSearch = gs
    local function placeSearch(compact)
        gs:ClearAllPoints()
        gs:SetPoint("LEFT", searchStrip, "LEFT", compact and 12 or 12, 0)
        gs:SetPoint("RIGHT", searchStrip, "RIGHT", compact and -12 or -12, 0)
        gs.text:SetShown(not compact)
        gs.icon:ClearAllPoints()
        if compact then gs.icon:SetPoint("CENTER") else gs.icon:SetPoint("LEFT", 9, 0) end
    end
    frame.placeSearch = placeSearch
    placeSearch(false)

    -- the page list tightens when the window is short and scrolls as a last resort
    frame.navScroll = CreateFrame("ScrollFrame", nil, side)
    frame.navScroll:SetPoint("TOPLEFT", searchStrip, "BOTTOMLEFT", 0, -2)
    frame.navScroll:SetPoint("BOTTOMRIGHT", 0, 4)
    frame.nav = CreateFrame("Frame", nil, frame.navScroll)
    frame.nav:SetSize(SIDEBAR_W, 1)
    frame.navScroll:SetScrollChild(frame.nav)
    frame.navScroll:EnableMouseWheel(true)
    frame.navScroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, frame.nav:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)
    frame.navScroll:SetScript("OnSizeChanged", function(self, w, h)
        frame.nav:SetWidth(w)
        if math.abs((frame.navBuiltH or 0) - (h or 0)) > 1 then ns.Debounce("lg-nav-fit", 0.05, Window.BuildNav) end
    end)
    frame.navItems, frame.navHeads, frame.navLines = {}, {}, {}

    -------------------------------------------------------------------
    -- header
    -------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    drag(header)
    local hbg = UI.Fill(header, "header")
    hbg:SetAllPoints()
    hbg:SetDrawLayer("BACKGROUND", -8)
    -- map strip behind the page title, fading out to the right
    local map = header:CreateTexture(nil, "BACKGROUND", nil, -4)
    map:SetPoint("TOPLEFT"); map:SetPoint("BOTTOMLEFT")
    -- the strip files carry their own fade to the right (alpha channel)
    local mapShade = UI.Gradient(header, "header", 0.55)
    mapShade:SetDrawLayer("BACKGROUND", 0)
    mapShade:SetPoint("TOPLEFT"); mapShade:SetPoint("BOTTOMLEFT")
    mapShade:SetWidth(260)
    frame.map, frame.mapShade = map, mapShade
    -- the map runs on under the controls; a long, soft shade keeps the sliders readable
    local ctrlBg = header:CreateTexture(nil, "BACKGROUND", nil, 2)
    ctrlBg:SetTexture(Theme.WHITE)
    ctrlBg:SetPoint("TOPRIGHT"); ctrlBg:SetPoint("BOTTOMRIGHT")
    local ctrlFade = header:CreateTexture(nil, "BACKGROUND", nil, 2)
    ctrlFade:SetTexture(Theme.WHITE)
    ctrlFade:SetPoint("TOPRIGHT", ctrlBg, "TOPLEFT"); ctrlFade:SetPoint("BOTTOMRIGHT", ctrlBg, "BOTTOMLEFT")
    ctrlFade:SetWidth(220)
    local function fadeColors()
        local r, g, b = Theme.Color("header")
        if ctrlFade.SetGradient and CreateColor then
            ctrlFade:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.45))
            ctrlBg:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.45), CreateColor(r, g, b, 0.8))
        else
            ctrlFade:SetVertexColor(r, g, b, 0.25)
            ctrlBg:SetVertexColor(r, g, b, 0.6)
        end
    end
    fadeColors()
    Theme.OnApply(fadeColors)
    frame.ctrlBg, frame.ctrlFade = ctrlBg, ctrlFade
    frame.mapCredit = UI.Text(header, 9, "muted")
    frame.mapCredit:SetPoint("BOTTOMLEFT", 22, 5)
    frame.mapCredit:SetAlpha(0.7)
    frame.title = UI.Text(header, 21, "text")
    frame.title:SetPoint("LEFT", 22, 2)
    -- search in this page only (pages that offer page.Search): placed in the page area, see below
    local ps = UI.EditBox(frame, Window.SEARCH_W, Window.SEARCH_H, "")
    ps:SetTextInsets(28, 26, 0, 0)
    ps.icon = UI.Icon(ps, "search", 12, "textDim")
    ps.icon:SetPoint("LEFT", 10, 0)
    ps.placeholder:ClearAllPoints()
    ps.placeholder:SetPoint("LEFT", 28, 0)
    ps.placeholder:SetPoint("RIGHT", -26, 0)
    -- number of hits, right inside the field
    ps.count = UI.Text(ps, 10, "muted", "RIGHT", nil, true)
    ps.count:SetPoint("RIGHT", -26, 0)
    ps.clear = UI.IconButton(ps, "x", 20, function() ps:SetText(""); ps:ClearFocus() end)
    ps.clear:SetPoint("RIGHT", -3, 0)
    ps.clear.tip = L.SEARCH_CLEAR
    ps.clear:Hide()
    -- Enter: jump to the first match and mark it
    ps.onEnter = function()
        local page = current
        if not page then return end
        if page.SearchEnter then ns.Safe(page.SearchEnter)
        elseif page.searchList and page.searchList.rows[1] then page.searchList:JumpTo(page.searchList.rows[1].key) end
    end
    ps:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") end
        self:ClearFocus()
    end)
    ps.onChange = function(self, text)
        self.clear:SetShown(text ~= "")
        local page = current
        if not page or not page.Search or text == (page.query or "") then return end
        page.query = text
        ns.Debounce("lg-page-search", 0.12, function() if current == page then Window.RunPageSearch(page) end end)
    end
    frame.pageSearch = ps
    local accentLine = UI.Gradient(header, "accent", 0.9, "ARTWORK")
    accentLine:SetPoint("BOTTOMLEFT", 20, 0)
    accentLine:SetPoint("BOTTOMRIGHT", -20, 0)
    accentLine:SetHeight(1)

    local close = UI.IconButton(header, "x", 28, function() frame:Hide() end, true)
    close:SetPoint("RIGHT", -16, 0)
    close.tip = L.CLOSE
    local minimize = UI.IconButton(header, "minus", 28, function() Window.Collapse(not frame.collapsed) end)
    minimize:SetPoint("RIGHT", close, "LEFT", -6, 0)
    minimize.tip = L.MINIMIZE
    -- refresh: asks the guild for fresh data (profiles, versions, roster) and redraws
    local refreshBtn = UI.IconButton(header, "rotate-ccw", 28, function() if ns.RefreshData then ns.RefreshData() end end)
    refreshBtn:SetPoint("RIGHT", minimize, "LEFT", -6, 0)
    refreshBtn.tip = L.REFRESH
    refreshBtn.tipLines = { L.REFRESH_TIP }
    frame.refresh = refreshBtn
    frame.move = UI.Button(header, L.MOVE_ELEMENTS, 150, 28, function() Window.ToggleMovers() end, "move")
    frame.move:SetPoint("RIGHT", refreshBtn, "LEFT", -10, 0)
    frame.move.tip = { L.MOVE_ELEMENTS_TIP }
    frame.move.tipTitle = L.MOVE_ELEMENTS
    frame.move.fullText = L.MOVE_ELEMENTS

    -- three slim sliders: opacity, window scale, font size of every addon text
    local theme = settings().theme
    local function pct(v) return ("%d%%"):format(v * 100 + 0.5) end
    local function headerSlider(labelText, minV, maxV, get, set)
        local sld = UI.Slider(header, nil, minV, maxV, 0.05, get, set, pct)
        sld:SetSize(HEADER_SLIDER_W, 16)
        Theme.RegisterText(sld.value, 10, "text")
        Theme.SetFont(sld.value, Theme.Font(), Theme.FontSize(10), "")
        sld.value:SetWidth(32)
        local lbl = UI.Text(header, 10, "textDim", "RIGHT")
        lbl:SetText(labelText)
        return sld, lbl
    end
    local fontS, fontL = headerSlider(L.HEADER_FONT, 0.8, 1.4, function() return theme.fontScale or 1 end, function(v)
        theme.fontScale = v
        ns.Debounce("theme-apply", 0.3, Theme.Apply)
    end)
    local scale, scaleLabel = headerSlider(L.SCALE, 0.6, 1.4, function() return theme.windowScale or 1 end, function(v)
        theme.windowScale = v
        ns.Debounce("window-scale", 0.25, applyLook)
    end)
    local alpha, alphaLabel = headerSlider(L.OPACITY, 0.3, 1, function() return theme.windowAlpha or 1 end, function(v)
        theme.windowAlpha = v
        applyLook()
    end)
    -- right to left: font size, scale, opacity (Window.Responsive places them)
    frame.headerSliders = { fontS, scale, alpha }
    frame.headerParts = { { fontS, fontL }, { scale, scaleLabel }, { alpha, alphaLabel } }
    -- texts change width with the font size: lay the header out again
    Theme.OnApply(function() if frame and frame:IsShown() then Window.Responsive() end end)

    -------------------------------------------------------------------
    -- footer
    -------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    local fbg = UI.Fill(footer, "header")
    fbg:SetAllPoints()
    local fline = UI.Fill(footer, "borderDim", "ARTWORK")
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
    local hint = UI.Text(footer, 11, "muted")
    hint:SetPoint("LEFT", 22, 0)
    hint:SetText(L.FOOTER_HINT)
    local closeBtn = UI.Button(footer, L.CLOSE, 120, 30, function() frame:Hide() end)
    closeBtn:SetPoint("RIGHT", -18, 0)
    local reload = UI.Button(footer, L.RELOAD_UI, 120, 30, function() ReloadUI() end)
    reload:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    frame.footer = footer

    -------------------------------------------------------------------
    -- content
    -------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 20, -14)
    content:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -20, 12)
    -- pages never draw outside their area when the window gets small
    if content.SetClipsChildren then content:SetClipsChildren(true) end
    frame.content = content
    ps:SetParent(content)
    ps:SetFrameLevel(content:GetFrameLevel() + 200)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gt:SetAllPoints()
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); save() end)
    frame.grip = grip

    frame:HookScript("OnSizeChanged", function() Window.Responsive() end)
    -- the looping animations only run while the window is open
    frame:HookScript("OnHide", function() frame.flashAnim:Stop(); frame.shineAnim:Stop(); Window.ClearMark() end)
    frame:SetScript("OnShow", function()
        for _, s in ipairs(frame.headerSliders) do s:Refresh() end
        Window.UpdateStatus(true)
        frame.flashAnim:Play()
        frame.shineAnim:Play()
        Window.UpdateMoveButton()
        if current and current.OnShow then ns.Safe(current.OnShow, current) end
    end)
    Window.BuildNav()
    Window.Responsive()
    Window.SetUpdate(pendingUpdate)
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
-- Layout: group title in the accent colour, a thin line between the groups,
-- the open page with an accent bar and a soft accent fade (colours from the theme)
local NAV_ITEM_MAX, NAV_ITEM_MIN, NAV_HEAD_H, NAV_GAP = 30, 21, 24, 13
local function navItem(i)
    local b = frame.navItems[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame.nav)
    b:SetHeight(NAV_ITEM_MAX)
    b.sel = UI.Gradient(b, "accent", 0.30, "BACKGROUND")
    b.sel:SetAllPoints()
    b.bar = UI.Fill(b, "accent", "ARTWORK")
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
    b.hl = UI.Fill(b, "hover", "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(15, 15)
    b.icon:SetPoint("LEFT", 18, 0)
    b.text = UI.Text(b, 13, "textDim")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 11, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    -- small badge on the right (e.g. NEW for a page not opened yet)
    b.badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    UI.Skin(b.badge, "sidebar", "accentDim")
    b.badge:SetHeight(14)
    b.badge:SetPoint("RIGHT", -10, 0)
    b.badge.text = UI.Text(b.badge, 9, "accent", "CENTER", nil, true)
    b.badge.text:SetPoint("CENTER", 0, 0)
    b.badge:Hide()
    -- compact sidebar: the page name shows as tooltip
    b:SetScript("OnEnter", function(self) if frame.compact and self.page then UI.Tooltip(self, self.page.title) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.navItems[i] = b
    return b
end

function Window.BuildNav()
    if not frame then return end
    for _, b in ipairs(frame.navItems) do b:Hide() end
    for _, h in ipairs(frame.navHeads) do h:Hide() end
    for _, l in ipairs(frame.navLines) do l:Hide() end
    -- density: full size when it fits, tighter rows (down to 21 px) when the window is short
    local avail = frame.navScroll:GetHeight() or 0
    frame.navBuiltH = avail
    local count, groups = 0, 0
    for _, section in ipairs(Window.SECTIONS) do
        local k = 0
        for _, page in ipairs(pageList) do if page.section == section.key and Window.PageVisible(page) then k = k + 1 end end
        if k > 0 then count = count + k; groups = groups + 1 end
    end
    local headH = frame.compact and 0 or NAV_HEAD_H
    local gap = NAV_GAP
    local fixed = 6 + groups * headH + math.max(0, groups - 1) * gap
    local itemH = NAV_ITEM_MAX
    if avail > 50 and count > 0 then
        local fit = math.floor((avail - fixed) / count)
        -- short windows: the gaps shrink before the rows do
        if fit < 25 then gap = 7; fixed = 6 + groups * headH + math.max(0, groups - 1) * gap; fit = math.floor((avail - fixed) / count) end
        itemH = math.max(NAV_ITEM_MIN, math.min(NAV_ITEM_MAX, fit))
    end
    local y, n, heads = 6, 0, 0
    for _, section in ipairs(Window.SECTIONS) do
        local any = false
        for _, page in ipairs(pageList) do if page.section == section.key and Window.PageVisible(page) then any = true end end
        if any then
            if heads > 0 then
                -- a thin line between the groups
                local line = frame.navLines[heads]
                if not line then
                    line = UI.Fill(frame.nav, "borderDim", "ARTWORK")
                    line:SetHeight(1)
                    frame.navLines[heads] = line
                end
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", 14, -y - math.floor(gap / 2))
                line:SetPoint("TOPRIGHT", -14, -y - math.floor(gap / 2))
                line:Show()
                y = y + gap
            end
            heads = heads + 1
            local head = frame.navHeads[heads]
            if not head then
                head = UI.Text(frame.nav, 12, "accent", nil, nil, true)
                frame.navHeads[heads] = head
            end
            head:ClearAllPoints()
            head:SetPoint("LEFT", frame.nav, "TOPLEFT", 16, -y - headH / 2)
            head:SetText(ns.Upper(L[section.title]))
            head:SetShown(not frame.compact)
            y = y + headH
            for _, page in ipairs(pageList) do
                if page.section == section.key and Window.PageVisible(page) then
                    n = n + 1
                    local b = navItem(n)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 0, -y)
                    b:SetPoint("TOPRIGHT", -1, -y)
                    b.text:SetText(page.title)
                    b.text:SetShown(not frame.compact)
                    local badge = page.badge and ns.Call(page.badge)
                    if type(badge) == "string" and badge ~= "" and not frame.compact then
                        b.badge.text:SetText(badge)
                        b.badge:SetWidth(math.max(20, (b.badge.text:GetStringWidth() or 18) + 8))
                        b.badge:Show()
                    else
                        b.badge:Hide()
                    end
                    b.icon:ClearAllPoints()
                    if frame.compact then b.icon:SetPoint("CENTER", 1, 0) else b.icon:SetPoint("LEFT", 18, 0) end
                    Theme.SetIcon(b.icon, page.icon)
                    b.page = page
                    b:SetScript("OnClick", function() Window.Show(page.key) end)
                    b:SetHeight(itemH)
                    b:Show()
                    y = y + itemH
                end
            end
        end
    end
    y = y + 6
    frame.nav:SetHeight(math.max(1, y))
    if y <= avail then frame.navScroll:SetVerticalScroll(0) end
    Window.UpdateNav()
end

function Window.UpdateNav()
    if not frame then return end
    for _, b in ipairs(frame.navItems) do
        if b.page then
            local on = b.page == current
            b.sel:SetShown(on)
            b.bar:SetShown(on)
            b.text:SetTextColor(Theme.Color(on and "text" or "textDim"))
            b.icon:SetVertexColor(Theme.Color(on and "text" or "textDim"))
            if not on then b.icon:SetAlpha(0.85) else b.icon:SetAlpha(1) end
        end
    end
    if current then frame.title:SetText(current.title) end
    Window.UpdateMap()
    Window.LayoutPageSearch()
end

---------------------------------------------------------------------------
-- Collapse and movers
---------------------------------------------------------------------------
function Window.Collapse(on)
    if not frame then return end
    frame.collapsed = on
    local win = settings().window
    frame.content:SetShown(not on)
    frame.footer:SetShown(not on)
    frame.navScroll:SetShown(not on)
    frame.grip:SetShown(not on)
    -- collapsed: only the brand and the header stay
    frame.searchStrip:SetHeight(on and 0.1 or SEARCH_STRIP_H)
    frame.globalSearch:SetShown(not on)
    Window.LayoutPageSearch()
    if on then frame:SetHeight(HEADER_H + 8) else frame:SetHeight(win.h or 760) end
end

-- Responsive layout: narrow windows get an icon sidebar and a slimmer header
local COMPACT_SIDEBAR = 60
function Window.Responsive()
    if not frame then return end
    -- sidebar list follows the window height (tighter rows before it scrolls)
    local navH = frame.navScroll and frame.navScroll:GetHeight() or 0
    if navH > 0 and math.abs((frame.navBuiltH or 0) - navH) > 1 then Window.BuildNav() end
    local w = frame:GetWidth() or 1160
    local compact = w < 1040
    if compact ~= frame.compact then
        frame.compact = compact
        frame.side:SetWidth(compact and COMPACT_SIDEBAR or SIDEBAR_W)
        for _, t in ipairs(frame.brandTexts) do t:SetShown(not compact) end
        Window.SetUpdate(pendingUpdate)
        frame.status:SetHeight(compact and 0.1 or 40)
        for _, b in ipairs(frame.chips) do b:SetShown(not compact) end
        frame.crest:SetSize(compact and 40 or 52, compact and 40 or 52)
        frame.crest:ClearAllPoints()
        if compact then frame.crest:SetPoint("CENTER", 0, 0) else frame.crest:SetPoint("LEFT", 14, 0) end
        frame.placeSearch(compact)
        Window.BuildNav()
    end
    local headerW = w - (compact and COMPACT_SIDEBAR or SIDEBAR_W)
    Window.LayoutStatus()
    Window.CropMap(headerW)
    Window.UpdateStatus()
    local function lw(fs) return ((fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 60) end
    local small = headerW < 640
    local ctrlW = 16 + 28 * 3 + 12 + 10 + (small and 34 or 150)
    -- room left of the controls: title and page search come first, then the sliders (full, slim, or hidden)
    local titleW = (frame.title.GetUnboundedStringWidth and frame.title:GetUnboundedStringWidth()) or frame.title:GetStringWidth() or 120
    local wantSearch = 0
    local room = headerW - 22 - titleW - 18 - ctrlW - (wantSearch > 0 and (wantSearch + 22) or 0)
    -- as many sliders as fit (font size first, opacity last), each 96 px, else 72 px
    local parts = frame.headerParts
    local shown, sliderW = 0, HEADER_SLIDER_W
    for _, sw in ipairs({ HEADER_SLIDER_W, 72 }) do
        local need, n = 0, 0
        for _, p in ipairs(parts) do
            local add = 14 + sw + 6 + lw(p[2])
            if room >= need + add then need, n = need + add, n + 1 else break end
        end
        if n > shown then shown, sliderW = n, sw end
        if n == #parts then break end
    end
    local anchor = frame.move
    for i, p in ipairs(parts) do
        local on = i <= shown
        p[1]:SetShown(on); p[2]:SetShown(on)
        if on then
            if math.abs((p[1]:GetWidth() or 0) - sliderW) > 0.5 then p[1]:SetWidth(sliderW); p[1]:Refresh() end
            p[1]:ClearAllPoints()
            p[1]:SetPoint("RIGHT", anchor, "LEFT", -14, 0)
            p[2]:ClearAllPoints()
            p[2]:SetPoint("RIGHT", p[1], "LEFT", -6, 0)
            anchor = p[2]
            ctrlW = ctrlW + 14 + sliderW + 6 + lw(p[2])
        end
    end
    frame.ctrlBg:SetWidth(math.min(headerW - 120, ctrlW + 12))
    frame.headerW, frame.ctrlW = headerW, ctrlW
    Window.LayoutPageSearch()
    frame.move:SetWidth(small and 34 or 150)
    frame.move:SetText(small and "" or (frame.move.fullText or frame.move.label:GetText()))
    if frame.move.icon then
        frame.move.icon:ClearAllPoints()
        if small then frame.move.icon:SetPoint("CENTER") else frame.move.icon:SetPoint("RIGHT", frame.move.label, "LEFT", -6, 0) end
    end
end

---------------------------------------------------------------------------
-- Header map strips (one per page, chosen by page key, else by section)
---------------------------------------------------------------------------
Window.MAPS = {
    drowned = "The Drowned City", wetlands = "Excavation Site: Wetlands", lordaeron = "Ruins of Lordaeron",
    thanes = "Hall of Thanes", kroldok = "Krol'dok Stronghold", shaper = "Shaper's Terrace",
    blackmaw = "Blackmaw Hold", dalaran = "City of Dalaran",
}
Window.PAGE_MAPS = {
    roster = "drowned", versions = "drowned", guide = "dalaran", feed = "wetlands", community = "wetlands", coguild = "lordaeron",
    blessings = "kroldok", cooldowns = "kroldok", council = "thanes", attune = "thanes",
    professions = "shaper", stats = "blackmaw",
}
Window.SECTION_MAPS = { guild = "drowned", raid = "thanes", forever = "shaper", me = "blackmaw", settings = "dalaran" }
local MAP_ASPECT = 1024 / 128

function Window.MapFor(page)
    if not page then return nil end
    return page.map or Window.PAGE_MAPS[page.key] or Window.SECTION_MAPS[page.section]
end

function Window.UpdateMap()
    if not frame then return end
    local key = settings().theme.headerMaps ~= false and Window.MapFor(current) or nil
    local name = key and Window.MAPS[key]
    if name then
        frame.map:SetTexture(ns.media .. "Maps\\" .. key)
        frame.map:Show()
        frame.mapShade:Show()
        frame.mapCredit:Hide()
    else
        frame.map:Hide()
        frame.mapShade:Hide()
        frame.mapCredit:Hide()
    end
end

-- the strip keeps (roughly) its proportions: wide headers show a thinner slice, narrow ones less of the width
function Window.CropMap(headerW)
    -- full header width: the strip's own alpha fade then runs out under the controls
    local mw = math.max(200, headerW or 900)
    frame.map:SetWidth(mw)
    local aspect = mw / HEADER_H
    if aspect >= MAP_ASPECT then
        local vh = math.max(0.7, MAP_ASPECT / aspect) -- slight stretch instead of a too thin slice
        frame.map:SetTexCoord(0, 1, (1 - vh) / 2, (1 + vh) / 2)
    else
        frame.map:SetTexCoord(0, aspect / MAP_ASPECT, 0, 1)
    end
end

---------------------------------------------------------------------------
-- Sidebar status: online members, partner guild, new feed entries
---------------------------------------------------------------------------
function Window.LayoutStatus()
    if not frame or frame.compact then return end
    local w = frame.side:GetWidth() - 1
    local gap, pad = 4, 10
    local bw = math.floor((w - pad * 2 - gap * 2) / 3)
    for i, b in ipairs(frame.chips) do
        b:ClearAllPoints()
        b:SetWidth(bw)
        b:SetPoint("LEFT", frame.status, "LEFT", pad + (i - 1) * (bw + gap), 0)
    end
end

function Window.UpdateStatus(animate)
    if not frame or not frame:IsShown() then return end
    local total, online = 0, 0
    for _, m in pairs(ns.Guild and ns.Guild.members or {}) do
        total = total + 1
        if m.online then online = online + 1 end
    end
    local c1, c2, c3 = frame.chips[1], frame.chips[2], frame.chips[3]
    c1:SetText(("%d/%d"):format(online, total))
    c1.tipTitle, c1.tip = L.PAGE_ROSTER, { L.STATUS_ONLINE_TIP:format(online, total) }
    local partner = ns.CoGuild and ns.CoGuild.OnlineCount and ns.CoGuild.OnlineCount() or 0
    c2:SetText(partner > 0 and tostring(partner) or L.STATUS_PARTNER)
    c2.tipTitle, c2.tip = L.PAGE_COGUILD, { L.STATUS_PARTNER_TIP:format(partner) }
    local new = ns.Feed and ns.Feed.NewCount and ns.Feed.NewCount() or 0
    c3:SetText(L.STATUS_NEW:format(new))
    c3.tipTitle, c3.tip = L.PAGE_FEED, { L.STATUS_NEW_TIP }
    local w = frame.rail:GetWidth() or 0
    local fillW = math.max(1, total > 0 and w * online / total or 1)
    frame.railFill:SetWidth(fillW)
    frame.shineMove:SetOffset(fillW + 40, 0)
    frame.railFill:SetShown(online > 0)
    if animate then frame.railGrow:Stop(); frame.railGrow:Play() end
end

ns.On("LG_ROSTER", function() ns.Debounce("lg-status", 1, Window.UpdateStatus) end)
ns.On("LG_COGUILD", function() ns.Debounce("lg-status", 1, Window.UpdateStatus) end)

-- "Move elements": unlocks the cooldown displays and shows the preview
function Window.ToggleMovers()
    local cd = settings().cd
    local unlocking = cd.locked or not ns.Cooldowns.IsPreview()
    if unlocking then
        cd.locked = false
        ns.Cooldowns.SetPreview(true)
    else
        cd.locked = true
        ns.Cooldowns.SetPreview(false)
    end
    if ns.Movers then ns.Movers.SetActive(unlocking) end
    ns.Fire("LG_COOLDOWNS")
    Window.UpdateMoveButton()
end

function Window.UpdateMoveButton()
    if not frame then return end
    local active = not settings().cd.locked and ns.Cooldowns.IsPreview()
    frame.move.fullText = active and L.MOVE_DONE or L.MOVE_ELEMENTS
    frame.move:SetText(frame.compactMove and "" or frame.move.fullText)
    Window.Responsive()
    frame.move:SetBackdropBorderColor(Theme.Color(active and "accent" or "border"))
end

---------------------------------------------------------------------------
-- Page search (header): filters the current page
---------------------------------------------------------------------------
function Window.LayoutPageSearch()
    if not frame or not frame.pageSearch then return end
    local ps = frame.pageSearch
    local page = current
    if not page or not page.Search or frame.collapsed then ps:Hide(); return end
    -- always the same width, so the pages can keep exactly this corner free
    ps:SetWidth(Window.SEARCH_W)
    ps:ClearAllPoints()
    ps:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", page.head and -14 or 0, -(page.searchY or 0))
    ps:Show()
end

-- room a page leaves free in its top right corner for the page search
function Window.SearchReserve()
    return Window.SEARCH_RESERVE
end

function Window.UpdatePageSearch()
    if not frame or not frame.pageSearch then return end
    local ps, page = frame.pageSearch, current
    if page and page.Search then
        ps.placeholder:SetText(page.searchHint or L.SEARCH_PAGE:format(page.title))
        if ps:GetText() ~= (page.query or "") then ps:SetText(page.query or "") end
        ps.count:SetText("")
    end
    Window.LayoutPageSearch()
end

-- runs the page's search and shows its number of hits in the field
function Window.RunPageSearch(page)
    local n = ns.Try(page.Search, page.query or "")
    if not frame or current ~= page then return end
    local ps = frame.pageSearch
    local q = page.query or ""
    if q:find("%S") and type(n) == "number" then
        ps.count:SetText(n > 0 and L.SEARCH_HITS:format(n) or Theme.HexColor("warn", L.SEARCH_NO_HITS))
        ps:SetTextInsets(28, 26 + math.max(30, (ps.count:GetStringWidth() or 30) + 8), 0, 0)
    else
        ps.count:SetText("")
        ps:SetTextInsets(28, 26, 0, 0)
    end
end

-- fills the page search (e.g. from the global search) and runs it right away
function Window.SetPageSearch(text)
    local page = current
    if not page or not page.Search or not frame then return end
    page.query = text or ""
    frame.pageSearch:SetText(page.query)
    Window.RunPageSearch(page)
end

---------------------------------------------------------------------------
-- Search mark ("jump to"): one at a time; the next click in the window, a page
-- change or closing the window removes it
---------------------------------------------------------------------------
local clearMark
function Window.SetMark(fn)
    if clearMark then ns.Safe(clearMark) end
    clearMark = fn
    -- the click that picked the result must not remove the new mark
    Window.markSince = GetTime()
end
function Window.ClearMark()
    if clearMark then local fn = clearMark; clearMark = nil; ns.Safe(fn) end
end
ns.On("GLOBAL_MOUSE_DOWN", function()
    if not clearMark or not frame or not frame:IsShown() then return end
    if GetTime() - (Window.markSince or 0) < 0.3 then return end
    if frame:IsMouseOver() then Window.ClearMark() end
end)

---------------------------------------------------------------------------
-- Global search (sidebar): pages, settings, guide, commands, members, recipes
---------------------------------------------------------------------------
local LIMIT = 6
local CRUMB = "  ›  "   -- breadcrumb separator in the second line

-- 0 = starts with, 1 = word starts with, 2 = contains, nil = no match
local function score(text, q)
    text = (text or ""):lower()
    if q == "" then return 2 end
    local i = text:find(q, 1, true)
    if not i then return nil end
    if i == 1 then return 0 end
    -- word starts: also later in the text ("auto role" → "role")
    local pos = i
    while pos do
        if pos == 1 or text:sub(pos - 1, pos - 1):find("[%s%p]") then return 1 end
        pos = text:find(q, pos + 1, true)
    end
    -- in the middle of a word only from three letters on (short queries stay precise)
    return #q >= 3 and 2 or nil
end

local function sorted(list)
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return (a.sort or "") < (b.sort or "")
    end)
    return list
end

local function iconSetter(name, role)
    return function(tex)
        Theme.SetIcon(tex, name)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(Theme.Color(role or "bronze"))
    end
end

function Window.SearchEntries(q)
    q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    local function add(title, list, limit)
        if #list == 0 then return end
        out[#out + 1] = { head = title }
        for i = 1, math.min(#list, limit or LIMIT) do out[#out + 1] = list[i] end
    end
    local sectionTitle = {}
    for _, sec in ipairs(Window.SECTIONS) do sectionTitle[sec.key] = L[sec.title] end

    -- pages (all of them when nothing is typed: quick navigation)
    local list = {}
    for _, page in ipairs(pageList) do
        if Window.PageVisible(page) then
            local sc = score(page.title, q) or (q ~= "" and score(page.key, q))
            if sc then
                list[#list + 1] = { score = sc, sort = string.format("%03d", page.order), text = page.title,
                    sub = L.SEARCH_CRUMB_PAGE .. (sectionTitle[page.section] and (CRUMB .. sectionTitle[page.section]) or ""),
                    value = { kind = "page", key = page.key }, setIcon = iconSetter(page.icon) }
            end
        end
    end
    add(L.SEARCH_PAGES, sorted(list), q == "" and 99 or LIMIT)
    if q == "" then return out end

    -- settings (rows of every settings form): the same label in several places
    -- is one entry ("3 places: …") that opens to its places
    list = {}
    local groups, seen = {}, {}
    for _, form in ipairs(UI.forms or {}) do
        local page = form.page and pages[form.page]
        if page and not form.noIndex and Window.PageVisible(page) then
            local function offer(label, sc, card, isSection)
                if not sc then return end
                local id = page.key .. "\1" .. (card or "") .. "\1" .. label .. (isSection and "\1s" or "")
                if seen[id] then return end
                seen[id] = true
                local gk = (isSection and "s\1" or "r\1") .. label:lower()
                local g = groups[gk]
                if not g then
                    g = { label = label, isSection = isSection, score = sc, places = {} }
                    groups[gk] = g
                    list[#list + 1] = g
                end
                g.score = math.min(g.score, sc)
                local crumb = page.title .. ((not isSection and card and card ~= "") and (CRUMB .. card) or "")
                g.places[#g.places + 1] = { page = page, card = card, crumb = crumb,
                    value = { kind = "setting", key = page.key, label = label, form = form } }
            end
            for _, section in ipairs(form.sections) do
                -- the card itself ("Import / export", "Sound" …)
                if section.title ~= "" then offer(section.title, score(section.title, q), section.title, true) end
                for _, row in ipairs(section.rows) do
                    local label = row.label and row.label:GetText() or row.searchTitle
                    -- rows that are switched off for you (show = false) are not offered
                    if row.opts and row.opts.show and not row.opts.show() then label = nil end
                    if label and label ~= "" then
                        local sc = score(label, q)
                        if not sc and #q >= 3 and form.RowText(row):lower():find(q, 1, true) then sc = 3 end
                        offer(label, sc, section.title)
                    end
                    -- buttons are settings, too ("Export", "Test sound" …)
                    for _, btn in ipairs(row.buttons or {}) do
                        local t = btn.label and btn.label:GetText()
                        if t and t ~= "" then offer(t, score(t, q), section.title) end
                    end
                end
            end
        end
    end
    for i, g in ipairs(list) do
        local prefix = g.isSection and L.SEARCH_SECTION or nil
        local icon = iconSetter(g.isSection and "layout-grid" or "settings", "muted")
        local e = { score = g.score, sort = g.label, text = g.label, prefix = prefix, setIcon = icon }
        if #g.places == 1 then
            e.sub, e.value = g.places[1].crumb, g.places[1].value
        else
            -- "3 places: Unit Frames, Raid" – pages, or the cards when it is one page
            local names, have, pagesN = {}, {}, {}
            for _, pl in ipairs(g.places) do if not pagesN[pl.page.key] then pagesN[pl.page.key] = true; pagesN[#pagesN + 1] = pl.page.title end end
            local byCard = #pagesN == 1
            for _, pl in ipairs(g.places) do
                local n = byCard and (pl.card ~= "" and pl.card or pl.page.title) or pl.page.title
                if not have[n] then have[n] = true; names[#names + 1] = n end
            end
            e.sub = L.SEARCH_PLACES:format(#g.places, table.concat(names, ", "))
            e.children = {}
            for _, pl in ipairs(g.places) do
                e.children[#e.children + 1] = { text = g.label, prefix = prefix, sub = pl.crumb, value = pl.value, setIcon = icon }
            end
        end
        list[i] = e
    end
    add(L.SEARCH_SETTINGS, sorted(list), 6)

    -- guide topics
    list = {}
    for _, e in ipairs(ns.Guide and ns.Guide.LIST or {}) do
        local sc = score(e.name, q)
        if not sc and #q >= 3 and (e.sum or ""):lower():find(q, 1, true) then sc = 3 end
        if sc then
            list[#list + 1] = { score = sc, sort = e.name, text = e.name,
                sub = L.PAGE_GUIDE .. (sectionTitle[e.section] and (CRUMB .. sectionTitle[e.section]) or ""),
                value = { kind = "guide", key = e.key }, setIcon = iconSetter(e.icon) }
        end
    end
    add(L.SEARCH_GUIDE, sorted(list), 4)

    -- members of the guild
    list = {}
    for key, m in pairs(ns.Guild and ns.Guild.members or {}) do
        local name = ns.Names.Display(m.name or key)
        local sc = score(name, q)
        if sc then
            local r, g, b = ns.ClassColor(m.class)
            local info = {}
            if m.level then info[#info + 1] = L.SEARCH_LEVEL:format(m.level) end
            if m.class then info[#info + 1] = ns.ClassName and ns.ClassName(m.class) or m.class end
            if m.rank then info[#info + 1] = m.rank end
            list[#list + 1] = { score = sc + (m.online and 0 or 0.5), sort = name, text = ns.ColorName(name, m.class),
                sub = L.SEARCH_CRUMB_MEMBER .. (#info > 0 and (CRUMB .. table.concat(info, " · ")) or ""),
                tag = m.online and L.SEARCH_ONLINE or nil,
                value = { kind = "member", key = key },
                setIcon = function(tex)
                    tex:SetVertexColor(1, 1, 1)
                    if not ns.SetSpecIcon(tex, m.class, ns.SpecPoints(ns.Database.Member(key))) then tex:SetTexture(nil) end
                end, border = { r * 0.6, g * 0.6, b * 0.6 } }
        end
    end
    add(L.SEARCH_MEMBERS, sorted(list), 5)

    -- commands
    list = {}
    for _, g in ipairs(ns.Commands or {}) do
        for _, c in ipairs(g.commands) do
            local text = ns.CommandText(c, g)
            local sc = score(c.cmd, q) or score(text, q)
            if not sc and #q >= 3 and (c.desc or ""):lower():find(q, 1, true) then sc = 3 end
            if g.key == "test" and sc and not q:find("test", 1, true) then sc = sc + 1 end
            if sc then
                list[#list + 1] = { score = sc, sort = text, hlRole = "text", text = Theme.HexColor("accent", text), sub = c.desc,
                    value = { kind = "command", c = c, g = g }, setIcon = iconSetter("chevron-right", "accent") }
            end
        end
    end
    add(L.SEARCH_COMMANDS, sorted(list), 5)

    -- recipes: hands the text to the crafting search
    if #q >= 3 and Window.PageVisible(pages.professions or { hidden = true }) then
        add(L.SEARCH_RECIPES, { { text = L.SEARCH_RECIPES_FOR:format(q), sub = L.PAGE_PROFESSIONS .. CRUMB .. L.SEARCH_CRUMB_CRAFT,
            value = { kind = "recipe", q = q }, setIcon = iconSetter("hammer") } })
    end
    if #out == 0 then
        out[1] = { head = L.SEARCH_NOTHING:format(q) }
    end
    return out
end

function Window.PickSearch(v)
    if type(v) ~= "table" then return end
    if v.kind == "page" then
        Window.Show(v.key)
    elseif v.kind == "setting" then
        -- jump there: the whole page stays visible, the setting is scrolled into view and flashes
        Window.Show(v.key)
        if (pages[v.key].query or "") ~= "" then Window.SetPageSearch("") end
        if v.form and v.form.reveal then ns.Safe(v.form.reveal) end
        if not (v.form and v.form.JumpTo and v.form:JumpTo(v.label)) then Window.SetPageSearch(v.label) end
    elseif v.kind == "guide" then
        ns.Guide.Open(v.key)
    elseif v.kind == "member" then
        Window.Show("roster")
        if (pages.roster.query or "") ~= "" then Window.SetPageSearch("") end
        if ns.Roster and ns.Roster.JumpTo then ns.Roster.JumpTo(v.key) end
    elseif v.kind == "command" then
        local c, g = v.c, v.g
        if g.chat or (c.args and c.args:sub(1, 1) == "<") then
            local text = ns.CommandText(c, g):gsub("%s*[<%[].*$", "")
            if ChatFrame_OpenChat then ChatFrame_OpenChat(text .. " ") end
        elseif g.runnable and c.run then
            ns.Safe(c.run, "")
        else
            ns.HandleSlash(c.cmd)
        end
    elseif v.kind == "recipe" then
        ns.HandleSlash("craft " .. v.q)
    end
end

function Window.OpenSearch(text)
    if not frame or not frame:IsShown() then Window.Show() end
    if frame.collapsed then Window.Collapse(false) end
    Window.BuildAll()
    local gs = frame.globalSearch
    UI.SearchMenu(gs, {
        width = 440, twoLine = true, placeholder = L.SEARCH_ALL, text = text, hint = L.SEARCH_KEYS,
        point = { "TOPLEFT", "TOPLEFT", -8, 8 },
        build = Window.SearchEntries, onPick = Window.PickSearch,
    })
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
Window.HEAD_H = 60
function Window.PageHead(page)
    local band = CreateFrame("Frame", nil, frame.content)
    band:SetHeight(Window.HEAD_H)
    local bg = UI.Gradient(band, "accent", 0.10, "BACKGROUND")
    bg:SetAllPoints()
    local line = UI.Gradient(band, "accent", 0.9, "ARTWORK")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT", band, "BOTTOM", 0, 0)
    line:SetHeight(1)
    local box = CreateFrame("Frame", nil, band, "BackdropTemplate")
    box:SetSize(40, 40)
    box:SetPoint("LEFT", 10, 0)
    UI.Skin(box, "input", "border")
    local icon = UI.Icon(box, page.icon or "settings", 22, "accent")
    icon:SetPoint("CENTER")
    local title = UI.Text(band, 18, "text", "LEFT", nil, true)
    title:SetPoint("TOPLEFT", box, "TOPRIGHT", 14, -2)
    title:SetText(page.title or "")
    local sub = UI.Text(band, 11, "muted", "LEFT")
    sub:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 14, 3)
    sub:SetWordWrap(false)
    band:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then sub:SetWidth(math.max(60, w - 68 - Window.SEARCH_W - 40)) end
    end)
    sub:SetText(page.head == true and "" or page.head)
    band.title, band.sub = title, sub
    return band
end

local function build(page)
    if page.frame then return end
    page.frame = CreateFrame("Frame", nil, frame.content)
    page.frame:SetAllPoints()
    Window.building = page.key
    ns.Safe(page.builder, page.frame, page)
    Window.building = nil
    -- settings pages: a head with icon, title and what the page is for; the
    -- page search sits on its right
    if page.head then
        local band = Window.PageHead(page)
        page.frame:ClearAllPoints()
        page.frame:SetPoint("TOPLEFT", 0, -(Window.HEAD_H + 12))
        page.frame:SetPoint("BOTTOMRIGHT")
        band:SetParent(page.frame)
        band:SetPoint("TOPLEFT", frame.content, "TOPLEFT")
        band:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT")
        page.searchY = math.floor((Window.HEAD_H - Window.SEARCH_H) / 2)
    -- pages without a top row of their own give the page search a row above them
    elseif page.searchRow then
        page.frame:ClearAllPoints()
        page.frame:SetPoint("TOPLEFT", 0, -(Window.SEARCH_H + 10))
        page.frame:SetPoint("BOTTOMRIGHT")
    end
end

-- builds every visible page once (hidden), so the search knows all settings
function Window.BuildAll()
    if not frame then create() end
    if frame.allBuilt then return end
    frame.allBuilt = true
    for _, page in ipairs(pageList) do
        if not page.frame and Window.PageVisible(page) then
            build(page)
            if page ~= current then page.frame:Hide() end
        end
    end
end

function Window.Show(key)
    if not frame then create() end
    local page = pages[key or (current and current.key) or ""] or current or pageList[1]
    if not page then return end
    if frame.collapsed then Window.Collapse(false) end
    if current and current ~= page and current.frame then current.frame:Hide(); Window.ClearMark() end
    current = page
    build(page)
    page.frame:Show()
    Window.UpdateNav()
    Window.Responsive()
    Window.UpdatePageSearch()
    if frame:IsShown() then
        if page.OnShow then ns.Safe(page.OnShow, page) end
    else
        frame:Show()
    end
end

-- a module page with its "Settings" tab open
function Window.ShowSettings(key)
    Window.Show(key)
    local page = pages[key]
    if page and page.ShowSettings then ns.Safe(page.ShowSettings) end
end

function Window.Toggle(key)
    if frame and frame:IsShown() and (not key or (current and current.key == key)) then
        frame:Hide()
    else
        Window.Show(key)
    end
end

function Window.IsShown(key)
    return frame and frame:IsShown() and (not key or (current and current.key == key))
end

function Window.Refresh(key)
    if Window.IsShown(key) and current.OnShow then ns.Safe(current.OnShow, current) end
end

ns.On("LG_THEME", function()
    if not frame then return end
    applyLook()
    Window.UpdateNav()
    Window.UpdateMoveButton()
    if frame:IsShown() and current and current.OnShow then ns.Safe(current.OnShow, current) end
end)
ns.On("LG_COOLDOWNS", function() Window.UpdateMoveButton() end)

-- Addon compartment (retail-style addon menu)
function LiebeGruesse_OnCompartmentClick() Window.Toggle() end
function LiebeGruesse_OnCompartmentEnter(_, button)
    UI.Tooltip(button or UIParent, ns.title, { L.MINIMAP_TIP })
end
function LiebeGruesse_OnCompartmentLeave() GameTooltip:Hide() end
