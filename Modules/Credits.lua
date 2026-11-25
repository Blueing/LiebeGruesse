-- Credits page: the addon, the map strips (with their author), the font and
-- where the license texts are.
local _, ns = ...
local UI, Theme, L = ns.UI, ns.Theme, ns.L

local Credits = {}
ns.Credits = Credits

local function card(parent, title, right)
    local c = UI.Panel(parent, "panel", "borderDim")
    c.right = UI.Text(c, 10, "muted", "RIGHT")
    c.right:SetPoint("TOPRIGHT", -12, -11)
    c.right:SetText(right or "")
    c.title = UI.CardTitle(c, title, c.right)
    return c
end

UI.AddPage("credits", L.PAGE_CREDITS, 98, function(content, page)
    local scroll, body = UI.ScrollArea(content)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -8, 0)

    -- hero: crest, name, version, one line about the guild
    local hero = UI.Panel(body, "panel", "borderDim")
    hero:SetHeight(124)
    UI.Corners(hero)
    local glow = UI.Gradient(hero, "lapis", 0.12, "BORDER")
    glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1)
    hero.crest = hero:CreateTexture(nil, "ARTWORK")
    hero.crest:SetTexture(ns.media .. "logo")
    hero.crest:SetSize(96, 96)
    hero.crest:SetPoint("LEFT", 22, 0)
    hero.name = UI.Text(hero, 30, "text")
    hero.name:SetPoint("TOPLEFT", hero.crest, "TOPRIGHT", 20, -14)
    hero.name:SetText("Liebe " .. Theme.HexColor("gold", "Grüße") .. " " .. Theme.HexColor("textDim", "Guild Tools"))
    hero.version = UI.Text(hero, 13, "textDim")
    hero.version:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -6)
    hero.line = UI.Text(hero, 13, "textDim")
    hero.line:SetPoint("TOPLEFT", hero.version, "BOTTOMLEFT", 0, -4)
    hero.line:SetText(L.CREDITS_GUILD)

    -- map strips: every map with its page, then the author
    local maps = card(body, L.CREDITS_MAPS, L.CREDITS_MAPS_COUNT:format(8))
    local MAPS = ns.Window.MAPS
    local ORDER = { { "drowned", "PAGE_ROSTER" }, { "wetlands", "PAGE_FEED" }, { "lordaeron", "PAGE_COGUILD" }, { "thanes", "PAGE_COUNCIL" },
        { "kroldok", "PAGE_BLESSINGS" }, { "shaper", "PAGE_PROFESSIONS" }, { "blackmaw", "PAGE_STATS" }, { "dalaran", "CREDITS_SETTINGS" } }
    maps.thumbs = {}
    for i, def in ipairs(ORDER) do
        local t = CreateFrame("Frame", nil, maps)
        t.edge = UI.Fill(t, "borderDim", "BORDER")
        t.base = UI.Fill(t, "bg", "BORDER")
        t.img = t:CreateTexture(nil, "ARTWORK")
        t.img:SetTexture(ns.media .. "Maps\\" .. def[1])
        t.img:SetTexCoord(0.04, 0.40, 0, 1)
        t.img:SetPoint("TOPLEFT"); t.img:SetPoint("TOPRIGHT")
        t.img:SetHeight(54)
        t.edge:SetPoint("TOPLEFT", t.img, "TOPLEFT", -1, 1); t.edge:SetPoint("BOTTOMRIGHT", t.img, "BOTTOMRIGHT", 1, -1)
        t.base:SetAllPoints(t.img)
        t.name = UI.Text(t, 12, "text")
        t.name:SetPoint("TOPLEFT", t.img, "BOTTOMLEFT", 0, -5)
        t.name:SetText(MAPS[def[1]] or def[1])
        t.page = UI.Text(t, 11, "muted")
        t.page:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -2)
        t.page:SetText(L.CREDITS_MAP_PAGE:format(L[def[2]] or def[2]))
        maps.thumbs[i] = t
    end
    maps.rule = UI.Fill(maps, "borderDim", "ARTWORK"); maps.rule:SetHeight(1)
    maps.star = UI.Icon(maps, "star", 16, "bronze")
    maps.author = UI.Text(maps, 13, "textDim")
    maps.author:SetWordWrap(true)
    maps.author:SetJustifyV("TOP")
    maps.author:SetText(L.CREDITS_MAPS_AUTHOR)

    -- font
    local font = card(body, L.CREDITS_FONT)
    font.sample = UI.Text(font, 26, "text", "LEFT", nil, true)
    font.sample:SetText("Barlow Condensed")
    font.text = UI.Text(font, 15, "textDim", "LEFT", nil, false)
    font.text:SetText(L.CREDITS_FONT_TEXT)
    font.lic = UI.Text(font, 11, "muted")
    font.lic:SetText("The Barlow Project Authors · SIL Open Font License 1.1")

    -- licenses
    local lic = card(body, L.CREDITS_LICENSES)
    lic.text = UI.Text(lic, 12, "textDim")
    lic.text:SetWordWrap(true)
    lic.text:SetJustifyV("TOP")
    lic.text:SetText(L.CREDITS_LICENSES_TEXT)

    -- thanks
    local thanks = card(body, L.CREDITS_THANKS)
    thanks.text = UI.Text(thanks, 12, "textDim")
    thanks.text:SetWordWrap(true)
    thanks.text:SetJustifyV("TOP")
    thanks.text:SetText(L.CREDITS_THANKS_TEXT)
    thanks.news = UI.Button(thanks, L.CREDITS_WHATS_NEW, 120, 26, function() if ns.WhatsNew then ns.WhatsNew.Show(nil, true) end end, "newspaper")
    thanks.help = UI.Button(thanks, L.PAGE_HELP, 120, 26, function() ns.Window.Show("help") end, "book-open")

    local function wrapH(fs, x, y, w)
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, y); fs:SetWidth(w)
        return fs:GetStringHeight() or 14
    end

    function Credits.Fill()
        local W = math.max(420, (scroll:GetWidth() or 900) - 4)
        hero.version:SetText(L.CREDITS_VERSION:format(ns.version))
        hero:ClearAllPoints(); hero:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0); hero:SetWidth(W)
        local stacked = W < 860
        local sideW = stacked and W or 330
        local mainW = stacked and W or (W - sideW - 10)

        -- map grid: 4 columns, 2 when narrow
        local cols = mainW >= 560 and 4 or 2
        local gap = 12
        local tw = math.floor((mainW - 24 - (cols - 1) * gap) / cols)
        for i, t in ipairs(maps.thumbs) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", maps, "TOPLEFT", 12 + col * (tw + gap), -38 - row * 100)
            t:SetSize(tw, 92)
            t.name:SetWidth(tw); t.page:SetWidth(tw)
        end
        local my = 38 + math.ceil(#maps.thumbs / cols) * 100 + 2
        maps.rule:ClearAllPoints(); maps.rule:SetPoint("TOPLEFT", 12, -my); maps.rule:SetWidth(mainW - 24)
        maps.star:ClearAllPoints(); maps.star:SetPoint("TOPLEFT", 12, -(my + 12))
        local ah = wrapH(maps.author, 36, -(my + 12), mainW - 48)
        maps:ClearAllPoints(); maps:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -134)
        maps:SetWidth(mainW); maps:SetHeight(my + 12 + math.max(16, ah) + 14)

        -- side cards
        local sx = stacked and 0 or (mainW + 10)
        local sy = stacked and (134 + maps:GetHeight() + 10) or 134
        local inner = sideW - 24
        local function place(c, h)
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", body, "TOPLEFT", sx, -sy); c:SetWidth(sideW); c:SetHeight(h)
            sy = sy + h + 10
        end
        font.sample:ClearAllPoints(); font.sample:SetPoint("TOPLEFT", 12, -36); font.sample:SetWidth(inner)
        font.text:ClearAllPoints(); font.text:SetPoint("TOPLEFT", 12, -66); font.text:SetWidth(inner)
        font.lic:ClearAllPoints(); font.lic:SetPoint("TOPLEFT", 12, -90); font.lic:SetWidth(inner)
        place(font, 112)
        place(lic, 38 + wrapH(lic.text, 12, -38, inner) + 14)
        local th = 38 + wrapH(thanks.text, 12, -38, inner) + 10
        thanks.news:ClearAllPoints(); thanks.news:SetPoint("TOPLEFT", 12, -th)
        thanks.help:ClearAllPoints(); thanks.help:SetPoint("LEFT", thanks.news, "RIGHT", 6, 0)
        place(thanks, th + 38)

        body:SetHeight(math.max(134 + maps:GetHeight(), sy) + 12)
        scroll.UpdateBar()
    end

    -- page search: maps, font, licenses and thanks – matches are marked, other maps fade
    page.searchRow = true
    local texts = {
        { maps.author, L.CREDITS_MAPS_AUTHOR }, { font.text, L.CREDITS_FONT_TEXT }, { lic.text, L.CREDITS_LICENSES_TEXT },
        { thanks.text, L.CREDITS_THANKS_TEXT }, { hero.line, L.CREDITS_GUILD },
    }
    page.Search = function(text)
        local q = (text or ""):find("%S") and text or nil
        local hits = 0
        for i, t in ipairs(maps.thumbs) do
            local name, pg = MAPS[ORDER[i][1]] or ORDER[i][1], L.CREDITS_MAP_PAGE:format(L[ORDER[i][2]] or ORDER[i][2])
            t.name:SetText(q and ns.Highlight(name, q) or name)
            t.page:SetText(q and ns.Highlight(pg, q) or pg)
            if q and ns.SearchAny(name .. " " .. pg, q) then hits = hits + 1 end
        end
        for _, t in ipairs(texts) do
            t[1]:SetText(q and ns.Highlight(t[2], q) or t[2])
            if q and ns.SearchAny(t[2], q) then hits = hits + 1 end
        end
        return hits
    end
    scroll:HookScript("OnSizeChanged", function() ns.Debounce("credits-layout", 0.05, Credits.Fill) end)
    page.OnShow = function() Credits.Fill() end
end, { section = "settings", icon = "star" })
