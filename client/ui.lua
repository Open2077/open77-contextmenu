-- The ALT context menu on NativeUI (ui/contextmenu.rml).
--
-- client/main.lua keeps every decision (targeting, predicates, revalidation, input
-- claims) and talks to this module through the page API it used with the WebUI page:
-- page:on(event, fn), page:send(event, payload), show, hide, setFocus, hasFocus,
-- destroy. Events this surface raises: context:ready, context:pick {epoch,x,y},
-- context:select {epoch,token}, context:cancel {epoch} and context:blur (reason),
-- the last when the input lease is taken away or refused.
--
-- Why a native document: the WebUI page lost its focus whenever another surface
-- moved the input (a NativeUI HUD or chat taking the keyboard), and the menu closed
-- on its own. The NativeUI lease cannot be taken by another document; only a WebUI
-- page that really opens takes it, and then closing is the right answer.
ContextMenuUi = {}
local M = ContextMenuUi

M.DEFAULT_ACCENT = "#18d6e7"
M.PANEL_WIDTH = 272   -- dp, keep in step with #panel in contextmenu.rcss
M.ROW_HEIGHT = 34     -- dp, a row and its margins
M.GROUP_HEIGHT = 24   -- dp
M.CHROME_HEIGHT = 66  -- dp: header, sweep, list padding, foot
M.MAX_LIST = 384      -- dp, #rows max-height

-- Local vector glyphs (24 x 24): no icon font, no remote asset, no provider markup.
M.ICONS = {
    interact = "M8 12V5a2 2 0 0 1 4 0v6 M12 9h3l4 4v4l-3 4h-5l-6-7a2 2 0 0 1 3-2Z",
    person = "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z M4 21v-3a8 8 0 0 1 16 0v3",
    vehicle = "M4 10l2-6h12l2 6 M3 10h18v8H3Z M5 18v3 M19 18v3 M6 14h2 M16 14h2",
    info = "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z M12 11v6 M12 7v.2",
    lock = "M6 10V7a6 6 0 0 1 12 0v3 M4 10h16v11H4Z M12 14v3",
    tool = "M14 3a6 6 0 0 0-6 8l-6 6 5 5 6-6a6 6 0 0 0 8-7l-4 4-5-5 4-4Z",
    location = "M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z M15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z",
}

local KIND_LABELS = {
    player = "Player", self = "You", vehicle = "Vehicle", npc = "NPC", prop = "Object",
    door = "Door", world = "Surface", sky = "Sky",
}
local KIND_TITLES = {
    player = "Player", self = "Your character", vehicle = "Vehicle", npc = "Character", prop = "Object",
    door = "Door", world = "Surface", sky = "Direction",
}

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

--- Text safe to place inside RML: markup escaped, and no "{{" a data model would evaluate.
function M.escape(value)
    local text = tostring(value == nil and "" or value)
    text = text:gsub("[%c]", " ")
    text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
    text = text:gsub("{", "{ "):gsub("}", " }")
    return text
end

function M.safeColor(value)
    local text = tostring(value or "")
    return text:match("^#%x%x%x%x%x%x$") and text:lower() or M.DEFAULT_ACCENT
end

--- The accent as a stylesheet layer over contextmenu.rcss (every rule that uses it).
function M.theme(color)
    local c = M.safeColor(color)
    return table.concat({
        "#stage.available .br { border-color: " .. c .. "; }",
        ".ring-shape { stroke: " .. c .. "; }",
        "#stage.available #dot { background-color: " .. c .. "; }",
        "#panel { border-color: " .. c .. "; }",
        "#kind { background-color: " .. c .. "; }",
        "#sweep-bar { background-color: " .. c .. "; filter: glow(4dp " .. c .. " 1); }",
        "#rows scrollbarvertical sliderbar { background-color: " .. c .. "99; }",
        ".row .spin { stroke: " .. c .. "; }",
        ".row .go { border-color: " .. c .. "; }",
        ".row.focus { background-color: " .. c .. "2e; border-color: " .. c .. "; }",
        ".row.focus .ic path { stroke: " .. c .. "; }",
        "#hint-key { background-color: " .. c .. "; }",
    }, "\n")
