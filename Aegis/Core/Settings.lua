-- Aegis/Core/Settings.lua
-- Standalone settings dialog. Modeled on the Iron addon's Settings.lua:
-- a movable frame with dialog-style backdrop, tabs along the top, and a
-- content area that swaps per tab.
--
-- Three tabs:
--   Pressure - thresholds (TTD ladders, drain ladders, hysteresis,
--              healing sustain) and the critical-entry sound toggle.
--   Visual   - per-bar text-format dropdowns (HP, mana, rage, energy,
--              runic), combo count overlay, halo OOC gating, and the
--              default style for newly-created blocks. Setters call
--              notify() so changes appear live on the HUD without /rl.
--   Blocks   - per-row block editor: orientation toggle, style
--              dropdown, Delete button, widget chip strip with
--              reorder (`<` `>`) and remove (`x`) controls, and a
--              `+ Add widget` dropdown. Footer adds an empty block,
--              toggles drag mode (Move blocks / Lock positions), and
--              resets to the default layout.
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
-- Notify: push a refresh to every live widget so visual setting
-- changes (text format, combo count, ...) appear immediately
-- instead of waiting for the next event tick. Block-structure
-- changes (orientation/style/widget list) call BlockManager.RebuildBlock
-- directly, not this.
----------------------------------------------------------------

local function notify()
    if ns.BlockManager and ns.BlockManager.RefreshAllWidgets then
        ns.BlockManager.RefreshAllWidgets()
    end
end

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

-- Wrap a tab parent in a vertical scrollframe and return the inner content
-- frame. Widgets that would have anchored to the tab now anchor to `content`
-- instead, and the scroll panel handles overflow when content height exceeds
-- the tab's visible area. Width is sized to the tab minus scrollbar room.
local function withScroll(parent, topInset, bottomInset)
    topInset    = topInset    or 0
    bottomInset = bottomInset or 0
    local sf = CreateFrame("ScrollFrame", uniqName("Scroll"), parent,
        "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",      0,    -topInset)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28,    bottomInset)

    local content = CreateFrame("Frame", nil, sf)
    -- Width: parent minus scrollbar gutter (~28). The default panel width
    -- (560) leaves ~500 px for content. Setting an initial size avoids a
    -- 0-width child on the first paint.
    content:SetSize(500, 1)
    sf:SetScrollChild(content)

    return content, sf
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
local FRAME_MIN_WIDTH   = 560

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
    f:SetSize(FRAME_MIN_WIDTH, 520)
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

local TEXT_FORMAT_OPTIONS = {
    { key = "value",             text = "Value (1234)"      },
    { key = "percent",           text = "Percent (47%)"     },
    { key = "value_and_percent", text = "Value + Percent"   },
    { key = "none",              text = "None (no text)"    },
}

local function readBarFormat(key)
    local v = visual()[key]
    if v == true  then return "value_and_percent" end
    if v == false then return "none" end
    return v or "value_and_percent"
end

