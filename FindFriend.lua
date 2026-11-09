FF = FF or {}

FF.ADDON_PREFIX = "FFLoc1"

FF.SAMPLE_INTERVAL   = 0.1
FF.PING_INTERVAL     = 1
FF.REQUEST_INTERVAL  = 15
FF.STALE_AFTER       = 45
FF.WATCH_EXPIRES     = 300

FF.MAX_TRACKED = 3
FF.tracked     = {}
FF.myPos       = nil

FF.reports     = {}
FF.watchers    = {}

local FF_TRACE = false
local function DEBUG(...)
    if FF_TRACE then
        print("|cff40ff40[FF]|r", ...)
    end
end

function FF:SamplePositions(units)
    local px, py = GetPlayerMapPosition("player")
    local zone = GetRealZoneText()
    local out = {}

    local function LeerUnidades()
        if not units then return end
        for _, u in ipairs(units) do
            local x, y = GetPlayerMapPosition(u)
            if x and not (x == 0 and y == 0) then

                local hp, hpMax = UnitHealth(u), UnitHealthMax(u)
                local pct
                if hp and hpMax and hpMax > 0 then
                    pct = math.floor(hp / hpMax * 100 + 0.5)
                end
                out[u] = { x = x * 100, y = y * 100, hp = pct }
            end
        end
    end

    if px and not (px == 0 and py == 0) then

        LeerUnidades()
    else

        local prevContinent, prevZone = GetCurrentMapContinent(), GetCurrentMapZone()
        SetMapToCurrentZone()
        px, py = GetPlayerMapPosition("player")
        zone = GetRealZoneText()
        LeerUnidades()
        SetMapZoom(prevContinent, prevZone)
    end

    if not px or (px == 0 and py == 0) then
        px, py = nil, nil
    end
    if px then px, py = px * 100, py * 100 end

    return px, py, zone, out
end

function FF:FindGroupUnit(name)
    if not name then return nil end
    local target = strlower(name)

    local myName = UnitName("player")
    if myName and strlower(myName) == target then
        return "player"
    end

    local prefix, count = "party", GetNumPartyMembers()
    if GetNumRaidMembers() > 0 then
        prefix, count = "raid", GetNumRaidMembers()
    end

    for i = 1, count do
        local unit = prefix .. i
        if not UnitIsUnit(unit, "player") then
            local uName = UnitName(unit)
            if uName and strlower(uName) == target then
                return unit
            end
        end
    end
    return nil
end

function FF:FindAnyUnitToken(name)
    local unit = self:FindGroupUnit(name)
    if unit then return unit end
    if not name then return nil end

    local target = strlower(name)
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        local uName = UnitName(u)
        if uName and strlower(uName) == target then
            return u
        end
    end
    return nil
end

FF.YARDS_TO_METERS = 0.9144

local INTERACT_ORDER = { 3, 2, 1, 4 }
local INTERACT_YARDS = { [1] = 28, [2] = 11.11, [3] = 9.9, [4] = 28 }

function FF:TryCalibrate(unit, pctDist)
    if not unit or not pctDist or pctDist < 0.3 then
        return
    end
    local zone = self.myPos and self.myPos.zone
    if not zone then return end
    FF_Settings.zoneScale = FF_Settings.zoneScale or {}

    for _, idx in ipairs(INTERACT_ORDER) do
        if CheckInteractDistance(unit, idx) then
            local yards = INTERACT_YARDS[idx]
            local scale = yards / pctDist
            local prev = FF_Settings.zoneScale[zone]

            if not prev or yards <= prev.yards then
                FF_Settings.zoneScale[zone] = { scale = scale, yards = yards }
            end
            return
        end
    end
end

function FF:CalibratedYards(zone, pctDist)
    local cal = FF_Settings.zoneScale and FF_Settings.zoneScale[zone]
    if not cal then return nil end
    return pctDist * cal.scale
end

function FF:RealDistance(zone, pctDist)
    local yards = self:CalibratedYards(zone, pctDist)
    if not yards then return nil end
    if FF_Settings.units == "meters" then
        return yards * self.YARDS_TO_METERS, "m"
    end
    return yards, "yd"
end

FF.SPEED_EPS    = 0.0005
FF.SPEED_MIN_DT = 0.5

function FF:UpdateOwnSpeed(px, py, zone, now)
    if self._psZone ~= zone then

        self._psX, self._psY, self._psCT, self._psZone = px, py, now, zone
        self.playerSpeedYps = nil
        return
    end

    local cal = FF_Settings.zoneScale and FF_Settings.zoneScale[zone]

    if math.abs(px - self._psX) < self.SPEED_EPS and math.abs(py - self._psY) < self.SPEED_EPS then

        self.playerSpeedYps = cal and 0 or nil
        self._psCT = now
        self._psX, self._psY = px, py
        return
    end

    local dt = now - self._psCT
    if dt > self.SPEED_MIN_DT then
        if cal then
            local pctMoved = math.sqrt((px - self._psX) ^ 2 + (py - self._psY) ^ 2)
            self.playerSpeedYps = pctMoved * cal.scale / dt
        else
            self.playerSpeedYps = nil
        end
        self._psCT = now
        self._psX, self._psY = px, py
    end

