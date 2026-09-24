--=========================================================================--
-- Find Friend - Flecha
--
-- CAMBIO IMPORTANTE (2da vuelta): las texturas que veniamos usando
-- (IconWayTarget/IconArrowGrad) son del sistema de ICONOS DE MAPA de
-- Carbonite (Nx.Map:DrT1). Pero lo que el usuario en realidad pedia desde
-- el principio es OTRA cosa: Carbonite tiene un modulo aparte, dedicado,
-- para esto: Nx.HUD -- una flecha grande que se muestra flotando en la
-- pantalla (no en un mapa), EXACTAMENTE el mismo concepto que este addon.
-- Encontramos su archivo de textura real: "HUDArrow" + un sufijo de
-- estilo seleccionable ("","Chip","Gloss","Glow","Neon" -- literal de
-- Nx.HUD.TeN en el codigo), y su funcion de actualizacion Nx.HUD:Upd nos
-- dio la posta completa de como se calcula todo. Codigo real (resumido):
--
--   local dis=map.TDY                    -- distancia en yardas
--   local dir=(map.TrD-map.PlD) % 360     -- RUMBO RELATIVO a tu orientacion
--   if dis<1 then dir=0 end               -- evita temblor si estas encima
--   local diD=dir<=180 and dir or 360-dir -- que tan lejos del "de frente" (0-180)
--   -- (misma rotacion manual via SetTexCoord que ya teniamos)
--   if diD<5 then
--     if dis<1 then tex2:SetVertexColor(.2,1,.2,.4); tex2:SetBlendMode("BLEND")
--     else tex2:SetVertexColor(.7,.7,1,1); tex2:SetBlendMode("ADD") end   -- brilla si apuntas bien
--   else
--     tex2:SetVertexColor(1,1,.5,.9); tex2:SetBlendMode("BLEND")          -- amarillo palido si no
--   end
--
-- Dos cosas clave que esto confirma:
--   1. dir = TrD - PlD (bearing menos tu orientacion): la brujula "gira
--      con vos" que dejamos de default es exactamente como Carbonite arma
--      SU flecha de pantalla completa (no es un invento nuestro).
--   2. La tecnica de rotacion (SetTexCoord manual + cos/sin en grados) es
--      identica a la que ya habiamos portado para los iconos de mapa.
-- Lo que agregamos ahora: el guard "dis<1 -> dir=0" (jitter cuando estas
-- encima del objetivo) y el feedback de color/brillo segun que tan bien
-- apuntado estas.
--
-- (nota: no implementamos el ETA -tiempo estimado de llegada- que Nx.HUD
-- tambien muestra, basado en tu velocidad de movimiento -map.PlS-; lo
-- dejamos afuera para no agregar mas alcance del que se pidio, pero
-- queda documentado en el README como posible mejora futura)
--
-- ROTACION: SetTexCoord manual + cos/sin en GRADOS (globales de WoW, no
-- math.cos/sin), no Texture:SetRotation (mas nueva, puede faltar/andar
-- mal en un cliente de servidor privado). Verificado en los 4 puntos
-- cardinales + 90/180 grados con tests.
--
-- MATEMATICA DEL RUMBO (independiente de como se dibuja):
--   dx = tx - px, dy = ty - py
--   rumboAbsoluto = atan2(dx, -dy)  -- 0=norte, 90=este, sentido horario
--   rumboRelativo = rumboAbsoluto - tuOrientacion   -- (modo default)
--
-- ACTUALIZACION EN DOS VELOCIDADES (para que se sienta "en tiempo real"):
--   * FF:RefreshTargetInfo()  -> cada ~0.3s: resuelve donde esta el
--     objetivo, arma nombre/distancia, guarda dx,dy en cache.
--   * FF:RefreshRotation()    -> cada frame: recalcula el angulo con la
--     orientacion MAS RECIENTE, asi responde al instante al girar.
--
-- =========================================================================
-- VARIAS FLECHAS A LA VEZ  (cambio de esta vuelta)
--
-- Antes habia UNA flecha y su estado vivia suelto en FF (FF.lastDX,
-- FF.hasBearing, FF.smDX...). Para seguir a dos o tres a la vez eso no
-- sirve: cada uno necesita su propio rumbo, su propio suavizado y su
-- propio estado de alineacion, porque son cuentas independientes.
--
-- Ahora hay una FILA por seguido. Cada fila es un marco con su flecha y
-- sus dos textos, y se lleva su estado adentro. Las filas cuelgan de un
-- contenedor que es lo unico que se arrastra: movés una cosa y se mueven
-- todas, y se guarda una sola posicion.
--
-- Las filas no se destruyen al dejar de seguir a alguien (en WoW un marco
-- no se puede destruir): se esconden y se reusan. Con MAX_TRACKED en 3
-- nunca hay mas de tres dando vueltas.
-- =========================================================================

