-- Aegis/Core/Settings.lua
-- Standalone settings dialog. Modeled on the Iron addon's Settings.lua:
-- a movable frame with dialog-style backdrop, tabs along the top, and a
-- content area that swaps per tab.
--
-- Three tabs:
--   Pressure - thresholds (TTD ladders, drain ladders, hysteresis,
--              healing sustain) and the critical-entry sound toggle.
--   Visual   - per-bar text toggles (mana, rage, energy, runic), HP
--              format dropdown, combo count overlay, halo OOC gating,
--              default block style.
--   Blocks   - row list of installed blocks (one row per block, with
--              its id, position, orientation/style, widget list, and a
--              Delete button), plus Add/Reset action buttons.
--
-- The dialog is parented to UIParent (not registered with the Blizzard
-- Interface Options framework) for full layout control. Escape closes
-- via UISpecialFrames.

local _, ns = ...
ns.Settings = ns.Settings or {}
local S = ns.Settings

S.tabs = {}
S.tabOrder = {}
S.refreshHandlers = {}

local SETTINGS_FRAME_NAME = "AegisSettingsFrame"

----------------------------------------------------------------
-- Refresh + tab registry
----------------------------------------------------------------

function S.Refresh()
    for i = 1, #S.refreshHandlers do
        local ok, err = pcall(S.refreshHandlers[i])
        if not ok then
            print("|cffff5555Aegis settings refresh error|r: " .. tostring(err))
        end
    end
end

function S.RegisterTab(def)
    if not S.tabs[def.name] then
        tinsert(S.tabOrder, def.name)
    end
    S.tabs[def.name] = def
    if S.frame and S.rebuild then
        S.rebuild()
    end
end

----------------------------------------------------------------
-- Builder helpers
----------------------------------------------------------------

local function uniqName(base)
    S._uniq = (S._uniq or 0) + 1
    return ("Aegis%s%d"):format(base, S._uniq)
end

local function makeSlider(parent, label, min, max, step, getter, setter, fmt, displayMul)
    displayMul = displayMul or 1
    local name = uniqName("Slider")
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetWidth(200)
    s:SetHeight(16)

    local lo   = _G[name .. "Low"]
    local hi   = _G[name .. "High"]
    local text = _G[name .. "Text"]
    local function f(v)
        return fmt and fmt:format(v * displayMul) or tostring(v * displayMul)
    end
    if lo   then lo:SetText(f(min))  end
    if hi   then hi:SetText(f(max))  end
    if text then text:SetText(label) end

    local valLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valLabel:SetPoint("LEFT", s, "RIGHT", 12, 0)

    local function refresh()
        local v = getter()
        s:SetValue(v)
        valLabel:SetText(f(v))
    end

    s:SetScript("OnValueChanged", function(self, value)
        setter(value)
        valLabel:SetText(f(value))
    end)

    refresh()
    tinsert(S.refreshHandlers, refresh)
    return s
end

local function makeCheckbox(parent, label, getter, setter)
    local name = uniqName("Check")
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)

    local function refresh()
        cb:SetChecked(getter() and true or false)
    end
    cb:SetScript("OnShow", refresh)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    refresh()
    tinsert(S.refreshHandlers, refresh)
    return cb
end

local function makeDropdown(parent, label, options, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 50)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT", container, "TOPLEFT", 18, 0)
    labelFS:SetText(label)

    local name = uniqName("Drop")
    local dd = CreateFrame("Frame", name, container, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dd, 180)

    local function applySelection(key)
        UIDropDownMenu_SetSelectedValue(dd, key)
        for _, opt in ipairs(options) do
            if opt.key == key then
                UIDropDownMenu_SetText(dd, opt.text)
                break
            end
        end
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.key
            info.func  = function(b)
                applySelection(b.value)
                setter(b.value)
            end
            info.checked = (getter() == opt.key)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local function refresh() applySelection(getter()) end
    refresh()
    tinsert(S.refreshHandlers, refresh)
    return container
end

