-- Module settings live in the module's own page, in a tab "Settings".
--   UI.SettingsPane(parent, fill)                 -- a settings form as tab content (pages with tabs)
--   local content, tabs = UI.PageWithSettings(root, page, mainTitle, fill)
--   ... build the page in content ... ; tabs.Finish()   -- pages without tabs
-- fill(form) adds the sections. The page search covers both tabs, the global
-- search jumps into the settings tab, ns.Window.ShowSettings(key) opens it.
local _, ns = ...
local UI, L = ns.UI, ns.L

function UI.SettingsPane(parent, fill)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    local form = UI.Form(pane)
    form.scroll:SetPoint("TOPLEFT")
    form.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    ns.Safe(fill, form)
    form:Layout()
    pane.form = form
    pane.Refresh = function() form:Refresh() end
    pane.SearchHits = function(q) return form:Filter(q) end
    pane.SearchApply = function(q) form:Filter(q) end
    pane:Hide()
    return pane
end

local TAB_H = 34

function UI.PageWithSettings(root, page, mainTitle, fill)
    local holder = CreateFrame("Frame", nil, root)
    holder:SetPoint("TOPLEFT", 0, -TAB_H)
    holder:SetPoint("BOTTOMRIGHT")
    local main = CreateFrame("Frame", nil, holder)
    main:SetAllPoints()
    local pane = UI.SettingsPane(holder, fill)
    local tabs = { main = main, settings = pane }
    local ctl = { main = main, settings = pane }
    local bar = UI.SubTabs(root, { { key = "main", title = mainTitle }, { key = "settings", title = L.SETTINGS_TAB } }, function(key)
        main:SetShown(key == "main")
        pane:SetShown(key == "settings")
        if key == "settings" then pane.Refresh() elseif ctl.mainShow then ns.Safe(ctl.mainShow, page) end
    end)
    -- the top right corner belongs to the page search
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -ns.Window.SearchReserve(), 0)
    bar:Select("main")
    ctl.bar = bar

    -- after the page is built: page search and OnShow cover both tabs
    function ctl.Finish()
        local mainSearch, mainShow, mainEnter = page.Search, page.OnShow, page.SearchEnter
        ctl.mainShow = mainShow
        main.SearchHits = function(q) return mainSearch and (tonumber(mainSearch(q)) or 0) or 0 end
        main.SearchApply = function(q) if mainSearch then mainSearch(q) end end
        page.Search = function(q)
            if not (q or ""):find("%S") then
                if mainSearch then mainSearch(q or "") end
                pane.form:Filter("")
                bar:SetHits("main", nil); bar:SetHits("settings", nil)
                return 0
            end
            return UI.TabSearch(bar, tabs, q)
        end
        page.SearchEnter = function()
            if bar.current == "settings" then pane.form:JumpFirst() elseif mainEnter then mainEnter() end
        end
        -- the main tab is kept up to date also behind the settings (its search reads it)
        page.OnShow = function(...)
            if mainShow then mainShow(...) end
            if bar.current == "settings" then pane.Refresh() end
        end
        page.ShowSettings = function() bar:Select("settings") end
        page.ShowMain = function() bar:Select("main") end
        pane.form.reveal = page.ShowSettings
    end
    return main, ctl
end