local FF = FF

-- 48 de flecha + los textos de abajo. La tercera linea (la vida) solo
-- ocupa lugar cuando esta encendida: con tres flechas, reservarla siempre
-- serian 36 pixeles de aire por nada.
local ROW_W        = 48
local ROW_H_BASE   = 74
local ROW_H_HEALTH = 86

local function RowHeight()
    return (FF_Settings and FF_Settings.showHealth) and ROW_H_HEALTH or ROW_H_BASE
end

--=========================================================================--
-- Iconos
--
-- SE ELIGEN POR NUMERO: /ff icon 1 .. /ff icon 6. Es lo mas corto de
-- escribir y no hay que acordarse de ningun nombre. Los nombres viejos
-- siguen entrando por LEGACY, asi que nadie pierde su configuracion
-- guardada ni tiene que reaprender nada.
--
-- SE SACARON "pin" Y "trail". Eran los dos iconos del sistema de MAPA de
-- Carbonite (IconWayTarget / IconArrowGrad) y NUNCA ANDUVIERON: esos dos
-- .tga no estan en Media, asi que elegirlos dejaba la flecha invisible.
-- Y WoW no avisa cuando falta una textura: SetTexture con un archivo que
-- no existe simplemente no dibuja nada.
--
-- Los cinco que quedan estan verificados: los cinco archivos existen, son
-- 64x64, 32 bits, RLE, y son distintos entre si (base liso, Chip con
-- textura, Gloss gris, Glow naranja, Neon con contorno).
--
-- ESTOS ARCHIVOS SE COPIAN A MANO (ver Media/LEEME.txt): el addon carga
-- su PROPIA COPIA desde su carpeta Media, no depende de que Carbonite
-- siga instalado. Si no copiaste ninguno, "/ff icon blizz" anda igual
-- (usa una textura nativa del juego).
--=========================================================================--
local MEDIA = "Interface\\AddOns\\FindFriend\\Media\\"

