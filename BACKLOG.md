# BACKLOG — model-routing-kit

Tickets pendientes, detectados durante el dogfood del plugin. Se implementan después
(no hoy). Cada uno es una mejora concreta sobre el comportamiento ya funcionando.

---

## TICKET 1 — El hook lee `RISKY` desde la config del proyecto

Hoy el patrón `RISKY` (rutas de datos/lógica que el scope-guard protege) está **hardcodeado**
en `hooks/scope-guard.sh`. Debería leerse de la configuración del proyecto (p. ej. un valor
que `/onboard` escribe en el `CLAUDE.md` o en un archivo de config), para que cada repo defina
sus propias rutas riesgosas sin editar el script del plugin.

- **Estado:** ✅ HECHO (2026-06-17). El hook lee `RISKY` de `.claude/scope-guard.conf`
  (formato `key=value`: `RISKY=<regex>`), con fallback al default built-in cuando el conf no
  existe o no define la clave (backward-compat). El formato `key=value` se eligió a propósito
  para que el Ticket 2 agregue `RISKY_visual_polish=` / `RISKY_text_and_copy_editor=` sin tocar
  el parser. `/onboard` (step 9) ahora escribe el conf y NUNCA forkea el script. Cubierto por
  3 tests nuevos (10/10 en scope-guard.test.sh: deny por conf, conf reemplaza al default,
  conf vacío → default).
- **Archivos:** `hooks/scope-guard.sh`, `hooks/scope-guard.test.sh`, `commands/onboard.md`,
  `CLAUDE.template.md`, `CLAUDE.md`.
- **Follow-up (cuando esto shippee):** migrar tecnologiasvm a `.claude/scope-guard.conf` y
  **dropear el `RISKY` inline** de su `scope-guard.sh` forkeado (ya en `main`). Eso de paso
  colapsa el doble-guard señalado en `learnings.md`.

---

## TICKET 2 — Scope por-agente (copy-editor vs visual-polish)

El scope-guard trata a `text-and-copy-editor` y `visual-polish` con el **mismo** patrón
`RISKY`. Pero sus alcances legítimos difieren: el copy-editor solo debe tocar texto/strings,
mientras visual-polish sí puede tocar CSS/markup. Hace falta un scope **diferenciado por
agente** para que cada uno tenga sus propios límites.

- **Estado:** ✅ HECHO (2026-06-17). Construido sobre el `key=value` del Ticket 1. El hook
  resuelve RISKY por agente: `RISKY_<agente>` (guiones→underscores, p.ej. `RISKY_visual_polish`)
  > `RISKY` base > default built-in. Una clave por-agente **reemplaza** la base (no fusiona).
  Los defaults built-in ya están **diferenciados**: ambos agentes UI bloqueados de data/lógica,
  pero `text-and-copy-editor` **también** de stylesheets (`\.css|\.scss|\.sass|\.less`) —
  re-estilar es trabajo de visual-polish. Cubierto por 6 tests nuevos (16/16): diferenciación
  built-in (copy-editor.css DENY / visual-polish.css ALLOW) + claves por-agente (aplica + reemplaza
  base, para ambos agentes). Parser **sin cambios** (era el objetivo del formato).
- **Archivos:** `hooks/scope-guard.sh`, `hooks/scope-guard.test.sh`, `commands/onboard.md`,
  `CLAUDE.template.md`, `CLAUDE.md`.

---

## TICKET 3 — El copy-editor (Haiku) sobre-reescribe

En el dogfood, `text-and-copy-editor` reescribió copy **más de lo pedido**. Debe mantener sus
ediciones al **string exacto solicitado**. Endurecer su prompt o agregar un guardrail para
que no reformule texto no solicitado.

- **Estado:** pendiente.
- **Archivos:** `agents/text-and-copy-editor.md` (prompt), y posible guardrail en
  `hooks/scope-guard.sh`.

---

## TICKET 4 — Ledger de routing + comando `/route-review`

