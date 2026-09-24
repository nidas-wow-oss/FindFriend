--=========================================================================--
-- Find Friend
--
-- Addon standalone que reimplementa, de forma limpia y documentada, la
-- logica de la flecha "Track Player" de Carbonite (la que te guia hacia
-- un companero de grupo/banda, tipica para encontrar a tu dupla en BG).
--
-- De donde sale cada cosa (ver notas completas en README.md):
--   Nx.Map:M_OTP / M_ORT   -> elegir a quien seguir      -> FF:StartTracking / StopTracking
--   Nx.Map:UpG             -> posicion via API de Blizzard-> FF:FindGroupUnit + FF:SamplePositions
--   Nx.Com:UpI / Nx.Com:OC__ (broadcast por addon)        -> FF:BroadcastPosition / OnCommReceived
--   Nx.Map:DrT1            -> matematica del angulo/flecha-> FF:UpdateArrow (en el otro archivo)
--
-- Diferencia deliberada con Carbonite: en vez de un canal de chat propio
-- (zona completa) usamos PARTY/RAID (a tu grupo, gratis) + WHISPER
-- (a un companero puntual que no esta en tu grupo, requiere que el otro
-- jugador tambien tenga este addon corriendo). Es mas simple, mas privado,
-- y cubre exactamente el caso que pediste: encontrar a tu compañero en BG.
--=========================================================================--

FF = FF or {}

-- Prefijo del canal de addon (max 16 caracteres). No hace falta
-- RegisterAddonMessagePrefix en 3.3.5a: esa funcion no existe en este
-- cliente, así que ni la llamamos.
FF.ADDON_PREFIX = "FFLoc1"

-- Antes esto era 1s, y por eso la distancia se sentia "a saltos" (cada
-- vez que cambiaba, cambiaba de golpe). Carbonite recalcula esto en cada
-- tick de su OnUpdate (basicamente cada frame). No necesitamos ir tan
-- rapido -leer posicion + convertir mapa tiene un costo minimo, pero no
-- cero-, pero 0.1s (10 veces por segundo) ya se siente completamente
-- fluido al ojo humano y es una fraccion despreciable de trabajo.
FF.SAMPLE_INTERVAL   = 0.1   -- cada cuanto leemos nuestra propia posicion (y la del objetivo si esta en tu grupo)
FF.PING_INTERVAL     = 1     -- cada cuanto avisamos nuestra posicion al grupo/whisper
FF.REQUEST_INTERVAL  = 15    -- cada cuanto insistimos con un "REQ" si el objetivo no esta en el grupo
FF.STALE_AFTER       = 45    -- segundos: despues de esto, un reporte se considera viejo
FF.WATCH_EXPIRES     = 300   -- cuanto seguimos contestandole a alguien que nos pidio posicion

-- Estado en memoria (no se guarda entre sesiones a proposito: cada vez que
-- entras querés elegir de nuevo a quien seguir, igual que "Track Player"
-- en Carbonite no sobrevive un /reload)
-- VARIOS A LA VEZ.
--
-- Antes era un solo nombre. En un BG queres ver a tu dupla Y al que lleva
-- la bandera, asi que ahora es una LISTA ordenada, con una flecha por
-- cada uno. El orden es el orden en que los agregaste, y es el orden en
-- que se apilan las flechas en pantalla.
FF.MAX_TRACKED = 3            -- mas que esto tapa media pantalla
FF.tracked     = {}           -- lista ordenada de nombres
FF.myPos       = nil          -- {x, y, zone, t}  (0-100, 0-100, texto, GetTime())
-- Las tablas por jugador van en MINUSCULAS.
--
-- El mismo jugador llega escrito de tres formas distintas: como lo
-- escribiste en /ff track, como lo devuelve UnitName del objetivo, y como
-- viene en el remitente de un mensaje de addon. Guardar con la
-- capitalizacion de cada uno hacia que "iorlyn" y "Iorlyn" fueran dos
-- entradas diferentes y la flecha se quedara en "buscando...".
FF.reports     = {}           -- [nombre en minusculas] = {x, y, zone, t, source="live"|"comm"}
FF.watchers    = {}           -- [nombre] = GetTime() hasta cuando le seguimos mandando whisper

