-- The area list: what you can meet where you are, from the area the game's
-- banner last named -- pkmn_stats' FRLG route panel (its 70_ui_route.lua).
--
-- The banner ("Rolling Fields" / "Wild Area", bottom right on entering an
-- area) is read by 30_reader.lua and handed to SWSH.onArea. The list, top
-- left: each species in the version being played, coloured by its best way of
-- meeting it, its best rate, and the ball (click: caught). Hovering a row
-- opens its ways here -- how, rate, levels, the weather it needs -- and
-- where else it's met; clicking it opens its Bulbapedia page.
--
-- Data: SWSH.AREAS (08_areas.lua) and SWSH.POKEDEX (07_pokedex.lua), from the
-- game's files.

local R = { name = nil, area = nil, special = nil }   -- the banner's name, its SWSH.AREAS / SWSH.SPECIALS entries
SWSH.route = R

local FILE = "area.txt"                 -- where you were, across restarts

------------------------------------------------------------- the banner --
-- OCR slips: up to two in a short name, three in a long one; the single
-- closest only.
local function fold(s) return (s:lower():gsub("[^%w]", "")) end
local function distance(a, b)
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur, ai = { [0] = i }, a:byte(i)
        for j = 1, #b do
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ai == b:byte(j) and 0 or 1))
        end
        prev = cur
    end
    return prev[#b]
end
local function match(text)
    local k = fold(text)
    if #k < 3 then return nil end
    local max = #k >= 10 and 3 or 2
    local best, bestD, tie = nil, max + 1, false
    local seen = {}
    for _, t in ipairs({ SWSH.AREAS or {}, SWSH.SPECIALS or {} }) do
        for name in pairs(t) do
            if not seen[name] then
                seen[name] = true
                local d = distance(k, fold(name))
                if d < bestD then best, bestD, tie = name, d, false
                elseif d == bestD then tie = true end
            end
        end
    end
    return not tie and best or nil
end

local function set(name, how)
    if name == R.name then return end
    R.name, R.area, R.special = name, SWSH.AREAS[name], (SWSH.SPECIALS or {})[name]
    if data and data.write and how ~= "remembered" then data.write(FILE, name) end
    SWSH.log(SWSH.LV.dialogue, SWSH.C.system, "[area] ", SWSH.C.text,
             name .. (R.area and (" (" .. R.area.region .. ")") or (R.special and "" or " (no wild Pokemon)")))
end

-- A name counts once it's read the same twice running (the banner slides in;
-- a half-shown one reads as something else). A town with no wild Pokemon is
-- still where you are: the list says so.
local last
function SWSH.onArea(text, sub)
    if not text then last = nil return end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local name = match(text)
    if not name and text:find("%a%a%a") then name = SWSH.overlayText(text) end
    if name and name == last then set(name) end
    last = name
end

do
    local body = data and data.read and data.read(FILE)
    if body and body ~= "" then set(body:match("^[^\r\n]*"), "remembered") end
end

--------------------------------------------------------------- drawing --
local function width(s, size) return #tostring(s) * size end
local function rightText(d, xr, y, s, size, r, g, b)
    s = tostring(s)
    d:text(xr - width(s, size), y, s, size, r, g, b, 255)
