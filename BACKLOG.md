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
3. **`/onboard` añade `.claude/routing-log.jsonl` al `.gitignore`** del proyecto destino.

Nota: la mitad *costo* (tokens/cuota por tier) NO es auto-capturable — `/usage` es interactivo;
el review pide pegarlo a mano. Depende del Ticket 1 (RISKY desde config) para no re-forkear el hook.

- **Estado:** pendiente (prototipo validado en tecnologiasvm).
- **Archivos:** `hooks/scope-guard.sh`, `commands/route-review.md` (nuevo), `commands/onboard.md`.

---

## TICKET 5 — Knob de tier por tarea (`/run-at`) + intermedios + log de elección manual

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

**Opcional encima:** 1-2 agentes nombrados para los combos intermedios que se repitan (p.ej.
un `implementer` en opus/medium o sonnet/high), pero el knob genérico ataca la raíz.

- **Estado:** pendiente (depende del dispatch de `/route` y del ledger del Ticket 4).
- **Archivos:** `commands/run-at.md` (nuevo), `hooks/scope-guard.sh` o el comando (log manual),
  `USAGE.md`, `CLAUDE.template.md`.