-- Traza para desarrollo. Ya no es una opcion del usuario (se saco
-- "/ff debug"): se prende cambiando este false a mano cuando hay algo que
-- investigar, que es la unica vez que sirve.
local FF_TRACE = false
local function DEBUG(...)
    if FF_TRACE then
        print("|cff40ff40[FF]|r", ...)
    end
end

--=========================================================================--
-- Posicion propia y de unidades de grupo (equivalente a Nx.Map:UpG)
--=========================================================================--

-- Lee nuestra propia posicion y (si se pide) la de una unidad de grupo.
--
-- IMPORTANTE (bug real, reportado dentro de un BG): la version anterior
-- llamaba SetMapToCurrentZone() SIEMPRE, sin importar si hacia falta, y
-- trataba de devolver el mapa a como estaba despues. Dentro de un
-- battleground, SetMapToCurrentZone() puede resolver mal (el mapa de una
-- instancia no siempre tiene una relacion continente/zona limpia) y saltar
-- a otra vista -- y como esto corre 10 veces por segundo (para que la
-- distancia no se sienta "a saltos"), el salto se notaba muchisimo.
--
-- La solucion: probar a leer la posicion SIN TOCAR NADA primero. Si el
-- mapa que el jugador tiene abierto ya incluye su propia posicion -que es
-- el caso normal: al entrar a un BG y abrir el mapa, Blizzard ya te
-- muestra el mapa del BG, que ES tu zona actual- alcanza con eso y no
-- hace falta cambiar ni restaurar absolutamente nada. Solo si el mapa
-- actual NO incluye al jugador (esta mirando otra zona/continente a
-- proposito, por ejemplo planeando un viaje) forzamos el cambio, leemos
-- todo lo que necesitamos, y recien ahi restauramos.
--
-- Ahora recibe una LISTA de unidades y las lee TODAS dentro del mismo
-- contexto de mapa. Leerlas de a una habria significado, en el caso malo,
-- un SetMapToCurrentZone por cada seguido y diez veces por segundo.
function FF:SamplePositions(units)
    local px, py = GetPlayerMapPosition("player")
    local zone = GetRealZoneText()
    local out = {}

    local function LeerUnidades()
        if not units then return end
        for _, u in ipairs(units) do
            local x, y = GetPlayerMapPosition(u)
            if x and not (x == 0 and y == 0) then
                -- La vida se lee aca mismo: es la misma unidad y el mismo
                -- momento, asi que no hace falta recorrerlos otra vez.
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
        -- El mapa actual ya nos incluye: no tocamos nada.
        LeerUnidades()
    else
        -- El mapa actual no nos incluye: cambiamos, leemos TODO lo que
        -- necesitamos de una, y restauramos antes de devolver nada.
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

-- Busca si "name" corresponde a una unidad de tu grupo/banda ahora mismo.
-- Analogo al loop de Nx.Map:UpG sobre "party1..4" / "raid1..40".
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

-- Como FindGroupUnit, pero tambien prueba "target"/"mouseover"/"focus" por si
-- el companero que seguis no esta en tu grupo pero lo tenes a la vista en
-- ese momento. Solo lo usa la calibracion de distancia (mas abajo): no
-- cambia de donde sacamos la posicion para la flecha, solo nos da una
-- oportunidad extra de medir la escala real de la zona.
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

