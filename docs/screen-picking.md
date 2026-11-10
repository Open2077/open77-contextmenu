# Screen picking and cursor utilities

Client-only helpers for pointing at the 3D world from a 2D interface. These APIs
are available in Open77 `2.31.13+op77.63` (protocol 1.26) or a compatible newer
build. The previously published `.62` client does not contain them.

For a ready-made ALT/click interface, use [open77_contextmenu](context-menu.md).

## Coordinates and permissions

Coordinates are **normalized viewport coordinates**: `(0,0)` is top-left,
`(1,1)` bottom-right and `(.5,.5)` the centre. Do not pass desktop pixels,
CEF backing-texture pixels or engine NDC coordinates. Browser `clientX/innerWidth`
and `clientY/innerHeight` follow this convention on a fullscreen surface.

`Open77.camera.screenRay` and `screenRaycast` require `world.query`.
`Open77.input.cursor` requires `input.actions`. These queries do not exist on
the dedicated server. They return `nil, reason` when unavailable or invalid.

## Screen2DPointTo3DSpace / screenRay

```lua
local ray, reason = Open77.camera.screenRay(0.5, 0.5, 25)
-- Identical global alias:
local sameRay = Screen2DPointTo3DSpace(0.5, 0.5, 25)
```

Returns `{ origin={x,y,z}, direction={x,y,z}, position={x,y,z}, maxDistance }`.
The origin is the active camera, direction is a unit world-space vector, and
position is the point `origin + direction * maxDistance`. This is **not a hit**:
unprojecting a pixel defines a ray, not a unique surface position.

Distance defaults to 100 metres and must be finite, within `[0.1,1000]`.
Both screen coordinates must be finite numbers within `[0,1]`. Strings are not
coerced. The native projection is checked against the unprojected ray; inconsistent
camera state returns `camera_projection_mismatch` rather than a guessed direction.

## screenRaycast

```lua
local hit, reason = Open77.camera.screenRaycast(0.5, 0.5, 12, {
    static = true, dynamic = true, self = true -- Optional visible F7 body picking.
})
if not hit then print(reason); return end
if not hit.hit then return end
print(hit.position.x, hit.distance, hit.material)
if hit.target then
    print(hit.target.kind, hit.target.engineEntity, hit.target.vehicleId)
end
```

Uses the same arguments as `screenRay`, plus optional boolean collision filters.
Both filters default to true; at least one must remain enabled. It selects the
nearest blocking physical hit, not the nearest object to the cursor. Static,
dynamic, terrain, collider, destructible, vehicle and NPC-hitbox categories are
included; the two options restrict actor mobility, not the target's Lua kind.
Query-only player sensors are excluded.

`self` is a third strict boolean, **false by default**. With `self=true` and
`dynamic=true`, the active visible F7 body is also tested using capsules around
its native animated body slots. This presentation object intentionally has no
physical colliders. A closer physical hit wins; hidden/suspended proxies are
excluded. No colliders, actor movement, animation or gameplay state are changed.
This is a local UI picking approximation, not mesh-perfect selection, combat
collision or a hidden first-person self button. It requires the client with
context-menu 1.1.0 support, beyond the first screen-query implementation.

All ray fields remain present. A miss has `hit=false` and `position` at the
maximum distance. A hit additionally returns:

| Field | Meaning |
|---|---|
| `position`, `normal` | World-space impact and normal. |
| `distance` | Camera-to-impact distance in metres. |
| `material` | Engine material name, possibly empty. |
| `entityLookupAvailable` | Whether the native physics-owner resolver is available. |
| `target` | Entity descriptor, or nil for geometry without an entity owner. |
| `hitSource` | `self_presentation` for an opt-in F7 visual hit; absent for ordinary physics. |

An F7 visual hit has `hit=true`, distance, position and target, but **no physical
normal or material**. Its `target.kind` is `player`, `isLocalPlayer=true`, and
`playerId` is the current local network player. Use the canonical player ID for
resource requests, not the F7 proxy's ephemeral engine handle.