Para poder **medir y corregir** el routing sesión a sesión (hoy es manual, vía `learnings.md`).
Prototipado a mano en tecnologiasvm (rama `chore/routing-policy`): el `scope-guard.sh` ya
escribe una línea JSON por `Edit|Write|MultiEdit|Bash` a `.claude/routing-log.jsonl`
(gitignored) con `ts`, `agent` (atribución por tier), `tool`, `tool_target`, `decision`,
`matched`. Falta subir esto al plugin para que **todo proyecto onboarded lo herede**:

1. **Auto-log en el `scope-guard.sh` del plugin** — portar la línea JSONL ya probada en
   tecnologiasvm. Captura la mitad *correctitud* (qué tier hizo qué, bloqueos falsos).
2. **Comando `/route-review`** — lee `.claude/routing-log.jsonl` de la sesión + el diff, y
   reporta: ¿cada tarea cayó en su tier?, ¿bloqueos falsos?, ¿el driver hizo trivialidades?
   → propone correcciones (RISKY, prompts) o abre ticket.
3. **`/onboard` añade los artefactos locales del kit al `.gitignore`** del proyecto destino —
   AMBOS: `.claude/routing-log.jsonl` (este ticket) y `.claude/.routing-kit-regcheck` (el stamp
   de warn-once del Ticket 6). Ninguno debe poder comitearse por accidente; son del mismo dominio
   (estado local por-proyecto del kit). `commands/onboard.md` ya añade ambos (paso 11) — al
   formalizar este ticket, consolidar ahí en vez de duplicar el mecanismo.

Nota: la mitad *costo* (tokens/cuota por tier) NO es auto-capturable — `/usage` es interactivo;
el review pide pegarlo a mano. Depende del Ticket 1 (RISKY desde config) para no re-forkear el hook.

- **Estado:** pendiente (prototipo validado en tecnologiasvm).
- **Archivos:** `hooks/scope-guard.sh`, `commands/route-review.md` (nuevo), `commands/onboard.md`.

---

## TICKET 5 — Knob de tier por tarea (`/run-at`) + intermedios + log de elección manual ✅ HECHO

La escalera actual es **bimodal**: haiku · sonnet/low · opus/high · opus/xhigh — sin
intermedios (**opus/medium, sonnet/high, opus/low**), que es donde vive mucho trabajo real.
Hoy `/route` clasifica y elige por ti; no hay forma de que **el usuario** dirija una tarea
puntual a un tier arbitrario sin cambiar el `/model` y `/effort` de toda la sesión.

**Diseño:**
1. **Comando `/run-at <model> <effort> "<tarea>"`** — despacha la tarea como subagente puntual
   en el tier exacto pedido, **sin tocar el `/model`/`/effort` de la sesión** (cache intacto).
   Esto expone el continuo completo por tarea → hace innecesario predefinir rungs intermedios.
2. **Shorthand de una letra (posicional, rápido de tipear):**
   - modelo: `o`=opus, `s`=sonnet, `h`=haiku
   - effort: `l`=low, `m`=medium, `h`=high, `x`=xhigh
   - La `h` no choca porque la posición lo desambigua: `s h` = sonnet/high; `h m` = haiku/medium.
     Aceptar también palabras completas y la forma pegada `oh` / `sm`.
3. **Loguear la elección manual** (conecta con Ticket 4) — el comando escribe su propia línea a
   `.claude/routing-log.jsonl` con `source:"manual"`, `model`, `effort`, `task`. Así
   `/route-review` puede **detectar misfires de intuición**: ej. "escalaste a opus/high una
   tarea que 3 señales dicen trivial", o "corriste haiku algo que falló y reintentaste arriba".
   Aprender de las elecciones manuales es la mitad más rica del ledger.