--=========================================================================--
-- Distancia real (yardas/metros) por autocalibracion
--
-- Por que esto y no una tabla de tamaños de zona: investigue esto en serio
-- (ver README, seccion "Sobre la distancia real") y ni las librerias
-- estandar de la comunidad (Astrolabe, HereBeDragons) tienen datos
-- confiables para instancias/battlegrounds en un cliente 3.3.5a genuino
-- -las versiones modernas de esas librerias usan una API (C_Map) que
-- directamente no existe en este cliente-. En vez de inventar numeros,
-- calculamos la escala real de la zona usando datos que el juego SI nos
-- da gratis: CheckInteractDistance(unit, indice) dice si estas a menos de
-- una distancia exacta y conocida (9.9/11.11/28 yardas) de alguien. Si en
-- algun momento estas así de cerca de tu compañero, comparamos esa
-- distancia real contra la distancia en "% del mapa" de ese mismo instante
-- y de ahí sacamos cuantas yardas equivalen a 1% del mapa EN ESA ZONA.
-- Una vez calibrada una zona, se guarda entre sesiones (FF_Settings.zoneScale)
-- y la distancia se muestra en yardas/metros reales de ahí en adelante,
-- incluso si tu compañero despues se aleja mucho.
--=========================================================================--

FF.YARDS_TO_METERS = 0.9144

-- indice de CheckInteractDistance -> yardas exactas que representa
-- (orden: del mas ajustado -- mejor calibracion -- al mas amplio)
local INTERACT_ORDER = { 3, 2, 1, 4 }
local INTERACT_YARDS = { [1] = 28, [2] = 11.11, [3] = 9.9, [4] = 28 }

-- pctDist: distancia entre vos y el objetivo en las mismas unidades que
-- usamos en toda la UI (0-100, la diagonal completa del mapa serían ~141).
function FF:TryCalibrate(unit, pctDist)
    if not unit or not pctDist or pctDist < 0.3 then
        return -- muy cerca -> dividir por un numero chico da un resultado inestable
    end
    local zone = self.myPos and self.myPos.zone
    if not zone then return end
    FF_Settings.zoneScale = FF_Settings.zoneScale or {}

    for _, idx in ipairs(INTERACT_ORDER) do
        if CheckInteractDistance(unit, idx) then
            local yards = INTERACT_YARDS[idx]
            local scale = yards / pctDist -- yardas reales por cada 1% de mapa, en ESTA zona
            local prev = FF_Settings.zoneScale[zone]
            -- nos quedamos con la calibracion mas ajustada que hayamos visto
            -- (menos yardas = mas precision; comparamos yardas, NO el
            -- indice crudo, porque el indice 3 -9.9y- es mas preciso que
            -- el indice 1 -28y- aunque 3 sea numericamente mayor que 1)
            if not prev or yards <= prev.yards then
                FF_Settings.zoneScale[zone] = { scale = scale, yards = yards }
            end
            return
        end
    end
end

-- Yardas reales SIN convertir a la unidad de display (crudo), o nil si la
-- zona todavia no se calibro. Lo usa RealDistance (abajo) y tambien el
-- guard "estoy practicamente encima del objetivo" de la flecha, que
-- necesita yardas de verdad, no metros/yardas segun la preferencia del
-- usuario (ver FF:RefreshRotation en FindFriend_Arrow.lua).
function FF:CalibratedYards(zone, pctDist)
    local cal = FF_Settings.zoneScale and FF_Settings.zoneScale[zone]
    if not cal then return nil end
    return pctDist * cal.scale
end

-- Convierte una distancia en "% de mapa" a yardas/metros reales si ya
-- calibramos la zona; si no, devuelve nil (el que llama muestra el % como
-- respaldo).
function FF:RealDistance(zone, pctDist)
    local yards = self:CalibratedYards(zone, pctDist)
    if not yards then return nil end
    if FF_Settings.units == "meters" then
        return yards * self.YARDS_TO_METERS, "m"
    end
    return yards, "yd"
end

