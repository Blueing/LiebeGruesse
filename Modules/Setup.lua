-- Setup assistant (/lg setup): what is still open for this character, one row
-- per topic with its state and a button that leads there. Reads only; every
-- change happens on the page or window the button opens.
local _, ns = ...
local UI, Theme, L, Names = ns.UI, ns.Theme, ns.L, ns.Names
local Setup = {}
ns.Setup = Setup

local W = 500
local frame

local function modOn(key) return ns.Database.Settings().modules[key] ~= false end
local function isPaladin() local _, c = ns.Call(UnitClass, "player"); return c == "PALADIN" end

-- each check: state "done" | "open" | "optional", detail text, button (text, fn)
-- test: every row as "open" with sample text (nothing changes)
local CHECKS = {
    { key = "version", icon = "circle-arrow-up", title = "SETUP_VERSION",
      check = function()
          local v = ns.Versions and ns.Versions.Available and ns.Versions.Available()
          if v then return "open", L.SETUP_VERSION_OPEN:format(v, ns.version), L.PAGE_VERSIONS, function() ns.Window.Show("versions") end end
          return "done", L.SETUP_VERSION_DONE:format(ns.version)
      end },
    { key = "profs", icon = "scroll-text", title = "SETUP_PROFS", show = function() return modOn("professions") end,
      check = function()
          local PS = ns.ProfSync
          local missing = PS and PS.Missing() or {}
          if #missing > 0 then
              local names = {}
              for _, k in ipairs(missing) do names[#names + 1] = ns.Crafts.ProfName(k) end
              return "open", L.SETUP_PROFS_OPEN:format(table.concat(names, ", ")), L.SETUP_SYNC, function() PS.Show() end
          end
          if PS and #PS.All() == 0 then return "done", L.SETUP_PROFS_NONE end
          return "done", L.SETUP_PROFS_DONE, L.SETUP_SHOW, function() PS.Show() end
      end },
    { key = "main", icon = "users", title = "SETUP_MAIN",
      check = function()
          local me = Names.Me()
          local main = ns.Account and ns.Account.Main and ns.Account.Main()
          local manual = ns.Database.Char().main
          local open = function() ns.Window.Show("general") end
          if manual and manual ~= "" then return "done", L.SETUP_MAIN_SET:format(Names.Display(manual)), L.PAGE_GENERAL, open end
          if main and Names.Same(main, me) then return "done", L.SETUP_MAIN_IS, L.PAGE_GENERAL, open end
          if main and ns.Account.Settings().autoAlts then return "done", L.SETUP_MAIN_AUTO:format(Names.Display(main)), L.PAGE_GENERAL, open end
          return "open", L.SETUP_MAIN_OPEN, L.PAGE_GENERAL, open
      end },
    { key = "role", icon = "shield", title = "SETUP_ROLE",
      check = function()
          local v = ns.QoL and ns.QoL.Setting and ns.QoL.Setting() or "auto"
          local open = function() ns.Window.Show("general") end
          if v == "off" then return "optional", L.SETUP_ROLE_OFF, L.PAGE_GENERAL, open end
          local text = (v == "auto") and L.ROLE_FROM_TALENTS or (L["ROLE_" .. (v == "DAMAGER" and "DAMAGE" or v)] or v)
          return "done", L.SETUP_ROLE_DONE:format(text), L.PAGE_GENERAL, open
      end },
    { key = "bless", icon = "sparkles", title = "SETUP_BLESS", show = function() return modOn("blessings") and isPaladin() end,
      check = function()
          local me = ns.Blessings and ns.Blessings.Me()
          local open = function() ns.Window.Show("blessings") end
          if not (me and next(me.set or {})) then return "open", L.SETUP_BLESS_OPEN, L.PAGE_BLESSINGS, open end
          local n = 0
          for _ in pairs(me.set) do n = n + 1 end
          return "done", L.SETUP_BLESS_DONE:format(n), L.PAGE_BLESSINGS, open
      end },
    { key = "cds", icon = "timer", title = "SETUP_CDS", show = function() return modOn("cooldowns") end,
      check = function()
          local Bars = ns.CooldownBars
          local on = {}
          for _, key in ipairs(Bars and Bars.Keys() or {}) do
              local d = Bars.Display(key)
              if d.enabled then on[#on + 1] = d.name end
          end
          local open = function() ns.Window.ShowSettings("cooldowns") end
          if #on == 0 then return "optional", L.SETUP_CDS_OFF, L.CD_TAB_DISPLAYS, open end
          return "done", L.SETUP_CDS_DONE:format(table.concat(on, ", ")), L.CD_TAB_DISPLAYS, open
      end },
}
Setup.CHECKS = CHECKS

-- current rows: { def, state, detail, button text, fn }
function Setup.Rows(test)
    local out = {}
    for _, def in ipairs(CHECKS) do
        if test or not def.show or def.show() then
            local ok, state, detail, btn, fn = pcall(def.check)
            if not ok then state, detail = "optional", tostring(state) end
            if test then state, detail = "open", L.SETUP_TEST_ROW end
            out[#out + 1] = { def = def, state = state, detail = detail, btn = btn, fn = fn }
        end
    end
    return out
end

function Setup.OpenCount(rows)
    local n = 0
    for _, r in ipairs(rows or Setup.Rows()) do if r.state == "open" then n = n + 1 end end
    return n
end

local function create()
    frame = UI.Panel(UIParent, "panel", "border")
    frame:SetSize(W, 300)
    frame:SetPoint("CENTER", 0, 80)
    UI.Float(frame)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    _G.LiebeGruesseSetup = frame
    tinsert(UISpecialFrames, "LiebeGruesseSetup")

    frame.glow = UI.VGradient(frame, { 0.090, 0.129, 0.192, 0.9 }, { 0.090, 0.129, 0.192, 0 }, "BORDER")
    frame.glow:SetPoint("TOPLEFT", 1, -1); frame.glow:SetPoint("TOPRIGHT", -1, -1); frame.glow:SetHeight(90)
    frame.logo = frame:CreateTexture(nil, "ARTWORK")
    frame.logo:SetTexture(ns.media .. "logo")
    frame.logo:SetSize(52, 52)
    frame.logo:SetPoint("TOPLEFT", 16, -14)
    frame.kicker = UI.Text(frame, 11, "accent", nil, nil, true)
    frame.kicker:SetPoint("TOPLEFT", frame.logo, "TOPRIGHT", 12, -6)
    frame.title = UI.Text(frame, 22, "text", nil, nil, true)
    frame.title:SetPoint("TOPLEFT", frame.kicker, "BOTTOMLEFT", 0, -4)
    frame.title:SetWidth(W - 100)
    frame.close = UI.IconButton(frame, "x", 22, function() frame:Hide() end)
    frame.close:SetPoint("TOPRIGHT", -10, -10)
    frame.rule = UI.Fill(frame, "bronzeDim", "ARTWORK")
    frame.rule:SetHeight(1)
    frame.rule:SetPoint("TOPLEFT", 16, -80); frame.rule:SetPoint("TOPRIGHT", -16, -80)
    frame.intro = UI.Text(frame, 13, "textDim")
    frame.intro:SetPoint("TOPLEFT", 16, -94)
    frame.intro:SetWidth(W - 32)
    frame.intro:SetWordWrap(true)
    frame.intro:SetJustifyH("LEFT")
    frame.rows = {}

    frame.status = UI.Text(frame, 12, "muted")
    frame.status:SetPoint("BOTTOMLEFT", 16, 26)
    frame.status:SetWidth(W - 32 - 150)
    frame.status:SetJustifyH("LEFT")
    frame.ok = UI.Button(frame, L.SETUP_DONE_BTN, 130, 32, function() frame:Hide() end)
    frame.ok:SetPoint("BOTTOMRIGHT", -16, 16)
    UI.Skin(frame.ok, "accentDim", "accent")
    frame.ok:SetScript("OnLeave", function(self)
        self:SetBackdropColor(Theme.Color("accentDim")); self:SetBackdropBorderColor(Theme.Color("accent")); GameTooltip:Hide()
    end)
end

local function row(i)
    local r = frame.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, frame)
    r:SetSize(W - 32, 46)
    r.bg = UI.Fill(r, (i % 2 == 0) and "rowAlt" or "row", "BACKGROUND")
    r.bg:SetAllPoints()
    r.mark = UI.Fill(r, "accent", "ARTWORK")
    r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); r.mark:SetWidth(2)
    r.icon = UI.Icon(r, "dot", 16, "accent")
    r.icon:SetPoint("LEFT", 12, 0)
    r.title = UI.Text(r, 13, "text")
    r.title:SetPoint("TOPLEFT", 40, -7)
    r.state = UI.Text(r, 11, "muted")
    r.state:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
    r.detail = UI.Text(r, 11, "textDim")
    r.detail:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.detail:SetWidth(W - 32 - 40 - 120)
    r.detail:SetWordWrap(true)
    r.detail:SetJustifyH("LEFT")
    r.button = UI.Button(r, "", 104, 24, function(self) if self.fn then ns.Safe(self.fn) end end)
    r.button:SetPoint("RIGHT", -10, 0)
    frame.rows[i] = r
    return r
end

local STATE_COLOR = { done = "good", open = "warn", optional = "muted" }

function Setup.Update()
    if not frame or not frame:IsShown() then return end
    local rows = Setup.Rows(frame.test)
    frame.intro:SetText(L.SETUP_INTRO)
    local y = 94 + math.max(18, frame.intro:GetStringHeight() or 18) + 12
    for i, data in ipairs(rows) do
        local r = row(i)
        Theme.SetIcon(r.icon, data.def.icon)
        r.icon:SetVertexColor(Theme.Color(data.state == "open" and "accent" or "textDim"))
        r.title:SetText(L[data.def.title])
        r.state:SetText(Theme.HexColor(STATE_COLOR[data.state] or "muted", L["SETUP_STATE_" .. data.state:upper()]))
        r.detail:SetText(data.detail or "")
        r.mark:SetShown(data.state == "open")
        r.button.fn = (not frame.test) and data.fn or nil
        r.button:SetText(data.btn or "")
        r.button:SetShown(data.btn ~= nil)
        local h = math.max(46, 7 + 16 + 3 + (r.detail:GetStringHeight() or 14) + 8)
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 16, -y)
        r:Show()
        y = y + h + 2
    end
    for i = #rows + 1, #frame.rows do frame.rows[i]:Hide() end
    local open = Setup.OpenCount(rows)
    frame.status:SetText(open == 0 and Theme.HexColor("good", L.SETUP_ALL_DONE) or L.SETUP_OPEN_COUNT:format(open))
    frame:SetHeight(y + 70)
