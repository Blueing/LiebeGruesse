-- Virtual list with sortable column headers
local _, ns = ...
local UI, Theme = ns.UI, ns.Theme

--[[ opts:
  columns = { { key=, title=, width= (or flex=true), align=, text=fn(row)->string,
                sort=fn(row)->value, icon=fn(row)->texture } }
  column extras: onClick=fn(row, button, cell) makes the cell its own button,
                 tip=fn(row) -> title, lines   (tooltip for clickable cells)
  rowHeight, onClick(row, button, frame), onEnter(frame, row), isSelected(row), noHeader
  sortKey, sortDesc
]]
function UI.List(parent, opts)
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- nothing may draw outside the list (narrow windows)
    if list.SetClipsChildren then list:SetClipsChildren(true) end
    list.opts = opts
    -- the page this list was built on: its page search marks matches and explains an empty result
    list.page = ns.Window and ns.Window.building
    list.rows, list.offset = {}, 0
    list.rowHeight = opts.rowHeight or 26
    list.sortKey, list.sortDesc = opts.sortKey, opts.sortDesc
    local headerHeight = opts.noHeader and 0 or 28
    -- tables get their own dark frame, unless they already sit inside a card
    local framed = opts.frame
    if framed == nil then framed = not (parent.GetBackdrop and parent:GetBackdrop()) end
    local inset = framed and 1 or 0
    local pad = framed and 12 or 4
    if framed then UI.Skin(list, "bg", "borderDim") end

    list.header = CreateFrame("Frame", nil, list)
    list.header:SetPoint("TOPLEFT", inset, -inset)
    list.header:SetPoint("TOPRIGHT", -10 - inset, -inset)
    list.header:SetHeight(headerHeight)
    list.header.cells = {}

    list.body = CreateFrame("Frame", nil, list)
    list.body:SetPoint("TOPLEFT", inset, -headerHeight - inset)
    list.body:SetPoint("BOTTOMRIGHT", -10 - inset, inset)
    list.body:EnableMouseWheel(true)
    list.lines = {}

    list.bar = CreateFrame("Slider", nil, list, "BackdropTemplate")
    list.bar:SetPoint("TOPRIGHT", -inset - 2, -headerHeight - inset)
    list.bar:SetPoint("BOTTOMRIGHT", -inset - 2, inset)
    list.bar:SetWidth(4)
    UI.Skin(list.bar, "bg", "bg")
    list.bar:SetOrientation("VERTICAL")
    list.bar:SetThumbTexture(Theme.WHITE)
    local thumb = list.bar:GetThumbTexture()
    thumb:SetVertexColor(Theme.Color("borderDim"))
    Theme.RegisterFill(thumb, "borderDim")
    thumb:SetSize(4, 30)
    list.bar:SetMinMaxValues(0, 0)
    list.bar:SetValueStep(1)
    list.bar:SetObeyStepOnDrag(true)
    list.bar:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= list.offset then list.offset = value; list:Draw() end
    end)

    list.body:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #list.rows - list:Visible())
        list.offset = math.min(max, math.max(0, list.offset - delta * 3))
        list.bar:SetValue(list.offset)
        list:Draw()
    end)

    -- flex = true (weight 1) or a number (weight); minWidth keeps a flexible column readable.
    -- optional = n: when the list is too narrow, optional columns disappear (highest n first)
    local function visibleColumns(total)
        local hidden = {}
        local function need()
            local sum = pad + 2
            for i, col in ipairs(opts.columns) do
                if not hidden[i] then sum = sum + (col.flex and (col.minWidth or 40) or (col.width or 80)) end
            end
            return sum
        end
        while need() > total do
            local best, bestPrio
            for i, col in ipairs(opts.columns) do
                if col.optional and not hidden[i] and (not bestPrio or col.optional > bestPrio) then best, bestPrio = i, col.optional end
            end
            if not best then break end
            hidden[best] = true
        end
        return hidden
    end
    local function layoutCells(cells, parentFrame)
        local total = parentFrame:GetWidth()
        if not total or total <= 0 then return end
        local hidden = visibleColumns(total)
        local fixed, weights = 0, 0
        for i, col in ipairs(opts.columns) do
            if not hidden[i] then
                if col.flex then weights = weights + (col.flex == true and 1 or col.flex) else fixed = fixed + (col.width or 80) end
            end
        end
        local room = math.max(0, total - fixed - 2 - pad)
        local x = pad
        for i, col in ipairs(opts.columns) do
            local cell = cells[i]
            if hidden[i] then
                cell:Hide()
            else
                local w = col.width or 80
                if col.flex then
                    local weight = col.flex == true and 1 or col.flex
                    w = math.max(col.minWidth or 40, weights > 0 and room * weight / weights or 0)
                end
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", parentFrame, "LEFT", x, 0)
                cell:SetWidth(math.max(1, w - 6))
                cell:Show()
                x = x + w
            end
        end
    end

    for i, col in ipairs(opts.columns) do
        local h = CreateFrame("Button", nil, list.header)
        h:SetHeight(headerHeight)
        h.text = UI.Text(h, 11, "muted", col.align or "LEFT", nil, true)
        h.text:SetAllPoints()
        h.text:SetText((col.title or ""):upper())
        -- sort direction next to the active column title
        h.sort = UI.Icon(h, "chevron-down", 9, "accent")
        h.sort:Hide()
        h:SetScript("OnClick", function()
            if not col.sort and not col.text then return end
            if list.sortKey == col.key then list.sortDesc = not list.sortDesc
            else list.sortKey, list.sortDesc = col.key, col.defaultDesc or false end
            list:Sort(); list:Draw()
        end)
        h:SetScript("OnSizeChanged", function(self) if list.UpdateHeader then list:UpdateHeader() end end)
        list.header.cells[i] = h
    end
    if headerHeight > 0 then
        local line = UI.Divider(list.header)
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
    end

    function list:UpdateHeader()
        for i, col in ipairs(opts.columns) do
            local h = self.header.cells[i]
            if h then
                local active = self.sortKey == col.key and (col.sort or col.text) and (col.title or "") ~= ""
                h.text:SetTextColor(Theme.Color(active and "accent" or "muted"))
                h.sort:SetShown(active and true or false)
                if active then
                    local w = h.text:GetStringWidth() or 0
                    h.sort:ClearAllPoints()
                    if col.align == "RIGHT" then h.sort:SetPoint("RIGHT", h, "RIGHT", -w - 4, 0)
                    elseif col.align == "CENTER" then h.sort:SetPoint("LEFT", h, "CENTER", w / 2 + 3, 0)
                    else h.sort:SetPoint("LEFT", h, "LEFT", w + 4, 0) end
                    if self.sortDesc then h.sort:SetTexCoord(0, 1, 0, 1) else h.sort:SetTexCoord(0, 1, 1, 0) end
                end
            end
        end
    end

    function list:Visible()
        return math.max(1, math.floor((self.body:GetHeight() or 0) / self.rowHeight))
    end

    function list:Line(i)
        local line = self.lines[i]
        if line then return line end
        line = CreateFrame("Button", nil, self.body)
        line:SetHeight(self.rowHeight)
        line:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowHeight)
        line:SetPoint("TOPRIGHT", 0, -(i - 1) * self.rowHeight)
        line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        line.bg = UI.Fill(line, (i % 2 == 0) and "rowAlt" or "row", "BACKGROUND")
        line.bg:SetAllPoints()
        line.sel = UI.Fill(line, "selected", "BORDER")
        line.sel:SetAllPoints()
        line.selBar = UI.Fill(line, "accent", "ARTWORK")
        line.selBar:SetPoint("TOPLEFT"); line.selBar:SetPoint("BOTTOMLEFT"); line.selBar:SetWidth(2)
        line.hl = UI.Fill(line, "hover", "HIGHLIGHT")
        line.hl:SetAllPoints()
        -- opts.rowMark(row) -> colour role: light tint and a bar on the left (e.g. own characters)
        line.mark = UI.Fill(line, "lapis", "BORDER")
        line.mark:SetAllPoints()
        line.mark:Hide()
        line.markBar = UI.Fill(line, "lapis", "ARTWORK")
        line.markBar:SetPoint("TOPLEFT"); line.markBar:SetPoint("BOTTOMLEFT"); line.markBar:SetWidth(2)
        line.markBar:Hide()
        -- search hit: accent bar on the left edge
        line.hitBar = UI.Fill(line, "accent", "OVERLAY")
        line.hitBar:SetPoint("TOPLEFT", 0, -1); line.hitBar:SetPoint("BOTTOMLEFT", 0, 1); line.hitBar:SetWidth(3)
        line.hitBar:Hide()
        -- flash after "jump to": accent frame that fades out
        line.flash = CreateFrame("Frame", nil, line, "BackdropTemplate")
        line.flash:SetAllPoints()
        line.flash:SetFrameLevel(line:GetFrameLevel() + 6)
        UI.Skin(line.flash, "selected", "accent")
        line.flash:SetBackdropColor(0, 0, 0, 0)
        line.flash:Hide()
        line.cells = {}
        for c, col in ipairs(opts.columns) do
            local cell = CreateFrame(col.onClick and "Button" or "Frame", nil, line)
            cell:SetHeight(self.rowHeight)
            if col.onClick then
                cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                cell:SetScript("OnClick", function(f, button)
                    if line.row then ns.Safe(col.onClick, line.row, button, f) end
                end)
                cell:SetScript("OnEnter", function(f)
                    if not line.row then return end
                    if col.tip then
                        local title, lines = col.tip(line.row)
                        if title then UI.Tooltip(f, title, lines) end
                    elseif opts.onEnter then ns.Safe(opts.onEnter, line, line.row) end
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            -- search hit: soft accent tint behind the cell
            cell.hit = UI.Fill(cell, "accent", "BACKGROUND")
            cell.hit:SetPoint("TOPLEFT", -4, -3); cell.hit:SetPoint("BOTTOMRIGHT", 2, 3)
            cell.hit:SetAlpha(0.16)
            cell.hit:Hide()
            cell.text = UI.Text(cell, 13, "textDim", col.align or "LEFT")
            if col.wrap then
                cell.text:SetWordWrap(true)
                cell.text:SetJustifyV("MIDDLE")
                if cell.text.SetMaxLines then cell.text:SetMaxLines(math.max(2, math.floor(self.rowHeight / 14))) end
            end
            cell.text:SetPoint("TOPLEFT")
            cell.text:SetPoint("BOTTOMRIGHT")
            if col.icon or col.iconSet then
                local size = col.iconSize or (self.rowHeight - 4)
                cell.icon = cell:CreateTexture(nil, "ARTWORK")
                cell.icon:SetSize(size, size)
                cell.icon:SetPoint("LEFT", col.iconBorder and 1 or 0, 0)
                cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if col.iconBorder then
                    -- 1px frame around the icon (e.g. class color)
                    cell.iconBorder = cell:CreateTexture(nil, "BORDER")
                    cell.iconBorder:SetTexture(Theme.WHITE)
                    cell.iconBorder:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -1, 1)
                    cell.iconBorder:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 1, -1)
                end
                cell.text:SetPoint("TOPLEFT", size + (col.iconBorder and 8 or 4), 0)
            end
            -- a switch in the cell: col.toggle = { get = fn(row), set = fn(row, value), tip = text }
            if col.toggle then
                cell.toggle = UI.Toggle(cell, function() return line.row and col.toggle.get(line.row) end,
                    function(v) if line.row then ns.Safe(col.toggle.set, line.row, v) end end)
                cell.toggle:SetPoint("CENTER")
                if col.toggle.tip then
                    cell.toggle:HookScript("OnEnter", function(f) UI.Tooltip(f, col.toggle.tip) end)
                    cell.toggle:HookScript("OnLeave", function() GameTooltip:Hide() end)
                end
            end
            line.cells[c] = cell
        end
        layoutCells(line.cells, line)
        line:SetScript("OnSizeChanged", function(f) layoutCells(f.cells, f) end)
        line:SetScript("OnClick", function(f, button)
            if f.row and opts.onClick then ns.Safe(opts.onClick, f.row, button, f) end
        end)
        line:SetScript("OnEnter", function(f) if f.row and opts.onEnter then ns.Safe(opts.onEnter, f, f.row) end end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.lines[i] = line
        return line
    end

    function list:Sort()
        if not self.sortKey then return end
        local col
        for _, c in ipairs(opts.columns) do if c.key == self.sortKey then col = c end end
        if not col then return end
        local getter = col.sort or col.text
        local desc = self.sortDesc
        local cache = {}
        for _, row in ipairs(self.rows) do
            local v = getter(row)
            if type(v) == "string" then v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower() end
            cache[row] = v
        end
        table.sort(self.rows, function(a, b)
            local x, y = cache[a], cache[b]
            if x == y then return tostring(a.key or "") < tostring(b.key or "") end
            if x == nil then return false end
            if y == nil then return true end
            if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
            if desc then return x > y end
            return x < y
        end)
    end

    -- scrolls to the row with that key and marks it for a moment ("jump to")
    function list:JumpTo(key)
        local index
        for i, row in ipairs(self.rows) do if row.key == key then index = i; break end end
        if not index then return false end
        local visible = self:Visible()
        local max = math.max(0, #self.rows - visible)
        self.offset = math.max(0, math.min(max, index - math.floor(visible / 2)))
        self.bar:SetValue(self.offset)
        -- marked for about 5 s, then only a small pin until the next click in the window
        self.flashKey, self.pinKey = key, nil
        self:Draw()
        ns.After(UI.FLASH_TIME, function()
            if self.flashKey == key then self.flashKey = nil; self.pinKey = key; self:Draw() end
        end)
        if ns.Window.SetMark then
            ns.Window.SetMark(function() self.flashKey, self.pinKey = nil, nil; self:Draw() end)
        end
        return true
    end

    -- text a row is found by: opts.searchText(row), else all its column texts
    function list:RowText(row)
        if opts.searchText then
            local ok, t = pcall(opts.searchText, row)
            if ok and t then return t end
        end
        local parts = {}
        for _, col in ipairs(opts.columns) do
            if col.text and not col.noHighlight then
                local ok, t = pcall(col.text, row)
                if ok and type(t) == "string" then parts[#parts + 1] = t end
            end
        end
        return table.concat(parts, " ")
    end
    function list:RowMatches(row, q)
        return ns.SearchMatch(self:RowText(row), q)
    end
    -- page search: number of matching rows; scrolls to the first one (rows stay, nothing is hidden)
    function list:SearchHits(q)
        if not q or not q:find("%S") then return 0 end
        local n, first = 0, nil
        for i, row in ipairs(self.rows) do
            if self:RowMatches(row, q) then n = n + 1; first = first or i end
        end
        self.firstHit = first and self.rows[first].key
        return n
    end
    function list:ShowFirstHit(q)
        local n = self:SearchHits(q)
        if self.firstHit then
            local index
            for i, row in ipairs(self.rows) do if row.key == self.firstHit then index = i end end
            local visible = self:Visible()
            local max = math.max(0, #self.rows - visible)
            -- only scroll when the hit is not visible yet
            if index and (index <= self.offset or index > self.offset + visible) then
                self.offset = math.max(0, math.min(max, index - 2))
                self.bar:SetValue(self.offset)
            end
        elseif not q or not q:find("%S") then
            self.offset = 0
            self.bar:SetValue(0)
        end
        self:Draw()
        return n
    end

    function list:SetRows(rows)
        self.rows = rows or {}
        self:Sort()
        local max = math.max(0, #self.rows - self:Visible())
        if self.offset > max then self.offset = max end
        self:Draw()
    end

    function list:Draw()
        local hw = self.header:GetWidth() or 0
        if hw > 0 and hw ~= self.headerW then self.headerW = hw; layoutCells(self.header.cells, self.header) end
        self:UpdateHeader()
        local visible = self:Visible()
        local max = math.max(0, #self.rows - visible)
        self.bar:SetMinMaxValues(0, max)
        self.bar:SetShown(max > 0)
        for i = 1, visible do
            local line = self:Line(i)
            -- lines follow the header layout even when their own size event comes late
            local lw = line:GetWidth() or 0
            if lw > 0 and line.layoutW ~= lw then line.layoutW = lw; layoutCells(line.cells, line) end
            local row = self.rows[self.offset + i]
            line.row = row
            if row then
                local q = self:Query()
                for c, col in ipairs(opts.columns) do
                    local cell = line.cells[c]
                    local text = col.text and col.text(row) or ""
                    local hit = q and not col.noHighlight and ns.SearchAny(text, q)
                    if hit then text = ns.Highlight(text, q) end
                    cell.hit:SetShown(hit and true or false)
                    cell.text:SetText(text)
                    if cell.toggle then cell.toggle:Refresh() end
                    if cell.icon then
                        local shown
                        if col.iconSet then
                            shown = col.iconSet(cell.icon, row) and true or false
                        else
                            local tex = col.icon(row)
                            cell.icon:SetTexture(tex)
                            shown = tex ~= nil
                        end
                        cell.icon:SetShown(shown)
                        if cell.iconBorder then
                            local r, g, b = col.iconBorder(row)
                            cell.iconBorder:SetVertexColor(r or 0.3, g or 0.3, b or 0.3, 1)
                            cell.iconBorder:SetShown(shown)
                        end
                    end
                end
                local selected = opts.isSelected and opts.isSelected(row) or false
                line.sel:SetShown(selected)
                line.selBar:SetShown(selected)
                local mark = opts.rowMark and opts.rowMark(row)
                if mark then
                    local r, g, b = Theme.Color(mark)
                    line.mark:SetVertexColor(r, g, b)
                    line.mark:SetAlpha(0.12)
                    line.markBar:SetVertexColor(r, g, b)
                end
                line.mark:SetShown(mark ~= nil and not selected)
                line.markBar:SetShown(mark ~= nil and not selected)
                line.hitBar:SetShown(q ~= nil and self:RowMatches(row, q))
                local flash = self.flashKey ~= nil and row.key == self.flashKey
                line.flash:SetShown(flash)
                if flash then UI.Flash(line.flash) end
                local pinned = self.pinKey ~= nil and row.key == self.pinKey
                if pinned or line.searchPin then UI.Pin(line):SetShown(pinned) end
                line:Show()
            else
                line:Hide()
            end
        end
        for i = visible + 1, #self.lines do self.lines[i]:Hide() end
        self:UpdateEmpty()
    end

    -- the current page search (nil when empty or the list belongs to no page)
    function list:Query()
        local page = self.page and ns.Window.Page(self.page)
        local q = page and page.query
        if q and not q:find("^%s*$") then return q end
    end

    function list:EmptyFrame()
        if not self.empty then
            self.empty = UI.Empty(self.body, 420)
            self.empty:SetPoint("TOP", 0, -36)
            self.empty:Hide()
        end
        return self.empty
    end

    function list:UpdateEmpty()
        if not self.empty and not self:Query() then return end
        local e = self:EmptyFrame()
        local none = #self.rows == 0
        e:SetShown(none)
        if not none then return end
        e:SetTextWidth(math.max(160, math.min(420, (self.body:GetWidth() or 420) - 40)))
        local q = self:Query()
        if q and not opts.keepEmptyText then
            UI.EmptySearch(e, q)
        else
            local page = self.page and ns.Window.Page(self.page)
            e:Set(self.emptyIcon or opts.emptyIcon or (page and page.icon) or "dot", self.emptyText or "", self.emptyHint)
        end
    end

    -- text (and optional hint / icon) when there are no rows
    function list:SetEmptyText(text, hint, icon)
        self.emptyText, self.emptyHint, self.emptyIcon = text, hint, icon
        self:EmptyFrame()
        self:UpdateEmpty()
    end

    list:SetScript("OnSizeChanged", function(self)
        layoutCells(self.header.cells, self.header)
        self:Draw()
    end)
    list:SetScript("OnShow", function(self) layoutCells(self.header.cells, self.header); self:Draw() end)
    return list
end