-- Velocidad propia (para el ETA). PORTADO LITERAL de como lo calcula
-- Carbonite (buscar ".PlS=" en Carbonite.lua):
--   if x==self.PlX and y==self.PlY then       -- no te moviste
--     self.PSCT=GetTime(); self.PlS=0; self.PSX=x; self.PSY=y
--   else                                       -- te moviste
--     local tmD=GetTime()-self.PSCT
--     if tmD>.5 then                           -- pero no recalcules mas
--       self.PSCT=GetTime()                    -- seguido que cada 0.5s,
--       self.PlS=(dist)^.5*4.575/tmD           -- si no, el ETA tiembla
--       self.PSX=x; self.PSY=y
--     end
--   end
-- Nuestra version usa NUESTRA escala calibrada (FF:CalibratedYards) en
-- vez de la constante fija "4.575" de Carbonite (esa es especifica de su
-- propio canvas interno, no reutilizable -- ver README seccion 4ter).
-- Si la zona todavia no esta calibrada, dejamos playerSpeedYps en nil
-- (no inventamos una velocidad con una escala que no tenemos).
FF.SPEED_EPS    = 0.0005 -- "no te moviste": ruido tipico de GetPlayerMapPosition a ignorar
FF.SPEED_MIN_DT = 0.5    -- igual que Carbonite: no recalcular la velocidad mas seguido que esto

function FF:UpdateOwnSpeed(px, py, zone, now)
    if self._psZone ~= zone then
        -- primera muestra en esta zona (o acabas de cambiar de zona):
        -- arrancamos de cero, sin mezclar datos de otra zona/escala.
        self._psX, self._psY, self._psCT, self._psZone = px, py, now, zone
        self.playerSpeedYps = nil
        return
    end

    local cal = FF_Settings.zoneScale and FF_Settings.zoneScale[zone]

    if math.abs(px - self._psX) < self.SPEED_EPS and math.abs(py - self._psY) < self.SPEED_EPS then
        -- no te moviste: velocidad 0 AL INSTANTE (no hace falta esperar
        -- el throttle de abajo para esto, tal cual Carbonite)
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
    -- si dt<=SPEED_MIN_DT: no tocamos nada todavia, igual que Carbonite
    -- (se mantiene el ultimo valor de playerSpeedYps hasta la proxima).
end

-- Actualiza nuestra posicion propia y, si el objetivo actual esta en
-- nuestro grupo, tambien la suya (via API de Blizzard, sin depender del
-- addon: exactamente el camino "paX/paY" que prioriza Carbonite antes de
-- usar los datos por comm).
function FF:Sample()
    -- Primero, a cuales de los seguidos los tenemos "en vivo" (estan en el
    -- grupo y Blizzard nos da su posicion sin necesidad del addon).
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

--=========================================================================--
-- La lista de seguidos
--=========================================================================--

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

--=========================================================================--
-- Comunicacion entre addons (equivalente simplificado de Nx.Com:UpI / OC__)
--=========================================================================--

-- Avisa nuestra posicion:
--  * al grupo/banda entero por PARTY o RAID (barato: un solo mensaje sirve
--    para que cualquiera que nos este siguiendo nos vea), y
--  * por WHISPER a cualquiera que nos haya pedido posicion con /ff track
--    (el "REQ" de mas abajo), aunque no sea de nuestro grupo.
function FF:BroadcastPosition()
    if not self.myPos then return end
    if (GetTime() - self.myPos.t) > self.STALE_AFTER then return end

    -- El quinto campo es la vida. Va al final y es OPCIONAL: el que lee
    -- parte el mensaje sin limite de trozos y toma lo que haya, asi que un
    -- mensaje viejo de cuatro campos se sigue entendiendo.
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

-- Le pide a alguien que no esta en nuestro grupo que empiece a mandarnos
-- su posicion. Solo funciona si esa persona tambien tiene este addon.
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

    -- Sin limite de trozos: asi entra el quinto campo (la vida) y siguen
    -- entrando los mensajes viejos, que solo traen cuatro.
    local kind, zone, x, y, hp = strsplit(":", message)
    if kind ~= "PING" then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end

    self.reports[self:Key(sender)] = {
        x = x, y = y, hp = tonumber(hp), zone = zone,
        t = GetTime(), source = "comm",
    }
end

