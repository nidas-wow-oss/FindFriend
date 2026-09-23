# Find Friend (standalone)

Addon suelto para World of Warcraft 3.3.5a (Interface 30300) que reimplementa
la lógica de la flecha **"Track Player"** de Carbonite: la que te guía hacia
un compañero de grupo/banda (por ejemplo, tu dupla en un BG).

Es un addon **separado** a propósito, como pediste, para poder probarlo suelto
antes de portarlo a `Nidhaus_UnitFrames`.

---

## 1. Qué extraje de Carbonite y de dónde

`Carbonite.lua` viene minificado (nombres cortos, pero código normal, no
ofuscado) y tiene un bloque de datos de misiones de ~1.2 MB metido en una
sola línea (la línea 344) que no tiene nada que ver con esto. El resto del
archivo sí tiene funciones normales, de a una por línea.

La cadena completa de la función es esta:

| Pieza original (Carbonite.lua)            | Qué hace                                                                                             | Dónde quedó en el addon nuevo         |
|--------------------------------------------|-------------------------------------------------------------------------------------------------------|----------------------------------------|
| `Nx.Map:M_OTP(ite)` — botón de menú **"Track Player"** (clic derecho sobre el ícono del jugador en el mapa) | Marca `self.TrP[nombre] = true`                                                                        | `FF:StartTracking(name)`             |
| `Nx.Map:M_ORT(ite)` — **"Remove From Tracking"**                                     | Borra `self.TrP[nombre]`                                                                              | `FF:StopTracking()`                  |
| `Nx.Map:UpG(plX,plY)`                      | Recorre `party1..4` / `raid1..40` con `GetPlayerMapPosition(unidad)` (API nativa de Blizzard, **no depende del addon** si están en el mismo mapa) | `FF:FindGroupUnit` + `FF:SamplePositions` |
| `Nx.Com:UpI` / `Nx.Com:UPI` / `Nx.Com:OC__` | Sistema de mensajes entre clientes con Carbonite (canal propio de zona + addon-comm) para cuando el otro jugador **no** está en tu mapa actual | `FF:BroadcastPosition` / `FF:OnCommReceived` (versión simplificada, ver sección 3) |
| `Nx.Map:DrT1(srX,srY,dsX,dsY,tex2,mod1,nam)` | La cuenta: `dir = deg(atan2(y,x)) + 90` sobre píxeles de su propio canvas, más el dibujo de una fila de íconos hacia el destino | `FF:UpdateArrow()` (rehecho con fracciones 0-100 de `GetPlayerMapPosition`, ver sección 4) |
| Selector final en el `OnUpdate` del mapa: `if (paX or cTX) and (iBG or next(self.TrP)) then ...` | Decide si mostrar la flecha: primero intenta con datos "en vivo" de Blizzard, si no hay, usa el dato por addon-comm | Misma prioridad en `FF:ResolveTarget()` (primero `Sample()` llena `reports[nombre]` con datos "live" si están en el grupo, si no, `reports[nombre]` se llena por comm) |
| **`Nx.HUD:Upd(map)`** — la flecha REAL de pantalla completa (no un ícono de mapa) | `dir=(map.TrD-map.PlD)%360` (rumbo **relativo a tu orientación**), guard `dis<1 → dir=0`, y feedback de color/brillo según qué tan bien apuntado estás | `FF:RefreshRotation()` — ver sección 4bis, este fue el hallazgo clave de esta vuelta |

> **Esta última fila es la importante.** Las primeras veces confundí la
> flecha real de Carbonite (`Nx.HUD`, un módulo aparte, dedicado a mostrar
> una flecha grande en pantalla) con el sistema de íconos de su mapa
> (`Nx.Map:DrT1`). Son cosas relacionadas —comparten la misma técnica de
> rotación— pero no es lo mismo. `Nx.HUD` es la que corresponde a este
> addon, porque los dos son "una flecha sola, flotando en la pantalla".

Las notas completas del reverse engineering (con los offsets exactos donde
encontré cada función dentro del archivo) quedan **fuera de este repo**: tienen
fragmentos de `Carbonite.lua` copiados textual, y ese código no es mío para
redistribuirlo. Están en la copia local del addon.