**Parte B — escalera intermedia (para que el medio también funcione automático):** el knob
genérico ataca la raíz, pero además se hizo automático el eje barato:
- **Principio "escalá effort antes que modelo"** documentado en `commands/route.md` y
  `CLAUDE.template.md`, con la escalera graduada explícita:
  `sonnet/low → sonnet/med → sonnet/high → opus/med → opus/high → opus/xhigh` (subí effort
  antes que modelo; un rung por vez).
- **Un solo agente intermedio nombrado:** `agents/implementer.md` (sonnet / effort high) — rung
  medio entre el driver y `complex-implementer` (opus/high). Para lógica no trivial, refactor
  multi-paso, componentes con estado que necesitan pensar más pero no capacidad Opus. Su
  `description` dice cuándo NO usarlo (trivial→copy-editor, CSS→visual-polish, animación/canvas/
  algoritmo duro→complex-implementer). Los demás combos (sonnet/med, opus/med, opus/low) NO son
  agentes nombrados — se alcanzan con `/run-at`. NO está scope-guarded (no es agente UI-only).

- **Estado:** ✅ HECHO (2026-06-17). **Parte A:** `/run-at <model> <effort> "<tarea>"` despacha
  un subagente puntual al tier exacto **sin tocar el `/model`/`/effort` de la sesión**; shorthand
  posicional de una letra (`o/s/h` modelo, `l/m/h/x` effort; la `h` se desambigua por posición;
  formas pegadas `oh`/`sm`); loguea la elección a `.claude/routing-log.jsonl` con `source:"manual"`
  para que el futuro `/route-review` (Ticket 4) detecte misfires de intuición. **Parte B:**
  escalera graduada + agente `implementer` (sonnet/high). Tests: `install-smoke` reconoce ambos
  (`/run-at` loguea manual + `implementer` en sonnet/high) → 10/10; `scope-guard` intacto 16/16.
- **Archivos:** `commands/run-at.md` (nuevo), `agents/implementer.md` (nuevo), `commands/route.md`,
  `CLAUDE.template.md`, `USAGE.md`, `hooks/install-smoke.test.sh`, `CLAUDE.md`.

---

## TICKET 6 — Self-check de registro: `enabled ≠ registered`

Detectado en el 3er dogfood (tecnologiasvm, 2026-06-19). El plugin estaba **habilitado** en
`settings.json` (`model-routing-kit@model-routing-kit: true`) y sus agentes habían funcionado
horas antes (el `routing-log.jsonl` prueba que `complex-implementer` corrió a las 16:25), pero
en una sesión posterior el routing intentó escalar a `complex-implementer` y falló con
`Agent type 'complex-implementer' not found` — **cero agentes del kit registrados**. Causa raíz:
el `CLAUDE_CONFIG_DIR` está **compartido entre proyectos**, y actividad de plugins en otro repo
(StoryPlots) reescribió el registro compartido y **expulsó el marketplace local** del kit de
`known_marketplaces.json` / `installed_plugins.json`. El flag `enabled` quedó `true`; el
marketplace que lo resuelve desapareció → los agentes no se registraron al arrancar.

El problema: el fallo solo se descubre **en el momento del escalado**, y el `scope-guard.sh`
hardcodea "escalate to complex-implementer or architecture-auditor" en su mensaje de denegación
— si ese agente no está registrado, el guard manda al driver a un callejón sin salida.

**Diseño:** un check (hook `SessionStart`, o lazy en el primer disparo del scope-guard) que
verifique que los agentes nombrados del kit (`complex-implementer`, `architecture-auditor`,
`visual-polish`, `text-and-copy-editor`, `implementer`) estén realmente registrados, y **avise
fuerte** si `enabled ≠ registered` — en vez de fallar callado al escalar. Diagnóstico: revisar
`known_marketplaces.json` (¿está el marketplace?) + `installed_plugins.json` (¿el plugin, scoped
al projectPath correcto?), no solo `settings.json`.

