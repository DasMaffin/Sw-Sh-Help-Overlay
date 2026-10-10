-- The Pokedex checklist: every species in Sword/Shield, in dex order, with a
-- ball you tick -- pkmn_stats' FRLG checklist (its 75_ui_dex.lua), for Galar.
--
-- Same gestures: the BALL toggles caught, the ROW opens the species'
-- Bulbapedia page, the wheel scrolls, hovering a row says where to find it in
-- the version being played. The filter cycles everything / still missing /
-- caught; the radios pick the dex: National (every species in the game) or
-- one of the three regional ones -- Galar, Isle of Armor, Crown Tundra -- in
-- their own order and numbers.
--
-- Opened from the mod's settings ("Pokedex checklist"); its own X writes the
-- setting back. Data: SWSH.POKEDEX (07_pokedex.lua, from the game's files).

------------------------------------------------------------------ caught --
-- Which species you have, by SWSH.DEX key, remembered across sessions.
-- Marked by "Gotcha! X was caught!" in the battle text and by clicking the
-- ball; only a click ever unmarks.
local C = {}
SWSH.caught = C
local FILE, known, loaded = "caught.txt", {}, false

local function load()
    if loaded then return end
    loaded = true
    local body = data and data.read and data.read(FILE)
    for k in (body or ""):gmatch("[^\r\n]+") do known[k] = true end
end
local function save()
    local t = {}
    for k in pairs(known) do t[#t + 1] = k end
    table.sort(t)
    if data and data.write then data.write(FILE, table.concat(t, "\n")) end
end
local function keyOf(e) return type(e) == "table" and SWSH.dexKey(e[1]) or e end

local count = 0                    -- bumped on every change: the list's stamp
function C.has(e) load() return known[keyOf(e)] == true end
function C.set(e, on, how)
    load()
    local k = keyOf(e)
    if (known[k] == true) == (on == true) then return end
    known[k] = on or nil
    count = count + 1
    save()
    local d = SWSH.DEX[k]
    SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, "[dex] ", SWSH.C.text,
             (d and d[1] or k) .. (on and " caught" or " no longer caught") .. " (" .. (how or "clicked") .. ")")
end
function C.mark(e, how) C.set(e, true, how) end
function C.toggle(e) C.set(e, not C.has(e), "clicked") end

-------------------------------------------------------------- drawing --
local function width(s, size) return #tostring(s) * size end
local rightText = function(d, xr, y, s, size, r, g, b)
    s = tostring(s)
    d:text(xr - width(s, size), y, s, size, r, g, b, 255)
end

-- A filled circle as horizontal spans (the draw API has nothing curved).
-- `col(dy)` picks each span's colour from its height off the centre.
local function disc(d, cx, cy, rad, col)
    local rows = math.max(4, math.floor(rad * 2.5))
    for i = 0, rows - 1 do
        local y0 = cy - rad + (i / rows) * 2 * rad
        local y1 = cy - rad + ((i + 1) / rows) * 2 * rad
        local dy = (y0 + y1) * 0.5 - cy
        local hw = math.abs(dy) < rad and math.sqrt(rad * rad - dy * dy) or 0
        if hw > 0 then
            local r, g, b = col(dy / rad)
            d:rect(cx - hw, y0, hw * 2, y1 - y0 + 0.5, r, g, b, 255)
        end
    end
end
local function flat(r, g, b) return function() return r, g, b end end

local function radio(d, cx, cy, rad, on, hot)
    local c = hot and 200 or 140
    disc(d, cx, cy, rad, flat(c - 10, c, c + 35))
    disc(d, cx, cy, rad * 0.66, flat(24, 27, 38))
    if on then disc(d, cx, cy, rad * 0.44, flat(150, 220, 175)) end
end

-- A Poke Ball: red over white with a dark band; greyed while not caught.
local function ball(d, x, y, size, on)
    local rad = size / 2
    local cx, cy = x + rad, y + rad
    disc(d, cx, cy, rad, flat(30, 30, 36))
    disc(d, cx, cy, rad * 0.86, function(t)
        if math.abs(t) < 0.14 then return 30, 30, 36 end
        if t < 0 then
            if on then return 225, 60, 55 end
            return 92, 92, 100
        end
        if on then return 240, 240, 244 end
        return 125, 125, 132
    end)
    disc(d, cx, cy, rad * 0.3, flat(30, 30, 36))
    disc(d, cx, cy, rad * 0.17, on and flat(240, 240, 244) or flat(125, 125, 132))
end

---------------------------------------------------------------- the list --
local U       = 6.75      -- 1080p pixels per unit, as the stats panels
local W_N     = 66        -- panel width, units
local ROW_N   = 3.0
local HEAD_N  = 13.4      -- title, dex radios, filter
local PAD_N   = 1.4
local BALL_N  = 2.2

local FILTERS = { "all", "missing", "caught" }
local SCOPES  = { "national", "galar", "armor", "crown" }
local LABEL   = { national = "National", galar = "Galar", armor = "Armor", crown = "Tundra" }
local COL     = { galar = 3, armor = 4, crown = 5 }    -- into a SWSH.POKEDEX row
local filter, scope, top = 1, "national", 1
local hoverRow, hoverKind = nil, nil

local PREF_FILE = "dexprefs.txt"
local function savePrefs()
    if data and data.write then
        data.write(PREF_FILE, scope .. "\n" .. ((overlay.getUserMode and overlay.getUserMode("swsh.dex")) or "pinned"))
    end
end
local function loadPrefs()
    local body = data and data.read and data.read(PREF_FILE)
    if not body then return end
    local sc, mode = body:match("^(%S*)%s*(%S*)")
    if LABEL[sc] then scope = sc end
    if (mode == "pinned" or mode == "menu") and overlay.setUserMode then
        overlay.setUserMode("swsh.dex", mode)
    end
end

local function active()
    return game.isActive("pkmn_sword") or game.isActive("pkmn_shield")
end
local function isOpen() return SWSH.mod:get("pokedex") == true end
local function isPinned()
    return ((overlay.getUserMode and overlay.getUserMode("swsh.dex")) or "pinned") == "pinned"
end

-- The number shown for a row: the chosen dex's.
local function number(row) return scope == "national" and row[1] or row[COL[scope]] end

-- The filtered list, rebuilt only when it can have changed. `total` and
-- `owned` count within the chosen dex.
local list, stamp, total, owned = {}, nil, 0, 0
local function rebuild()
    local now = FILTERS[filter] .. scope .. count
    if stamp == now then return list end
    stamp, list, total, owned = now, {}, 0, 0
    local rows = {}
    for _, row in ipairs(SWSH.POKEDEX or {}) do
        if number(row) > 0 then rows[#rows + 1] = row end
    end
    if scope ~= "national" then
        table.sort(rows, function(a, b) return number(a) < number(b) end)
    end
    for _, row in ipairs(rows) do
        local has = C.has(row[2])
        total = total + 1
        if has then owned = owned + 1 end
        if FILTERS[filter] == "all" or (FILTERS[filter] == "missing") ~= has then
            list[#list + 1] = row
        end
    end
    return list
end

---------------------------------------------------------- where to get it --
-- The card beside the hovered row: the version being played's places, best
-- rate first. One only the other version has in the wild says so; one no
-- wild table has says that (it's evolved, from a raid, traded or a gift).
local WHERE_MAX = 9
local function paintWhere(d, x, u, row, rowY)
    local mine  = game.isActive("pkmn_shield") and "sh" or "sw"
    local other = mine == "sh" and "sw" or "sh"
    local e = SWSH.DEX[row[2]]
    local lines = {}
    if row[mine] then
        for i = 1, math.min(#row[mine], WHERE_MAX) do
            local p = row[mine][i]
            lines[#lines + 1] = { p[1], p[2] .. "% " .. p[3], 205, 212, 232 }
        end
        if #row[mine] > WHERE_MAX then
            lines[#lines + 1] = { "+" .. (#row[mine] - WHERE_MAX) .. " more", "", 150, 158, 180 }
        end
    elseif row[other] then
        lines[1] = { "In the wild only in " .. (other == "sh" and "Shield" or "Sword"), "", 235, 190, 120 }
    else
        lines[1] = { "Not found in the wild", "", 165, 172, 195 }
        lines[2] = { "(evolve, raid, trade or gift)", "", 150, 158, 180 }
    end

    local ts = 1.6 * u
    local wMax = width(e and e[1] or row[2], 1.8 * u)
    for _, ln in ipairs(lines) do
        local lw = width(ln[1], ts) + (ln[2] ~= "" and 3.0 * u + width(ln[2], ts) or 0)
        wMax = math.max(wMax, lw)
    end
    local bw = wMax + 2.4 * u
    local bh = (3.4 + #lines * 2.2 + 0.6) * u
    local bx = x - bw - 0.8 * u
    local by = math.max(2 * u, math.min(rowY - 0.4 * u, d:h() - bh - 2 * u))
    d:rect(bx, by, bw, bh, 20, 22, 32, 244)
    d:outline(bx, by, bw, bh, 120, 130, 165, 255)
    d:text(bx + 1.2 * u, by + 0.7 * u, e and e[1] or row[2], 1.8 * u, 238, 242, 252, 255)
    local ly = by + 3.4 * u
    for _, ln in ipairs(lines) do
        d:text(bx + 1.2 * u, ly, ln[1], ts, ln[3], ln[4], ln[5], 255)
        if ln[2] ~= "" then rightText(d, bx + bw - 1.2 * u, ly, ln[2], ts, 170, 210, 180) end
        ly = ly + 2.2 * u
    end
end

-- Bulbapedia, the reference for per-Pokemon detail, through the engine's
-- browser command.
local function openWiki(e)
    if not (e and browser and browser.open) then return end
    local slug = ({ ["Nidoran-F"] = "Nidoran%E2%99%80", ["Nidoran-M"] = "Nidoran%E2%99%82" })[e[1]]
        or e[1]:gsub(" ", "_"):gsub("'", "%%27")
    browser.open("https://bulbapedia.bulbagarden.net/wiki/" .. slug .. "_(Pok%C3%A9mon)")
end

----------------------------------------------------------------- layout --
-- One layout for paint and hit-test. Against the window's right edge, full
-- height: furniture, not annotation, so sized by the window.
local function layout(screenW, screenH)
    if not screenH or screenH <= 0 then return nil end
    local u = U * screenH / SWSH.REF_H
    local W = W_N * u
    local x, y = screenW - W - 2 * u, 2 * u
    local H = screenH - 4 * u
    local rows = math.max(1, math.floor((H - (HEAD_N + 1.0) * u) / (ROW_N * u)))
    H = (HEAD_N + 1.0 + rows * ROW_N) * u
    return x, y, W, H, u, rows
end

local function clampTop(rows)
    local n = #rebuild()
    if top > n - rows + 1 then top = n - rows + 1 end
    if top < 1 then top = 1 end
end

local function closeRect(x, y, W, u) return x + W - PAD_N * u - 2.4 * u, y + 1.0 * u, 2.4 * u, 2.4 * u end
local function pinRect(x, y, W, u)   return x + W - PAD_N * u - 5.6 * u, y + 1.0 * u, 2.4 * u, 2.4 * u end
-- The dex radios, a row of their own under the title; the label is part of
-- the target.
local function scopeRect(x, y, u, which)
    local rx = x + PAD_N * u
    for _, s in ipairs(SCOPES) do
        local w = 2.0 * u + width(LABEL[s], 1.5 * u)
        if s == which then return rx, y + 5.6 * u, w, 2.2 * u end
        rx = rx + w + 2.4 * u
    end
end
local function filterRect(x, y, W, u) return x + PAD_N * u, y + 8.6 * u, W - 2 * PAD_N * u, 3.2 * u end
local function ballRectAt(x, W, u, ry) return x + W - PAD_N * u - BALL_N * u, ry - 0.1 * u, BALL_N * u, BALL_N * u end

------------------------------------------------------- remembered place --
-- Where the panel was dragged to, kept across runs (pkmn_stats'
-- 55_panelpos.lua): the engine's drag offset lives only as long as the
-- process, so the absolute position it settled at is saved and parked.
local POS_FILE, pos = "dexpos.txt", nil
do
    local body = data and data.read and data.read(POS_FILE)
    local px, py = (body or ""):match("^(-?[%d.]+)%s+(-?[%d.]+)")
    if px then pos = { x = tonumber(px), y = tonumber(py) } end
end

overlay.add("swsh.dex", {
    mode = "pinned",
    movable = true,
    OnDragEnd = function(self)
        if not (self and self.x and self.y) then return end
        pos = { x = self.x, y = self.y }
        if data and data.write then data.write(POS_FILE, string.format("%.0f %.0f", pos.x, pos.y)) end
    end,
    OnWheel = function(_, _, _, dy)
        local _, _, _, _, _, rows = layout(overlay.screenW(), overlay.screenH())
        if not rows then return end
        top = top - (dy > 0 and 3 or -3)
        clampTop(rows)
    end,
    OnMouseDown = function(self, lx, ly, btn)
        if btn ~= 1 then return end
        local bx, by, W, _, u, rows = layout(overlay.screenW(), overlay.screenH())
        if not bx then return end
        local x, y = self.x or bx, self.y or by
        local mx, my = lx + x, ly + y
        local function inside(rx, ry, rw, rh)
            return mx >= rx and mx < rx + rw and my >= ry and my < ry + rh
        end
        if inside(closeRect(x, y, W, u)) then SWSH.mod:set("pokedex", false) return end
        if inside(pinRect(x, y, W, u)) then
            if overlay.setUserMode then overlay.setUserMode("swsh.dex", isPinned() and "menu" or "pinned") end
            savePrefs()
            return
        end
        for _, which in ipairs(SCOPES) do
            if inside(scopeRect(x, y, u, which)) then
                if scope ~= which then scope, top = which, 1; savePrefs() end
                return
            end
        end
        if inside(filterRect(x, y, W, u)) then
            filter, top = filter % #FILTERS + 1, 1
            return
        end
        local i = math.floor((my - (y + HEAD_N * u)) / (ROW_N * u))
        local row = i >= 0 and i < rows and rebuild()[top + i]
        if not row then return end
        if inside(ballRectAt(x, W, u, y + HEAD_N * u + i * ROW_N * u)) then
            C.toggle(row[2])
        else
            openWiki(SWSH.DEX[row[2]])
        end
    end,
    paint = function(d, self)
        if not (active() and isOpen()) then return end
        local bx, by, W, H, u, rows = layout(d:w(), d:h())
        if not bx then return end
        self = self or {}
        local x, y = self.x or bx, self.y or by
        local shown = rebuild()
        clampTop(rows)

        -- Hover, here rather than in the hook: the engine applies the drag
        -- after the hook, so this is the first place x and y are true.
        hoverRow, hoverKind = nil, nil
        if self.hovered and overlay.mouseX then
            local mx, my = overlay.mouseX(), overlay.mouseY()
            local function inside(rx, ry, rw, rh)
                return mx >= rx and mx < rx + rw and my >= ry and my < ry + rh
            end
            if inside(closeRect(x, y, W, u)) then hoverKind = "close"
            elseif inside(pinRect(x, y, W, u)) then hoverKind = "pin"
            elseif inside(filterRect(x, y, W, u)) then hoverKind = "filter"
            else
                for _, which in ipairs(SCOPES) do
                    if inside(scopeRect(x, y, u, which)) then hoverKind = "scope:" .. which end
                end
                local i = math.floor((my - (y + HEAD_N * u)) / (ROW_N * u))
                if not hoverKind and i >= 0 and i < rows and shown[top + i] then hoverRow = top + i end
            end
        end

        d:rect(x, y, W, H, 20, 22, 32, 236)
        d:outline(x, y, W, H, 120, 130, 165, 255)
        d:rect(x, y, W, 5.0 * u, 40, 46, 64, 240)
        d:text(x + PAD_N * u, y + 1.2 * u, "POKEDEX", 2.4 * u, 238, 242, 252, 255)
        -- Caught out of everything in THAT dex, not the filtered length.
        rightText(d, x + W - PAD_N * u - 6.4 * u, y + 1.4 * u, owned .. "/" .. total, 1.7 * u, 170, 210, 180)

        -- The pin: filled while pinned (on screen with the overlay down too),
        -- hollow while it only comes up with the overlay.
        local px, py = pinRect(x, y, W, u)
        local pinned = isPinned()
        local pr, pg, pb = 150, 158, 180
        if pinned then pr, pg, pb = 170, 215, 180 end
        if hoverKind == "pin" then pr, pg, pb = math.min(255, pr + 60), math.min(255, pg + 40), math.min(255, pb + 40) end
        if pinned then d:rect(px + 0.5 * u, py + 0.4 * u, 1.4 * u, 1.0 * u, pr, pg, pb, 255)
        else d:outline(px + 0.5 * u, py + 0.4 * u, 1.4 * u, 1.0 * u, pr, pg, pb, 255) end
        d:rect(px + 1.05 * u, py + 1.4 * u, 0.3 * u, 1.0 * u, pr, pg, pb, 255)

        local cx, cy = closeRect(x, y, W, u)
        local hotX = hoverKind == "close"
        d:text(cx + 0.6 * u, cy + 0.2 * u, "X", 2.0 * u, hotX and 255 or 190, 200, hotX and 200 or 215, 255)

        for _, which in ipairs(SCOPES) do
            local rx, ry, rw, rh = scopeRect(x, y, u, which)
            local hot, on = hoverKind == "scope:" .. which, scope == which
            radio(d, rx + 0.7 * u, ry + rh / 2, 0.7 * u, on, hot)
            local c = on and 232 or (hot and 215 or 165)
            d:text(rx + 2.0 * u, ry + 0.35 * u, LABEL[which], 1.5 * u, c - 6, c, math.min(255, c + 20), 255)
        end

        local fx, fy, fw, fh = filterRect(x, y, W, u)
        local hotF = hoverKind == "filter"
        d:rect(fx, fy, fw, fh, hotF and 60 or 46, hotF and 70 or 52, hotF and 96 or 72, 255)
        d:outline(fx, fy, fw, fh, 100, 112, 145, 255)
        d:text(fx + 0.8 * u, fy + 0.5 * u, ({ all = "Showing: everything", missing = "Showing: still missing",
               caught = "Showing: caught" })[FILTERS[filter]], 1.8 * u, 220, 228, 244, 255)
        rightText(d, fx + fw - 0.8 * u, fy + 0.5 * u, #shown, 1.8 * u, 150, 162, 195)

        if #shown == 0 then
            d:text(x + PAD_N * u, y + HEAD_N * u, "Nothing to show", 1.8 * u, 150, 156, 175, 255)
            return
        end
        for i = 0, rows - 1 do
            local row = shown[top + i]
            if not row then break end
            local ry = y + HEAD_N * u + i * ROW_N * u
            local e = SWSH.DEX[row[2]]
            if hoverRow == top + i then
                d:rect(x + 0.6 * u, ry - 0.3 * u, W - 1.2 * u, ROW_N * u, 58, 66, 92, 255)
            end
            rightText(d, x + PAD_N * u + 4.4 * u, ry + 0.15 * u, string.format("%03d", number(row)), 1.6 * u, 130, 140, 168)
            d:text(x + PAD_N * u + 5.6 * u, ry, e and e[1] or row[2], 1.8 * u, 226, 232, 246, 255)
            if e then
                local tw = width(e[2], 1.5 * u)
                SWSH.typeText(d, x + W - PAD_N * u - BALL_N * u - 1.0 * u - tw, ry + 0.25 * u, e[2], 1.5 * u)
            end
            local bxx, byy, bw = ballRectAt(x, W, u, ry)
            ball(d, bxx, byy, bw, C.has(row[2]))
        end
        if #shown > rows then
            local trackX, trackY, trackH = x + W - 0.9 * u, y + HEAD_N * u, rows * ROW_N * u
            d:rect(trackX, trackY, 0.5 * u, trackH, 44, 50, 68, 255)
            local barH = math.max(1.5 * u, trackH * rows / #shown)
            local barY = trackY + (trackH - barH) * ((top - 1) / math.max(1, #shown - rows))
            d:rect(trackX, barY, 0.5 * u, barH, 120, 140, 190, 255)
        end
        if hoverRow then
            paintWhere(d, x, u, shown[hoverRow], y + HEAD_N * u + (hoverRow - top) * ROW_N * u)
        end
    end,
})

-- Park the panel's home rect (or where it was left, kept on screen); what
-- the pointer is over is decided in paint.
hook.Add("OverlayElement", "swsh.dexRegion", function(el)
    if el.id ~= "swsh.dex" then return end
    if not (active() and isOpen()) then
        el.hidden = true
        hoverRow, hoverKind = nil, nil
        return
    end
    local sw, sh = overlay.screenW(), overlay.screenH()
    local x, y, W, H = layout(sw, sh)
    if not x then el.hidden = true return end
    if pos then
        x = math.max(0, math.min(pos.x, math.max(0, sw - W)))
        y = math.max(0, math.min(pos.y, math.max(0, sh - H)))
    end
    el.x, el.y, el.w, el.h = x, y, W, H
end)

loadPrefs()