## 2. Qué decidí **no** copiar tal cual, y por qué

- **El canal de chat propio de Carbonite (zona completa).** Carbonite abre un
  canal de comunicación para *todos* los que tengan el addon en la zona, no
  solo tu grupo. Eso agrega bastante complejidad (crear/unirse al canal,
  manejar reconexiones, etc.) y no hace falta para "encontrar a mi
  compañero": con **PARTY/RAID** (gratis, todo tu grupo ya lo recibe) +
  **WHISPER** (para un compañero puntual que no está en tu grupo) alcanza y
  sobra, y de paso es más privado (no le contás tu posición a extraños).

- **Los íconos/arte de Carbonite.** Esto pasó por tres vueltas, cada una
  corrigiendo a la anterior con información nueva que me diste:
  1. Al principio no tenía ningún archivo `.tga` (solo me pasaste `.lua`,
     `.xml`, `.toc`), así que usé `Interface\Minimap\ROTATING-MINIMAPGUIDEARROW`
     (textura nativa de Blizzard).
  2. Me mandaste una captura de la flecha real de Carbonite y volví al
     código: identifiqué `IconWayTarget` (el pin con nombre+distancia de tu
     captura) e `IconArrowGrad` (íconos chicos que sí rotan) — ambos del
     sistema de **íconos de mapa** (`Nx.Map:DrT1`).
  3. Me mandaste la lista de tu carpeta con `HUDArrow`, `HUDArrowChip`,
     `HUDArrowGloss`, `HUDArrowGlow`, `HUDArrowNeon` — volví al código de
     nuevo y hasta ese momento no los había visto: son de `Nx.HUD`, un
     **módulo aparte y dedicado** a mostrar una flecha grande en pantalla
     completa (no un ícono de mapa) — el mismo concepto exacto de este
     addon. Ver sección 4quater para el detalle completo de cómo funciona
     esa flecha.

  Con esto, el addon ahora ofrece **8 estilos** de ícono, todos cargados
  desde copias locales en la carpeta `Media` (ver `Media\LEEME.txt`):

  | Estilo | Archivo (copiar desde `Interface\AddOns\Carbonite\Gfx\Map\`) | Comando |
  |---|---|---|
  | **Flecha real (default)** | `HUDArrow.tga` | `/ff icon hud` |
  | Variante "Chip" | `HUDArrowChip.tga` | `/ff icon hud-chip` |
  | Variante "Gloss" | `HUDArrowGloss.tga` | `/ff icon hud-gloss` |
  | Variante "Glow" | `HUDArrowGlow.tga` | `/ff icon hud-glow` |
  | Variante "Neon" | `HUDArrowNeon.tga` | `/ff icon hud-neon` |
  | Pin de mapa (no diseñado para rotar) | `IconWayTarget.tga` | `/ff icon pin` |
  | Fila de flechas de mapa | `IconArrowGrad.tga` | `/ff icon trail` |
  | Nativo de Blizzard (no necesita copiar nada) | — | `/ff icon blizzard` |

  Un addon no tiene forma de saber si un archivo de textura existe o no
  (`SetTexture` simplemente no dibuja nada si falta, sin avisar): si no
  copiás el `.tga` del estilo que elegiste, vas a ver la flecha vacía
  hasta que copies el archivo o cambies a `/ff icon blizzard`.

- **Distancia en yardas exactas.** Esto lo investigué en serio antes de
  descartarlo: ni siquiera Astrolabe (la librería estándar de la comunidad
  para esto) tiene una tabla completa y confiable del tamaño real de cada
  zona de WotLK — es un dato que se obtiene minando cada mapa a mano, zona
  por zona. Carbonite convierte con una constante (`dis*4.575`) que es
  específica de su propio canvas interno a un nivel de zoom fijo, no un
  valor reutilizable fuera de su sistema. Antes que inventar un número que
  parezca preciso pero esté mal, calibro la escala real usando
  `CheckInteractDistance` (ver sección 4ter) en vez de una tabla fija.

- **Cuando tu compañero está en OTRA zona/instancia:** en vez de dibujar una
  flecha que probablemente apunte para cualquier lado (no hay forma de
  comparar coordenadas de dos mapas distintos sin esa tabla de tamaños), el
  addon te avisa directamente el nombre de la zona donde está. Esto también
  es lo que vas a ver casi siempre si tu compañero todavía no entró al
  mismo BG que vos (loading screen, etc.).

## 3. Cómo funciona el protocolo (resumen)

1. Cada 1s (`FF.SAMPLE_INTERVAL`), leés tu propia posición
   (`GetPlayerMapPosition("player")`) y, si el compañero que seguís está en
   tu grupo/banda, también la suya — todo por API nativa, sin addon.
2. Cada 2s (`FF.PING_INTERVAL`), avisás tu posición: al grupo entero por
   `PARTY`/`RAID`, y por `WHISPER` a cualquiera que te haya pedido tu
   posición (ver punto 4).
3. Si el compañero que seguís **no** está en tu grupo, le mandás un mensaje
   `REQ` por whisper pidiéndole que te empiece a mandar su posición (se
   reintenta cada 15s mientras no tengas respuesta). Esto **solo funciona si
   la otra persona también tiene este addon corriendo** — es la misma
   limitación que ya habías notado en Carbonite, y es inherente a cualquier
   sistema de este tipo: no hay forma de saber dónde está alguien sin que
   esa persona (o algo que corra en su nombre) te lo diga.
4. Al recibir un `REQ`, le contestás a esa persona con `PING` por whisper
   durante 5 minutos (`FF.WATCH_EXPIRES`).
5. Un reporte de posición se considera "viejo" y se descarta a los 45s
   (`FF.STALE_AFTER`) — así la flecha nunca te muestra una ubicación
   desactualizada sin avisar.

## 4. La matemática del rumbo y el dibujo de la flecha (esto cambió)

**Si probaste una versión anterior de este addon y la flecha no se movía o
no se veía bien: era esto.** Mi primera versión usaba `Texture:SetRotation()`
para girar el ícono. Volví a revisar el código real de Carbonite
(`Nx.Map:CFW`, la función que efectivamente rota los íconos en su mapa) y
resulta que **Carbonite no usa `SetRotation` para nada** — usa una técnica
más vieja y manual: reacomoda a mano las 4 esquinas de la textura con
`SetTexCoord` (la variante que recibe 8 valores, uno por esquina) usando
trigonometría, en vez de rotar el frame entero. Código real:

```lua
local tX1,tX2,tY1,tY2 = -.5,.5,-.5,.5
local co=cos(dir)   -- OJO: cos()/sin() GLOBALES de WoW, no math.cos/math.sin
local si=sin(dir)   -- estas reciben GRADOS, no radianes (resabio de cuando
                     -- el juego corria sobre Lua 4.0, antes de tener math.*)
t1x=tX1*co+tY1*si+.5   -- esquina superior-izquierda
t1y=tX1*-si+tY1*co+.5
t2x=tX1*co+tY2*si+.5   -- esquina inferior-izquierda
t2y=tX1*-si+tY2*co+.5
t3x=tX2*co+tY1*si+.5   -- esquina superior-derecha
t3y=tX2*-si+tY1*co+.5
t4x=tX2*co+tY2*si+.5   -- esquina inferior-derecha
t4y=tX2*-si+tY2*co+.5
frm.tex:SetTexCoord(t1x,t1y,t2x,t2y,t3x,t3y,t4x,t4y)
```

Por qué esto probablemente era el bug real y no solo una diferencia de
estilo: `SetRotation` es una función más nueva, y en el cliente 3.3.5a de
un servidor privado puede directamente faltar o estar mal implementada
—cosa que no le pasa a `SetTexCoord`, que es básica y existe desde
siempre—. Ahora el addon usa **exactamente** la técnica de Carbonite
(`FF._RotateArrow` en `FindFriend_Arrow.lua`), verificada
matemáticamente a mano contra los 4 puntos cardinales (y con tests: le paso
90°, 180°, etc. a la función y comparo cada esquina contra el resultado
calculado con lápiz y papel).

El rumbo en sí (hacia dónde apunta, no cómo se dibuja) sigue siendo:
```lua
dx = tx - px          -- positivo = el objetivo esta al este
dy = ty - py          -- positivo = el objetivo esta al sur
rumbo = atan2(dx, -dy)   -- 0=norte, 90=este, 180=sur, 270=oeste (radianes)
```
que después se pasa a grados para alimentar `RotateArrow`, tal como
Carbonite hace con su `dir`.

```lua
dx = tx - px      -- positivo = el objetivo está al este
dy = ty - py      -- positivo = el objetivo está al sur (GetPlayerMapPosition
                  -- crece hacia abajo, como coordenadas de imagen)
rumbo = atan2(dx, -dy)   -- 0° = norte, 90° = este, 180° = sur, 270° = oeste
```

Comprobé los 4 puntos cardinales (y 90°/180° contra `FF._RotateArrow`
directamente) con una batería de tests automatizados (instalé Lua 5.1 —la
misma versión que usa el cliente de WoW 3.3.5— y corrí el addon contra un
stub del API del juego). 60 verificaciones en total, incluyendo casos
límite: seguir a alguien fuera del grupo, datos viejos, zona distinta,
intentar seguirte a vos mismo, el doble clic sobre el objetivo, y que la
rotación cambie con la orientación sin esperar un nuevo muestreo de
posición. Dejo los archivos de test (`test_stub.lua`, `run_tests.lua`) por
si querés correrlos de nuevo o agregar más casos vos mismo — no forman
parte del addon, no hace falta copiarlos al juego.

**Por default la brújula gira con tu personaje** (como el minimapa cuando
tenés "Rotar minimapa" activado). Siempre: el modo norte-arriba existió
un tiempo y se sacó a pedido, porque para "ir hacia allá" lo único que
sirve es el rumbo relativo a hacia dónde estás mirando.

**Para verificar rápido que anda, sin necesitar a otro jugador**, usá
`/ff demo`: crea un objetivo de prueba fijo al este tuyo. Girá tu
personaje sin caminar — la flecha tiene que seguir señalando siempre el
mismo punto del mundo, de forma continua, sin saltos ni parpadeos. `/ff off`
para salir del modo de prueba. Si el giro te queda invertido (para el lado
contrario de cómo girás), es un cambio de un signo en `FF:RefreshRotation`
(`FindFriend_Arrow.lua`) — avisame y lo ajusto.

Para que se sienta realmente "en tiempo real" al girar sobre tu eje, separé
el trabajo en dos partes que corren a velocidades distintas:
- **Cada ~0.3s:** se recalcula dónde está el objetivo (`FF:RefreshTargetInfo`) — esto no necesita ser instantáneo, la posición de otra persona no cambia varias veces por segundo.
- **En cada frame:** se recalcula solo el ángulo de la flecha usando tu orientación actual (`FF:RefreshRotation`) — esto sí es barato y se nota al instante cuando girás, sin esperar el próximo muestreo de posición.

## 4quater. La flecha real: `Nx.HUD` (el hallazgo clave de esta vuelta)

Cuando mandaste la lista de archivos con `HUDArrow`, `HUDArrowChip`,
`HUDArrowGloss`, `HUDArrowGlow`, `HUDArrowNeon`, volví al código y hasta
ese momento no los había encontrado — resultó que son de un **módulo
aparte y dedicado** que hasta ahora no había mirado: `Nx.HUD`. A
diferencia de `Nx.Map:DrT1` (que dibuja íconos sobre un mapa/minimapa),
`Nx.HUD` es literalmente una flecha grande flotando en la pantalla — el
mismo concepto exacto que este addon. Es la respuesta correcta a "cuál es
la flecha de Carbonite" que veníamos buscando.

Su función central, `Nx.HUD:Upd(map)`, me dio tres cosas nuevas y muy
concretas (código real, resumido):

```lua
local dis=map.TDY                    -- distancia en yardas
local dir=(map.TrD-map.PlD) % 360    -- RUMBO RELATIVO a tu orientación
if dis<1 then dir=0 end              -- evita temblor si estás encima
local diD=dir<=180 and dir or 360-dir -- qué tan lejos de "de frente" (0-180)
-- ... (misma rotación manual vía SetTexCoord que ya teníamos)
if diD<5 then
  if dis<1 then tex2:SetVertexColor(.2,1,.2,.4); tex2:SetBlendMode("BLEND")
  else tex2:SetVertexColor(.7,.7,1,1); tex2:SetBlendMode("ADD") end -- brilla si apuntás bien
else
  tex2:SetVertexColor(1,1,.5,.9); tex2:SetBlendMode("BLEND")        -- amarillo pálido si no
end
```

1. **`dir = TrD - PlD`** confirma que la brújula "gira con vos" (nuestro
   default) es exactamente como Carbonite arma SU flecha de pantalla
   completa — no fue una interpretación mía, es literal.
2. **Guard anti-temblor**: si estás a menos de 1 yarda del objetivo, se
   fuerza `dir=0` en vez de dejar que el ruido normal de posición haga
   temblar la flecha para cualquier lado. Ya lo agregué (`FF:RefreshRotation`,
   usa yardas reales si la zona está calibrada, si no un umbral de % de mapa).
3. **Feedback de color/brillo**: la flecha te avisa con un vistazo qué tan
   bien apuntado estás, además de girar — celeste y brillante (blend
   `ADD`) si apuntás bien (menos de 5° de error), amarillo pálido si no, y
   verde si estás prácticamente encima. Ya lo porté tal cual. Esto solo
   tiene sentido con la brújula girando con vos — sin eso no hay un
   "de frente" al que apuntar, así que ahí queda un color neutro fijo.

**ACTUALIZACIÓN (3ra vuelta):** las tres cosas de acá abajo las pediste
específicamente después de probar la vuelta de `Nx.HUD`, así que las
detallo con precisión (nada de "quedó mejor o peor a ojo"):

**1) El color de alineación.** Ya estaba portado en el párrafo de arriba,
pero para que lo puedas confirmar sin depender de mi palabra agregué
`/ff debug`: mientras está activado, el chat avisa cada vez que la
flecha CAMBIA de estado, con el ángulo exacto:
```
[FF debug] diD=3.2°  rumbo rel=3.2°  estado=ALIGNED -> celeste, brilla (bien apuntado)
```
Solo avisa en los cambios (no en cada frame, para no inundar el chat).
Colores reales, idénticos a `Nx.HUD:Upd`: celeste con brillo (`ADD`) si
apuntás a menos de 5° del objetivo, amarillo pálido si no, verde si estás
a menos de 1 yarda. Tres tests nuevos verifican que el aviso se dispara
justo en las transiciones, ni antes ni después.

**2) La distancia "a saltos".** El bug real: muestreaba tu posición una
vez por segundo (`FF.SAMPLE_INTERVAL`), así que solo podía cambiar una
vez por segundo — de ahí el salto. Lo bajé a **0.1s** (10 veces por
segundo) y sincronicé el refresco del texto en pantalla a la misma
velocidad. Carbonite recalcula esto en cada tick de su propio `OnUpdate`
(básicamente cada frame); no llegamos a ese extremo para no gastar de más,
pero 10 actualizaciones por segundo ya es indistinguible de "tiempo real"
a simple vista.

**3) El ETA.** Ahora sí portado — y de paso encontré cómo Carbonite
calcula tu velocidad (`.PlS` en su código)
y la porté literal, no aproximada:
```lua
if x==self.PlX and y==self.PlY then      -- no te moviste
  self.PlS=0                              -- velocidad 0 AL INSTANTE
else
  local tmD=GetTime()-self.PSCT
  if tmD>.5 then                          -- pero no recalcules mas seguido
    self.PlS=(dist)^.5*4.575/tmD          -- que cada 0.5s (si no, tiembla)
  end
end
```
Usamos nuestra propia escala calibrada en vez del `4.575` fijo de
Carbonite (esa constante es de su canvas interno, no reutilizable — ver
sección 4ter). El ETA sigue el mismo throttle de "recalcular cada ~10
ticks" que `Nx.HUD:Upd`, para que el número no tiemble mostrando
fracciones de segundo:
```
~45 m  12 seg
~230 m  1.8 min
```
No aparece hasta que: (a) la zona está calibrada (necesita yardas reales,
no se puede expresar velocidad en "% de mapa por segundo" de forma útil)
y (b) te estás moviendo a más de 0.1 yardas/seg (umbral literal de
Carbonite, `map.PlS>.1`).

Agregué 16 tests nuevos para estas tres cosas (velocidad: primera muestra,
no-moverse, throttle de 0.5s, cálculo correcto, sin calibrar, cambio de
zona; ETA: sin velocidad, velocidad mínima, formato segundos, formato
minutos, throttle del texto; debug: aparece en el cambio, no se repite,
aparece en el cambio contrario) — **94 tests en total, todos pasan.**

## 4ter. Distancia real (yardas o metros)

Le pediste al addon que la distancia se muestre en yardas o metros en vez
de "% del mapa". Antes de escribir cualquier cosa, investigué en serio si
existía una forma confiable de hacerlo, porque no quería inventar un
número que pareciera preciso pero estuviera mal.

**Lo que encontré:** el juego no tiene ninguna función que te diga la
distancia exacta a otro jugador lejano. La única forma de convertir el "%
del mapa" que da `GetPlayerMapPosition` a yardas reales es conocer el
tamaño real (ancho/alto en yardas) de esa zona específica — un dato que
Blizzard guarda en un archivo interno del cliente (`WorldMapArea.dbc`), no
en ninguna función de Lua a la que un addon pueda llamar. Revisé las
librerías que la comunidad usa para esto (Astrolabe, HereBeDragons): las
versiones actuales de HereBeDragons —la que usa TomTom hoy en día,
inclusive en Wrath Classic— sacan ese dato de una API (`C_Map`) que
**no existe en un cliente 3.3.5a auténtico** (esa API la agregó Blizzard
mucho después; los clientes "Classic" corren sobre el motor moderno del
juego, con esa API disponible aunque el contenido sea viejo — un servidor
privado corriendo el cliente 3.3.5a real de 2010 no la tiene). Encontré
también un hilo de un desarrollador de esa misma época (2008) topándose
con este exacto problema y sin solución limpia. Con esto confirmado, no
iba a hardcodear una tabla de tamaños de zona a mano: el margen de error
de inventar esos números sería alto, sobre todo en instancias/battlegrounds.

**Lo que hice en cambio — autocalibración:** el juego sí tiene una función
que da una distancia EXACTA y conocida a otro jugador: `CheckInteractDistance`,
que dice si estás a menos de 9.9, 11.11 o 28 yardas de alguien (los rangos
de duelo/comercio/inspeccionar). La primera vez que estás así de cerca de
tu compañero, el addon compara esa distancia real contra el "% del mapa"
de ese mismo instante, y calcula cuántas yardas equivalen a un 1% del mapa
**en esa zona en particular**. Esa calibración:
- se guarda entre sesiones (por zona, en `FF_Settings.zoneScale`), así que una vez calibrada una zona no hace falta volver a acercarse;
- se refina sola: si más adelante te acercás lo suficiente como para estar a 9.9 yardas (más preciso que los 28 yardas del primer cálculo), el addon actualiza la calibración con el dato más ajustado;
- funciona incluso si tu compañero no está en tu grupo, siempre que en algún momento lo hayas tenido como target/mouseover/focus estando cerca.

Hasta que una zona se calibra al menos una vez, se sigue mostrando "% del
mapa" (el respaldo que ya tenía) en vez de inventar una cifra.

`/ff units` alterna entre metros (por defecto) y yardas. La conversión es
exacta (1 yarda = 0.9144 metros); lo único aproximado es la calibración en
sí, no la conversión de unidades.

Agregué 6 tests nuevos para esto (autocalibración, que no se pise una
calibración buena con una peor, que la calibración se seguya usando aunque
el objetivo se aleje, y la conversión de unidades) — de hecho, escribir el
test encontró un bug real en mi primera versión (comparaba el índice del
rango en vez de las yardas que representa, así que una calibración peor
podía pisar a una mejor). Quedó arreglado y con test que lo cubre.

## 4bis. Doble clic para activar el seguimiento

Además de `/ff track` y `/ff target`, ahora **doble clic con el botón
izquierdo sobre el retrato/frame de tu objetivo** (el `TargetFrame` de
Blizzard, el que muestra vida/nombre/retrato arriba a la izquierda) empieza
a seguir a quien tengas targeteado en ese momento. Usé `HookScript` (no
`SetScript`) a propósito: eso agrega nuestra función sin pisar el
comportamiento normal del frame (atacar con clic, etc.), que es protegido y
no se puede reemplazar directamente.

**Importante para cuando lo integres a Nidhaus_UnitFrames:** si tu addon
reemplaza el `TargetFrame` de Blizzard por uno propio (muy común en addons
de unit frames), este hook va a dejar de recibir clics porque el frame de
Blizzard queda tapado. En ese momento alcanza con enganchar el mismo
`FF:StartTracking(name)` al doble clic de tu propio frame de objetivo.

## 4quinquies. Bug: el mapa "saltaba" al abrirlo dentro de un BG

Reportaste que al abrir el mapa del mundo dentro de un battleground, el
mapa se iba "para cualquier lado", como un salto hacia atrás. Causa real:
para leer tu posición, `FF:SamplePositions` llamaba `SetMapToCurrentZone()`
**siempre**, sin fijarse si hacía falta, y trataba de devolver el mapa a
como estaba justo después. Dentro de una instancia (los battlegrounds lo
son), `SetMapToCurrentZone()` no siempre resuelve bien la relación
continente/zona y puede saltar a otra vista — y como esto corre 10 veces
por segundo (el cambio que hice para que la distancia no saltara), el
efecto se notaba muchísimo más que antes.

**Arreglo:** ahora primero se intenta leer la posición **sin tocar nada**.
Si el mapa que tenés abierto ya te incluye —el caso normal: al entrar a un
BG y abrir el mapa, Blizzard ya te muestra el mapa del BG, que ES tu zona
actual— alcanza con eso, y el addon no llama ni `SetMapToCurrentZone()` ni
`SetMapZoom()` en absoluto. Solo si el mapa actual NO te incluye (estás
mirando otra zona/continente a propósito, por ejemplo planeando un viaje)
se fuerza el cambio, se lee todo de una, y recién ahí se restaura. Esto
elimina el interferir con el mapa en el caso normal, que es exactamente el
de estar parado dentro de un BG con el mapa abierto.

Agregué 2 tests que verifican esto puntualmente: que `SetMapToCurrentZone`/
`SetMapZoom` NO se llaman cuando no hace falta, y que SÍ se llaman
(una sola vez cada uno) cuando el mapa realmente está mostrando otra cosa.

## 4sexies. Sonido + auto-seguir a tu dupla al entrar a un BG

Dos funciones nuevas que pediste, elegidas entre varias opciones por ser
las que menos ambigüedad de diseño tenían (a diferencia de "un botón de
minimapa" o "seguir a varios a la vez", que cambian bastante la interfaz y
prefiero confirmar el diseño antes de construirlas).

**Sonido** (`/ff sound` para on/off, `/ff sound test` para probarlo):
- Suena `igQuestListOpen` la primera vez que hay rumbo calculable hacia tu
  compañero (lo encontraste, o lo recuperaste después de perderlo).
- Suena `igPlayerInvite` al pasar a "apuntando bien" (ALIGNED/ONTOP) desde
  otro estado — pero no en el primer cálculo (para no duplicar con el
  sonido de "encontrado"), y no se repite mientras seguís alineado.
- Elegí estos dos sonidos nativos porque son de UI básica de Blizzard que
  existe desde Vanilla (log de misiones, invitación a grupo) — el riesgo
  de que falten en tu cliente es mínimo. Confirmé además que `PlaySound`
  con nombres de string (no ID numérico) funciona así en la API vieja que
  corresponde a 3.3.5a.
- Bug real que encontré escribiendo el test: el conteo de "cambió el
  estado" solo se actualizaba cuando `/ff debug` estaba prendido, así que
  con el debug apagado el sonido de alineación hubiera sonado en cada
  frame en vez de solo en la transición. Ya está separado y cubierto por
  test.

**Auto-seguir a tu dupla** (`/ff autoduo` para on/off, default: on):
Los battlegrounds convierten a todo el mundo en banda (raid), incluso si
entraste solo/a — una vez adentro, no hay forma de saber vía API quién
era tu premade y quién es gente random de la banda. La solución: mientras
estás afuera de una instancia, el addon recuerda con quién estás en party
si es *exactamente* una persona más (una dupla real — si son más, no se
sabe a cuál elegir, así que no se guarda nada). Al detectar que entraste a
un battlefield (`IsInInstance()` devuelve `"pvp"`), si tenés una dupla
recordada y no estás siguiendo ya a alguien manualmente, arranca solo. Uso
`GROUP_ROSTER_UPDATE` para mantener el dato actualizado y
`PLAYER_ENTERING_WORLD` para detectar la entrada al BG.

20 tests nuevos para estas dos cosas.

## 5. Cómo probarlo

1. Copiá la carpeta `FindFriend` completa a
   `World of Warcraft/Interface/AddOns/`.
2. **Copiá al menos `HUDArrow.tga`** (ver `Media\LEEME.txt` dentro del
   addon, tiene la lista completa de los 7 archivos posibles): desde
   `Interface\AddOns\Carbonite\Gfx\Map\HUDArrow.tga`, pegalo tal cual en
   `Interface\AddOns\FindFriend\Media\HUDArrow.tga`. Si no lo
   copiás, el addon igual funciona con `/ff icon blizzard` (no necesita
   nada externo).
3. Entrá al juego y activalo en la lista de addons si hace falta.
4. Comandos:
   - `/ff track <nombre>` — seguir a un jugador por nombre.
   - `/ff target` — seguir a tu objetivo actual.
   - `/ff off` — dejar de seguir.
   - `/ff units` — alternar metros (default) / yardas.
   - `/ff icon hud|hud-chip|hud-gloss|hud-glow|hud-neon|pin|trail|blizzard` — elegir el ícono de la flecha (ver la tabla de la sección 2; `hud` es el default, la flecha real de Carbonite).
   - `/ff demo` — probar la flecha sin necesitar a otro jugador online.
   - `/ff debug` — avisar por chat, en vivo, el estado de alineación (ONTOP/ALIGNED/OFFAIM) cada vez que cambia — para confirmar el color sin dudas.
   - `/ff sound` — alternar sonido on/off (`/ff sound test` lo prueba sin condiciones).
   - `/ff autoduo` — alternar el auto-seguimiento de tu dupla al entrar a un BG (default: on).
   - **Doble clic** con el botón izquierdo sobre el retrato de tu objetivo — empieza a seguirlo (atajo equivalente a `/ff target`).
5. La flecha aparece debajo del minimapa por default; se puede arrastrar
   con el botón izquierdo y la posición se guarda entre sesiones. Cuando
   apuntes bien hacia tu compañero (menos de 5° de error) la vas a ver
   brillar en celeste — es el mismo feedback que usa Carbonite.

Al principio vas a ver la distancia como "% del mapa" hasta que en algún
momento estés lo bastante cerca de tu compañero (rango de duelo/comercio/
inspeccionar, unas pocas yardas) — ahí el addon calibra esa zona solo, y de
ahí en adelante vas a ver metros/yardas reales, incluso si tu compañero
después se aleja mucho.

Para probar el caso "está en mi grupo" alcanza con vos y un amigo en la
misma party. Para probar el caso "no está en mi grupo", necesitás que esa
otra persona también tenga este addon instalado (es la limitación que ya
sabías, la dejamos así por ahora tal como dijiste).

## 6. Ideas para cuando lo integres a Nidhaus_UnitFrames

- El lugar más natural para "elegir a quién seguir" sería un clic derecho
  sobre el unit frame de un miembro de party/raid (igual que Carbonite lo
  hace sobre su ícono de mapa) llamando directo a `FF:StartTracking(name)`.
- `FF.reports` y `FF:FindGroupUnit` están pensados para poder reusarse
  tal cual si en tu addon ya tenés unit frames de grupo: es trivial pintar
  un pequeño indicador de distancia/dirección directo sobre cada frame en
  vez de (o además de) la flecha flotante.
- Si más adelante querés soportar varios compañeros a la vez (no solo uno),
  la estructura ya lo permite del lado de datos (`reports` es una tabla por
  nombre); lo único que habría que cambiar es la UI (`FindFriend_Arrow.lua`)
  para dibujar más de una flecha o una lista.