local function buildVisualTab(parent)
    parent = withScroll(parent)
    local hdr = makeHeader(parent, "Visual")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -4)

    -- Two columns of dropdowns: HP/Mana on the left, Rage/Energy/Runic on
    -- the right. Each dropdown changes the text format of its bar live (no
    -- /rl) by pushing a Refresh to all widgets after the value is set.
    local hpDD = makeDropdown(parent, "Health bar text", TEXT_FORMAT_OPTIONS,
        function() return readBarFormat("showHealthText") end,
        function(v) visual().showHealthText = v; notify() end)
    hpDD:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -8)

    local manaDD = makeDropdown(parent, "Mana bar text", TEXT_FORMAT_OPTIONS,
        function() return readBarFormat("showManaText") end,
        function(v) visual().showManaText = v; notify() end)
    manaDD:SetPoint("TOPLEFT", hpDD, "BOTTOMLEFT", 0, -10)

    local rageDD = makeDropdown(parent, "Rage bar text", TEXT_FORMAT_OPTIONS,
        function() return readBarFormat("showRageText") end,
        function(v) visual().showRageText = v; notify() end)
    rageDD:SetPoint("TOPLEFT", manaDD, "BOTTOMLEFT", 0, -10)

    local energyDD = makeDropdown(parent, "Energy bar text", TEXT_FORMAT_OPTIONS,
        function() return readBarFormat("showEnergyText") end,
        function(v) visual().showEnergyText = v; notify() end)
    energyDD:SetPoint("TOPLEFT", rageDD, "BOTTOMLEFT", 0, -10)

    local runicDD = makeDropdown(parent, "Runic power bar text", TEXT_FORMAT_OPTIONS,
        function() return readBarFormat("showRunicText") end,
        function(v) visual().showRunicText = v; notify() end)
    runicDD:SetPoint("TOPLEFT", energyDD, "BOTTOMLEFT", 0, -10)

    local cbCombo = makeCheckbox(parent, "Show combo point count next to pips",
        function() return visual().showComboCount end,
        function(v) visual().showComboCount = v; notify() end)
    cbCombo:SetPoint("TOPLEFT", runicDD, "BOTTOMLEFT", 18, -2)

    local cbHaloOOC = makeCheckbox(parent, "Hide pressure halo out of combat",
        function() return visual().haloInCombatOnly end,
        function(v) visual().haloInCombatOnly = v; notify() end)
    cbHaloOOC:SetPoint("TOPLEFT", cbCombo, "BOTTOMLEFT", 0, -2)

    local cbShowTTD = makeCheckbox(parent, "Show TTD readout on the HP bar",
        function()
            local v = visual().showTTD
            if v == nil then return true end
            return v ~= false
        end,
        function(v) visual().showTTD = v end)
    cbShowTTD:SetPoint("TOPLEFT", cbHaloOOC, "BOTTOMLEFT", 0, -2)

    -- TTD position for vertical HP bars. Horizontal bars always show TTD to
    -- the right (no setting). The setting is read on every applyTTDText
    -- call so changing it is live (next pressure tick).
    local ttdPosDD = makeDropdown(parent,
        "TTD position (vertical bars)",
        {
            { key = "below", text = "Below bar" },
            { key = "above", text = "Above bar" },
        },
        function() return visual().ttdPositionVertical or "below" end,
        function(v) visual().ttdPositionVertical = v end)
    ttdPosDD:SetPoint("TOPLEFT", cbShowTTD, "BOTTOMLEFT", -18, -10)

    local styleDD = makeDropdown(parent,
        "Default style for new blocks",
        {
            { key = "standard", text = "Standard (flat)"           },
            { key = "glossy",   text = "Glossy (gradient overlay)" },
        },
        function() return visual().defaultBlockStyle end,
        function(v) visual().defaultBlockStyle = v end)
    -- Note: keep the long labels here in the Visual tab where horizontal
    -- space allows them. The per-row Style dropdown in the Blocks tab uses
    -- the short labels (STYLE_OPTIONS) to fit the row layout.
    styleDD:SetPoint("TOPLEFT", ttdPosDD, "BOTTOMLEFT", 0, -8)

    -- Tell the scrollframe how tall the content actually is. ~520 px covers
    -- the current widget stack with breathing room; if more settings are
    -- added later, bump this.
    parent:SetHeight(560)
end

----------------------------------------------------------------
-- Blocks tab — full per-block editor
----------------------------------------------------------------
-- Each row is a block, rendered with two stripes:
--   Top stripe:    id | position | orientation toggle | style dropdown | Delete
--   Bottom stripe: Widgets:  [chip] [chip] ...  [+ Add ▼]
-- Chip layout: [◀ widget_id ▶ ×]   ◀/▶ swap with neighbour, × removes.
-- Every edit calls BlockManager.RebuildBlock(id) so the HUD updates live;
-- structural changes (add/remove block) call BM.Build() once.

local BLOCK_ROW_PAD      = 6
local CHIP_W             = 80
local CHIP_H             = 20
local CHIP_GAP           = 4
local CHIP_LINE_H        = CHIP_H + 4
local TOP_STRIPE_H       = 28      -- id, pos, orient, style, delete
local BOTTOM_STRIPE_H    = 28      -- + Add widget   |   Scale slider
local CHIP_AREA_LEFT     = 64      -- margin + "Widgets:" label + gap
local CHIP_AREA_RIGHT_PAD = 6      -- right margin inside the row
local CHIP_AREA_W_FALLBACK = 440   -- before listHost has a real width
local STYLE_OPTIONS = {
    { key = "standard", text = "Standard" },
    { key = "glossy",   text = "Glossy"   },
}
local blockRows = {}

