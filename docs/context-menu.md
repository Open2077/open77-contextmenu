# Generic context menu — open77_contextmenu

A standalone, resource-extensible ALT/click menu for any Open77 gamemode.
No Freeroam dependency and no built-in admin powers. Version **1.2.0** is a
framework for other client resources: **it intentionally supplies no gameplay
actions on its own**. Install a consumer to populate it. This standalone repository ships no consumer or demonstration actions.

## Built-in consumers, not built-in actions

`open77_contextmenu` itself has **zero default actions**, including on the sky,
on yourself, or when no consumer is installed. It never depends on Freeroam or
admin. Demo actions live only in the separately enabled example/lab resources;
leave both out of production `resources.load` lists.

The following consumers ship separately in [open77-base](https://github.com/Open2077/open77-base/tree/3e1afe421e6fc0b79bdc7516439e222ab57a34ac/resources), not this repository. They are independent integrations using the same public exports:

| Consumer | Actions |
|---|---|
| `freeroam` | Copy a network player's ID; copy a network vehicle's ID/model; open Freeroam or animations from your visible F7 body. |
| `open77_admin` | Player management, heal/revive, kick/ban with reason and confirmation; visual/full vehicle repair, lock/unlock and confirmed deletion; door ID/state, manual open/close, locks, seals and automatic mode; time/weather presets from empty sky. |

Admin entries require `command.admin` and their exact action ACL. The server
checks permissions again when executing, not just when displaying the menu.
Kick, ban and delete open the existing admin forms/confirmation screen, with
**Cancel selected by default**. Sky actions hand off to the time/weather submenus.
Permissions are sent automatically after joining and refreshed on ACL changes.

Vehicle IDs remain generation-checked Lua integers. Door engine IDs remain strings;
the native door API converts a decimal uint64 string to its exact hexadecimal ID.
Never convert an engine ID to a floating-point number or substitute the nearest door.

The admin package can cooperate with Freeroam to repair, lock or delete its
vehicles. Freeroam verifies the calling resource, the operator's live ACL, the
vehicle's resource owner, routing bucket and 20m proximity. Occupied vehicles
cannot be deleted or fully/mechanically repaired; visual repair remains available.
This does not grant ownership over another gamemode's vehicles.

Door controls use `command.admin.dev.doors.control` and the player's server-side
bucket/12m range. A door must already be discovered. Administration preserves
the original resource owner. Lift opening stays controlled by the elevator;
manual open/close is not offered for lift doors. `command.admin.dev.doors.inspect`
allows copying the ID and using the existing Developer → Doors inspector.

For large action sets, use awaited batches of up to five definitions rather than
one large registration burst: validation/copying must fit the client's per-resume
instruction budget. Re-register on consumer/context-menu restart; keep callbacks
in the consumer and retain server checks even when `canInteract` hides an entry.

## Player experience

Hold **ALT** to release the mouse from camera control. Click an entity or world
surface, your visible F7 body, or empty sky to see registered actions. Click an action to dispatch it. Releasing
the activation key, Escape, right-click, death, focus loss or target invalidation
closes the menu and restores controls. The activation key is rebindable through
Open77's existing key-binding settings.

The native weapon wheel is blocked for the lifetime of this resource, before the
first ALT press, using `Open77.input.setNativeActionBlocked("WeaponWheel", true)`.
It is released on resource stop/reload/disconnect, not after each click (which
could reopen the wheel while ALT is still held). Other resources' blocks remain
independent. This covers the native action, including its gamepad binding.
If your server deliberately uses both interfaces on different keys, set
`blockNativeWeaponWheel = false` in `shared/config.lua` and rebind the context menu.

The menu is a NativeUI document (`ui/contextmenu.rml`, driven by
`client/ui.lua`) drawn by the game's renderer. While ALT is held a reticle follows
the pointer; a click locks it on the pick (a spring), a ring and a sweep show the
target being resolved, and a glass panel opens beside it with the target's kind
(PLAYER, YOU, VEHICLE, NPC, OBJECT, DOOR, SURFACE, SKY), its distance and the
icon/label rows, which slide in staggered. Mouse hover and keyboard focus (arrows,
Home/End, Enter) share one highlighted row, whose description shows under the
list; the first row is not pre-selected. A chosen action shows a spinner, a
refused one shakes the panel with a message, and the menu fades in and out. The
panel flips left near the right edge and never leaves the screen. While idle the
document is hidden and no raycast runs. While a target menu is open, its original
ray is rechecked at a bounded rate; a moving target leaving that ray closes it.

## Install

Clone or copy this repository into `resources/system/open77_contextmenu`, with `open77.lua` at the resource root. See the [installation instructions](../README.md#installation).
Add `open77_contextmenu` to an explicit `resources.load` list, before consumers.
The resource is otherwise auto-startable. Consumers should declare:

```lua
dependency "open77_contextmenu"
```

The consumer must itself start on the client (normally `auto_start true` in its
manifest). The upstream example and test lab (not included here) ship with `auto_start false`: explicitly
enable the example's manifest when trying it on a private server. Starting only
its server runtime with `ensure` does not automatically start a client script
whose manifest still has `auto_start false`.

Requires Open77 `2.50.0+op77.219` / `2.50.0-unstable+op77.217` (protocol 1.52) or newer: a client with NativeUI (`Open77.ui`) and the [screen-picking APIs](screen-picking.md). The package refuses to activate on older clients instead
of interfering with other interfaces (use the 1.1.0 WebUI version there). Keep the
complete `client`, `shared` and `ui` directories and manifest together. Reconnect
clients after updating it.

The menu closes when ALT is released, on Escape or right-click, on death, when the
game window stays in the background for three polls, or when another interface
really takes the input lease (a NativeUI `focus`/`error` event). It does not poll a
focus flag: the 1.1.0 WebUI page lost its focus whenever a NativeUI HUD or the chat
moved the input, and the menu closed on its own while ALT was still held.

The package declares `world.query`, `input.actions`, `players.controls` and
`local.events`. A consuming resource needs only the permissions used by its own
callbacks, plus a dependency. Cross-resource arguments are copied data: closures
cannot be passed as `onSelect` or `canInteract`.

## Appearance

Edit [`shared/config.lua`](../shared/config.lua):

```lua
appearance = {
    accentColor = "#a78bfa", -- Example: purple; default Open77 cyan #18d6e7.
    scale = 1.0,
    showGroups = false,
},
```

This is the `appearance` field inside `ContextMenuConfig`, not a separate global.
`accentColor` accepts a six-digit `#RRGGBB` hex color. It controls the eye when
actions are available, the selected/hovered row accent, icons and progress spinner.
Invalid colors fall back to cyan; arbitrary CSS/URLs are not accepted.
Destructive actions keep their red warning color.

`scale` is clamped to 0.75–1.5; the default uses 32 dp action rows in a 272 dp
panel (1 dp = 1 px of the 1080p reference, so it is the same size at every
resolution). Accent and scale are applied as named stylesheet layers. Set
`showGroups = true` to show small category headings; they are hidden by default.
A description appears under the list for the focused row only.

Publish/reload the resource and reconnect clients after changing configuration.
The theme is applied on every menu open. No native client rebuild is needed.

## Register an action

Client script in your own resource:

```lua
exports("canInspectVehicle", function(context)
    return context.target.vehicleId ~= nil
end)

exports("inspectVehicle", function(context)
    -- UI data is an observation, not server authorization.
    print("Selected vehicle: " .. tostring(context.target.vehicleId))
    return true
end)

CreateThread(function()
    local promise, reason = Open77.exports.call("open77_contextmenu", "register", {
        id = "inspect_vehicle",
        label = "Inspect vehicle",
        description = "Show information about this vehicle.",
        group = "Vehicle",
        icon = "info",
        types = { "vehicle" },
        networked = true,
        distance = 4.0,
        order = 10,
        canInteract = "canInspectVehicle", -- Export in THIS resource.
        onSelect = "inspectVehicle",      -- Export in THIS resource.
    })
    if not promise then print(reason); return end
    local token, error = promise:await()
    if not token then print(error) end
end)
```

Registration captures the real invoking resource and generation. You cannot
register callbacks under someone else's identity. Registering the same `id`
again replaces your previous entry and invalidates its old token.

## Options

| Option | Contract |
|---|---|
| `id` | Required resource-local identifier, at most 64 characters. |
| `label` | Required plain text, at most 80 characters. |
| `onSelect` | Required name of a client export in the registering resource. |
| `canInteract` | Optional export name; must return exactly `true` to show/execute. |
| `description`, `group` | Optional plain text, maximum 180 / 40 characters. |
| `icon` | `interact`, `person`, `vehicle`, `info`, `lock`, `tool` or `location`. |
| `types` | Optional list: `player`, `vehicle`, `npc`, `prop`, `door`, `device`, `item`, `object`, `world`. |
| `types={"sky"}` | Explicitly opts into misses/empty space. A generic action without `types` does not match sky. |
| `records` | Optional exact record whitelist; targets without a record do not match. |
| `entities` | Optional list of exact selectors: `{playerId=7}`, `{vehicleId=12}`, `{npcId=3}`, `{propId="123"}` or `{engineEntity="123"}`. Exactly one ID per selector. Matches any selector; combines with other filters using AND. |
| `networked` | Optional boolean filter; omitted accepts both networked and local targets. |
| `distance` | Maximum player-to-impact distance, default 3 m, range 0.1–50 m. |
| `order` | Integer sorting priority, -1000 to 1000; lower first. |
| `enabled` | Defaults true. |
| `allowSelf` | Defaults false; opt in to targeting your own body. |
| `selfOnly` | Defaults false; requires `allowSelf=true` and limits the action to yourself. Prefer `registerSelf`. |
| `danger` | Defaults false; visually marks a destructive action, not an authorization check. |
| `data` | Optional copied JSON-like static metadata, available in both callbacks as `context.action.data`. Up to 4 nesting levels and a conservative 2048-byte accounting budget; no functions/cycles/non-finite numbers. |

Limits: 128 registrations total, 32 per resource, 32 entries per filter list.
Configuration defaults to a 12 m camera ray, 24 visible actions, 750 ms per
predicate wait, a 1500 ms total lookup budget and 200 ms target revalidation. Player distance and camera-ray
length are deliberately separate. Keep predicates fast, read-only and free of
network round trips.

## Callback context

Callbacks receive the latest [screen-raycast result](screen-picking.md), plus:

- `playerDistance`: distance from the local body to the hit; absent for sky.
- `screen = { x, y }`: original normalized selection coordinates.
- `kind`: normal target kind, `self` for yourself, or `sky` for a miss.
- `hasSurface`: true only for physical hits. False for sky and the F7 presentation approximation.
- `target`: entity descriptor; unowned geometry uses `{kind="world",networked=false}`;
  sky uses `{kind="sky",networked=false}`. Self keeps `target.kind="player"`,
  `target.isLocalPlayer=true` and the canonical local `playerId`.
- `action = { id, owner, token, data }`: added for both `canInteract` and `onSelect`.

For **sky**, `hit=false`: use `origin` and unit `direction` to aim. `position`
is only the ray endpoint at `maxDistance`, **not a ground point or teleport destination**.
“Sky” means no collision within the configured ray length, so distant objects or
collisionless effects can also yield this context. Distance filtering is skipped
only for explicitly sky-enabled actions; no fabricated zero distance is supplied.

For **self**, the package enables `screenRaycast(..., {self=true})`. The active,
visible F7 presentation uses animated body-slot capsules because its physical
colliders must remain disabled. `hitSource="self_presentation"` labels this
approximation; it supplies no invented normal/material. A closer physical obstacle
blocks it. Hidden/suspended F7 bodies are excluded; this is not an invisible
self hotspot in first person and is not a combat hitbox or pixel-perfect mesh test.

`onSelect` is called after the menu releases its input, so your callback can
open another interface. A false/error result is logged. The package never accepts
an event name, command, target ID or export name supplied by the UI. Only
normalized click coordinates, the current menu epoch and an opaque action token
cross this boundary; entity identity is resolved again by the native raycast.

## Exports and lifecycle

Call all exports using `Open77.exports.call(...):await()` with the dispatch error
check shown above. Do not use FiveM's `exports.resource:method()` syntax.

| Export | Result |
|---|---|
| `register(definition)` | Action token, or nil/error. |
| `registerMany(definitions)` | Dense array of tokens, or nil/error. Entire batch is atomic, even when replacing entries. |
| `registerPlayers(definitions)` | Shortcut with `types={"player"}`; self still requires `allowSelf`. |
| `registerVehicles(definitions)` | Shortcut with `types={"vehicle"}`. |
| `registerNpcs(definitions)` | Shortcut with `types={"npc"}`. |
| `registerProps(definitions)` | Shortcut with `types={"prop"}`. |
| `registerDoors(definitions)` | Shortcut with `types={"door"}`. |
| `registerWorld(definitions)` | Shortcut for physical geometry without a resolved entity. |
| `registerSky(definitions)` | Shortcut for empty-space direction actions. |
| `registerSelf(definitions)` | Shortcut for local player only (`types`, `allowSelf`, `selfOnly` set for you). |
| `registerModels(records, definitions)` | Exact record whitelist; does not guess missing records. |
| `registerEntities(selectors, definitions)` | Exact canonical or local engine-ID whitelist. |
| `update(token, patch)` | Validates a merged definition; returns a **new token**, invalidating the old token. ID cannot change; invalid patches leave the previous action intact. |
| `get(token)` | Your owned `{token, definition}` copy, or nil/error. |
| `unregister(token)` | Boolean; only your own actions. |
| `unregisterMany(tokens)` | Boolean/error; validates all ownership before removing any action. |
| `clear()` | Removes all your resource's actions. |
| `setEnabled(token, boolean)` | Enables/disables one owned action. |
| `list()` | Your actions' token, ID, label and enabled state. |
| `isOpen()` | Whether targeting/menu input is active. |
| `isReady()` | Whether the NativeUI document has loaded. |
| `getVersion()` | Framework API version string, currently `1.2.0`. |
| `getContext()` | Current selection snapshot or nil; no new raycast/predicate execution. No `action` field. |
| `getTarget()` | Current target descriptor or nil. |
| `setTargetingEnabled(boolean)` | Resource-owned disable claim. `false` closes an active menu and blocks reopening; `true` releases only your claim. |
| `isTargetingEnabled()` | True when no live resource holds a disable claim; independent of readiness/life/focus. |
| `close()` | Closes the current menu and releases its input. A fresh activation-key press is required to reopen. |

Typed/model/entity shortcuts accept **one definition → one token** or **a dense
definition array → a token array**. They override only their associated filters;
all other options, validation and quotas are shared with `register`. Duplicate IDs
inside one batch are rejected. Metadata and returned definitions are copied.
`update` replaces whole filter arrays/data fields, not individual elements. To
remove an optional field altogether, register the same ID with a new full definition.
Keep the new token returned by `update`; stale tokens deliberately stop working.

`getContext` is a local UI observation (revalidated every 200 ms), not guaranteed
fresh or authorized. Use the freshly retraced callback context for actions.
Disable claims are released on provider stop/generation change; one consumer
cannot override another consumer's disable claim.

Stopped/reloaded providers lose their registrations. Generation mismatches are
checked before display and execution. A provider should register on each start;
if the context-menu package is restarted independently, register again when its
`onClientResourceStart` event arrives. Resource manifests use reconnect reload
policy for a clean UI lifecycle.

Local informational events: `open77:contextmenu:opened()` and
`open77:contextmenu:closed(reason)` and `open77:contextmenu:selected(context)`.
The selected event means dispatch was accepted, not that the provider's operation
succeeded. These are not authorization signals. Close reasons include `selected`,
`cancelled`, `pause`, `input_released`, `target_changed`, `action_unavailable`,
`provider_closed`, `provider_disabled` and `resource_stopped`.

## Consumer recipes

Put the following in a client script of a resource with a dependency on
`open77_contextmenu`. Add `local.events` to its permissions for lifecycle handlers.

```lua
local function menu(method, ...)
    local promise, dispatchError = Open77.exports.call("open77_contextmenu", method, ...)
    if not promise then return nil, dispatchError end
    return promise:await()
end

exports("inspectMe", function(ctx)
    print("My network player ID: " .. tostring(ctx.target.playerId))
    return true
end)
exports("aimDirection", function(ctx)
    -- E.g. orient a local preview; do not teleport to ctx.position.
    print(Open77.json.encode({origin=ctx.origin, direction=ctx.direction}))
    return true
end)
exports("inspectCar", function(ctx)
    print("Vehicle " .. tostring(ctx.target.vehicleId))
    return true
end)

local function registerActions()
    local token, err = menu("registerSelf", {
        id="my_character", label="My character", icon="person", onSelect="inspectMe",
    })
    if not token then print(tostring(err)); return end
    local sky, skyError = menu("registerSky", {
        id="direction", label="Point here", icon="location", onSelect="aimDirection",
    })
    if not sky then print(tostring(skyError)) end
    local car, carError = menu("registerVehicles", {
        id="car", label="Inspect vehicle", icon="vehicle", networked=true,
        distance=4, onSelect="inspectCar", data={mode="inspect"},
    })
    if not car then print(tostring(carError)); return end
    -- Optional: patch text and keep the replacement token.
    local updated, updateError = menu("update", car, {label="Vehicle details"})
    if updated then car=updated else print(tostring(updateError)) end
end

AddEventHandler("onClientResourceStart", function(name)
    if name==GetCurrentResourceName() or name=="open77_contextmenu" then registerActions() end
end)
-- No stop handler needed for registrations; framework owns their cleanup.
```

Useful variations (call from a yielding client handler/thread, using `menu` above):

```lua
-- Your inventory/modal opens: prevent the target menu until it closes.
menu("setTargetingEnabled", false)
-- ... on inventory close:
menu("setTargetingEnabled", true)

-- Only your scripted taxi, not every vehicle. Capture the server's vehicle ID.
local taxiAction, err = menu("registerEntities", {{vehicleId=taxiId}}, {
    id="taxi_info", label="Taxi information", icon="vehicle", distance=4,
    onSelect="inspectCar",
})
-- Do not convert engineEntity/propId strings into numbers.
-- Remove your specific action, or all your actions:
if taxiAction then menu("unregister", taxiAction) else print(tostring(err)) end
menu("clear")
```

## Server-side actions

For gameplay effects, your `onSelect` sends a specific request to your own server
resource, normally only a canonical target ID and the requested operation.
Never send a caller-chosen player ID as the actor, never let the UI choose
an arbitrary server command, and never trust the client's range check.

The server handler must use its authenticated `source`, resolve the current
canonical target, check the same bucket, actor/target life and distance, apply
your permissions/ownership/cooldown rules, then perform the operation. Client
`canInteract` improves UX; it is not an ACL or anti-cheat boundary.

No built-in lock/teleport/delete handlers are shipped: each gamemode has its own
ownership and authorization model. The upstream opt-in example only prints selected target information and grants no gameplay powers; it is not included in this standalone resource.

## Limitations

Except for the explicitly supported F7 presentation, physics-less effects/props
and geometry without entity owners cannot invent a
network entity ID. Walls block picking. Targeting is a desktop mouse/keyboard
workflow, not a controller radial menu. Actions do not attach to a moving object
after selection; if it leaves the original ray, select it again.