local function makeButton(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 140, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function makeHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    return fs
end

local function makeBody(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

----------------------------------------------------------------
-- Tab switching + frame creation
----------------------------------------------------------------

local function showTab(f, name)
    for _, tabFrame in pairs(f.tabFrames) do tabFrame:Hide() end
    if f.tabFrames[name] then f.tabFrames[name]:Show() end
    for n, btn in pairs(f.tabButtons) do
        if n == name then
            btn:LockHighlight()
            btn:Disable()
        else
            btn:UnlockHighlight()
            btn:Enable()
        end
    end
    f.activeTab = name
end

local TAB_HEIGHT     = 22
local TAB_PADDING    = 24
local TAB_MIN_WIDTH  = 60
local TAB_GAP        = 4
local FRAME_SIDE_MARGIN = 12
local FRAME_MIN_WIDTH   = 480

local function buildTabs(f)
    if f.tabButtons then
        for _, btn in pairs(f.tabButtons) do btn:Hide() end
    end
    if f.tabFrames then
        for _, frame in pairs(f.tabFrames) do frame:Hide() end
    end
    f.tabButtons = {}
    f.tabFrames  = {}

    local lastBtn
    local rowWidth = FRAME_SIDE_MARGIN
    for i, name in ipairs(S.tabOrder) do
        local def = S.tabs[name]
        local title = def.title or name
        if type(title) == "function" then title = title() end

        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetText(title)
        local fs = btn:GetFontString()
        local textW = (fs and fs:GetStringWidth()) or TAB_MIN_WIDTH
        local btnW = math.max(TAB_MIN_WIDTH, math.ceil(textW) + TAB_PADDING)
        btn:SetSize(btnW, TAB_HEIGHT)
        if i == 1 then
            btn:SetPoint("TOPLEFT", FRAME_SIDE_MARGIN, -32)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", TAB_GAP, 0)
            rowWidth = rowWidth + TAB_GAP
        end
        rowWidth = rowWidth + btnW
        btn:SetScript("OnClick", function() showTab(f, name) end)
        f.tabButtons[name] = btn

        local tabFrame = CreateFrame("Frame", nil, f.content)
        tabFrame:SetAllPoints(f.content)
        tabFrame:Hide()
        f.tabFrames[name] = tabFrame
        if def.build then
            def.build(tabFrame)
        end

        lastBtn = btn
    end
    rowWidth = rowWidth + FRAME_SIDE_MARGIN

    if rowWidth > f:GetWidth() then
        f:SetWidth(rowWidth)
    end

    if S.tabOrder[1] then
        local target = (f.activeTab and f.tabFrames[f.activeTab]) and f.activeTab
            or S.tabOrder[1]
        showTab(f, target)
    end
end

local function createFrame()
    if S.frame then return S.frame end

    local f = CreateFrame("Frame", SETTINGS_FRAME_NAME, UIParent)
    f:SetSize(FRAME_MIN_WIDTH, 480)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Aegis - Settings")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 14, -68)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    f.content = content

    f:SetScript("OnShow", function() S.Refresh() end)

    S.frame   = f
    S.rebuild = function() buildTabs(f) end
    buildTabs(f)

    tinsert(UISpecialFrames, SETTINGS_FRAME_NAME)

    f:Hide()
    return f
end

----------------------------------------------------------------
-- Pressure tab
----------------------------------------------------------------

local function pressure()   return AegisDB.pressure              end
local function thresholds() return AegisDB.pressure.thresholds   end
local function visual()     return AegisDB.visual                end

local function buildPressureTab(parent)
    local hdr = makeHeader(parent, "Pressure thresholds")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -4)

    local s1 = makeSlider(parent, "Sliding window", 1, 10, 0.5,
        function() return pressure().windowSeconds end,
        function(v) pressure().windowSeconds = v end,
        "%.1fs")
    s1:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 8, -28)

    local s2 = makeSlider(parent, "Warning TTD", 5, 30, 1,
        function() return thresholds().warningTTD end,
        function(v) thresholds().warningTTD = v end,
        "%ds")
    s2:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -32)

    local s3 = makeSlider(parent, "Critical TTD", 1, 10, 1,
        function() return thresholds().criticalTTD end,
        function(v) thresholds().criticalTTD = v end,
        "%ds")
    s3:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -32)

    local s4 = makeSlider(parent, "Warning drain", 0.005, 0.05, 0.005,
        function() return thresholds().warningDrain end,
        function(v) thresholds().warningDrain = v end,
        "%.1f%%/s", 100)
    s4:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -32)

    local s5 = makeSlider(parent, "Critical drain", 0.01, 0.10, 0.005,
        function() return thresholds().criticalDrain end,
        function(v) thresholds().criticalDrain = v end,
        "%.1f%%/s", 100)
    s5:SetPoint("TOPLEFT", s4, "BOTTOMLEFT", 0, -32)

    local s6 = makeSlider(parent, "Hysteresis (state-down delay)", 0.0, 3.0, 0.1,
        function() return pressure().hysteresisSeconds end,
        function(v) pressure().hysteresisSeconds = v end,
        "%.1fs")
    s6:SetPoint("TOPLEFT", s5, "BOTTOMLEFT", 0, -32)

    local s7 = makeSlider(parent, "Healing sustain time", 0.0, 5.0, 0.1,
        function() return pressure().healingSustainTime end,
        function(v) pressure().healingSustainTime = v end,
        "%.1fs")
    s7:SetPoint("TOPLEFT", s6, "BOTTOMLEFT", 0, -32)

    local cbSound = makeCheckbox(parent,
        "Play RaidWarning sound on critical entry",
        function() return pressure().soundOnCritical end,
        function(v) pressure().soundOnCritical = v end)
    cbSound:SetPoint("TOPLEFT", s7, "BOTTOMLEFT", -4, -16)