local function generateBlockId()
    local used = {}
    if AegisDBChar and AegisDBChar.blocks then
        for _, b in ipairs(AegisDBChar.blocks) do
            if b.id then used[b.id] = true end
        end
    end
    local i = 1
    while used["block" .. i] do i = i + 1 end
    return "block" .. i
end

local function findBlockIndex(id)
    if not (AegisDBChar and AegisDBChar.blocks and id) then return nil end
    for i, b in ipairs(AegisDBChar.blocks) do
        if b.id == id then return i end
    end
    return nil
end

local function rebuildOne(id)
    if ns.BlockManager and ns.BlockManager.RebuildBlock then
        ns.BlockManager.RebuildBlock(id)
    end
end

----------------------------------------------------------------
-- Widget chip (one per widget id inside a block)
----------------------------------------------------------------

local function makeChip(parent, blockId, slotIndex, widgetId)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetSize(CHIP_W, CHIP_H)

    local bg = chip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.18, 0.18, 0.20, 0.85)

    local left = CreateFrame("Button", nil, chip)
    left:SetSize(14, CHIP_H)
    left:SetPoint("LEFT", chip, "LEFT", 0, 0)
    left:SetNormalFontObject("GameFontHighlightSmall")
    left:SetText("<")

    local right = CreateFrame("Button", nil, chip)
    right:SetSize(14, CHIP_H)
    right:SetPoint("RIGHT", chip, "RIGHT", -16, 0)
    right:SetNormalFontObject("GameFontHighlightSmall")
    right:SetText(">")

    local del = CreateFrame("Button", nil, chip)
    del:SetSize(14, CHIP_H)
    del:SetPoint("RIGHT", chip, "RIGHT", -1, 0)
    del:SetNormalFontObject("GameFontRedSmall")
    del:SetText("x")

    local label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", left, "RIGHT", 2, 0)
    label:SetPoint("RIGHT", right, "LEFT", -2, 0)
    label:SetJustifyH("CENTER")
    label:SetText(widgetId)

    local function swap(delta)
        local idx = findBlockIndex(blockId)
        if not idx then return end
        local b = AegisDBChar.blocks[idx]
        if not b.widgets then return end
        local target = slotIndex + delta
        if target < 1 or target > #b.widgets then return end
        b.widgets[slotIndex], b.widgets[target] = b.widgets[target], b.widgets[slotIndex]
        rebuildOne(blockId)
        S.Refresh()
    end

    left:SetScript("OnClick", function() swap(-1) end)
    right:SetScript("OnClick", function() swap(1)  end)
    del:SetScript("OnClick", function()
        local idx = findBlockIndex(blockId)
        if not idx then return end
        local b = AegisDBChar.blocks[idx]
        if not b.widgets then return end
        tremove(b.widgets, slotIndex)
        rebuildOne(blockId)
        S.Refresh()
    end)

    return chip
end

local function catalogIds()
    local ids = {}
    if ns.WidgetCatalog then
        for k in pairs(ns.WidgetCatalog) do tinsert(ids, k) end
        table.sort(ids)
    end
    return ids
end