end

function Setup.Show(test)
    if not frame then create() end
    frame.test = test
    frame.kicker:SetText(ns.Upper(L.SETUP_KICKER) .. (test and ("  ·  " .. ns.Upper(L.TEST_TAG:gsub("[%[%]]", ""))) or ""))
    frame.title:SetText(L.SETUP_TITLE)
    frame:Show()
    Setup.Update()
    ns.After(0, Setup.Update)   -- string heights are final one frame later
end

---------------------------------------------------------------------------
-- Once at login when something is open (per character and set of open
-- things; a newer addon version alone does not count – it has its own hint).
-- It covers the profession sync hint, which then stays quiet.
---------------------------------------------------------------------------
function Setup.AutoEnabled()
    local s = ns.Database.Settings()
    if s.setupHint == nil then s.setupHint = true end
    return s.setupHint
end

local function openSignature()
    local parts = {}
    for _, r in ipairs(Setup.Rows()) do
        if r.state == "open" and r.def.key ~= "version" then parts[#parts + 1] = r.def.key .. "=" .. tostring(r.detail or "") end
    end
    return table.concat(parts, "|")
end
Setup.OpenSignature = openSignature

function Setup.Auto()
    if not Setup.AutoEnabled() then return end
    -- the "what's new" window goes first
    local wn = _G.LiebeGruesseWhatsNew
    if (ns.WhatsNew and ns.WhatsNew.pending) or (wn and wn:IsShown()) then
        if wn and not Setup.waiting then
            Setup.waiting = true
            wn:HookScript("OnHide", function()
                if Setup.waiting then Setup.waiting = false; ns.After(1, function() ns.AfterCombat("setup-auto", Setup.Auto) end) end
            end)
        elseif not wn then
            ns.After(5, function() ns.AfterCombat("setup-auto", Setup.Auto) end)
        end
        return
    end
    local sig = openSignature()
    if sig == "" then return end
    local char = ns.Database.Char()
    if char.setupHinted == sig then return end
    char.setupHinted = sig
    Setup.Show()
end

ns.On("LG_READY", function()
    -- professions are read a few seconds after login
    ns.After(14, function() ns.AfterCombat("setup-auto", Setup.Auto) end)
end)
-- fires right before combat lockdown: the window is in the way in a fight
ns.On("PLAYER_REGEN_DISABLED", function() if frame and frame:IsShown() and not frame.test then frame:Hide() end end)

-- keep it current while open (professions read, settings changed, …)
for _, e in ipairs({ "LG_PROFILE", "LG_PROF_SCANNED", "LG_BLESSINGS", "LG_MODULES", "LG_COOLDOWNS" }) do
    ns.On(e, function() if frame and frame:IsShown() then ns.Debounce("setup-update", 0.3, Setup.Update) end end)
end