end

--- What the header names: the target's kind and a title.
function M.describe(target, distance)
    target = type(target) == "table" and target or {}
    local kind = target.isLocalPlayer and "self" or tostring(target.kind or "world")
    local title = KIND_TITLES[kind] or "Target"
    if kind == "player" then
        if type(target.name) == "string" and target.name ~= "" then title = target.name
        elseif tonumber(target.playerId) then title = "Player #" .. math.floor(tonumber(target.playerId)) end
    elseif type(target.name) == "string" and target.name ~= "" then
        title = target.name
    end
    local dist = ""
    local d = tonumber(distance)
    if d and d == d and d >= 0 then dist = (d < 10 and ("%.1f M"):format(d) or ("%d M"):format(math.floor(d + 0.5))) end
    return {
        kindLabel = (KIND_LABELS[kind] or kind):upper(),
        title = title:sub(1, 40),
        distance = dist,
    }
end

--- The action list as RML: groups (optional), then rows r1..rN. Returns the RML and
--- the rows as { token, description, danger } in display order.
function M.rows(actions, showGroups)
    local out, rows, group = {}, {}, nil
    for _, action in ipairs(type(actions) == "table" and actions or {}) do
        if type(action) == "table" and action.token ~= nil then
            if showGroups and action.group ~= group then
                group = action.group
                if group ~= nil and tostring(group) ~= "" then
                    out[#out + 1] = '<div class="grp"><span>' .. M.escape(group) .. '</span></div>'
                end
            end
            local i = #rows + 1
            rows[i] = {
                token = action.token,
                description = action.description and tostring(action.description):sub(1, 160) or "",
                danger = action.danger == true,
            }
            local icon = M.ICONS[action.icon] or M.ICONS.interact
            out[#out + 1] = ('<div class="row%s" id="r%d"><div class="ic"><path view-box="0 0 24 24" d="%s"/>'
                .. '<shape type="circle" class="spin"/></div><span class="lb">%s</span><div class="go"></div></div>')
                :format(action.danger and " danger" or "", i, icon, M.escape(action.label))
        end
    end
    return table.concat(out), rows
end

--- Where the panel goes for a pick at (ax, ay), fractions of a W x H screen: to the
--- right of the reticle, or to its left when it would leave the screen, and never
--- below the bottom edge. Pixels, for the top-left corner of the (scaled) panel.
function M.place(ax, ay, width, height, scale, rowCount, groupCount)
    local r = math.max(0.5, height / 1080) * scale
    local w = M.PANEL_WIDTH * r
    local list = math.min(M.MAX_LIST, (rowCount or 0) * M.ROW_HEIGHT + (groupCount or 0) * M.GROUP_HEIGHT)
    local h = (M.CHROME_HEIGHT + math.max(list, 40)) * r
    local x, y = ax * width, ay * height
    local gap, margin = 26 * r, 8
    local left = x + gap
    local flipped = left + w > width - margin
    if flipped then left = x - gap - w end
    left = clamp(left, margin, math.max(margin, width - w - margin))
    local top = clamp(y - 16 * r, margin, math.max(margin, height - h - margin))
    return { left = math.floor(left + 0.5), top = math.floor(top + 0.5), flipped = flipped }
end

--- Sizes for a configured scale (0.75 to 1.5): a stylesheet layer, so the motion
--- channels (scale, x, opacity) stay free for the animations.
function M.scaleSheet(scale)
    local k = clamp(tonumber(scale) or 1, 0.75, 1.5)
    if math.abs(k - 1) < 0.01 then return "" end
    local function dp(v) return ("%.1fdp"):format(v * k) end
    return table.concat({
        "#panel { width: " .. dp(M.PANEL_WIDTH) .. "; }",
        "#head, #kind { height: " .. dp(32) .. "; }",
        "#kind span { font-size: " .. dp(10) .. "; line-height: " .. dp(32) .. "; }",
        "#title span { font-size: " .. dp(12) .. "; }",
        "#dist span, #status-text { font-size: " .. dp(11) .. "; }",
        "#rows { max-height: " .. dp(M.MAX_LIST) .. "; }",
        ".row { height: " .. dp(32) .. "; }",
        ".row .lb { font-size: " .. dp(12.5) .. "; }",
        ".row .ic, .row .ic path { width: " .. dp(18) .. "; height: " .. dp(18) .. "; }",
        ".grp span { font-size: " .. dp(9) .. "; }",
        "#desc span { font-size: " .. dp(11) .. "; line-height: " .. dp(15) .. "; }",
    }, "\n")
end

local function defaults()
    return {
        open = false, locked = false, loading = false, available = false, keyboard = false,
        left = false, up = false, panelShown = false, empty = false, hasError = false, busy = false,
        kindLabel = "", title = "", distance = "", status = "", statusTag = "", desc = "",
        key = "ALT", hint = "Hold - click a target - right click or Esc to close",
    }
end

--- A surface with the page API client/main.lua uses.
function M.create(config)
    if type(Open77) ~= "table" or type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then
        return nil, "nativeui_unavailable"
    end
    local appearance = type(config) == "table" and type(config.appearance) == "table" and config.appearance or {}
    local ui, why = Open77.ui.create({
        document = "ui/contextmenu.rml", layer = "hud", zIndex = 60, visible = true,
        models = { cm = defaults() },
    })
    if not ui then return nil, why end

    local page = { handlers = {} }
    local S = {
        opened = false, epoch = 0, busy = false, shown = false, rows = {}, focus = nil,
        accent = nil, scale = 1, showGroups = false, generation = 0, width = nil, height = nil,
        locked = false, anchor = nil, flipped = false, fading = false, scaleApplied = nil,
    }
    local alive = true

    local function emit(name, payload)
        local fn = page.handlers[name]
        if fn then fn(payload) end
    end
    local function screen()
        local ok, state = pcall(ui.state, ui)
        if ok and type(state) == "table" and tonumber(state.width) and tonumber(state.width) > 0 then
            S.width, S.height = tonumber(state.width), tonumber(state.height)
        elseif not S.width and type(Open77.input) == "table" and type(Open77.input.cursor) == "function" then
            local c = Open77.input.cursor()
            if type(c) == "table" and tonumber(c.width) then S.width, S.height = tonumber(c.width), tonumber(c.height) end
        end
        return S.width or 1920, S.height or 1080
    end
    local function applyAppearance(value)
        value = type(value) == "table" and value or {}
        local accent = M.safeColor(value.accentColor)
        if accent ~= S.accent then
            S.accent = accent
            ui:stylesheet("accent", M.theme(accent))
        end
        local scale = clamp(tonumber(value.scale) or 1, 0.75, 1.5)
        if scale ~= S.scale or S.scaleApplied == nil then
            S.scale, S.scaleApplied = scale, true
            ui:stylesheet("scale", M.scaleSheet(scale))
        end
        S.showGroups = value.showGroups == true
    end

    -- ---- focus, rows ---------------------------------------------------------------------
    local function setRowFocus(index, keyboard)
        if index == S.focus then return end
        if S.focus then ui:class("#r" .. S.focus, "focus", false) end
        S.focus = index
        if index then
            ui:class("#r" .. index, "focus", true)
            if keyboard then ui:scrollTo("#r" .. index, "nearest", true) end
        end
        ui:merge("cm", { desc = index and S.rows[index] and S.rows[index].description or "", keyboard = keyboard == true })
    end
    local function moveFocus(step, absolute)
        local n = #S.rows
        if n == 0 or S.busy then return end
        local index
        if absolute == "first" then index = 1
        elseif absolute == "last" then index = n
        elseif not S.focus then index = step < 0 and n or 1
        else index = (S.focus - 1 + step) % n + 1 end
        setRowFocus(index, true)
    end
    local function choose(index)
        local row = index and S.rows[index]
        if not S.opened or S.busy or not row then return end
        emit("context:select", { epoch = S.epoch, token = row.token })
    end

    -- ---- the panel -------------------------------------------------------------------------
    local function placePanel(rowCount, groupCount, animate)
        if not S.anchor then return end
        local w, h = screen()
        local p = M.place(S.anchor.x, S.anchor.y, w, h, S.scale, rowCount, groupCount)
        local flippedChanged = p.flipped ~= S.flipped
        S.flipped = p.flipped
        ui:style("#panel", { left = p.left .. "px", top = p.top .. "px" })
        ui:set("cm", "left", p.flipped)
        if animate then
            local dx = p.flipped and 14 or -14
            ui:animate("#panel", { from = { opacity = 0, x = dx, scale = 0.96 }, to = { opacity = 1, x = 0, scale = 1 },
                spring = { duration = 0.32, bounce = 0.18 } })
        elseif flippedChanged then
            ui:animate("#panel", { from = { opacity = 0.4 }, to = { opacity = 1 }, preset = "snappy" })
        end
    end
    local function lockReticle(px, py)
        S.locked = true
        ui:style("#reticle", { left = px .. "px", top = py .. "px" })
        ui:animate("#reticle", { from = { scale = 1.55, opacity = 0.6 }, to = { scale = 1, opacity = 1 },
            spring = { duration = 0.36, bounce = 0.35 } })
    end
    local function startLoading()
        ui:merge("cm", { loading = true })
        ui:keyframes("#ring", { channel = "rotate", stops = { { offset = 0, value = 0 }, { offset = 1, value = 360 } },
            duration = 0.9, iterations = -1 })
        ui:keyframes("#sweep-bar", { channel = "x", stops = { { offset = 0, value = -100 }, { offset = 1, value = M.PANEL_WIDTH } },
            duration = 0.85, iterations = -1 })
    end
    local function stopLoading()
        ui:merge("cm", { loading = false })
        ui:stop("#ring")
        ui:stop("#sweep-bar")
    end
    local function clearRows()
        S.rows, S.focus, S.busy = {}, nil, false
        ui:rml("#rows", "")
        ui:merge("cm", { desc = "", busy = false, hasError = false, empty = false, available = false })
    end

    -- ---- page API --------------------------------------------------------------------------
    function page.on(_, name, fn) page.handlers[name] = fn end
    function page.show() ui:show(); return true end
    -- a close fades out first (context:close hides the document when it is done)
    function page.hide() if not S.fading then ui:hide() end; return true end
    function page.hasFocus() return ui:hasFocus() == true end
    function page.setFocus(_, keyboard, cursor)
        if keyboard or cursor then
            local ok = ui:focus({ keyboard = true, cursor = true })
            return ok ~= false and ok ~= nil
        end
        ui:blur()
        return true
    end
    function page.destroy()
        alive = false
        pcall(ui.destroy, ui)
    end

    function page.send(_, name, p)
        p = type(p) == "table" and p or {}
        if name == "context:open" then
            S.generation = S.generation + 1
            S.fading = false
            S.opened, S.epoch, S.locked, S.anchor, S.flipped = true, tonumber(p.epoch) or 0, false, nil, false
            applyAppearance(p.appearance)
            clearRows()
            stopLoading()
            local key = tostring(p.key or "ALT"):upper():sub(1, 12)
            ui:merge("cm", { open = true, locked = false, panelShown = false, key = key,
                hint = "Hold - click a target - right click or Esc to close", status = "", statusTag = "",
                kindLabel = "", title = "", distance = "" })
            ui:show()
            local w, h = screen()
            -- the lease puts the pointer at the centre of the screen
            ui:style("#reticle", { left = math.floor(w / 2) .. "px", top = math.floor(h / 2) .. "px" })
            ui:animate("#reticle", { from = { opacity = 0, scale = 1.7, rotate = -45 }, to = { opacity = 1, scale = 1, rotate = 0 },
                spring = { duration = 0.4, bounce = 0.28 } })
            ui:animate("#hintbar", { from = { opacity = 0, y = 16 }, to = { opacity = 1, y = 0 }, spring = { duration = 0.35, bounce = 0.2 } })
        elseif name == "context:close" then
            if not S.opened then return end
            S.opened, S.busy = false, false
            stopLoading()
            ui:merge("cm", { open = false })
            ui:animate("#reticle", { to = { opacity = 0, scale = 0.7 }, duration = 0.12, easing = "ease-in" })
            ui:animate("#hintbar", { to = { opacity = 0, y = 10 }, duration = 0.12, easing = "ease-in" })
            if S.shown then ui:animate("#panel", { to = { opacity = 0, scale = 0.97 }, duration = 0.12, easing = "ease-in" }) end
            local generation = S.generation
            S.fading = true
            CreateThread(function()
                Wait(150)
                if alive and generation == S.generation and not S.opened then
                    S.fading = false
                    S.shown = false
                    ui:merge("cm", { panelShown = false, locked = false })
                    clearRows()
                    ui:hide()
                end
            end)
        elseif name == "context:loading" then
            if not S.opened or (tonumber(p.epoch) or -1) < S.epoch then return end
            S.epoch = tonumber(p.epoch)
            local x, y = clamp(tonumber(p.x) or 0.5, 0, 1), clamp(tonumber(p.y) or 0.5, 0, 1)
            S.anchor = { x = x, y = y }
            local w, h = screen()
            lockReticle(math.floor(x * w + 0.5), math.floor(y * h + 0.5))
            clearRows()
            ui:merge("cm", { locked = true, panelShown = true, kindLabel = "Scan", title = "Looking",
                distance = "", statusTag = "SCAN", status = "Resolving the target..." })
            local first = not S.shown
            S.shown = true
            placePanel(0, 0, first)
            startLoading()
        elseif name == "context:empty" then
            if not S.opened or p.epoch ~= S.epoch then return end
            stopLoading()
            ui:merge("cm", { empty = true, kindLabel = "None", title = "No target",
                statusTag = "EMPTY", status = tostring(p.message or "Click another object or surface."):sub(1, 120) })
            ui:animate("#reticle", { from = { scale = 0.85 }, to = { scale = 1 }, spring = { duration = 0.3, bounce = 0.5 } })
        elseif name == "context:menu" then
            if not S.opened or p.epoch ~= S.epoch then return end
            stopLoading()
            local rml, rows = M.rows(p.actions, S.showGroups)
            S.rows, S.focus, S.busy = rows, nil, false
            local groups = 0
            if S.showGroups then for _ in rml:gmatch('class="grp"') do groups = groups + 1 end end
            local head = M.describe(p.target, p.distance)
            local any = #rows > 0
            ui:merge("cm", { kindLabel = head.kindLabel, title = head.title, distance = head.distance,
                available = any, empty = not any, hasError = false, busy = false, desc = "",
                statusTag = any and "" or "NONE", status = any and "" or "Nothing to do with this target." })
            ui:rml("#rows", rml)
            placePanel(#rows, groups, false)
            if any then
                ui:animate("#rows .row", { from = { opacity = 0, x = -10 }, to = { opacity = 1, x = 0 },
                    spring = { duration = 0.3, bounce = 0.16 }, stagger = 0.028 })
                ui:animate("#reticle", { from = { scale = 1.18 }, to = { scale = 1 }, spring = { duration = 0.32, bounce = 0.45 } })
            end
        elseif name == "context:busy" then
            if not S.opened or p.epoch ~= S.epoch then return end
            S.busy = true
            ui:set("cm", "busy", true)
            for i, row in ipairs(S.rows) do
                if row.token == p.token then
                    ui:class("#r" .. i, "pending", true)
                    ui:keyframes("#r" .. i .. " .spin", { channel = "rotate",
                        stops = { { offset = 0, value = 0 }, { offset = 1, value = 360 } }, duration = 0.7, iterations = -1 })
                else
                    ui:class("#r" .. i, "idle", true)
                end
            end
        elseif name == "context:error" then
            if not S.opened or p.epoch ~= S.epoch then return end
            S.busy = false
            for i in ipairs(S.rows) do
                ui:class("#r" .. i, "pending", false)
                ui:class("#r" .. i, "idle", false)
                ui:stop("#r" .. i .. " .spin")
            end
            ui:merge("cm", { busy = false, hasError = true, statusTag = "ERROR",
                status = tostring(p.message or "Action unavailable."):sub(1, 120) })
            ui:keyframes("#panel", { channel = "x", stops = {
                { offset = 0, value = 0 }, { offset = 0.2, value = -7 }, { offset = 0.4, value = 6 },
                { offset = 0.6, value = -4 }, { offset = 0.8, value = 2 }, { offset = 1, value = 0 } }, duration = 0.34 })
        end
    end

    -- ---- input -----------------------------------------------------------------------------
    local function mouse(e)
        local x, y = tonumber(e and e.mouse_x), tonumber(e and e.mouse_y)
        if not x or not y then return nil end
        return x, y
    end
    ui:on("mousemove", "#hit", function(e)
        if not S.opened or S.locked then return end
        local x, y = mouse(e)
        if x then ui:style("#reticle", { left = math.floor(x) .. "px", top = math.floor(y) .. "px" }) end
    end)
    ui:on("click", "#hit", function(e)
        if not S.opened or S.busy then return end
        local x, y = mouse(e)
        if not x then return end
        local w, h = screen()
        local nx, ny = x / w, y / h
        if nx ~= nx or ny ~= ny or nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
        emit("context:pick", { epoch = S.epoch, x = nx, y = ny })
    end)
    ui:on("mousedown", function(e)
        if S.opened and tonumber(e and e.button) == 1 then emit("context:cancel", { epoch = S.epoch }) end
    end)
    ui:on("mouseover", ".row", function(e)
        if not S.opened or S.busy then return end
        local index = tonumber(tostring(e.id or ""):match("^r(%d+)$"))
        if index then setRowFocus(index, false) end
    end)
    ui:on("click", ".row", function(e)
        local index = tonumber(tostring(e.id or ""):match("^r(%d+)$"))
        if index then choose(index) end
    end)
    ui:on("keydown", function(e)
        if not S.opened then return end
        local key = tostring(e.key or "")
        if key == "escape" then emit("context:cancel", { epoch = S.epoch })
        elseif key == "down" then moveFocus(1)
        elseif key == "up" then moveFocus(-1)
        elseif key == "home" then moveFocus(0, "first")
        elseif key == "end" then moveFocus(0, "last")
        elseif key == "enter" or key == "space" then choose(S.focus) end
    end)

    -- ---- lifecycle -------------------------------------------------------------------------
    local function ready()
        S.accent, S.scaleApplied = nil, nil
        applyAppearance(appearance)
        ui:hide()
        emit("context:ready")
    end
    ui:onEvent("loaded", ready)
    ui:onEvent("reloaded", function()
        S.accent, S.scaleApplied = nil, nil
        applyAppearance(appearance)
        if S.opened then emit("context:blur", "reloaded") else ui:hide() end
    end)
    ui:onEvent("focus", function(kind, detail)
        if kind == "blur" and S.opened then emit("context:blur", detail and detail.reason or "blur") end
    end)
    ui:onEvent("error", function(kind, detail)
        local message = tostring(detail and detail.message or "")
        if kind == "focus" then
            if S.opened then emit("context:blur", message ~= "" and message or "focus_unavailable") end
            return
        end
        print("[contextmenu] UI " .. tostring(kind) .. ": " .. message)
    end)
    return page
end
