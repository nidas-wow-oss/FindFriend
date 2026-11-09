local FF = FF

local ROW_W        = 48
local ROW_H_BASE   = 74
local ROW_H_HEALTH = 86

local function RowHeight()
    return (FF_Settings and FF_Settings.showHealth) and ROW_H_HEALTH or ROW_H_BASE
end

local MEDIA = "Interface\\AddOns\\FindFriend\\Media\\"

local ICON_STYLES = {
    { key = "1", file = MEDIA .. "HUDArrow"      },
    { key = "2", file = MEDIA .. "HUDArrowChip"  },
    { key = "3", file = MEDIA .. "HUDArrowGloss" },
    { key = "4", file = MEDIA .. "HUDArrowGlow"  },
    { key = "5", file = MEDIA .. "HUDArrowNeon"  },
    { key = "6", file = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW" },
}

local LEGACY = {
    arrow = "1", hud = "1",
    chip  = "2", ["hud-chip"]  = "2",
    gloss = "3", ["hud-gloss"] = "3",
    glow  = "4", ["hud-glow"]  = "4",
    neon  = "5", ["hud-neon"]  = "5",
    blizz = "6", blizzard      = "6",
}

local FILE_BY_KEY, INDEX_BY_KEY = {}, {}
for i, s in ipairs(ICON_STYLES) do
    FILE_BY_KEY[s.key]  = s.file
    INDEX_BY_KEY[s.key] = i
end

function FF:IsIconStyle(key)
    if key == nil then return false end
    key = strlower(key)
    return (FILE_BY_KEY[key] or LEGACY[key]) ~= nil
end

function FF:NormalizeIconStyle(key)
    key = key and strlower(key) or nil
    key = LEGACY[key] or key
    if not key or not FILE_BY_KEY[key] then return ICON_STYLES[1].key end
    return key
end

function FF:NextIconStyle()
    local cur = self:NormalizeIconStyle(FF_Settings and FF_Settings.iconStyle)
    local i = (INDEX_BY_KEY[cur] or 0) + 1
    if i > #ICON_STYLES then i = 1 end
    return ICON_STYLES[i].key
end

function FF:IconStyleList()
    return "1-" .. #ICON_STYLES
end

FF._ICON_BY_STYLE = FILE_BY_KEY
FF._ICON_BLIZZARD = FILE_BY_KEY.blizz

local COLOR_STALE  = { 0.6, 0.6, 0.6, 0.6 }
local COLOR_OTHERZ = { 0.5, 0.7, 1, 0.9 }

local COLOR_ONTOP   = { .2, 1, .2, .4 }
local COLOR_ALIGNED = { .7, .7, 1, 1 }
local COLOR_OFFAIM  = { 1, 1, .5, .9 }

local function HealthColor(pct)
    if pct > 50 then return "|cff40ff40"
    elseif pct > 25 then return "|cffffd100"
    else return "|cffff4040" end
end

FF.BEARING_TAU = 0.12

local ALIGN_ENTER = 5
local ALIGN_EXIT  = 9

local container = CreateFrame("Frame", "FFArrowFrame", UIParent)
container:SetSize(ROW_W, ROW_H_BASE)
container:SetPoint("CENTER", Minimap, "BOTTOM", 0, -40)
container:SetMovable(true)
container:SetClampedToScreen(true)

container:Hide()

local rows = {}

local DOUBLE_CLICK_WINDOW = 0.4

local function GuardarPosicion()
    local point, _, relPoint, x, y = container:GetPoint()
    FF_Settings.point = { point = point, relPoint = relPoint, x = x, y = y }
end

local function NewRow(i)
    local r = {}
    r.frame = CreateFrame("Frame", nil, container)
    r.frame:SetSize(ROW_W, RowHeight())
    r.frame:SetPoint("TOP", container, "TOP", 0, -(i - 1) * RowHeight())

    r.frame:EnableMouse(true)
    r.frame:RegisterForDrag("LeftButton")
    r.frame:SetScript("OnDragStart", function() container:StartMoving() end)
    r.frame:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        GuardarPosicion()
    end)

    r.lastClick = 0
    r.frame:SetScript("OnMouseUp", function(self, button)
        if button and button ~= "LeftButton" then return end
        local now = GetTime()
        if (now - r.lastClick) <= DOUBLE_CLICK_WINDOW then
            r.lastClick = 0
            if r.name then FF:StopTracking(r.name) end
        else
            r.lastClick = now
        end
    end)

    r.frame:SetScript("OnEnter", function(self)
        if not r.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        GameTooltip:AddLine("Double-click to stop tracking", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move all arrows", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    r.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local bg = r.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOP", r.frame, "TOP", 0, 0)
    bg:SetSize(ROW_W, ROW_W)
    bg:SetTexture(0, 0, 0, 0.25)

    r.tex = r.frame:CreateTexture(nil, "ARTWORK")
    r.tex:SetPoint("TOP", r.frame, "TOP", 0, 0)
    r.tex:SetSize(32, 32)

    r.nameText = r.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("TOP", r.frame, "TOP", 0, -ROW_W - 2)

    r.distText = r.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.distText:SetPoint("TOP", r.nameText, "BOTTOM", 0, -1)

    r.hpText = r.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.hpText:SetPoint("TOP", r.distText, "BOTTOM", 0, -1)

    r.etaTicks, r.etaText = 0, ""
    r.frame:Hide()
    return r
end

local function GetRow(i)
    if not rows[i] then rows[i] = NewRow(i) end
    return rows[i]
end

function FF:ApplyArrowIcon()
    FF_Settings = FF_Settings or {}
    local style = self:NormalizeIconStyle(FF_Settings.iconStyle)
    FF_Settings.iconStyle = style
    for _, r in ipairs(rows) do
        r.tex:SetTexture(FILE_BY_KEY[style])
    end
    self._iconStyleApplied = style
end

function FF:ApplySavedPosition()
    local p = FF_Settings and FF_Settings.point
    if p and p.point then
        container:ClearAllPoints()
        container:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    end
end

function FF:RefreshArrows()
    local n = #self.tracked

    local h = RowHeight()
    for i = 1, n do
        local r = GetRow(i)

        r.frame:SetHeight(h)
        r.frame:ClearAllPoints()
        r.frame:SetPoint("TOP", container, "TOP", 0, -(i - 1) * h)
        r.name = self.tracked[i]

        r.hasBearing, r.smDX, r.smDY = false, nil, nil
        r.aligned, r.state = false, nil
        r.etaTicks, r.etaText = 0, ""
        r.tex:SetTexture(FILE_BY_KEY[self:NormalizeIconStyle(FF_Settings and FF_Settings.iconStyle)])
        r.frame:Show()
    end
    for i = n + 1, #rows do
        rows[i].name = nil
        rows[i].frame:Hide()
    end

    if n == 0 then
        container:Hide()
    else
        container:SetHeight(n * h)
        container:Show()
    end

    self._arrowTex = rows[1] and rows[1].tex or nil
end

function FF:ShowArrow() self:RefreshArrows() end
function FF:HideArrow() self:RefreshArrows() end

local function Poner(fs, texto)
    if fs.nufTexto ~= texto then
        fs.nufTexto = texto
        fs:SetText(texto)
    end
end

local ETA_RECALC_TICKS = 10

local function ETATexto(r, speed)
    if not speed or speed <= 0.1 or not r.lastYards then
        r.etaTicks, r.etaText = 3, ""
        return ""
    end
    r.etaTicks = r.etaTicks - 1
    if r.etaTicks <= 0 then
        r.etaTicks = ETA_RECALC_TICKS
        local eta = r.lastYards / speed
        if eta < 60 then
            r.etaText = format(" |cffdfffdf%.0f sec|r", eta)
        else
            r.etaText = format(" |cffdfdfdf%.1f min|r", eta / 60)
        end
    end
    return r.etaText
end

local wowCos = cos or function(d) return math.cos(math.rad(d)) end
local wowSin = sin or function(d) return math.sin(math.rad(d)) end

local function RotateArrow(tex, deg)
    if deg == 0 then
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    local tX1, tX2, tY1, tY2 = -0.5, 0.5, -0.5, 0.5
    local co, si = wowCos(deg), wowSin(deg)
    local t1x = tX1 * co + tY1 * si + .5
    local t1y = tX1 * -si + tY1 * co + .5
    local t2x = tX1 * co + tY2 * si + .5
    local t2y = tX1 * -si + tY2 * co + .5
    local t3x = tX2 * co + tY1 * si + .5
    local t3y = tX2 * -si + tY1 * co + .5
    local t4x = tX2 * co + tY2 * si + .5
    local t4y = tX2 * -si + tY2 * co + .5
    tex:SetTexCoord(t1x, t1y, t2x, t2y, t3x, t3y, t4x, t4y)
end
FF._RotateArrow = RotateArrow

local function RefreshRowInfo(r)
    local name = r.name
    if not name then return end

    local tx, ty, tzone, source, hp = FF:ResolveTarget(name)
    local mp = FF.myPos

    if not tx or not mp then
        Poner(r.nameText, name .. "  |cffaaaaaa(searching...)|r")
        Poner(r.distText, "")
        Poner(r.hpText, "")
        r.tex:SetVertexColor(unpack(COLOR_STALE))
        r.hasBearing = false
        return
    end

    if FF_Settings.showHealth and hp then
        Poner(r.hpText, format("%s%d %%|r", HealthColor(hp), hp))
    else
        Poner(r.hpText, "")
    end

    if mp.zone ~= tzone then

        Poner(r.nameText, format("%s  |cffaaaaaain:|r %s", name, tzone or "?"))
        Poner(r.distText, source == "live" and "" or "(via addon)")
        r.tex:SetVertexColor(unpack(COLOR_OTHERZ))
        r.hasBearing = false
        return
    end

    r.lastDX = tx - mp.x
    r.lastDY = ty - mp.y
    r.hasBearing = true

    local pct = math.sqrt(r.lastDX * r.lastDX + r.lastDY * r.lastDY)

    FF:TryCalibrate(FF:FindAnyUnitToken(name), pct)

    r.lastYards = FF:CalibratedYards(mp.zone, pct)
    r.lastPct   = pct

    local dist, unitLabel = FF:RealDistance(mp.zone, pct)
    local sourceTag = source == "comm" and " |cff8080ff(addon)|r" or ""
    local etaText = ETATexto(r, FF.playerSpeedYps)

    Poner(r.nameText, name)

    if dist then
        Poner(r.distText, format("%.0f %s%s%s", dist, unitLabel, etaText, sourceTag))
    else
        Poner(r.distText, format("%.0f%% of map%s%s", pct, etaText, sourceTag))
    end
end

local function RefreshRowRotation(r, elapsed)
    if not r.hasBearing then

        r.smDX, r.smDY = nil, nil
        return
    end

    if elapsed and r.smDX and r.smDY then
        local k = 1 - math.exp(-elapsed / FF.BEARING_TAU)
        r.smDX = r.smDX + (r.lastDX - r.smDX) * k
        r.smDY = r.smDY + (r.lastDY - r.smDY) * k
    else
        r.smDX, r.smDY = r.lastDX, r.lastDY
    end

    local bearingDeg = math.deg(math.atan2(r.smDX, -r.smDY))

    local facingDeg = 360 - math.deg(GetPlayerFacing() or 0)

    local onTop
    if r.lastYards then
        onTop = r.lastYards < 1
    else
        onTop = (r.lastPct or 0) < 0.3
    end

    local relDeg = onTop and 0 or ((bearingDeg - facingDeg) % 360)
    RotateArrow(r.tex, relDeg)

    local diD = relDeg <= 180 and relDeg or 360 - relDeg

    local aligned = r.aligned
    if aligned then
        if diD > ALIGN_EXIT then aligned = false end
    else
        if diD < ALIGN_ENTER then aligned = true end
    end
    r.aligned = aligned

    if aligned then
        if onTop then
            r.tex:SetVertexColor(unpack(COLOR_ONTOP))
            r.tex:SetBlendMode("BLEND")
        else
            r.tex:SetVertexColor(unpack(COLOR_ALIGNED))
            r.tex:SetBlendMode("ADD")
        end
    else
        r.tex:SetVertexColor(unpack(COLOR_OFFAIM))
        r.tex:SetBlendMode("BLEND")
    end
end

function FF:RefreshTargetInfo()
    for _, r in ipairs(rows) do
        if r.name then RefreshRowInfo(r) end
    end
end

function FF:RefreshRotation(elapsed)
    for _, r in ipairs(rows) do
        if r.name then RefreshRowRotation(r, elapsed) end
    end
end

function FF:UpdateArrow()
    self:RefreshTargetInfo()
    self:RefreshRotation()
end

local dataAccum = 0
container:SetScript("OnUpdate", function(self, elapsed)
    dataAccum = dataAccum + elapsed
    local refrescarDatos = dataAccum >= 0.1
    if refrescarDatos then dataAccum = 0 end

    for _, r in ipairs(rows) do
        if r.name then
            if refrescarDatos then RefreshRowInfo(r) end
            RefreshRowRotation(r, elapsed)
        end
    end
end)