local ICON_STYLES = {
    { key = "1", file = MEDIA .. "HUDArrow"      },  -- Nx.HUD, el liso (default)
    { key = "2", file = MEDIA .. "HUDArrowChip"  },
    { key = "3", file = MEDIA .. "HUDArrowGloss" },
    { key = "4", file = MEDIA .. "HUDArrowGlow"  },
    { key = "5", file = MEDIA .. "HUDArrowNeon"  },
    { key = "6", file = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW" },
}

-- Nombres aceptados ademas del numero. Los de la izquierda son los que
-- alguien pueda tener guardados de versiones anteriores; si no se
-- reconoce ninguno, NormalizeIconStyle cae al 1 y no rompe nada.
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

-- Acepta el numero y tambien los nombres viejos. Los reconocia solo al
-- leer la configuracion guardada, asi que "/ff icon glow" contestaba que
-- no existia aunque el valor si estuviera soportado.
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

-- para que los tests puedan verificar sin duplicar los strings
FF._ICON_BY_STYLE = FILE_BY_KEY
FF._ICON_BLIZZARD = FILE_BY_KEY.blizz

--=========================================================================--
-- Colores
--
-- De "sin datos"/"otra zona" (invencion nuestra, para dar info de un
-- vistazo cuando no hay rumbo calculable):
local COLOR_STALE  = { 0.6, 0.6, 0.6, 0.6 }
local COLOR_OTHERZ = { 0.5, 0.7, 1, 0.9 }
-- Los de ALINEACION SI son literales de Nx.HUD:Upd -- la flecha te avisa
-- que tan bien apuntado estas, ademas de girar.
local COLOR_ONTOP   = { .2, 1, .2, .4 } -- practicamente encima del objetivo
local COLOR_ALIGNED = { .7, .7, 1, 1 }  -- apuntando bien -- este brilla (blend ADD)
local COLOR_OFFAIM  = { 1, 1, .5, .9 }  -- todavia hay que girar

-- La vida se colorea como una barra de vida, que es lo que uno ya sabe
-- leer sin pensar: verde arriba del 50%, amarillo hasta 25%, rojo abajo.
local function HealthColor(pct)
    if pct > 50 then return "|cff40ff40"
    elseif pct > 25 then return "|cffffd100"
    else return "|cffff4040" end
end

-- SUAVIZADO DEL RUMBO.
--
-- La posicion del objetivo se lee diez veces por segundo, y
-- GetPlayerMapPosition devuelve valores con escalones (no es continua).
-- El giro de la camara SI es continuo, asi que la flecha ya se sentia
-- suave al girar vos -- pero cuando el que se movia era el OTRO, el rumbo
-- daba saltitos diez veces por segundo. Y de cerca es peor: a poca
-- distancia, un escalon minimo de posicion cambia el rumbo un monton.
--
-- Se arregla filtrando el VECTOR (dx, dy), no el angulo: un angulo cruza
-- de 359 a 1 y cualquier promedio da un giro completo para el lado
-- equivocado; el vector no tiene ese problema y ademas amortigua el ruido
-- solo. TAU es el tiempo en que alcanza ~63% del valor nuevo.
FF.BEARING_TAU = 0.12

-- ALINEACION CON HISTERESIS.
--
-- Antes era un solo umbral de 5 grados: parado justo en el borde, el
-- estado iba y venia entre "bien apuntado" y "gira" en cada cuadro, y eso
-- hacia titilar el color. Con dos umbrales hay que entrar por debajo de 5
-- pero recien se sale pasando 9: en el medio no cambia nada.
local ALIGN_ENTER = 5
local ALIGN_EXIT  = 9

--=========================================================================--
-- El contenedor y las filas
--=========================================================================--

local container = CreateFrame("Frame", "FFArrowFrame", UIParent)
container:SetSize(ROW_W, ROW_H_BASE)   -- RefreshArrows le pone el alto real
container:SetPoint("CENTER", Minimap, "BOTTOM", 0, -40)
container:SetMovable(true)
container:SetClampedToScreen(true)
-- Sin EnableMouse ni drag propio: las filas lo cubren entero y son ellas
-- las que lo arrastran (ver NewRow). Tenerlo aca tambien no suma nada y
-- confunde a quien lea esto despues.
container:Hide()

local rows = {}

-- DOBLE CLIC SOBRE UNA FLECHA = SACAR ESA.
--
-- Mismo criterio que el retrato del objetivo: doble clic pone y doble clic
-- saca. Aca es por flecha, asi que con tres seguidos sacas justo la que
-- quieras sin escribir nada.
--
-- Se mide el tiempo entre dos clics a mano y no con OnDoubleClick porque
-- ese script es de los Button y no siempre esta en un cliente de servidor
-- privado. Es exactamente lo que ya hace el hook del TargetFrame en el
-- otro archivo: si funciona alla, funciona aca.
local DOUBLE_CLICK_WINDOW = 0.4

-- ARRASTRAR AHORA VA EN LAS FILAS, NO EN EL CONTENEDOR.
--
-- Al darles el mouse a las filas, estas tapan al contenedor y el se queda
-- sin recibir nada -- lo cubren entero. Asi que cada fila arrastra al
-- padre: agarras cualquier flecha y se mueven todas juntas, que es lo que
-- uno espera.
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
            r.lastClick = 0 -- para que un tercer clic rapido no cuente de nuevo
            if r.name then FF:StopTracking(r.name) end
        else
            r.lastClick = now
        end
    end)

    -- El unico lugar donde se dice como sacarla. Como el addon ya no
    -- escribe nada en el chat, va aca: solo aparece si pasas el mouse.
    r.frame:SetScript("OnEnter", function(self)
        if not r.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        GameTooltip:AddLine("Double-click to stop tracking", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move all arrows", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    r.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- fondo suave: se ve donde agarrar aunque la flecha este
    -- semitransparente por estar "buscando" o en otra zona
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

-- Se llama cada vez que cambia la lista de seguidos: prepara una fila por
-- cada uno, esconde las que sobran y ajusta el alto del contenedor (que es
-- el area que se puede agarrar para arrastrar).
function FF:RefreshArrows()
    local n = #self.tracked

    local h = RowHeight()
    for i = 1, n do
        local r = GetRow(i)
        -- El alto cambia al prender o apagar la vida, asi que se reubican
        -- siempre: si no, al encenderla la segunda flecha se monta sobre
        -- el texto de la primera.
        r.frame:SetHeight(h)
        r.frame:ClearAllPoints()
        r.frame:SetPoint("TOP", container, "TOP", 0, -(i - 1) * h)
        r.name = self.tracked[i]
        -- Estado de rumbo en cero: esta fila puede venir de otro jugador.
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

    -- Los tests miran la primera flecha.
    self._arrowTex = rows[1] and rows[1].tex or nil
end

-- Compatibilidad con el codigo viejo que llamaba a estas dos.
function FF:ShowArrow() self:RefreshArrows() end
function FF:HideArrow() self:RefreshArrows() end

--=========================================================================--
-- Texto y rumbo de una fila
--=========================================================================--

-- SetText solo si el texto CAMBIO.
--
-- Esto corre diez veces por segundo por fila y casi siempre escribe lo
-- mismo. Cada SetText, aunque el texto sea identico, obliga a la
-- FontString a remedirse y reubicarse.
local function Poner(fs, texto)
    if fs.nufTexto ~= texto then
        fs.nufTexto = texto
        fs:SetText(texto)
    end
end

-- ETA (tiempo estimado de llegada), literal de Nx.HUD:Upd:
--   if map.PlS>.1 then
--     self.ETAD=self.ETAD-1
--     if self.ETAD<=0 then
--       self.ETAD=10
--       local eta=dis/map.PlS
--       self.ETAS = eta<60 and format("%.0f secs",eta) or format("%.1f mins",eta/60)
--     end
--     str=str..self.ETAS
--   else
--     self.ETAD=3; self.ETAS=""
--   end
-- Igual que alli, el TEXTO del ETA se recalcula cada ~10 ticks (no en
-- cada llamada): la distancia ya cambia sola con el zoom rapido de
-- muestreo (0.1s), pero mostrar segundos bajando de a fracciones se ve
-- nervioso -- Carbonite tiene exactamente el mismo throttle por la misma
-- razon. Necesita la zona calibrada (yardas reales), si no, no hay ETA.
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

-- Rota una textura EXACTAMENTE como Nx.Map:CFW en Carbonite: en vez de
-- Texture:SetRotation (mas nueva, puede faltar o andar mal en un cliente
-- de servidor privado), reacomoda a mano los 4 vertices de la textura via
-- SetTexCoord. "deg" son GRADOS (no radianes), igual que el "dir" de
-- Carbonite. Verificado numericamente (y con test): deg=90 hace que el
-- contenido que estaba en la esquina superior-izquierda de la imagen
-- termine en la esquina superior-derecha de la pantalla, es decir, rota
-- la imagen 90° en sentido HORARIO -- exactamente lo que hace falta para
-- que un rumbo de brujula (0=norte,90=este,horario) apunte bien, siempre
-- que la imagen de base apunte "hacia arriba" sin rotar (como cualquier
-- icono de flecha/brujula normal).
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
FF._RotateArrow = RotateArrow -- expuesta para los tests

-- Resuelve donde esta el objetivo de ESTA fila y arma nombre/distancia.
-- Corre cada 0.1s (ver el OnUpdate del final).
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

    -- La vida se muestra aunque este en otra zona: sigue siendo util saber
    -- como viene el otro aunque no puedas ir hacia el.
    if FF_Settings.showHealth and hp then
        Poner(r.hpText, format("%s%d %%|r", HealthColor(hp), hp))
    else
        Poner(r.hpText, "")
    end

    if mp.zone ~= tzone then
        -- No tenemos tabla de tamaños reales de cada zona en yardas (ver
        -- README), asi que no inventamos una direccion que seria
        -- incorrecta. Se dice en que zona esta, y nada mas.
        Poner(r.nameText, format("%s  |cffaaaaaain:|r %s", name, tzone or "?"))
        Poner(r.distText, source == "live" and "" or "(via addon)")
        r.tex:SetVertexColor(unpack(COLOR_OTHERZ))
        r.hasBearing = false
        return
    end

    r.lastDX = tx - mp.x
    r.lastDY = ty - mp.y
    r.hasBearing = true

    local pct = math.sqrt(r.lastDX * r.lastDX + r.lastDY * r.lastDY) -- % de la diagonal del mapa

    -- Si en algun momento estuvimos lo bastante cerca como para calibrar
    -- la zona (ver FF:TryCalibrate), se muestra la distancia real.
    FF:TryCalibrate(FF:FindAnyUnitToken(name), pct)

    -- yardas CRUDAS, para el guard "estoy encima" -- ese necesita yardas
    -- de verdad, no la unidad de display que haya elegido el usuario.
    r.lastYards = FF:CalibratedYards(mp.zone, pct)
    r.lastPct   = pct

    local dist, unitLabel = FF:RealDistance(mp.zone, pct)
    local sourceTag = source == "comm" and " |cff8080ff(addon)|r" or ""
    local etaText = ETATexto(r, FF.playerSpeedYps)

    Poner(r.nameText, name)
    -- Sin el "~" de "aproximadamente": la distancia es estimada igual, pero
    -- el simbolo no agregaba nada y ensuciaba la linea.
    if dist then
        Poner(r.distText, format("%.0f %s%s%s", dist, unitLabel, etaText, sourceTag))
    else
        Poner(r.distText, format("%.0f%% of map%s%s", pct, etaText, sourceTag))
    end
end

-- Recalcula el angulo Y el color de UNA fila, con el dx,dy en cache mas
-- la orientacion ACTUAL del personaje. Corre en cada cuadro porque es una
-- cuenta barata, y es lo que hace que se sienta en tiempo real al girar.
local function RefreshRowRotation(r, elapsed)
    if not r.hasBearing then
        -- Se perdio el rumbo: se olvida el suavizado, asi al recuperarlo
        -- apunta de una y no viene barriendo desde la direccion vieja.
        r.smDX, r.smDY = nil, nil
        return
    end

    -- Filtro exponencial hacia el vector crudo. Sin elapsed se toma de una.
    if elapsed and r.smDX and r.smDY then
        local k = 1 - math.exp(-elapsed / FF.BEARING_TAU)
        r.smDX = r.smDX + (r.lastDX - r.smDX) * k
        r.smDY = r.smDY + (r.lastDY - r.smDY) * k
    else
        r.smDX, r.smDY = r.lastDX, r.lastDY
    end

    local bearingDeg = math.deg(math.atan2(r.smDX, -r.smDY)) -- 0=norte, horario

    -- Misma conversion que usa Carbonite para su indicador de
    -- hacia-donde-mira-el-jugador (self.PlD): GetPlayerFacing da radianes.
    local facingDeg = 360 - math.deg(GetPlayerFacing() or 0)

    -- Guard identico a Nx.HUD:Upd ("if dis<1 then dir=0 end"): si estamos
    -- practicamente encima, se fuerza 0 en vez de dejar que el ruido de
    -- posicion haga temblar la flecha para cualquier lado.
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
            r.tex:SetBlendMode("ADD") -- blend aditivo = brilla, como en Carbonite
        end
    else
        r.tex:SetVertexColor(unpack(COLOR_OFFAIM))
        r.tex:SetBlendMode("BLEND")
    end
end

-- Mantenidas para probar a mano desde consola y para los tests.
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

-- El contenedor esta escondido cuando no seguis a nadie, y un marco
-- escondido no corre su OnUpdate: cuando no hay nada que mostrar, esto no
-- cuesta nada.
--
-- OJO: 0.1 tiene que ser <= FF.SAMPLE_INTERVAL. Si fuera mas grande, el
-- texto se quedaria mostrando datos viejos entre lecturas y la distancia
-- saltaria en vez de fluir.
local dataAccum = 0
container:SetScript("OnUpdate", function(self, elapsed)
    dataAccum = dataAccum + elapsed
    local refrescarDatos = dataAccum >= 0.1
    if refrescarDatos then dataAccum = 0 end

    for _, r in ipairs(rows) do
        if r.name then
            if refrescarDatos then RefreshRowInfo(r) end
            RefreshRowRotation(r, elapsed) -- cada cuadro: gira en tiempo real
        end
    end
end)