end

----------------------------------------------------------------
-- Visual tab — per-bar settings
----------------------------------------------------------------

local function buildVisualTab(parent)
    local hdr = makeHeader(parent, "Visual")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -4)

    local healthFmt = makeDropdown(parent,
        "Health bar text",
        {
            { key = "value",             text = "Value (1234)"        },
            { key = "percent",           text = "Percent (47%)"       },
            { key = "value_and_percent", text = "Value + Percent"     },
            { key = "none",              text = "None (no text)"      },
        },
        function() return visual().showHealthText end,
        function(v) visual().showHealthText = v end)
    healthFmt:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -8)

    local cbMana = makeCheckbox(parent, "Show 'current / max' on mana bar",
        function() return visual().showManaText ~= false end,
        function(v) visual().showManaText = v end)
    cbMana:SetPoint("TOPLEFT", healthFmt, "BOTTOMLEFT", 18, -4)

    local cbRage = makeCheckbox(parent, "Show 'current / max' on rage bar",
        function() return visual().showRageText ~= false end,
        function(v) visual().showRageText = v end)
    cbRage:SetPoint("TOPLEFT", cbMana, "BOTTOMLEFT", 0, -2)

    local cbEnergy = makeCheckbox(parent, "Show 'current / max' on energy bar",
        function() return visual().showEnergyText ~= false end,
        function(v) visual().showEnergyText = v end)
    cbEnergy:SetPoint("TOPLEFT", cbRage, "BOTTOMLEFT", 0, -2)

    local cbRunic = makeCheckbox(parent, "Show 'current / max' on runic bar",
        function() return visual().showRunicText ~= false end,
        function(v) visual().showRunicText = v end)
    cbRunic:SetPoint("TOPLEFT", cbEnergy, "BOTTOMLEFT", 0, -2)

    local cbCombo = makeCheckbox(parent, "Show combo point count next to pips",
        function() return visual().showComboCount end,
        function(v) visual().showComboCount = v end)
    cbCombo:SetPoint("TOPLEFT", cbRunic, "BOTTOMLEFT", 0, -2)

    local cbHaloOOC = makeCheckbox(parent, "Hide pressure halo out of combat",
        function() return visual().haloInCombatOnly end,
        function(v) visual().haloInCombatOnly = v end)
    cbHaloOOC:SetPoint("TOPLEFT", cbCombo, "BOTTOMLEFT", 0, -10)

    local styleDD = makeDropdown(parent,
        "Default block style (for /ae block add)",
        {
            { key = "standard", text = "Standard (flat)"           },
            { key = "glossy",   text = "Glossy (gradient overlay)" },
        },
        function() return visual().defaultBlockStyle end,
        function(v) visual().defaultBlockStyle = v end)
    styleDD:SetPoint("TOPLEFT", cbHaloOOC, "BOTTOMLEFT", -18, -10)
end

----------------------------------------------------------------
-- Blocks tab — row list
----------------------------------------------------------------

local BLOCK_ROW_H = 36
local BLOCK_ROW_PAD = 4
local blockRows = {}

local function getBlockRow(parent, i)
    if blockRows[i] then return blockRows[i] end
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BLOCK_ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0.08, 0.08, 0.08, 0.6)
    bg:SetAllPoints()

    local idFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idFs:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
    idFs:SetWidth(70)
    idFs:SetJustifyH("LEFT")
    row.id = idFs

    local posFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    posFs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
    posFs:SetWidth(110)
    posFs:SetJustifyH("LEFT")
    row.pos = posFs

    local widgetsFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    widgetsFs:SetPoint("LEFT", idFs, "RIGHT", 6, 0)
    widgetsFs:SetWidth(220)
    widgetsFs:SetHeight(BLOCK_ROW_H - 8)
    widgetsFs:SetJustifyH("LEFT")
    widgetsFs:SetJustifyV("MIDDLE")
    row.widgets = widgetsFs

    local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    del:SetSize(70, 22)
    del:SetPoint("RIGHT", -4, 0)
    del:SetText("Delete")
    row.del = del

    blockRows[i] = row
    return row
