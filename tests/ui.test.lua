-- The NativeUI surface (client/ui.lua) against a recording fake of Open77.ui.
-- Run with Lua 5.4: lua tests/ui.test.lua <resource root>
local root = assert(arg[1])
local threads, time = {}, 0
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
local function step(ms)
    time = time + ms
    local current = threads; threads = {}
    for _, co in ipairs(current) do
        assert(coroutine.resume(co))
        if coroutine.status(co) ~= "dead" then threads[#threads + 1] = co end
    end
end

-- ---- a fake document ------------------------------------------------------------------------
local doc = { model = nil, styles = {}, classes = {}, rml = {}, sheets = {}, animations = {}, keyframes = {},
    stopped = {}, shown = nil, focus = false, listeners = {}, events = {} }
local ui = {}
function ui:show() doc.shown = true end
function ui:hide() doc.shown = false end
function ui:destroy() doc.destroyed = true end
function ui:focus() doc.focus = true; return true end
function ui:blur() doc.focus = false end
function ui:hasFocus() return doc.focus end
function ui:state() return { width = 2560, height = 1440 } end
function ui:merge(_, fields) for k, v in pairs(fields) do doc.model[k] = v end end
function ui:set(_, k, v) doc.model[k] = v end
function ui:style(sel, spec) doc.styles[sel] = doc.styles[sel] or {}; for k, v in pairs(spec) do doc.styles[sel][k] = v end end
function ui:class(sel, name, on) doc.classes[sel .. "." .. name] = on end
function ui:rml(sel, text) doc.rml[sel] = text end
function ui:stylesheet(name, text) doc.sheets[name] = text end
function ui:animate(sel) doc.animations[#doc.animations + 1] = sel end
function ui:keyframes(sel) doc.keyframes[#doc.keyframes + 1] = sel end
function ui:stop(sel) doc.stopped[#doc.stopped + 1] = sel end
function ui:scrollTo() end
function ui:on(kind, sel, fn) if fn == nil then fn, sel = sel, "" end; doc.listeners[kind .. "|" .. sel] = fn end
function ui:onEvent(kind, fn) doc.events[kind] = fn end
local function fire(kind, sel, e) return doc.listeners[kind .. "|" .. (sel or "")](e or {}) end

Open77 = { ui = { create = function(spec)
    assert(spec.document == "ui/contextmenu.rml" and spec.layer == "hud")
    doc.model = spec.models.cm
    return ui
end } }

dofile(root .. "/client/ui.lua")
local M = ContextMenuUi

-- ---- pure helpers -----------------------------------------------------------------------------
assert(M.escape('<b>"A&B"</b> {{x}}') == '&lt;b&gt;&quot;A&amp;B&quot;&lt;/b&gt; { { x } }', M.escape('<b>"A&B"</b> {{x}}'))
assert(M.safeColor("#ABCDEF") == "#abcdef" and M.safeColor("red") == M.DEFAULT_ACCENT)
assert(M.theme("#ff0000"):find("#kind { background-color: #ff0000; }", 1, true))
assert(M.scaleSheet(1) == "" and M.scaleSheet(1.5):find("#panel { width: 408.0dp; }", 1, true))
local d = M.describe({ kind = "player", playerId = 7 }, 3.25)
assert(d.kindLabel == "PLAYER" and d.title == "Player #7" and d.distance == "3.2 M", d.distance)
assert(M.describe({ kind = "player", isLocalPlayer = true }).kindLabel == "YOU")
assert(M.describe({ kind = "vehicle" }, 42.6).distance == "43 M" and M.describe({ kind = "sky" }).distance == "")
local rml, rows = M.rows({
    { token = "a", label = "Open <door>", icon = "lock", group = "World" },
    { token = "b", label = "Kick", danger = true, description = "Remove them", group = "Admin" },
    { label = "no token" },
}, true)
assert(#rows == 2 and rows[2].danger and rows[2].description == "Remove them")
assert(rml:find('id="r1"', 1, true) and rml:find('Open &lt;door&gt;', 1, true) and rml:find('class="row danger" id="r2"', 1, true))
assert(select(2, rml:gsub('class="grp"', "")) == 2)
-- right of the reticle, flipped near the right edge, never below the screen
local p = M.place(0.25, 0.4, 1920, 1080, 1, 3, 0)
assert(not p.flipped and p.left == math.floor(480 + 26 + 0.5))
p = M.place(0.95, 0.5, 1920, 1080, 1, 3, 0)
assert(p.flipped and p.left + 272 <= 1920 - 8 and p.left < 0.95 * 1920)
p = M.place(0.5, 0.99, 1920, 1080, 1, 20, 0)
assert(p.top + (66 + 384) <= 1080 - 8 + 1, p.top)

-- ---- the surface ------------------------------------------------------------------------------
local page = assert(M.create({ appearance = { accentColor = "#22d8e2", scale = 1 } }))
local got = {}
for _, name in ipairs({ "context:ready", "context:pick", "context:select", "context:cancel", "context:blur" }) do
    page:on(name, function(payload) got[#got + 1] = { name, payload } end)
end
doc.events.loaded()
assert(got[1][1] == "context:ready" and doc.shown == false and doc.sheets.accent:find("#22d8e2", 1, true))

page:send("context:open", { epoch = 4, key = "alt", appearance = { accentColor = "#22d8e2" } })
assert(doc.shown and doc.model.open and doc.model.key == "ALT")
assert(doc.styles["#reticle"].left == "1280px" and doc.styles["#reticle"].top == "720px", "the lease starts at the centre")
assert(page:setFocus(true, true) and page:hasFocus())

-- the reticle follows the pointer until a pick locks it
fire("mousemove", "#hit", { mouse_x = 100, mouse_y = 200 })
assert(doc.styles["#reticle"].left == "100px")
fire("click", "#hit", { mouse_x = 640, mouse_y = 360 })
local pick = got[#got]
assert(pick[1] == "context:pick" and pick[2].epoch == 4 and pick[2].x == 0.25 and pick[2].y == 0.25)
page:send("context:loading", { epoch = 5, x = 0.25, y = 0.25 })
assert(doc.model.locked and doc.model.loading and doc.model.panelShown)
fire("mousemove", "#hit", { mouse_x = 10, mouse_y = 10 })
assert(doc.styles["#reticle"].left == "640px", "a locked reticle stays on the pick")
assert(doc.styles["#panel"].left == math.floor(640 + 26 * 1440 / 1080 + 0.5) .. "px")

page:send("context:menu", { epoch = 5, target = { kind = "vehicle" }, distance = 4, actions = {
    { token = "t1", label = "Lock", icon = "lock", description = "Lock the doors" },
    { token = "t2", label = "Impound", danger = true },
} })
assert(not doc.model.loading and doc.model.available and doc.model.kindLabel == "VEHICLE" and doc.model.distance == "4.0 M")
assert(doc.rml["#rows"]:find('id="r2"', 1, true))
-- mouse hover and keyboard share one focus; the description follows it
fire("mouseover", ".row", { id = "r1" })
assert(doc.classes["#r1.focus"] and doc.model.desc == "Lock the doors")
fire("keydown", "", { key = "down" })
assert(doc.classes["#r2.focus"] and not doc.classes["#r1.focus"] and doc.model.desc == "")
fire("keydown", "", { key = "enter" })
assert(got[#got][1] == "context:select" and got[#got][2].token == "t2" and got[#got][2].epoch == 5)
fire("click", ".row", { id = "r1" })
assert(got[#got][2].token == "t1")
-- busy: no more picks or selections until it settles
page:send("context:busy", { epoch = 5, token = "t1" })
assert(doc.classes["#r1.pending"] and doc.classes["#r2.idle"])
local before = #got
fire("click", "#hit", { mouse_x = 1, mouse_y = 1 }); fire("click", ".row", { id = "r2" })
assert(#got == before, "busy ignores picks and selections")
page:send("context:error", { epoch = 5, message = "No longer available" })
assert(doc.model.hasError and doc.model.statusTag == "ERROR" and not doc.classes["#r1.pending"])
-- a stale epoch changes nothing
page:send("context:menu", { epoch = 3, actions = {} })
assert(doc.model.available)
-- right click and Escape cancel
fire("mousedown", "", { button = 1 }); assert(got[#got][1] == "context:cancel")
fire("keydown", "", { key = "escape" }); assert(got[#got][1] == "context:cancel")
-- the lease taken by someone else is reported
doc.events.focus("blur", { reason = "taken" }); assert(got[#got][1] == "context:blur" and got[#got][2] == "taken")
doc.events.error("focus", { message = "focus_unavailable" }); assert(got[#got][2] == "focus_unavailable")

-- close fades out, then hides; main.lua's immediate hide waits for the fade
page:setFocus(false, false)
page:send("context:close", {})
page:hide()
assert(doc.shown == true and doc.model.open == false, "the fade is still on screen")
step(150); step(150)
assert(doc.shown == false and doc.model.panelShown == false and doc.rml["#rows"] == "")
-- events after close do nothing
before = #got
fire("click", "#hit", { mouse_x = 5, mouse_y = 5 }); fire("keydown", "", { key = "escape" })
assert(#got == before)
-- reopening during a fade keeps the document up
page:send("context:open", { epoch = 9 }); page:send("context:close", {}); page:send("context:open", { epoch = 10 })
step(150); step(150)
assert(doc.shown == true and doc.model.open)
print("contextmenu ui: escaping, placement, theme, pointer, pick, rows, keyboard, busy, errors, blur and fades PASS")
