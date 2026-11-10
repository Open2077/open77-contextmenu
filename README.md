# open77_contextmenu

A compact, standalone ALT + click targeting framework for Open77.
Version **1.2.0** — **no default actions**, no Freeroam dependency and no built-in
admin powers. Other resources register their own actions through client exports.
Since 1.2.0 the menu is drawn with **NativeUI**, by the game's own renderer.

## Requirements

Use Open77 **2.50.0+op77.219** (Stable) or **2.50.0-unstable+op77.217** (Unstable),
protocol **1.52**, or a newer build: clients need NativeUI (`Open77.ui`) and the
screen-picking, self-targeting and native weapon-wheel blocking APIs. The resource
refuses to start on an older client instead of interfering with other interfaces.
For older builds, stay on the 1.1.0 tag of this repository (the WebUI menu).
Both the server and clients must use matching network protocols.
This is an Open77 Lua resource, not a FiveM/QBCore resource.

## Installation

From your server's `resources/system` directory:

```sh
git clone https://github.com/Open2077/open77-contextmenu.git open77_contextmenu
```

Keep the folder named **`open77_contextmenu`**, with `open77.lua` directly inside it.
If downloading a ZIP, rename the extracted folder accordingly. No build step,
Node dependencies or external icon/font service is needed.

Add `"open77_contextmenu"` to your existing `resources.load` list in
`server.jsonc`, before resources using it. Keep all other entries.
Reconnect clients after installation or updates.

Your consuming resource's manifest must include:

```lua
dependency "open77_contextmenu"
auto_start true
client_script "client/main.lua"
permissions { "local.events" } -- Add permissions needed by your own actions.
```

The framework alone intentionally offers **nothing to select**. Freeroam and
admin integrations live in their own resources in
[open77-base](https://github.com/Open2077/open77-base/tree/3e1afe421e6fc0b79bdc7516439e222ab57a34ac/resources),
not in this repository. No demonstration resource is installed here.

## Register an action

Put this in your **consumer's** client script, not in the framework:

```lua
exports("selectedPlayer", function(context)
    print("Player ID: " .. tostring(context.target.playerId))
    return true
end)

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() and name ~= "open77_contextmenu" then return end
    local promise, err = Open77.exports.call("open77_contextmenu", "registerPlayers", {
        id = "player_id",
        label = "Player ID",
        icon = "person",
        networked = true,
        distance = 4,
        onSelect = "selectedPlayer",
    })
    if not promise then print(tostring(err)); return end
    local token, reason = promise:await()
    if not token then print(tostring(reason)) end
end)
```

Callbacks are named exports in the registering resource. Do not pass Lua
closures between resources or use FiveM's `exports.resource:method()` syntax.
For larger integrations, register in awaited batches of up to five actions.
Registrations are resource-owned and automatically removed when their owner stops.

## Controls and appearance

Hold **ALT**, click a target, then click an action (or use the arrow keys,
Home/End and Enter). Releasing ALT, Escape, right-click, death, the game window
staying in the background or another interface really taking the input closes the
menu and restores game controls. NativeUI HUDs and the chat moving the focus no
longer close it (the 1.1.0 WebUI menu closed on its own when they did).
The activation key is rebindable in Open77's key-binding settings.

The native weapon wheel is blocked while the framework is running, so it does
not conflict with ALT. The claim is released when the resource stops. Set
`blockNativeWeaponWheel = false` if you deliberately use separate bindings.

Customize `shared/config.lua`:

```lua
appearance = {
    accentColor = "#a78bfa", -- #RRGGBB; default cyan #18d6e7.
    scale = 1.0,            -- 0.75–1.5.
    showGroups = false,
},
```

A reticle follows the pointer and locks on the pick; a ring and a sweep show the
target being resolved; a glass panel names the target's kind and distance; the
icon/label rows slide in, follow mouse hover and keyboard focus, and show the
focused action's description; a pending spinner, an error shake and fades come
with it. The panel stays on screen (flipped left near the right edge).

## Developer documentation

- [Complete exports, options, lifecycle and consumer recipes](docs/context-menu.md)
- [Native screen raycasts, cursor and weapon-wheel APIs](docs/screen-picking.md)

Typed registration covers players, vehicles, NPCs, props, doors, world surfaces,
sky directions, the visible F7 self body, records and individual entities.
Actions can be updated, enabled, removed and queried. Other interfaces can hold
resource-owned targeting-disable claims.

**Client checks are not authorization.** Gameplay requests must validate the
authenticated actor, canonical target ID, permissions, distance, life state and
routing bucket again on your server.

Sky returns a ray **direction**, not a safe teleport position. Self targeting
uses the visible F7 body's animated approximation, not a combat collider.
Read the API documentation for precise limitations.

## Development checks

The registry, controller and NativeUI surface checks run with Lua 5.4 from this
directory:

```sh
lua5.4 tests/registry.test.lua .
lua5.4 tests/controller.test.lua .
lua5.4 tests/ui.test.lua .
```

These are deterministic Lua checks against recorded fakes, not an in-game
validation.

## Source and license

Standalone snapshot of
[open77-base `a9ca7cdd`](https://github.com/Open2077/open77-base/commit/a9ca7cdd),
`resources/system/open77_contextmenu` 1.2.0 (PR #178).
Runtime files are unchanged; documentation paths are adapted for this repository.

[PolyForm Noncommercial 1.0.0](LICENSE), inherited from the source repository.
Required Notice: Copyright 2026 Nightwolf93. All rights reserved.
