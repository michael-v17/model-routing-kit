# BACKLOG — model-routing-kit

Tickets pendientes, detectados durante el dogfood del plugin. Se implementan después
(no hoy). Cada uno es una mejora concreta sobre el comportamiento ya funcionando.

---

## TICKET 1 — El hook lee `RISKY` desde la config del proyecto

Hoy el patrón `RISKY` (rutas de datos/lógica que el scope-guard protege) está **hardcodeado**
en `hooks/scope-guard.sh`. Debería leerse de la configuración del proyecto (p. ej. un valor
que `/onboard` escribe en el `CLAUDE.md` o en un archivo de config), para que cada repo defina
sus propias rutas riesgosas sin editar el script del plugin.

- **Estado:** pendiente.
- **Archivos:** `hooks/scope-guard.sh`, `commands/onboard.md`.

---

## TICKET 2 — Scope por-agente (copy-editor vs visual-polish)

El scope-guard trata a `text-and-copy-editor` y `visual-polish` con el **mismo** patrón
`RISKY`. Pero sus alcances legítimos difieren: el copy-editor solo debe tocar texto/strings,
mientras visual-polish sí puede tocar CSS/markup. Hace falta un scope **diferenciado por
agente** para que cada uno tenga sus propios límites.

- **Estado:** pendiente.
- **Archivos:** `hooks/scope-guard.sh`.

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