-- Mejor posicion conocida del objetivo (ya sea que llegue por la API de
-- Blizzard -via Sample()- o por el addon de la otra persona).
function FF:ResolveTarget(name)
    if not name then return nil end
    local r = self.reports[self:Key(name)]
    if r and (GetTime() - r.t) <= self.STALE_AFTER then
        return r.x, r.y, r.zone, r.source, r.hp
    end
    return nil
end

--=========================================================================--
-- Elegir a quien seguir (equivalente a Nx.Map:M_OTP / M_ORT)
--=========================================================================--

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

    -- Sin aviso por chat: la flecha aparece, y eso ya es el aviso. Si no
    -- esta en el grupo se le pide la posicion y la flecha queda en
    -- "searching..." hasta que conteste, que dice lo mismo sin ruido.
    if not self:FindGroupUnit(name) then
        self:RequestFrom(name)
    end

    if self.RefreshArrows then self:RefreshArrows() end
end

-- Sin nombre, deja de seguir a todos. Con nombre, solo a ese.
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

--=========================================================================--
-- Doble clic en el retrato del objetivo -> empieza a seguirlo
--
-- TargetFrame es el frame por defecto de Blizzard (el que muestra el
-- retrato/vida/nombre de tu objetivo arriba a la izquierda). Todo el
-- frame es un solo boton clickeable -incluida el area del retrato-, asi
-- que enganchamos ahi. Usamos HookScript (no SetScript) a proposito: eso
-- agrega nuestra funcion SIN reemplazar el comportamiento normal del
-- frame (atacar con clic, etc.), que es protegido/"secure" y no se puede
-- pisar directamente. WoW no tiene un evento nativo de "doble clic", asi
-- que lo armamos a mano midiendo el tiempo entre dos clics con boton
-- izquierdo.
--
-- OJO: si mas adelante Nidhaus_UnitFrames reemplaza el TargetFrame por
-- defecto de Blizzard por uno propio, este hook va a dejar de recibir
-- clics (porque el frame de Blizzard queda tapado/oculto). En ese caso
-- alcanza con enganchar el mismo FF:StartTracking(name) al doble clic
-- del frame propio del objetivo que tenga esa addon.
--=========================================================================--

local DOUBLE_CLICK_WINDOW = 0.4
local lastTargetClick = 0

local function OnTargetFrameClicked(self, button)
    if button and button ~= "LeftButton" then return end

    local now = GetTime()
    if (now - lastTargetClick) <= DOUBLE_CLICK_WINDOW then
        lastTargetClick = 0 -- reset, para no confundir un 3er clic rapido con otro doble clic
        local name = UnitName("target")
        if name then
            -- El doble clic ALTERNA. Doble clic sobre el mismo al que ya
            -- estas siguiendo = dejar de seguirlo, sin tener que escribir
            -- /ff stop. Sobre otro distinto, cambia el seguimiento a ese.
            --
            -- Se compara en minusculas porque el nombre puede llegar con
            -- otra capitalizacion segun de donde salga (UnitName del
            -- objetivo, lo que escribiste en /ff track, o el remitente de
            -- un mensaje de addon).
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

--=========================================================================--
-- Ticker principal
--=========================================================================--

local ticker = CreateFrame("Frame")
local sinceSample, sinceBroadcast, sinceRequest = 0, 0, 0