-- Re-bind the row's persistent "+ Add widget" dropdown to the current block id.
-- The dropdown frame itself is created once in getBlockRow; re-creating it on
-- every refresh would leak global names (UIDropDownMenuTemplate requires a
-- unique name per frame).
local function bindAddDropdown(dd, blockId)
    UIDropDownMenu_SetText(dd, "+ Add widget")
    UIDropDownMenu_Initialize(dd, function()
        for _, wid in ipairs(catalogIds()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = wid
            info.value = wid
            info.notCheckable = true
            info.func = function()
                local idx = findBlockIndex(blockId)
                if not idx then return end
                local b = AegisDBChar.blocks[idx]
                b.widgets = b.widgets or {}
                tinsert(b.widgets, wid)
                rebuildOne(blockId)
                S.Refresh()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

----------------------------------------------------------------
-- Row factory: builds the persistent widgets that don't depend on
-- the block's contents. The chip strip and add-dropdown are rebuilt
-- per refresh because their handlers close over slot indices.
----------------------------------------------------------------

local function getBlockRow(parent, i)
    if blockRows[i] then return blockRows[i] end
    local row = CreateFrame("Frame", nil, parent)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.08, 0.08, 0.08, 0.6)

    -- Top stripe: id | pos | orient | style | delete
    row.id = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.id:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -6)
    row.id:SetWidth(54)
    row.id:SetJustifyH("LEFT")

    row.pos = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.pos:SetPoint("LEFT", row.id, "RIGHT", 4, 0)
    row.pos:SetWidth(110)
    row.pos:SetJustifyH("LEFT")

    row.orient = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.orient:SetSize(56, 20)
    row.orient:SetPoint("LEFT", row.pos, "RIGHT", 4, 0)

    row.styleDD = CreateFrame("Frame", uniqName("BlockStyle"), row, "UIDropDownMenuTemplate")
    row.styleDD:SetPoint("LEFT", row.orient, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(row.styleDD, 80)

    row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.del:SetSize(60, 20)
    row.del:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -6)
    row.del:SetText("Delete")

    -- Curve dropdown: only meaningful for vertical-orientation blocks (tall
    -- vertical bars side-by-side, where the texture-based ArcLeft / ArcRight
    -- shapes apply). Hidden in horizontal blocks. Sits to the right of
    -- styleDD so they read as a group.
    row.curveDD = CreateFrame("Frame", uniqName("BlockCurve"), row, "UIDropDownMenuTemplate")
    row.curveDD:SetPoint("LEFT", row.styleDD, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(row.curveDD, 60)

    -- Middle stripe: "Widgets:" label + chip area (variable height)
    row.widgetsLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.widgetsLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -(TOP_STRIPE_H + 2))
    row.widgetsLabel:SetText("Widgets:")
    row.widgetsLabel:SetWidth(54)

    row.chipHost = CreateFrame("Frame", nil, row)
    row.chipHost:SetPoint("TOPLEFT", row, "TOPLEFT", CHIP_AREA_LEFT, -TOP_STRIPE_H)
    -- chipHost size set per-refresh based on chip count and row width.

    -- Bottom stripe: + Add widget   |   Scale: [slider] xx%
    row.addDD = CreateFrame("Frame", uniqName("BlockAdd"), row, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(row.addDD, 70)

    row.scaleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.scaleLabel:SetText("Scale:")

    row.scale = CreateFrame("Slider", uniqName("BlockScale"), row, "OptionsSliderTemplate")
    row.scale:SetMinMaxValues(0.5, 2.0)
    row.scale:SetValueStep(0.05)
    if row.scale.SetObeyStepOnDrag then row.scale:SetObeyStepOnDrag(true) end
    row.scale:SetWidth(100)
    row.scale:SetHeight(14)
    -- OptionsSliderTemplate creates Low/High/Text font strings; we don't want
    -- the min/max labels on this compact slider.
    local snm = row.scale:GetName()
    if snm then
        local lo, hi, tx = _G[snm .. "Low"], _G[snm .. "High"], _G[snm .. "Text"]
        if lo then lo:SetText("") end
        if hi then hi:SetText("") end
        if tx then tx:SetText("") end
    end

    row.scaleValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Fixed width so the slider's right edge does not jitter as the text
    -- swings between "50%" and "200%" (FontStrings auto-size to content).
    row.scaleValue:SetWidth(36)
    row.scaleValue:SetJustifyH("RIGHT")

    -- Per-block gap slider (px between widgets in the layout). Compact like
    -- the scale slider; lives on the bottom stripe between Add and Scale.
    row.gapLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gapLabel:SetText("Gap:")

    row.gap = CreateFrame("Slider", uniqName("BlockGap"), row, "OptionsSliderTemplate")
    -- Negative gaps overlap widgets in the layout — useful for curved bars
    -- where the texture canvas has transparent padding around the silhouette,
    -- so a positive 0px "gap" still leaves visible empty space between bars.
    row.gap:SetMinMaxValues(-30, 30)
    row.gap:SetValueStep(1)
    if row.gap.SetObeyStepOnDrag then row.gap:SetObeyStepOnDrag(true) end
    row.gap:SetWidth(60)
    row.gap:SetHeight(14)
    local gnm = row.gap:GetName()
    if gnm then
        local lo, hi, tx = _G[gnm .. "Low"], _G[gnm .. "High"], _G[gnm .. "Text"]
        if lo then lo:SetText("") end
        if hi then hi:SetText("") end
        if tx then tx:SetText("") end
    end

    row.gapValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Wide enough for "-10px" through "30px". 28px clipped the leading "-"
    -- of two-digit negatives onto the previous line.
    row.gapValue:SetWidth(36)
    row.gapValue:SetJustifyH("RIGHT")

    row._chips = {}

    blockRows[i] = row
    return row
end

-- Lay out the chips inside row.chipHost, wrapping to the next line when
-- the row width is exceeded. Returns the number of chip lines used (>= 1
-- so the chip area never collapses to zero height — empty blocks still
-- get one empty line so the bottom stripe sits where the user expects).
local function refreshChips(row, b, parentWidth)
    -- Chip frames are unnamed (no global name pool to leak into) so it is
    -- safe to recreate them per refresh. The chip closures capture their
    -- slotIndex by upvalue, which is the simplest correct way to handle
    -- reorder/delete.
    for _, c in ipairs(row._chips) do
        c:Hide(); c:SetParent(nil)
    end
    wipe(row._chips)

    -- Compute available width for chips. parentWidth is the listHost width
    -- passed in by refreshBlockRows; on the very first refresh that may not
    -- be valid yet, so fall back to a constant matching the default panel size.
    local availW = (parentWidth or 0) - 8 - CHIP_AREA_LEFT - CHIP_AREA_RIGHT_PAD
    if availW < 200 then availW = CHIP_AREA_W_FALLBACK end

    local chipsPerLine = math.floor((availW + CHIP_GAP) / (CHIP_W + CHIP_GAP))
    if chipsPerLine < 1 then chipsPerLine = 1 end

    local widgets = b.widgets or {}
    local count = #widgets
    for slot, wid in ipairs(widgets) do
        local chip = makeChip(row.chipHost, b.id, slot, wid)
        local lineIdx = math.floor((slot - 1) / chipsPerLine)
        local colIdx  = (slot - 1) % chipsPerLine
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", row.chipHost, "TOPLEFT",
            colIdx * (CHIP_W + CHIP_GAP),
            -lineIdx * CHIP_LINE_H)
        tinsert(row._chips, chip)
    end

    local lines = (count > 0) and math.ceil(count / chipsPerLine) or 1
    row.chipHost:SetSize(availW, lines * CHIP_LINE_H)

    bindAddDropdown(row.addDD, b.id)
    return lines