- **Estado:** ✅ HECHO (2026-06-20). Hook **SessionStart** (`hooks/session-regcheck.sh`)
  + librería compartida (`hooks/registration-check.sh`). Es **file-based** (un hook no puede
  preguntarle a Claude Code "¿qué agentes están registrados?"): lee `known_marketplaces.json`
  (¿está el marketplace del kit?) + `installed_plugins.json` (¿el plugin, en scope user/global o
  con `projectPath` == este proyecto? — un entry de scope local/project de un repo hermano NO
  cuenta) bajo `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/`. La lista esperada de agentes se
  **deriva de `agents/*.md`** (no hardcodeada). Si `enabled ≠ registered`, avisa fuerte vía
  `additionalContext` con el fix (re-add marketplace + reinstall) y recomienda scope **user/global**.
  **Warning-once** por firma de problema (stamp `.claude/.routing-kit-regcheck`); se re-arma al
  sanarse. `commands/onboard.md` (paso 10) recomienda user/global; `USAGE.md` tiene sección
  "enabled ≠ registered" (síntoma + diagnóstico jq + fix). Tests: `registration-check.test.sh`
  (marketplace ausente → avisa; registrado → silencio).
- **Archivos:** `hooks/registration-check.sh` (nuevo), `hooks/session-regcheck.sh` (nuevo),
  `hooks/hooks.json`, `hooks/registration-check.test.sh` (nuevo), `hooks/install-smoke.test.sh`,
  `commands/onboard.md`, `USAGE.md`, `CLAUDE.template.md`.

---

## TICKET 7 — Fallback de escalado que nunca baje del tier requerido

Mismo dogfood. Cuando el agente de escalado nombrado no existe (Ticket 6), hoy el
comportamiento de hecho fue: el driver lo construyó inline. **Esta vez no dolió porque el driver
ya era Opus 4.8** — el tier exacto que `complex-implementer` mapea. Pero con el driver en
**Sonnet** (el default recomendado del propio kit, por el lever de "driver barato" de 2026-06-14),
la misma falla **degrada en silencio**: trabajo que la escalera marca Opus aterriza en Sonnet/main
sin ninguna señal. Tensión directa con el lever dominante: cuanto más barato el driver, más
depende el kit de que sus agentes de escalado estén realmente registrados.

**Diseño:** cuando un agente de escalado nombrado falta, la policy debe:
1. hacerlo en la sesión principal **solo si** el driver ya está **en o por encima** del tier
   requerido; de lo contrario
2. **parar y avisar** ("falta `complex-implementer`; subí con `/model opus` o reinstalá el plugin")
   — **nunca** degradar por debajo del tier que la escalera pide.

- **Estado:** ✅ HECHO (2026-06-20). Policy explícita en `commands/route.md` (paso 4) y
  `CLAUDE.template.md`: construir inline **solo si** el driver ya está en o por encima del tier
  requerido; si no, **parar y avisar** ("falta `complex-implementer`; subí con `/model opus` o
  reinstalá"); **nunca** degradar por debajo de lo que pide la escalera. El `scope-guard.sh`
  ahora **condiciona el mensaje de escalado al registro** (vía la librería del Ticket 6): si los
  agentes de escalado NO están registrados, el deny cambia a un mensaje SAFE FALLBACK que ordena
  STOP/subir tier en vez de mandar a `architecture-auditor` (que fallaría con "Agent type not
  found"). El chequeo está **gateado por `CLAUDE_PLUGIN_ROOT`** para que los tests de comportamiento
  (que pipean payloads crudos sin plugin root) mantengan su mensaje default determinista. El tier
  del driver se codifica como **texto de policy en el mensaje** (el modelo conoce su propio tier);
  el hook no puede leer de forma fiable el `/model` de la sesión. Tests: `registration-check.test.sh`
  cubre (b) agente ausente → no degrada / SAFE FALLBACK, y (b') registrado → mensaje normal.
- **Archivos:** `commands/route.md`, `CLAUDE.template.md`, `hooks/scope-guard.sh`,
  `hooks/registration-check.sh`, `hooks/registration-check.test.sh`.