-- EL TICKER NO TRABAJA SI NO HAY NADA QUE HACER.
--
-- Tal como estaba, este OnUpdate corria SIEMPRE desde que entrabas al
-- juego, siguieras a alguien o no. Un marco creado con CreateFrame nace
-- visible, y nadie lo escondia. Eso significaba, para siempre y en vacio:
--
--   * FF:Sample() diez veces por segundo -- o sea GetPlayerMapPosition y
--     GetRealZoneText 10 veces por segundo sin que nadie mire el
--     resultado. Y peor: si tenias el mapa abierto mirando OTRA zona, se
--     entraba en la rama que llama SetMapToCurrentZone() + SetMapZoom()
--     diez veces por segundo. Es exactamente el salto de mapa que el
--     comentario de SamplePositions dice haber arreglado: se arreglo para
--     el caso normal, pero seguia pasando cada vez que abrias el mapa
--     para mirar otro lado, aunque no estuvieras siguiendo a nadie.
--
--   * SendAddonMessage al grupo UNA VEZ POR SEGUNDO, siempre. En una
--     banda de 40 con varios usando esto es trafico real, y el servidor
--     de 3.3.5a tiene limite de mensajes de addon: pasarse desconecta.
--
-- Hace falta trabajar en dos casos y en ninguno mas: si estas siguiendo a
-- alguien, o si alguien te pidio tu posicion y todavia no vencio. Los
-- contadores se dejan en cero al salir para que al volver a activarse la
-- primera lectura sea inmediata y no arrastre el tiempo parado.
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

    -- Si estamos siguiendo a alguien que no esta en el grupo y todavia no
    -- nos contesto, insistimos cada tanto (por si prende el addon tarde).
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

--=========================================================================--
-- Comandos de barra
--=========================================================================--

SLASH_FF1 = "/ff"
SlashCmdList["FF"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = strsplit(" ", msg, 2)
    cmd = strlower(cmd or "")

    -- SIN PRINTS DE ESTADO.
    --
    -- "Tracking X", "Stopped tracking X", "Arrow icon: chip", "Distance
    -- units: yards" -- todos esos decian por chat algo que ya se ve en
    -- pantalla: la flecha aparece, desaparece, cambia de dibujo o cambia
    -- el numero. Repetirlo en el chat es ruido, y con doble clic pasaba en
    -- cada clic.
    --
    -- Quedan solo dos clases de mensaje, y las dos por el mismo motivo: no
    -- tienen ningun otro modo de enterarte.
    --   * la ayuda, que es lo unico que hace "/ff" a secas
    --   * "no se pudo": ahi no aparece ninguna flecha, y sin una linea de
    --     texto no hay forma de saber por que

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
            style = FF:NormalizeIconStyle(rest)   -- por si escribio un nombre viejo
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
            x = FF.myPos.x + 5, y = FF.myPos.y, -- 5% del mapa al ESTE tuyo, sin moverte
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
        -- Cualquier otra cosa es un NOMBRE: "/ff Iorlyn" alcanza, sin
        -- tener que escribir "track". Es lo que uno tipea por instinto.
        FF:StartTracking(msg)
    end
end

--=========================================================================--
-- Carga de SavedVariables
--=========================================================================--

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "FindFriend" then return end

    FF_Settings = FF_Settings or {}
    -- El modo norte-arriba se saco: la brujula gira SIEMPRE con tu
    -- personaje, como el minimapa con "Rotar minimapa" activado, que es el
    -- comportamiento de Carbonite que se pidio reproducir.
    --
    -- Se borra el valor viejo de las SavedVariables en vez de ignorarlo:
    -- si no, queda un campo huerfano que dentro de un tiempo no se sabe si
    -- todavia hace algo o no.
    -- Lo mismo con las opciones que se sacaron: se borran del archivo
    -- guardado en vez de quedar ahi sin hacer nada.
    FF_Settings.rotateWithFacing = nil
    FF_Settings.debug            = nil
    FF_Settings.soundEnabled     = nil

    if FF_Settings.units == nil then FF_Settings.units = "meters" end
    if FF_Settings.showHealth == nil then FF_Settings.showHealth = true end
    FF_Settings.autoDuo = nil   -- opcion sacada
    FF_Settings.iconStyle = FF:NormalizeIconStyle(FF_Settings.iconStyle)
    FF_Settings.zoneScale = FF_Settings.zoneScale or {} -- calibracion por zona, se guarda entre sesiones

    if FF.ApplySavedPosition then FF:ApplySavedPosition() end
    if FF.ApplyArrowIcon then FF:ApplyArrowIcon() end

    self:UnregisterEvent("ADDON_LOADED")
end)