end

local function refreshStyleDropdown(row, b)
    local dd = row.styleDD

    local function applyText(key)
        for _, opt in ipairs(STYLE_OPTIONS) do
            if opt.key == key then UIDropDownMenu_SetText(dd, opt.text); break end
        end
    end

    UIDropDownMenu_Initialize(dd, function()
        for _, opt in ipairs(STYLE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.key
            info.checked = (b.style or "standard") == opt.key
            info.func = function(self)
                local idx = findBlockIndex(b.id)
                if not idx then return end
                AegisDBChar.blocks[idx].style = self.value
                applyText(self.value)
                rebuildOne(b.id)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    applyText(b.style or "standard")
end

local CURVE_OPTIONS = {
    { key = "none",  text = "Normal"  },
    { key = "left",  text = "Left ("  },
    { key = "right", text = "Right )" },
}

local function refreshCurveDropdown(row, b)
    -- Only show in vertical blocks (tall vertical bars side-by-side); the
    -- texture set is designed for that direction. In horizontal blocks the
    -- dropdown is hidden so the user is not tempted to pick a value that
    -- would have no visual effect.
    local visible = (b.orientation == "vertical")
    if not visible then
        row.curveDD:Hide()
        return
    end
    row.curveDD:Show()

    local dd = row.curveDD
    local function applyText(key)
        for _, opt in ipairs(CURVE_OPTIONS) do
            if opt.key == key then UIDropDownMenu_SetText(dd, opt.text); break end
        end
    end

    UIDropDownMenu_Initialize(dd, function()
        for _, opt in ipairs(CURVE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.key
            info.checked = (b.curve or "none") == opt.key
            info.func = function(self)
                local idx = findBlockIndex(b.id)
                if not idx then return end
                AegisDBChar.blocks[idx].curve = self.value
                applyText(self.value)
                rebuildOne(b.id)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    applyText(b.curve or "none")
end

local function bindRowScale(row, b)
    local function setLabel(v)
        row.scaleValue:SetText(("%d%%"):format(math.floor(v * 100 + 0.5)))
    end
    -- Clear before SetValue so the old handler (which closed over a stale
    -- block ref when the row is reused for a different block) does not fire
    -- with the new SetValue side-effect.
    row.scale:SetScript("OnValueChanged", nil)
    row.scale:SetValue(b.scale or 1.0)
    setLabel(b.scale or 1.0)
    row.scale:SetScript("OnValueChanged", function(self, v)
        local idx = findBlockIndex(b.id)
        if not idx then return end
        AegisDBChar.blocks[idx].scale = v
        local live = ns.BlockManager and ns.BlockManager.GetBlockByConfigId(b.id)
        if live and live.frame then live.frame:SetScale(v) end
        setLabel(v)
    end)
end

local function bindRowGap(row, b)
    local function setLabel(v)
        row.gapValue:SetText(("%dpx"):format(math.floor(v + 0.5)))
    end
    row.gap:SetScript("OnValueChanged", nil)
    row.gap:SetValue(b.gap or 4)
    setLabel(b.gap or 4)
    row.gap:SetScript("OnValueChanged", function(self, v)
        local idx = findBlockIndex(b.id)
        if not idx then return end
        local intV = math.floor(v + 0.5)
        AegisDBChar.blocks[idx].gap = intV
        -- Gap drives widget positioning; relayout the block in place to
        -- pick up the new spacing without flickering the rest of the HUD.
        rebuildOne(b.id)
        setLabel(intV)
    end)
end

local function refreshBlockRows(parent)
    local blocks = (AegisDBChar and AegisDBChar.blocks) or {}
    for _, row in pairs(blockRows) do row:Hide() end

    local parentW = parent:GetWidth() or 0
    local cursor = 0
    for i, b in ipairs(blocks) do
        local row = getBlockRow(parent, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  4, -cursor)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -cursor)

        row.id:SetText(b.id or "?")

        local p = b.position or {}
        row.pos:SetText(("@ %s %+d,%+d"):format(
            p.point or "?", p.xOffset or 0, p.yOffset or 0))

        local orient = (b.orientation == "horizontal") and "horizontal" or "vertical"
        row.orient:SetText(orient == "horizontal" and "Horiz." or "Vert.")
        row.orient:SetScript("OnClick", function()
            local idx = findBlockIndex(b.id)
            if not idx then return end
            local cur = AegisDBChar.blocks[idx].orientation
            AegisDBChar.blocks[idx].orientation =
                (cur == "horizontal") and "vertical" or "horizontal"
            rebuildOne(b.id)
            S.Refresh()
        end)

        refreshStyleDropdown(row, b)
        refreshCurveDropdown(row, b)

        row.del:SetScript("OnClick", function()
            local idx = findBlockIndex(b.id)
            if not idx then return end
            tremove(AegisDBChar.blocks, idx)
            if ns.BlockManager and ns.BlockManager.Build then
                ns.BlockManager.Build()
            end
            S.Refresh()
        end)

        local lines = refreshChips(row, b, parentW)

        -- Bottom stripe layout: + Add widget (left), Gap slider (middle),
        -- Scale slider (right). UIDropDownMenuTemplate has ~16px of internal
        -- left padding, hence the -16 nudge on addDD.
        local bottomY = TOP_STRIPE_H + lines * CHIP_LINE_H + 4
        row.addDD:ClearAllPoints()
        row.addDD:SetPoint("TOPLEFT", row, "TOPLEFT", CHIP_AREA_LEFT - 16, -bottomY)

        -- Scale slider anchored from the right edge of the row.
        row.scaleValue:ClearAllPoints()
        row.scaleValue:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -(bottomY + 6))
        row.scale:ClearAllPoints()
        row.scale:SetPoint("RIGHT", row.scaleValue, "LEFT", -6, 0)
        row.scaleLabel:ClearAllPoints()
        row.scaleLabel:SetPoint("RIGHT", row.scale, "LEFT", -6, 0)

        -- Gap slider sits to the left of the scale group, with breathing room.
        row.gapValue:ClearAllPoints()
        row.gapValue:SetPoint("RIGHT", row.scaleLabel, "LEFT", -12, 0)
        row.gap:ClearAllPoints()
        row.gap:SetPoint("RIGHT", row.gapValue, "LEFT", -6, 0)
        row.gapLabel:ClearAllPoints()
        row.gapLabel:SetPoint("RIGHT", row.gap, "LEFT", -6, 0)

        bindRowScale(row, b)
        bindRowGap(row, b)

        local rowH = TOP_STRIPE_H + lines * CHIP_LINE_H + BOTTOM_STRIPE_H
        row:SetHeight(rowH)
        cursor = cursor + rowH + BLOCK_ROW_PAD

        row:Show()
    end
    return cursor
end

local function buildBlocksTab(parent)
    local tabFrame = parent

    local hdr = makeHeader(tabFrame, "Blocks")
    hdr:SetPoint("TOPLEFT", tabFrame, "TOPLEFT", 8, -4)

    local hint = makeBody(tabFrame,
        "Per row: change orientation, style, add/remove/reorder widgets, "
        .. "or delete the block. Use 'Move blocks' below to drag them on screen.")
    hint:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 4, -6)
    hint:SetWidth(500)
    hint:SetJustifyH("LEFT")

    -- ScrollFrame holding the per-block rows. The footer (add / move / reset)
    -- stays anchored to the tab itself, OUTSIDE the scroll, so action buttons
    -- are always reachable no matter how many blocks the user has stacked.
    local sf = CreateFrame("ScrollFrame", uniqName("BlocksScroll"), tabFrame,
        "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     hint,     "BOTTOMLEFT", -4, -8)
    sf:SetPoint("BOTTOMRIGHT", tabFrame, "BOTTOMRIGHT", -28, 36)

    local listHost = CreateFrame("Frame", nil, sf)
    listHost:SetSize(500, 1)  -- height set per refresh below
    sf:SetScrollChild(listHost)

    local function refreshList()
        local total = refreshBlockRows(listHost)
        listHost:SetHeight(math.max(1, total))
    end
    refreshList()
    tinsert(S.refreshHandlers, refreshList)

    parent = tabFrame  -- footer buttons anchor to the tab, not the scroll

    -- Footer
    local addBtn = makeButton(parent, "+ Add empty block", 140, function()
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
            gap         = 4,
            curve       = "none",
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

    -- Move-mode toggle: flips the global lock flag so the user can drag
    -- blocks on screen from the panel itself, no slash command needed.
    local moveBtn = makeButton(parent, "Move blocks", 110, function() end)
    moveBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    local function refreshMoveBtn()
        local locked = (ns.BlockManager and ns.BlockManager.IsLocked()) ~= false
        moveBtn:SetText(locked and "Move blocks" or "Lock positions")
    end
    moveBtn:SetScript("OnClick", function()
        if not ns.BlockManager then return end
        if ns.BlockManager.IsLocked() then
            ns.BlockManager.Unlock()
        else
            ns.BlockManager.Lock()
        end
        refreshMoveBtn()
        S.Refresh() -- refresh row position labels after a save
    end)
    refreshMoveBtn()
    tinsert(S.refreshHandlers, refreshMoveBtn)

    local resetBtn = makeButton(parent, "Reset to defaults", 140, function()
        if StaticPopup_Show then StaticPopup_Show("AEGIS_RESET_CONFIRM") end
    end)
    resetBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)
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