end
local function wrap(str, maxc)
    local lines, cur = {}, ""
    for word in tostring(str):gmatch("%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if #try > maxc and cur ~= "" then lines[#lines + 1] = cur; cur = word else cur = try end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- How each way is shown: colour says where (green = on land, blue = water),
-- and the odder ways get a little glyph.
local METHOD = {
    ["overworld"]      = { c = { 150, 215, 170 } },
    ["grass (!)"]      = { c = { 120, 205, 130 } },
    ["surfing"]        = { c = { 110, 175, 235 }, icon = "wave" },
    ["fishing"]        = { c = { 110, 175, 235 }, icon = "rod" },
    ["Sharpedo spots"] = { c = { 110, 175, 235 }, icon = "wave" },
    ["puddles"]        = { c = { 130, 190, 230 } },
    ["beach"]          = { c = { 225, 205, 140 } },
    ["shaking trees"]  = { c = { 205, 170, 110 }, icon = "tree" },
    ["flying"]         = { c = { 180, 165, 245 } },
}
local function style(m) return METHOD[m] or { c = { 210, 214, 226 } } end

local function icon(d, kind, x, y, sz, r, g, b)
    if kind == "rod" then                 -- a bent rod with a line and hook
        d:line(x, y + sz, x + sz * 0.75, y, r, g, b, 255)
        d:line(x + sz * 0.75, y, x + sz * 0.75, y + sz * 0.55, r, g, b, 255)
        d:rect(x + sz * 0.6, y + sz * 0.55, sz * 0.3, sz * 0.18, r, g, b, 255)
    elseif kind == "wave" then            -- two little crests
        d:rect(x, y + sz * 0.35, sz * 0.45, sz * 0.16, r, g, b, 255)
        d:rect(x + sz * 0.5, y + sz * 0.2, sz * 0.45, sz * 0.16, r, g, b, 255)
        d:rect(x, y + sz * 0.7, sz * 0.95, sz * 0.16, r, g, b, 255)
    elseif kind == "tree" then            -- a crown on a trunk
        d:rect(x + sz * 0.1, y, sz * 0.8, sz * 0.6, r, g, b, 255)
        d:rect(x + sz * 0.4, y + sz * 0.6, sz * 0.2, sz * 0.4, r, g, b, 255)
    end
end

local function version() return game.isActive("pkmn_shield") and "Shield" or "Sword" end
local function ver() return game.isActive("pkmn_shield") and "sh" or "sw" end
-- A way's odds: one number, or "2-50%" when the place's parts differ (as
-- pkmn_stats' floors). Its parts, w[7], each keep their own.
local function pct(w) return (w[6] and w[6] < w[2]) and (w[6] .. "-" .. w[2] .. "%") or (w[2] .. "%") end

-- The separate part of the place a species is ONLY met in ("High Level"),
-- nil when it's met in the place itself.
local function onlyPart(e)
    local label
    for _, w in ipairs(e[3]) do
        if not w[7] then return nil end
        for _, f in ipairs(w[7]) do
            if f[1] == R.name then return nil end
            label = label or f[1]
        end
    end
    return label
end

local function lvText(w) return w[3] == w[4] and ("Lv" .. w[3]) or ("Lv" .. w[3] .. "-" .. w[4]) end

-- Everywhere else a species is met in this version (SWSH.POKEDEX's places),
-- this area's own zones left out.
local dexRow
local function elsewhere(key, max)
    if not dexRow then
        dexRow = {}
        for _, row in ipairs(SWSH.POKEDEX or {}) do dexRow[row[2]] = row end
    end
    local row, out, more = dexRow[key], {}, 0
    for _, p in ipairs(row and row[ver()] or {}) do
        local here = p[1] == R.name or p[1]:find(R.name, 1, true) == 1
                     or p[1]:find("(in " .. R.name .. ")", 1, true) or p[1]:find("(on " .. R.name .. ")", 1, true)
        if not here then
            if #out < max then out[#out + 1] = p else more = more + 1 end
        end
    end
    return out, more
end

------------------------------------------------------------------ layout --
local U       = 6.75     -- 1080p pixels per unit, as the other panels
local ROW_N   = 3.4
local LIST_N  = 50       -- panel width, units: room for "Name  High-level area"
local TOP_N   = 8.0      -- first row, under the two-line header
local RULE_N  = 1.4      -- the line between wild and special rows
local BALL_N  = 2.2
local BALL_PAD = 0.7
local MAX_ELSEWHERE = 7
local hoverRow = nil

local function visible()
    local mode = SWSH.mod:get("route_info")
    if mode == "off" or not (game.isActive("pkmn_sword") or game.isActive("pkmn_shield")) then return false end
    -- Nothing to say in a battle; out of the way of the enemy's HP panel.
    if SWSH.inBattle and SWSH.inBattle() then return false end
    if mode == "overlay only" then return overlay.isOpen and overlay.isOpen() end
    return true
end

-- One flat list of rows, so drawing and hit-testing agree.
local function layout(screenH)
    if not R.name then return nil end
    local u = U * screenH / SWSH.REF_H
    local list = R.area and R.area[ver()] or {}
    -- Gifts, trades and fixed Pokemon of this version, under a rule (as FRLG's).
    local sp = {}
    for _, e in ipairs(R.special or {}) do
        if e[6] == "" or e[6] == version() then sp[#sp + 1] = e end
    end
    local x, y = 2 * u, 2 * u
    -- A long list (the Wild Area's) runs off the bottom rather than shrinking
    -- to nothing: the longer of the two lists is cut to what fits, "+N more".
    local fit = math.floor((screenH - y - 2 * u - (TOP_N + 1.5) * u) / (ROW_N * u))
    local nw, ns = #list, #sp
    local function rowsFor(a, b) return math.max(a, 0) + (a < #list and 1 or 0) + (#list == 0 and #sp == 0 and 1 or 0)
                                       + (b > 0 and (b + RULE_N / ROW_N + (b < #sp and 1 or 0)) or 0) end
    while rowsFor(nw, ns) > fit and (nw > 0 or ns > 0) do
        if nw >= ns then nw = nw - 1 else ns = ns - 1 end
    end
    local rows, yy = {}, TOP_N
    if #list == 0 and #sp == 0 then rows[1] = { kind = "none", y = yy, h = ROW_N }; yy = yy + ROW_N end
    for i = 1, nw do rows[#rows + 1] = { kind = "wild", e = list[i], y = yy, h = ROW_N }; yy = yy + ROW_N end
    if nw < #list then rows[#rows + 1] = { kind = "more", n = #list - nw, y = yy, h = ROW_N }; yy = yy + ROW_N end
    if ns > 0 then
        rows[#rows + 1] = { kind = "rule", y = yy, h = RULE_N }; yy = yy + RULE_N
        for i = 1, ns do rows[#rows + 1] = { kind = "special", e = sp[i], y = yy, h = ROW_N }; yy = yy + ROW_N end
        if ns < #sp then rows[#rows + 1] = { kind = "more", n = #sp - ns, y = yy, h = ROW_N }; yy = yy + ROW_N end
    end
    return x, y, LIST_N * u, (yy + 1.5) * u, u, rows
end

local function rowAt(rows, y, u, my)
    for i, row in ipairs(rows) do
        local top = y + row.y * u
        if my >= top - 0.4 * u and my < top + row.h * u then return i, row end
    end
end

local function ballRect(x, y, W, u, row)
    if row.kind ~= "wild" then return nil end
    local txt = pct(row.e[3][1])
    local bx = x + W - 1.4 * u - width(txt, 1.8 * u) - BALL_PAD * u - BALL_N * u
    return bx, y + row.y * u - 0.2 * u, BALL_N * u, BALL_N * u
end

----------------------------------------------------------------- the list --
overlay.add("swsh.route", {
    mode = "pinned",
    OnMouseDown = function(self, lx, ly, btn)
        if btn ~= 1 then return end
        local x, y, W, _, u, rows = layout(overlay.screenH())
        if not rows then return end
        local mx, my = lx + (self.x or 0), ly + (self.y or 0)
        local _, row = rowAt(rows, y, u, my)
        if not row or not row.e then return end
        local bx, by, bw, bh = ballRect(x, y, W, u, row)
        if bx and mx >= bx and mx < bx + bw and my >= by and my < by + bh then
            SWSH.caught.toggle(row.e[1])
            return
        end
        if SWSH.openWiki then SWSH.openWiki(SWSH.DEX[row.e[1]]) end
    end,
    paint = function(d)
        if not visible() then return end
        local u = U * d:h() / SWSH.REF_H
        -- On but nothing known yet: say what would fix it, not an empty corner.
        if not R.name then
            local W = LIST_N * u
            d:rect(2 * u, 2 * u, W, 10.4 * u, 20, 22, 32, 232)
            d:outline(2 * u, 2 * u, W, 10.4 * u, 120, 130, 165, 255)
            d:text(3.4 * u, 3.2 * u, "No area detected", 2.0 * u, 225, 205, 150, 255)
            local ty = 6.6 * u
            for _, ln in ipairs(wrap("Walk into a new area: the name the game shows sets it.",
                                     math.floor((W - 2.8 * u) / (1.6 * u)))) do
                d:text(3.4 * u, ty, ln, 1.6 * u, 200, 206, 220, 255)
                ty = ty + 2.2 * u
            end
            return
        end
        local x, y, W, H, _, rows = layout(d:h())
        if not x then return end

        d:rect(x, y, W, H, 20, 22, 32, 232)
        d:outline(x, y, W, H, 120, 130, 165, 255)
        d:rect(x, y, W, 6.6 * u, 40, 46, 64, 240)
        -- The name gets the header's whole width (cut only past ~19 letters);
        -- under it the region and which version's table this is, so a wrong
        -- one is obvious.
        local name = R.name
        local fit = math.floor((W - 2.8 * u) / (2.2 * u))
        if #name > fit then name = name:sub(1, math.max(1, fit - 2)) .. ".." end
        d:text(x + 1.4 * u, y + 1.2 * u, name, 2.2 * u, 238, 242, 252, 255)
        d:text(x + 1.4 * u, y + 4.2 * u, R.area and R.area.region or "", 1.3 * u, 120, 132, 160, 255)
        rightText(d, x + W - 1.4 * u, y + 4.2 * u, version(), 1.3 * u, 150, 170, 205)

        for i, row in ipairs(rows) do
            local ry = y + row.y * u
            if hoverRow == i and (row.kind == "wild" or row.kind == "special") then
                d:rect(x + 0.6 * u, ry - 0.4 * u, W - 1.2 * u, row.h * u, 58, 66, 92, 255)
            end
            if row.kind == "none" then
                d:text(x + 1.4 * u, ry, "No wild Pokemon here", 1.8 * u, 150, 156, 175, 255)
            elseif row.kind == "more" then
                d:text(x + 1.4 * u, ry, "+" .. row.n .. " more", 1.6 * u, 140, 146, 165, 255)
            elseif row.kind == "rule" then
                d:line(x + 1.4 * u, ry + 0.5 * u, x + W - 1.4 * u, ry + 0.5 * u, 90, 100, 130, 255)
            elseif row.kind == "special" then
                -- Name plus a short tag (Gift / Trade / Static); the rest on hover.
                local e = row.e
                local tag = e[3] .. " Lv" .. e[5]
                local fit = math.floor((W - 2.8 * u - width(tag, 1.5 * u) - 1.0 * u) / (1.8 * u))
                local name = #e[2] > fit and (e[2]:sub(1, math.max(1, fit - 2)) .. "..") or e[2]
                d:text(x + 1.4 * u, ry, name, 1.8 * u, 215, 195, 245, 255)
                rightText(d, x + W - 1.4 * u, ry + 0.2 * u, tag, 1.5 * u, 165, 150, 200)
            else
                local top = row.e[3][1]
                local st = style(top[1])
                local c = st.c
                -- The name, and the part of the place it's only met in, stop
                -- short of the icon, ball and odds: a long one is cut.
                local bx, by, bw = ballRect(x, y, W, u, row)
                local room = bx - (st.icon and 2.8 or 0.8) * u - (x + 1.4 * u)
                local only = onlyPart(row.e)
                if only then room = room - (#only * 1.15 + 1.0) * u end
                local name, fit = row.e[2], math.floor(room / (1.8 * u))
                if #name > fit then name = name:sub(1, math.max(1, fit - 2)) .. ".." end
                d:text(x + 1.4 * u, ry, name, 1.8 * u, c[1], c[2], c[3], 255)
                if only then
                    d:text(x + 1.4 * u + #name * 1.8 * u + 1.0 * u, ry + 0.5 * u, only,
                           1.15 * u, 225, 190, 120, 255)
                end
                rightText(d, x + W - 1.4 * u, ry, pct(top), 1.8 * u, c[1], c[2], c[3])
                SWSH.drawBall(d, bx, by, bw, SWSH.caught.has(row.e[1]))
                if st.icon then icon(d, st.icon, bx - 2.4 * u, ry + 0.2 * u, 1.7 * u, c[1], c[2], c[3]) end
            end
        end
    end,
})

------------------------------------------------------------- the row detail --
overlay.add("swsh.routeinfo", {
    mode = "pinned",
    paint = function(d)
        if not hoverRow or not visible() then return end
        local x, y, W, _, u, rows = layout(d:h())
        if not x then return end
        local row = rows[hoverRow]
        if not row then return end
        local fs = 1.6 * u
        if row.kind == "special" then
            local e = row.e
            local lines = wrap(e[4], math.floor(42 / 1.6) - 2)
            local pw, ph = 44 * u, (6.6 + #lines * 2.4) * u
            local px, py = x + W + 0.8 * u, y + row.y * u - 1.0 * u
            if px + pw > d:w() then px = x - pw - 0.8 * u end
            if py + ph > d:h() then py = d:h() - ph - 2 end
            if py < 2 then py = 2 end
            d:rect(px, py, pw, ph, 18, 20, 30, 244)
            d:outline(px, py, pw, ph, 150, 165, 205, 255)
            d:text(px + 1.2 * u, py + 0.8 * u, e[2], fs, 235, 238, 248, 255)
            d:text(px + 1.2 * u, py + 3.4 * u, e[3] .. (e[6] ~= "" and (" (" .. e[6] .. " only)") or ""), fs * 0.9, 215, 195, 245, 255)
            rightText(d, px + pw - 1.2 * u, py + 3.4 * u, "Lv" .. e[5], fs * 0.9, 205, 205, 175)
            for i, ln in ipairs(lines) do
                d:text(px + 1.2 * u, py + (6.0 + (i - 1) * 2.4) * u, ln, fs * 0.9, 200, 206, 220, 255)
            end
            return
        end
        if row.kind ~= "wild" then return end
        local others, more = elsewhere(row.e[1], MAX_ELSEWHERE)

        local pw = (#others > 0 and 58 or 44) * u
        local ph = 4.2
        for _, w in ipairs(row.e[3]) do
            ph = ph + 2.8 + (w[5] ~= "" and 2.2 or 0) + (w[7] and #w[7] * 2.2 or 0)
        end
        if #others > 0 then ph = ph + 3.0 + #others * 4.4 + (more > 0 and 2.4 or 0) + 1.4 end
        ph = ph * u

        local px, py = x + W + 0.8 * u, y + row.y * u - 1.0 * u
        if px + pw > d:w() then px = x - pw - 0.8 * u end
        if py + ph > d:h() then py = d:h() - ph - 2 end
        if py < 2 then py = 2 end
        d:rect(px, py, pw, ph, 18, 20, 30, 244)
        d:outline(px, py, pw, ph, 150, 165, 205, 255)
        d:text(px + 1.2 * u, py + 0.8 * u, row.e[2], fs, 235, 238, 248, 255)

        -- One way of meeting it: icon, how, rate, levels; under it the weather
        -- it needs, then each part of the place with its own odds -- the
        -- banner can't say which part you're in, so this does.
        local ry = py + 3.9 * u
        for _, w in ipairs(row.e[3]) do
            local st = style(w[1])
            local c, ix = st.c, px + 1.2 * u
            if st.icon then icon(d, st.icon, ix, ry + 0.2 * u, fs * 0.9, c[1], c[2], c[3]); ix = ix + fs * 1.5 end
            d:text(ix, ry, w[1], fs, c[1], c[2], c[3], 255)
            rightText(d, px + pw - 14.0 * u, ry, pct(w), fs, c[1], c[2], c[3])
            rightText(d, px + pw - 1.2 * u, ry, lvText(w), fs, 205, 205, 175)
            ry = ry + 2.8 * u
            if w[5] ~= "" then
                d:text(px + 3.4 * u, ry - 0.6 * u, "weather: " .. w[5], fs * 0.9, 170, 178, 200, 255)
                ry = ry + 2.2 * u
            end
            for _, f in ipairs(w[7] or {}) do
                local own = f[1] == R.name
                local cr, cg, cb = 170, 178, 200
                if not own then cr, cg, cb = 225, 190, 120 end
                d:text(px + 3.4 * u, ry - 0.6 * u, f[1] .. (f[5] ~= "" and (" (" .. f[5] .. ")") or ""), fs * 0.9, cr, cg, cb, 255)
                rightText(d, px + pw - 14.0 * u, ry - 0.6 * u, f[2] .. "%", fs * 0.9, cr, cg, cb)
                rightText(d, px + pw - 1.2 * u, ry - 0.6 * u, lvText({ nil, nil, f[3], f[4] }), fs * 0.9, 175, 175, 155)
                ry = ry + 2.2 * u
            end
        end
        if #others > 0 then
            d:line(px + 1.2 * u, ry + 0.4 * u, px + pw - 1.2 * u, ry + 0.4 * u, 90, 100, 130, 255)
            ry = ry + 1.4 * u
            d:text(px + 1.2 * u, ry, "Also available at", fs, 150, 158, 180, 255)
            ry = ry + 2.6 * u
            -- The place, then how it's met there, indented under it.
            for _, p in ipairs(others) do
                d:text(px + 1.2 * u, ry, p[1], fs, 218, 224, 238, 255)
                ry = ry + 2.2 * u
                local how = p[3]:match("^[^,]+")
                local c = style(how).c
                d:text(px + 3.4 * u, ry, p[3], fs * 0.9, c[1], c[2], c[3], 255)
                rightText(d, px + pw - 14.0 * u, ry, p[2] .. "%", fs * 0.9, c[1], c[2], c[3])
                ry = ry + 2.2 * u
            end
            if more > 0 then d:text(px + 1.2 * u, ry, "+" .. more .. " more", fs, 140, 146, 165, 255) end
        end
    end,
})

-- Park the list's hit rect and work out which row the pointer is on.
hook.Add("OverlayElement", "swsh.routeRegion", function(el)
    if el.id ~= "swsh.route" then return end
    if not visible() then el.hidden = true; hoverRow = nil; return end
    local x, y, W, H, u, rows = layout(overlay.screenH())
    if not x then
        el.hidden = false
        el.x, el.y, el.w, el.h = 0, 0, 0, 0
        hoverRow = nil
        return
    end
    el.x, el.y, el.w, el.h = x, y, W, H
    hoverRow = nil
    if el.hovered then
        local i, row = rowAt(rows, y, u, overlay.mouseY())
        if i and (row.kind == "wild" or row.kind == "special") then hoverRow = i end
    end
end)