end

local function refreshBlockRows(parent)
    local blocks = AegisDBChar and AegisDBChar.blocks or {}
    -- Hide all rows first; we re-show the ones we use.
    for _, row in pairs(blockRows) do row:Hide() end

    local cursor = 0
    for i, b in ipairs(blocks) do
        local row = getBlockRow(parent, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  4, -cursor)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -cursor)
        cursor = cursor + BLOCK_ROW_H + BLOCK_ROW_PAD

        row.id:SetText(b.id or "?")

        local p = b.position or {}
        row.pos:SetText(("%s %+d,%+d"):format(
            p.point or "?", p.xOffset or 0, p.yOffset or 0))

        local widgets = (b.widgets and #b.widgets > 0)
            and table.concat(b.widgets, ", ") or "(empty)"
        local style = b.style or "standard"
        local orient = (b.orientation == "vertical") and "vertical" or "horizontal"
        row.widgets:SetText(("%s, %s\n%s"):format(orient, style, widgets))

        local id = b.id
        row.del:SetScript("OnClick", function()
            if not id or not AegisDBChar.blocks then return end
            for j = 1, #AegisDBChar.blocks do
                if AegisDBChar.blocks[j].id == id then
                    tremove(AegisDBChar.blocks, j)
                    break
                end
            end
            if ns.BlockManager and ns.BlockManager.Build then
                ns.BlockManager.Build()
            end
            S.Refresh()
        end)

        row:Show()
    end
    return cursor
end

local function generateBlockId()
    local used = {}
    if AegisDBChar.blocks then
        for _, b in ipairs(AegisDBChar.blocks) do
            if b.id then used[b.id] = true end
        end
    end
    local i = 1
    while used["block" .. i] do i = i + 1 end
    return "block" .. i
end

local function buildBlocksTab(parent)
    local hdr = makeHeader(parent, "Blocks")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -4)

    local hint = makeBody(parent,
        "Each row is a block. Click Delete to remove. Use /ae unlock to drag.\n"
        .. "Add widgets to a block via:  /ae block add <h|v> <widget1> [widget2] ...")
    hint:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 4, -6)
    hint:SetWidth(440)

    -- Container for rows.
    local listHost = CreateFrame("Frame", nil, parent)
    listHost:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -10)
    listHost:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    listHost:SetHeight(280)

    local function refreshList()
        refreshBlockRows(listHost)
    end
    refreshList()
    tinsert(S.refreshHandlers, refreshList)

    -- Footer buttons.
    local addBtn = makeButton(parent, "Add empty block at center", 200, function()
        local newBlock = {
            id          = generateBlockId(),
            position    = {
                point         = "CENTER",
                relativePoint = "CENTER",
                xOffset       = 0,
                yOffset       = 0,
            },
            orientation = "horizontal",
            style       = visual().defaultBlockStyle or "standard",
            scale       = 1.0,
            widgets     = {},
        }
        AegisDBChar.blocks = AegisDBChar.blocks or {}
        tinsert(AegisDBChar.blocks, newBlock)
        if ns.BlockManager and ns.BlockManager.Build then
            ns.BlockManager.Build()
        end
        S.Refresh()
    end)
    addBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)

    local resetBtn = makeButton(parent, "Reset to defaults", 160, function()
        if StaticPopup_Show then StaticPopup_Show("AEGIS_RESET_CONFIRM") end
    end)
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
end

----------------------------------------------------------------
-- Public
----------------------------------------------------------------

function S.Open(tabName)
    local f = createFrame()
    if tabName and S.tabs[tabName] then
        showTab(f, tabName)
        f:Show()
        S.Refresh()
        return
    end
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        S.Refresh()
    end
end

function S.Toggle() S.Open() end

----------------------------------------------------------------
-- Default tab registrations (in display order)
----------------------------------------------------------------

S.RegisterTab({ name = "pressure", title = "Pressure", build = buildPressureTab })
S.RegisterTab({ name = "visual",   title = "Visual",   build = buildVisualTab   })
S.RegisterTab({ name = "blocks",   title = "Blocks",   build = buildBlocksTab   })
