-- Aegis/Core/ConfigPanel.lua
-- The Interface Options panel. Surfaces the most-used global settings as
-- sliders / checkboxes / a dropdown. Block management (add / remove /
-- reorder widgets, per-block orientation and style) lives on the slash
-- commands (/ae block ...). A full per-block UI editor is post-1.0.
--
-- Settings apply live: sliders write to AegisDB on change, the values are
-- read by their consumers on the next tick. The exception is the health
-- text format dropdown, which the HealthBar reads each refresh — so a
-- new format takes effect on the next HP change without a /reload.

local _, ns = ...
ns.ConfigPanel = ns.ConfigPanel or {}
local Panel = ns.ConfigPanel

local panel  -- the registered InterfaceOptions frame

----------------------------------------------------------------
-- Builder helpers
----------------------------------------------------------------

-- displayMul lets the visible value differ from the saved value (e.g.
-- store drain as 0.01 fraction, display as "1.0%").
local function makeSlider(parent, name, label, min, max, step,
    getter, setter, fmt, displayMul)
    displayMul = displayMul or 1
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetWidth(220)
    s:SetHeight(16)

    local lo   = _G[name .. "Low"]
    local hi   = _G[name .. "High"]
    local text = _G[name .. "Text"]
    local function f(v)
        return fmt and fmt:format(v * displayMul) or tostring(v * displayMul)
    end
    if lo   then lo:SetText(f(min))   end
    if hi   then hi:SetText(f(max))   end
    if text then text:SetText(label) end

    local valLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valLabel:SetPoint("LEFT", s, "RIGHT", 12, 0)

    local function refresh(v)
        valLabel:SetText(f(v))
    end

    s:SetValue(getter())
    refresh(getter())
    s:SetScript("OnValueChanged", function(self, value)
        setter(value)
        refresh(value)
    end)

    return s
end

local function makeCheckbox(parent, name, label, getter, setter)
    local cb = CreateFrame("CheckButton", name, parent, "OptionsCheckButtonTemplate")
    local lbl = _G[name .. "Text"]
    if lbl then lbl:SetText(label) end
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    return cb
end

local function makeDropdown(parent, name, label, options, getter, setter)
    -- options: ordered list of { key = string, text = string }
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(180, 40)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT", container, "TOPLEFT", 18, 0)
    labelFS:SetText(label)

    local dd = CreateFrame("Frame", name, container, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dd, 160)

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
    applySelection(getter())

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
-- Build
----------------------------------------------------------------

local function pressure()    return AegisDB.pressure              end
local function thresholds()  return AegisDB.pressure.thresholds   end
local function visual()      return AegisDB.visual                end

