-- Aegis/UI/TextureBar.lua
-- Replacement for the WoW StatusBar primitive when the bar shape is not a
-- plain rectangle. The fill is achieved by cropping the bar texture's
-- vertical UV via SetTexCoord and resizing the displayed height.
--
-- Why not StatusBar? Blizzard's StatusBar stretches a single texture across
-- the frame; for any non-rectangular shape (curved, beveled, ...) the
-- stretched texture distorts at fractional fills. The TexCoord trick (same
-- one IceHUD uses) keeps the texture pixel-accurate by showing only the
-- bottom N% of it and resizing the frame to match.
--
-- API:
--   local bar = TextureBar.New(parent, w, h, shape, opts)
--     parent : owning frame
--     w, h   : visible bar size in pixels (the texture is scaled to fill it)
--     shape  : "Bar" | "ArcLeft" | "ArcRight"   (file basename under Wide/)
--     opts   : { set = "Wide" | "Thin" } (default "Wide")
--
--   bar:SetMinMaxValues(min, max)
--   bar:SetValue(v)               -- recomputes the fill and height
--   bar:SetStatusBarColor(r,g,b[,a])
--   bar:GetStatusBarTexture()     -- the fill texture (for SetVertexColor etc)
--   bar:SetSize(w, h)             -- resize, preserving the current fill ratio
--
-- The returned object is a Frame with these methods bolted on; it is NOT a
-- WoW StatusBar (does not respond to :GetValue() etc unless added). The
-- subset above is what HealthBar and _ResourceBarBase actually call.

local _, ns = ...
ns.TextureBar = ns.TextureBar or {}
local TextureBar = ns.TextureBar

local TEX_BASE = "Interface\\AddOns\\Aegis\\Textures\\"

local function pathFor(set, shape, isBg)
    return TEX_BASE .. set .. "\\" .. shape .. (isBg and "BG" or "")
end

----------------------------------------------------------------
-- Methods, attached to each Frame returned by New().
----------------------------------------------------------------

local function setMinMaxValues(self, mn, mx)
    self._min = mn or 0
    self._max = mx or 1
    if self._max <= self._min then self._max = self._min + 1 end
    -- Re-apply the current value so the displayed fill picks up the new range.
    self:SetValue(self._value or self._min)
end

local function setValue(self, v)
    v = v or self._min or 0
    self._value = v
    local mn, mx = self._min or 0, self._max or 1
    local scale = (v - mn) / (mx - mn)
    if scale < 0 then scale = 0 elseif scale > 1 then scale = 1 end
    self._scale = scale

    local fill = self._fill
    -- At scale 0 (rage / runic at rest, etc.) hide the fill outright. Setting
    -- height to 0 still leaves a 1-pixel sliver at the texture bottom which,
    -- with the texture's bottom row showing the bar's full-width spine cap,
    -- reads as a thin horizontal line overflowing the curved silhouette.
    if scale <= 0 then
        fill:Hide()
        return
    end
    fill:Show()

    local barH = self._h or 1
    -- Show only the bottom `scale` portion of the texture: TexCoord vertical
    -- range is (1-scale .. 1). The fill frame is anchored bottom and resized
    -- in height so the visible texture region stays pixel-accurate.
    fill:ClearAllPoints()
    fill:SetPoint("BOTTOMLEFT",  self, "BOTTOMLEFT",  0, 0)
    fill:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    fill:SetHeight(barH * scale)
    fill:SetTexCoord(0, 1, 1 - scale, 1)
end

local function setStatusBarColor(self, r, g, b, a)
    self._fill:SetVertexColor(r, g, b, a or 1)
end

local function getStatusBarTexture(self)
    return self._fill
end

local function setSize(self, w, h)
    self._w, self._h = w, h
    -- Frame:SetSize is the original method; it gets shadowed by our table
    -- copy. Call the real one via the metatable lookup that CreateFrame uses.
    -- Easiest: keep a reference to the original SetSize at construction time.
    self._origSetSize(self, w, h)
    -- Re-apply value so the fill height tracks the new bar height.
    self:SetValue(self._value or self._min or 0)
end

----------------------------------------------------------------
-- Constructor.
----------------------------------------------------------------

function TextureBar.New(parent, w, h, shape, opts)
    opts = opts or {}
    local set = opts.set or "Wide"

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(w, h)

    -- Background: dark variant of the shape, sits behind the fill so the
    -- empty portion of the bar reads as a "track". Sublevel 1 (not the
    -- default 0) so consumers like HealthBar can paint a halo at sublevel 0
    -- BEHIND this bg — without forcing the halo to use a negative sublevel,
    -- which 3.3.5a clamps to 0 (and then the halo, created later, ends up
    -- on TOP of the bg by creation order).
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints(frame)
    bg:SetTexture(pathFor(set, shape, true))
    frame._bg = bg

    -- Fill: white silhouette of the same shape, tinted via SetVertexColor.
    -- Anchored to BOTTOMLEFT/BOTTOMRIGHT and grown upward via SetHeight in
    -- setValue() — see the TexCoord trick in the comment at top.
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(pathFor(set, shape, false))
    fill:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    fill:SetHeight(h)
    fill:SetTexCoord(0, 1, 0, 1)
    frame._fill = fill

    frame._w, frame._h = w, h
    frame._min, frame._max, frame._value, frame._scale = 0, 1, 1, 1
    frame._origSetSize = frame.SetSize

    frame.SetMinMaxValues   = setMinMaxValues
    frame.SetValue          = setValue
    frame.SetStatusBarColor = setStatusBarColor
    frame.GetStatusBarTexture = getStatusBarTexture
    frame.SetSize           = setSize

    return frame
end