end

function FF:Sample()

    local units, nameOfUnit = {}, {}
    for _, name in ipairs(self.tracked) do
        local unit = self:FindGroupUnit(name)
        if unit and unit ~= "player" then
            units[#units + 1] = unit
            nameOfUnit[unit]  = name
        end
    end

    local px, py, zone, pos = self:SamplePositions(units)
    local now = GetTime()

    if px then
        self.myPos = { x = px, y = py, zone = zone, t = now }
        self:UpdateOwnSpeed(px, py, zone, now)
    end

    for unit, p in pairs(pos) do
        local name = nameOfUnit[unit]
        if name then
            self.reports[self:Key(name)] = {
                x = p.x, y = p.y, hp = p.hp, zone = zone, t = now, source = "live",
            }
        end
    end
end

function FF:Key(name)
    return name and strlower(name) or nil
end

function FF:IndexOf(name)
    if not name then return nil end
    local target = strlower(name)
    for i, n in ipairs(self.tracked) do
        if strlower(n) == target then return i end
    end
    return nil
end

function FF:IsTracking(name)
    return self:IndexOf(name) ~= nil
end

function FF:BroadcastPosition()
    if not self.myPos then return end
    if (GetTime() - self.myPos.t) > self.STALE_AFTER then return end

    local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
    local pct = (hp and hpMax and hpMax > 0) and math.floor(hp / hpMax * 100 + 0.5) or ""

    local msg = format("PING:%s:%.1f:%.1f:%s",
        self.myPos.zone or "?", self.myPos.x, self.myPos.y, tostring(pct))

    if GetNumRaidMembers() > 0 then
        SendAddonMessage(self.ADDON_PREFIX, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(self.ADDON_PREFIX, msg, "PARTY")
    end

    local now = GetTime()
    for name, expires in pairs(self.watchers) do
        if expires and expires > now then
            SendAddonMessage(self.ADDON_PREFIX, msg, "WHISPER", name)
        else
            self.watchers[name] = nil
        end
    end
end

function FF:RequestFrom(name)
    SendAddonMessage(self.ADDON_PREFIX, "REQ", "WHISPER", name)
    DEBUG("Pedido de posicion enviado a", name)
end

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= FF.ADDON_PREFIX then return end
    FF:OnCommReceived(sender, message)
end)

function FF:OnCommReceived(sender, message)
    if not sender or sender == UnitName("player") then return end

    if message == "REQ" then
        self.watchers[sender] = GetTime() + self.WATCH_EXPIRES
        DEBUG(sender, "pidio tu posicion (le vas a contestar por", self.WATCH_EXPIRES, "s)")
        return
    end

    local kind, zone, x, y, hp = strsplit(":", message)
    if kind ~= "PING" then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end

    self.reports[self:Key(sender)] = {
        x = x, y = y, hp = tonumber(hp), zone = zone,
        t = GetTime(), source = "comm",
    }
end

function FF:ResolveTarget(name)
    if not name then return nil end
    local r = self.reports[self:Key(name)]
    if r and (GetTime() - r.t) <= self.STALE_AFTER then
        return r.x, r.y, r.zone, r.source, r.hp
    end
    return nil
end

function FF:StartTracking(name)
    name = strtrim(name or "")
    if name == "" then
        print("|cff40ff40[FF]|r Usage: /ff track <name>")
        return
    end

    local myName = UnitName("player")
    if myName and strlower(myName) == strlower(name) then
        print("|cff40ff40[FF]|r You can't track yourself.")
        return
    end

    if self:IsTracking(name) then
        print(format("|cff40ff40[FF]|r Already tracking %s.", name))
        return
    end

    if #self.tracked >= self.MAX_TRACKED then
        print(format("|cff40ff40[FF]|r Tracking %d already, which is the limit. Drop one first: /ff off <name>",
            #self.tracked))
        return
    end

    self.tracked[#self.tracked + 1] = name

    if not self:FindGroupUnit(name) then
        self:RequestFrom(name)
    end

    if self.RefreshArrows then self:RefreshArrows() end
end

function FF:StopTracking(name)
    name = strtrim(name or "")

    if name ~= "" then
        local i = self:IndexOf(name)
        if not i then
            print(format("|cff40ff40[FF]|r You are not tracking %s.", name))
            return
        end
        table.remove(self.tracked, i)
    else
        if #self.tracked == 0 then return end
        for i = #self.tracked, 1, -1 do table.remove(self.tracked, i) end
    end

    if self.RefreshArrows then self:RefreshArrows() end
end

local DOUBLE_CLICK_WINDOW = 0.4
local lastTargetClick = 0

local function OnTargetFrameClicked(self, button)
    if button and button ~= "LeftButton" then return end

    local now = GetTime()
    if (now - lastTargetClick) <= DOUBLE_CLICK_WINDOW then
        lastTargetClick = 0
        local name = UnitName("target")
        if name then

            if FF:IsTracking(name) then
                FF:StopTracking(name)
            else
                FF:StartTracking(name)
            end
        end
    else
        lastTargetClick = now
    end
end

if TargetFrame then
    TargetFrame:HookScript("OnClick", OnTargetFrameClicked)
end

local ticker = CreateFrame("Frame")
local sinceSample, sinceBroadcast, sinceRequest = 0, 0, 0

ticker:SetScript("OnUpdate", function(self, elapsed)
    if not (FF.tracked[1] or next(FF.watchers)) then
        sinceSample, sinceBroadcast, sinceRequest = 0, 0, 0
        return
    end

    sinceSample = sinceSample + elapsed
    if sinceSample >= FF.SAMPLE_INTERVAL then
        sinceSample = 0
        FF:Sample()
    end

    sinceBroadcast = sinceBroadcast + elapsed
    if sinceBroadcast >= FF.PING_INTERVAL then
        sinceBroadcast = 0
        FF:BroadcastPosition()
    end

    sinceRequest = sinceRequest + elapsed
    if sinceRequest >= FF.REQUEST_INTERVAL then
        sinceRequest = 0
        for _, name in ipairs(FF.tracked) do
            if not FF:FindGroupUnit(name) then
                local r = FF.reports[FF:Key(name)]
                if not r or (GetTime() - r.t) > FF.STALE_AFTER then
                    FF:RequestFrom(name)
                end
            end
        end
    end
end)

SLASH_FF1 = "/ff"
SlashCmdList["FF"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = strsplit(" ", msg, 2)
    cmd = strlower(cmd or "")

    if cmd == "" then
        print("|cff40ff40Find Friend|r - commands:")
        print("  /ff <name>        - track that player (same as /ff track)")
        print("  /ff target        - track your current target")
        print("  /ff off [name]    - stop tracking everyone, or just that one")
        print("  /ff units         - switch between meters and yards")
        print("  /ff icon [name]   - next arrow icon, or pick one: " .. FF:IconStyleList())
        print("  /ff hp            - show or hide their health percentage")
        print("  /ff test          - try the arrow without needing another player")
        print(format("  Double-click your target's portrait to start or stop tracking them. Up to %d at once.",
            FF.MAX_TRACKED))
        return
    end

    if cmd == "target" then
        local name = UnitName("target")
        if name then
            FF:StartTracking(name)
        else
            print("|cff40ff40[FF]|r You have no target selected.")
        end

    elseif cmd == "off" or cmd == "stop" then
        FF:StopTracking(rest)

    elseif cmd == "units" then
        FF_Settings.units = (FF_Settings.units == "meters") and "yards" or "meters"

    elseif cmd == "icon" then
        rest = strlower(strtrim(rest or ""))
        local style
        if rest == "" then
            style = FF:NextIconStyle()
        elseif FF:IsIconStyle(rest) then
            style = FF:NormalizeIconStyle(rest)
        else
            print("|cff40ff40[FF]|r Unknown icon. Use: " .. FF:IconStyleList())
            return
        end
        FF_Settings.iconStyle = style
        if FF.ApplyArrowIcon then FF:ApplyArrowIcon() end

    elseif cmd == "test" then
        FF:Sample()
        if not FF.myPos then
            print("|cff40ff40[FF]|r Can't read your position yet. Try again in a second.")
            return
        end
        local name = "TestFF"
        FF.reports[FF:Key(name)] = {
            x = FF.myPos.x + 5, y = FF.myPos.y,
            zone = FF.myPos.zone, t = GetTime(), source = "comm",
        }
        if not FF:IsTracking(name) then
            FF.tracked[#FF.tracked + 1] = name
        end
        if FF.RefreshArrows then FF:RefreshArrows() end

    elseif cmd == "hp" then
        FF_Settings.showHealth = not FF_Settings.showHealth
        if FF.RefreshArrows then FF:RefreshArrows() end

    elseif cmd == "track" then
        FF:StartTracking(rest)

    else

        FF:StartTracking(msg)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "FindFriend" then return end

    FF_Settings = FF_Settings or {}

    FF_Settings.rotateWithFacing = nil
    FF_Settings.debug            = nil
    FF_Settings.soundEnabled     = nil

    if FF_Settings.units == nil then FF_Settings.units = "meters" end
    if FF_Settings.showHealth == nil then FF_Settings.showHealth = true end
    FF_Settings.autoDuo = nil
    FF_Settings.iconStyle = FF:NormalizeIconStyle(FF_Settings.iconStyle)
    FF_Settings.zoneScale = FF_Settings.zoneScale or {}

    if FF.ApplySavedPosition then FF:ApplySavedPosition() end
    if FF.ApplyArrowIcon then FF:ApplyArrowIcon() end

    self:UnregisterEvent("ADDON_LOADED")
end)