local function build()
    panel = CreateFrame("Frame", "AegisConfigPanel", UIParent)
    panel.name = "Aegis"

    -- Title and subtitle.
    local title = makeHeader(panel, "Aegis")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local subtitle = makeBody(panel,
        ("v%s - player HUD with pressure tracking"):format(ns.version or "?"))
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- =================== Pressure section ===================
    local pressureHdr = makeHeader(panel, "Pressure")
    pressureHdr:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -24)

    local s1 = makeSlider(panel, "AegisCfgWindow",
        "Sliding window (seconds)", 1, 10, 0.5,
        function() return pressure().windowSeconds end,
        function(v) pressure().windowSeconds = v end,
        "%.1fs")
    s1:SetPoint("TOPLEFT", pressureHdr, "BOTTOMLEFT", 16, -28)

    local s2 = makeSlider(panel, "AegisCfgWarnTTD",
        "Warning TTD", 5, 30, 1,
        function() return thresholds().warningTTD end,
        function(v) thresholds().warningTTD = v end,
        "%ds")
    s2:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -32)

    local s3 = makeSlider(panel, "AegisCfgCritTTD",
        "Critical TTD", 1, 10, 1,
        function() return thresholds().criticalTTD end,
        function(v) thresholds().criticalTTD = v end,
        "%ds")
    s3:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -32)

    local s4 = makeSlider(panel, "AegisCfgWarnDrain",
        "Warning drain", 0.005, 0.05, 0.005,
        function() return thresholds().warningDrain end,
        function(v) thresholds().warningDrain = v end,
        "%.1f%%/s", 100)
    s4:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -32)

    local s5 = makeSlider(panel, "AegisCfgCritDrain",
        "Critical drain", 0.01, 0.10, 0.005,
        function() return thresholds().criticalDrain end,
        function(v) thresholds().criticalDrain = v end,
        "%.1f%%/s", 100)
    s5:SetPoint("TOPLEFT", s4, "BOTTOMLEFT", 0, -32)

    local s6 = makeSlider(panel, "AegisCfgHyst",
        "Hysteresis (state-down delay)", 0.0, 3.0, 0.1,
        function() return pressure().hysteresisSeconds end,
        function(v) pressure().hysteresisSeconds = v end,
        "%.1fs")
    s6:SetPoint("TOPLEFT", s5, "BOTTOMLEFT", 0, -32)

    local s7 = makeSlider(panel, "AegisCfgHealSustain",
        "Healing sustain time", 0.0, 5.0, 0.1,
        function() return pressure().healingSustainTime end,
        function(v) pressure().healingSustainTime = v end,
        "%.1fs")
    s7:SetPoint("TOPLEFT", s6, "BOTTOMLEFT", 0, -32)

    local cbSound = makeCheckbox(panel, "AegisCfgSound",
        "Play RaidWarning sound on critical entry",
        function() return pressure().soundOnCritical end,
        function(v) pressure().soundOnCritical = v end)
    cbSound:SetPoint("TOPLEFT", s7, "BOTTOMLEFT", -4, -16)

    -- =================== Visual section ===================
    local visualHdr = makeHeader(panel, "Visual")
    visualHdr:SetPoint("TOPLEFT", panel, "TOPRIGHT", -340, -56)

    local healthFmt = makeDropdown(panel, "AegisCfgHealthFmt",
        "Health text format",
        {
            { key = "value",             text = "Value (1234)"        },
            { key = "percent",           text = "Percent (47%)"       },
            { key = "value_and_percent", text = "Value + Percent"     },
            { key = "none",              text = "None (no text)"      },
        },
        function() return visual().showHealthText end,
        function(v) visual().showHealthText = v end)
    healthFmt:SetPoint("TOPLEFT", visualHdr, "BOTTOMLEFT", 0, -8)

    local cbResourceText = makeCheckbox(panel, "AegisCfgResourceText",
        "Show 'current / max' on resource bars",
        function() return visual().showResourceText ~= false end,
        function(v) visual().showResourceText = v end)
    cbResourceText:SetPoint("TOPLEFT", healthFmt, "BOTTOMLEFT", 18, -8)

    local cbHaloOOC = makeCheckbox(panel, "AegisCfgHaloOOC",
        "Hide pressure halo out of combat",
        function() return visual().haloInCombatOnly end,
        function(v) visual().haloInCombatOnly = v end)
    cbHaloOOC:SetPoint("TOPLEFT", cbResourceText, "BOTTOMLEFT", 0, -4)

    local styleDD = makeDropdown(panel, "AegisCfgDefaultStyle",
        "Default block style (for /ae block add)",
        {
            { key = "standard", text = "Standard (flat)"           },
            { key = "glossy",   text = "Glossy (gradient overlay)" },
        },
        function() return visual().defaultBlockStyle end,
        function(v) visual().defaultBlockStyle = v end)
    styleDD:SetPoint("TOPLEFT", cbHaloOOC, "BOTTOMLEFT", -18, -8)

    -- =================== Blocks section ===================
    local blocksHdr = makeHeader(panel, "Blocks")
    blocksHdr:SetPoint("TOPLEFT", styleDD, "BOTTOMLEFT", 0, -32)

    local blocksHelp = makeBody(panel,
        "Block management lives on slash commands:\n"
        .. "  /ae block list                                 - list blocks\n"
        .. "  /ae block add <h|v> <widget1> [widget2] ...    - new block at center\n"
        .. "  /ae block remove <id>                          - delete a block\n"
        .. "  /ae unlock                                     - drag mode for all blocks")
    blocksHelp:SetPoint("TOPLEFT", blocksHdr, "BOTTOMLEFT", 4, -8)
    blocksHelp:SetWidth(420)

    local resetBtn = makeButton(panel, "Reset blocks to defaults", 200, function()
        if StaticPopup_Show then StaticPopup_Show("AEGIS_RESET_CONFIRM") end
    end)
    resetBtn:SetPoint("TOPLEFT", blocksHelp, "BOTTOMLEFT", -4, -16)

    InterfaceOptions_AddCategory(panel)
end

----------------------------------------------------------------
-- Public
----------------------------------------------------------------

function Panel.Build()
    if panel then return panel end
    build()
    return panel
end

-- Open the panel. WoW's InterfaceOptionsFrame_OpenToCategory has a
-- well-known quirk in 3.3.5a: the first call sometimes opens the parent
-- frame without scrolling to the addon's category, so we call it twice.
function Panel.Open()
    if not panel then build() end
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