The descriptor contains `engineEntity` as a **decimal string**, `className`,
`kind` and `networked`. Supported classifications include player, vehicle, NPC,
prop, door, device, item and object. Recognized network entities additionally
carry the corresponding `playerId`, `vehicleId`, `npcId` or `propId`.
`propId` is a **decimal string**, matching the props API; the other canonical IDs
are Lua integers. An NPC's `record`, when available, is its actual `Character.*`
record, not the virtual template label.
`entity`, when present, is an Open77 **local** registry handle encoded as a string.
Names/records are optional; `isLocalPlayer=true` identifies the local body,
including its F7 presentation proxy when hit.

Do not interchange these identifiers. Engine and registry IDs refer to this
client's streamed incarnation, not a portable network target. Keep their strings
intact through JavaScript; converting a 64-bit ID to `Number` can corrupt it.

Static world geometry can legitimately have no entity. Visual effects and props
without physics collision (apart from the explicit F7 option) are not promised as pickable targets. There is no
nearest-neighbour fallback, no through-wall selection and no authority granted
by a successful client raycast.

## Cursor and WebUI/NativeUI focus

```lua
local cursor, reason = Open77.input.cursor()
-- { x, y, pixelX, pixelY, width, height, inBounds, captured }
if cursor and cursor.inBounds then
    local hit = Open77.camera.screenRaycast(cursor.x, cursor.y, 12)
end

page:show()
page:setFocus(true, true) -- Keyboard + cursor; game input blocked by default.
local ownsFocus = page:hasFocus()
page:setFocus(false, false)
page:hide()
```

`cursor()` samples the actual foreground game window, not an arbitrary desktop
window. It returns `nil, game_not_focused` after Alt+Tab; coordinates can be outside
`[0,1]` if the pointer is outside the client area (`inBounds=false`). It does not
show or capture the cursor itself. Use a resource-owned WebUI surface for that.
`captured` is true if a WebUI already owns keyboard **or cursor** input; check
it before opening a new modal so cursor-only interfaces are not interrupted.
WebUI has a virtual pointer: for an exact click on its fullscreen page, pass
`event.clientX / innerWidth` and `event.clientY / innerHeight` from that click,
instead of sampling the OS cursor after the message arrives.
A NativeUI document's input lease has its own pointer too (it starts at the centre
of the screen): use the click event's `mouse_x` / `mouse_y` divided by
`ui:state().width` / `height`, as `open77_contextmenu` 1.2.0 does.

`page:hasFocus()` reads current keyboard/cursor ownership and presentation state.
It does not steal focus, and is false when another surface owns input. Releasing
focus on your page must not release another page's focus. Surface teardown
automatically releases its capture.

## Disable the native weapon wheel

```lua
-- Client, permission: input.actions. Reserve before ALT is pressed.
local ok, reason = Open77.input.setNativeActionBlocked("WeaponWheel", true)
-- Release only this resource's claim when your feature is disabled:
Open77.input.setNativeActionBlocked("WeaponWheel", false)
```

The native weapon-wheel state cannot enter while blocked. An already-open wheel
takes its normal cancellation/cleanup path, without selecting an item. Claims
from several resources compose: releasing yours never overrides another owner.
The host releases claims on stop, reload and disconnect. `OpenMapMenu` is also
supported; unknown names return `false, "unsupported_native_action"`.
This blocks the native action, including rebound keys and gamepad, not a physical
ALT key or every weapon command. `SwitchItem` and other radial menus are unchanged.
Combine it with a focused WebUI to consume gameplay input during your own menu.

## Cost and trust

Trace on a click or at a bounded rate while interacting. Do not scan the entire
world each frame. These are synchronous game-thread queries, not a server physics
engine. Server effects must validate authenticated source, canonical IDs, bucket,
distance, life state, cooldown and gameplay permissions independently.

Common errors: `permission_denied:world.query`, `permission_denied:input.actions`,
`screen_query_unavailable_on_this_host`, `invalid_screen_coordinates_or_distance`,
`invalid_collision_options`, `camera_unavailable`, `camera_projection_mismatch`,
`game_not_focused`, `cursor_unavailable`, `viewport_unavailable`.
