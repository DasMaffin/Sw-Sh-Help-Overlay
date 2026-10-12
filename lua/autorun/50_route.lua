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
    R.changed = true                     -- the list starts at its top again
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

-- Which rows show: everything, still missing, caught (as the Pokedex
-- panel); the button top right cycles it, kept across runs.
local FILTERS = { "all", "missing", "caught" }
local FLABEL  = { all = "All", missing = "Missing", caught = "Caught" }
local FILTER_FILE = "routefilter.txt"
local filter = 1
do
    local body = data and data.read and data.read(FILTER_FILE)
    for i, f in ipairs(FILTERS) do if body and body:match("^%a+") == f then filter = i end end
end
local function keep(key)
    local f = FILTERS[filter]
    if f == "all" then return true end
    return (SWSH.caught.has(key) and true or false) == (f == "caught")
end

-- The list scrolls (the wheel over it) when it's taller than the screen.
local scroll = 0

local function visible()
    local mode = SWSH.mod:get("route_info")
    if mode == "off" or not (game.isActive("pkmn_sword") or game.isActive("pkmn_shield")) then return false end
    -- Nothing to say in a battle; out of the way of the enemy's HP panel.
    if SWSH.inBattle and SWSH.inBattle() then return false end
    if SWSH.hideForMenu and SWSH.hideForMenu() then return false end   -- a game menu is up
    if mode == "overlay only" then return overlay.isOpen and overlay.isOpen() end
    return true
end

-- What a way surely needs and you surely lack (48_progress), or nil: the
-- Fishing Rod, Water Mode, or the badges to catch at its lowest level (key
-- "b<N>"). Those leave the list for a "Requires ..." group; a part of a place
-- you may not reach yet (a high-level area) can't be told, so reaching it
-- isn't -- only catching it is.
local REQUIRES = { ["Fishing Rod"] = "Requires Fishing Rod", ["Water Mode"] = "Requires Water Mode" }
local REQ_LONG = { ["Fishing Rod"] = "Requires the Fishing Rod", ["Water Mode"] = "Requires the bike's Water Mode" }
local function reqLabel(need, long)
    local n = tonumber(need:match("^b(%d+)$"))
    if n then return "Requires " .. n .. (n == 1 and " Badge" or " Badges") .. (long and " to catch" or "") end
    return (long and REQ_LONG or REQUIRES)[need]
end
local function reqRank(need) return need == "Fishing Rod" and 0 or need == "Water Mode" and 1 or 10 + tonumber(need:sub(2)) end
local function lacks(how, lo)
    local P = SWSH.progress
    if not P then return nil end
    if how == "fishing" and not P.hasRod() then return "Fishing Rod" end
    if (how == "surfing" or how == "Sharpedo spots") and not P.hasWater() then return "Water Mode" end
    if lo and lo > P.cap() then return "b" .. P.needs(lo) end
end

-- One flat list of rows, so drawing and hit-testing agree: { x, y, W, H, u,
-- rows (those on screen), btn (the filter button), scroll, maxScroll, n }.
local function layout(screenH)
    if not R.name then return nil end
    local u = U * screenH / SWSH.REF_H
    local x, y, W = 2 * u, 2 * u, LIST_N * u
    -- Each species split: the ways open to you stay in the list, the rest go
    -- under what they need -- one met both ways is in both.
    local wild, groups, order = {}, {}, {}
    for _, e in ipairs(R.area and R.area[ver()] or {}) do
        if keep(e[1]) then
            local open, shut = {}, {}
            for _, w in ipairs(e[3]) do
                local need = lacks(w[1], w[3])
                if need then
                    shut[need] = shut[need] or {}
                    table.insert(shut[need], w)
                else
                    open[#open + 1] = w
                end
            end
            if #open > 0 then wild[#wild + 1] = { e[1], e[2], open } end
            for need, ws in pairs(shut) do
                if not groups[need] then groups[need] = {}; order[#order + 1] = need end
                table.insert(groups[need], { e[1], e[2], ws })
            end
        end
    end
    -- Gifts, trades and fixed Pokemon of this version, under a rule (as FRLG's);
    -- a fixed one above your catch cap joins its badge group.
    local sp = {}
    for _, e in ipairs(R.special or {}) do
        if (e[6] == "" or e[6] == version()) and keep(e[1]) then
            local need = e[3] == "Static" and lacks(nil, e[5])
            if need then
                if not groups[need] then groups[need] = {}; order[#order + 1] = need end
                table.insert(groups[need], { e[1], e[2], { { "fixed (" .. e[3]:lower() .. ")", nil, e[5], e[5] } }, static = true })
            else
                sp[#sp + 1] = e
            end
        end
    end
    table.sort(order, function(a, b) return reqRank(a) < reqRank(b) end)

    local all = {}
    for _, e in ipairs(wild) do all[#all + 1] = { kind = "wild", e = e, h = ROW_N } end
    for _, need in ipairs(order) do
        all[#all + 1] = { kind = "req", label = reqLabel(need), long = reqLabel(need, true), list = groups[need], h = ROW_N }
    end
    if #sp > 0 then
        if #all > 0 then all[#all + 1] = { kind = "rule", h = RULE_N } end
        for _, e in ipairs(sp) do all[#all + 1] = { kind = "special", e = e, h = ROW_N } end
    end
    if #all == 0 then
        local nothing = not (R.area and #R.area[ver()] > 0) and #(R.special or {}) == 0
        all[1] = { kind = "none", h = ROW_N,
                   text = nothing and "No wild Pokemon here"
                          or (FILTERS[filter] == "missing" and "Nothing missing here" or "Nothing caught here yet") }
    end

    -- What fits under the header; past that it scrolls, a row at a time.
    local room = (screenH - y - 2 * u) / u - TOP_N - 1.5
    local total = 0
    for _, r in ipairs(all) do total = total + r.h end
    local maxScroll, rest = 0, total
    while rest > room and maxScroll < #all - 1 do maxScroll = maxScroll + 1; rest = rest - all[maxScroll].h end
    if R.changed then scroll, R.changed = 0, nil end
    scroll = math.max(0, math.min(scroll, maxScroll))
    local rows, yy = {}, TOP_N
    for i = scroll + 1, #all do
        local r = all[i]
        if yy + r.h - TOP_N > room + 0.01 then break end
        r.y = yy
        rows[#rows + 1] = r
        yy = yy + r.h
    end
    local bw = width("Missing", 1.4 * u) + 1.6 * u
    return { x = x, y = y, W = W, H = (yy + 1.5) * u, u = u, rows = rows,
             btn = { x + W - 1.0 * u - bw, y + 0.9 * u, bw, 2.6 * u },
             scroll = scroll, maxScroll = maxScroll, n = #all }
end

local function rowAt(rows, y, u, my)
    for i, row in ipairs(rows) do
        local top = y + row.y * u
        if my >= top - 0.4 * u and my < top + row.h * u then return i, row end
    end
end

-- Why a way isn't open to you yet (48_progress: the badges for its level --
-- rod and Water Mode ways are in their own group), or nil.
local function blocked(w) return SWSH.progress and SWSH.progress.blocked(w[1], w[3]) end
local function rowBlocked(row)
    if not SWSH.progress then return false end
    if row.kind == "special" then
        return row.e[3] == "Static" and SWSH.progress.blocked(nil, row.e[5]) ~= nil
    end
    for _, w in ipairs(row.e[3]) do if not blocked(w) then return false end end
    return true
end
-- Dimmed: nothing about it is open to you yet.
local function dim(c, off) if off then return { c[1] * 0.45, c[2] * 0.45, c[3] * 0.5 } end return c end

local function specialTag(e) return e[3] .. " Lv" .. e[5] end

local function ballRect(L, row)
    local x, y, W, u = L.x, L.y, L.W, L.u
    local bx
    if row.kind == "wild" then
        bx = x + W - 1.4 * u - width(pct(row.e[3][1]), 1.8 * u) - BALL_PAD * u - BALL_N * u
    elseif row.kind == "special" then        -- one column, left of the widest tag ("Static Lv100")
        bx = x + W - 1.4 * u - width("Static Lv100", 1.5 * u) - BALL_PAD * u - BALL_N * u
    else
        return nil
    end
    return bx, y + row.y * u - 0.2 * u, BALL_N * u, BALL_N * u
end

local function inside(r, mx, my) return mx >= r[1] and mx < r[1] + r[3] and my >= r[2] and my < r[2] + r[4] end

----------------------------------------------------------------- the list --
overlay.add("swsh.route", {
    mode = "pinned",
    OnWheel = function(_, _, _, dy)
        local L = layout(overlay.screenH())
        if not L or L.maxScroll == 0 then return end
        scroll = math.max(0, math.min(L.maxScroll, scroll - (dy > 0 and 3 or -3)))
    end,
    OnMouseDown = function(self, lx, ly, btn)
        if btn ~= 1 then return end
        local L = layout(overlay.screenH())
        if not L then return end
        local mx, my = lx + (self.x or 0), ly + (self.y or 0)
        if inside(L.btn, mx, my) then
            filter, scroll = filter % #FILTERS + 1, 0
            if data and data.write then data.write(FILTER_FILE, FILTERS[filter]) end
            return
        end
        local _, row = rowAt(L.rows, L.y, L.u, my)
        if not row or not row.e then return end
        local bx, by, bw, bh = ballRect(L, row)
        if bx and inside({ bx, by, bw, bh }, mx, my) then
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
        local L = layout(d:h())
        if not L then return end
        local x, y, W, H, rows = L.x, L.y, L.W, L.H, L.rows

        d:rect(x, y, W, H, 20, 22, 32, 232)
        d:outline(x, y, W, H, 120, 130, 165, 255)
        d:rect(x, y, W, 6.6 * u, 40, 46, 64, 240)
        -- The name gets the header's width up to the filter button; under it
        -- the region and which version's table this is, so a wrong one is
        -- obvious.
        local b = L.btn
        local name = R.name
        local fit = math.floor((b[1] - 0.8 * u - (x + 1.4 * u)) / (2.2 * u))
        if #name > fit then name = name:sub(1, math.max(1, fit - 2)) .. ".." end
        d:text(x + 1.4 * u, y + 1.2 * u, name, 2.2 * u, 238, 242, 252, 255)
        d:text(x + 1.4 * u, y + 4.2 * u, R.area and R.area.region or "", 1.3 * u, 120, 132, 160, 255)
        rightText(d, x + W - 1.4 * u, y + 4.2 * u, version(), 1.3 * u, 150, 170, 205)
        -- The filter: a small button saying what's shown (amber when it hides some).
        local hotB = overlay.mouseX and inside(b, overlay.mouseX(), overlay.mouseY())
        local on = FILTERS[filter] ~= "all"
        d:rect(b[1], b[2], b[3], b[4], hotB and 70 or 52, hotB and 80 or 58, hotB and 110 or 80, 255)
        d:outline(b[1], b[2], b[3], b[4], on and 225 or 100, on and 190 or 112, on and 120 or 145, 255)
        local lbl = FLABEL[FILTERS[filter]]
        d:text(b[1] + (b[3] - width(lbl, 1.4 * u)) / 2, b[2] + 0.6 * u, lbl, 1.4 * u,
               on and 235 or 200, on and 205 or 206, on and 140 or 222, 255)

        for i, row in ipairs(rows) do
            local ry = y + row.y * u
            if hoverRow == i and (row.kind == "wild" or row.kind == "special" or row.kind == "req") then
                d:rect(x + 0.6 * u, ry - 0.4 * u, W - 1.2 * u, row.h * u, 58, 66, 92, 255)
            end
            if row.kind == "none" then
                d:text(x + 1.4 * u, ry, row.text, 1.8 * u, 150, 156, 175, 255)
            elseif row.kind == "rule" then
                d:line(x + 1.4 * u, ry + 0.5 * u, x + W - 1.4 * u, ry + 0.5 * u, 90, 100, 130, 255)
            elseif row.kind == "req" then
                -- What you can't meet yet: one line, the Pokemon on hover.
                d:text(x + 1.4 * u, ry, row.label, 1.8 * u, 200, 165, 105, 255)
                rightText(d, x + W - 1.4 * u, ry + 0.2 * u, "(" .. #row.list .. ")", 1.5 * u, 160, 140, 110)
            elseif row.kind == "special" then
                -- Name plus a short tag (Gift / Trade / Static); the rest on hover.
                local e = row.e
                local bx, by, bw = ballRect(L, row)
                local fit = math.floor((bx - 0.8 * u - (x + 1.4 * u)) / (1.8 * u))
                local name = #e[2] > fit and (e[2]:sub(1, math.max(1, fit - 2)) .. "..") or e[2]
                local c1, c2 = dim({ 215, 195, 245 }, rowBlocked(row)), dim({ 165, 150, 200 }, rowBlocked(row))
                d:text(x + 1.4 * u, ry, name, 1.8 * u, c1[1], c1[2], c1[3], 255)
                rightText(d, x + W - 1.4 * u, ry + 0.2 * u, specialTag(e), 1.5 * u, c2[1], c2[2], c2[3])
                SWSH.drawBall(d, bx, by, bw, SWSH.caught.has(e[1]))
            else
                local top = row.e[3][1]
                local st = style(top[1])
                local c = dim(st.c, rowBlocked(row))
                -- The name, and the part of the place it's only met in, stop
                -- short of the icon, ball and odds: a long one is cut.
                local bx, by, bw = ballRect(L, row)
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
        -- A scroll bar on the right edge when the list doesn't fit.
        if L.maxScroll > 0 then
            local tx, ty, th = x + W - 0.75 * u, y + (TOP_N - 0.4) * u, H - (TOP_N + 0.6) * u
            d:rect(tx, ty, 0.45 * u, th, 44, 50, 68, 255)
            local bh = math.max(1.5 * u, th * #rows / L.n)
            d:rect(tx, ty + (th - bh) * (L.scroll / L.maxScroll), 0.45 * u, bh, 120, 140, 190, 255)
        end
    end,
})

------------------------------------------------------------- the row detail --
local function card(d, L, row, pw, ph)
    local u = L.u
    local px, py = L.x + L.W + 0.8 * u, L.y + row.y * u - 1.0 * u
    if px + pw > d:w() then px = L.x - pw - 0.8 * u end
    if py + ph > d:h() then py = d:h() - ph - 2 end
    if py < 2 then py = 2 end
    d:rect(px, py, pw, ph, 18, 20, 30, 244)
    d:outline(px, py, pw, ph, 150, 165, 205, 255)
    return px, py
end

overlay.add("swsh.routeinfo", {
    mode = "pinned",
    paint = function(d)
        if not hoverRow or not visible() then return end
        local L = layout(d:h())
        if not L then return end
        local u = L.u
        local row = L.rows[hoverRow]
        if not row then return end
        local fs = 1.6 * u
        if row.kind == "req" then
            -- The Pokemon that need it: each with its way, odds and levels.
            local pw = 52 * u
            local hint = wrap((row.long:find("Badge") and "Have them already? Tick them" or "Have it already? Tick it")
                              .. " in the progress editor (the mod's settings).",
                              math.floor((pw - 2.4 * u) / (fs * 0.85)))
            local ph = (4.4 + #row.list * 2.4 + 0.6 + #hint * 2.0) * u
            local px, py = card(d, L, row, pw, ph)
            d:text(px + 1.2 * u, py + 0.8 * u, row.long, fs, 225, 190, 120, 255)
            local ry = py + 3.8 * u
            for _, e in ipairs(row.list) do
                local w = e[3][1]
                local st = style(w[1])
                local c = st.c
                d:text(px + 1.2 * u, ry, e[2], fs * 0.95, 218, 224, 238, 255)
                d:text(px + 19.0 * u, ry, w[1], fs * 0.9, c[1], c[2], c[3], 255)
                if not e.static then rightText(d, px + pw - 13.0 * u, ry, pct(w), fs * 0.9, c[1], c[2], c[3]) end
                rightText(d, px + pw - 1.2 * u, ry, lvText(w), fs * 0.9, 205, 205, 175)
                ry = ry + 2.4 * u
            end
            for i, ln in ipairs(hint) do
                d:text(px + 1.2 * u, ry + (0.4 + (i - 1) * 2.0) * u, ln, fs * 0.85, 140, 146, 165, 255)
            end
            return
        end
        if row.kind == "special" then
            local e = row.e
            local why = e[3] == "Static" and SWSH.progress and SWSH.progress.blocked(nil, e[5])
            local lines = wrap(e[4] .. (why and (" " .. why:gsub("^n", "N") .. ".") or ""), 29)
            local pw, ph = 44 * u, (6.6 + #lines * 2.4) * u
            local px, py = card(d, L, row, pw, ph)
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
            ph = ph + 2.8 + (w[5] ~= "" and 2.2 or 0) + (w[7] and #w[7] * 2.2 or 0) + (blocked(w) and 2.2 or 0)
        end
        if #others > 0 then ph = ph + 3.0 + #others * 4.4 + (more > 0 and 2.4 or 0) + 1.4 end
        ph = ph * u

        local px, py = card(d, L, row, pw, ph)
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
            local why = blocked(w)
            if why then
                d:text(px + 3.4 * u, ry - 0.6 * u, why, fs * 0.9, 235, 130, 120, 255)
                ry = ry + 2.2 * u
            end
            if w[5] ~= "" then
                d:text(px + 3.4 * u, ry - 0.6 * u, "weather: " .. w[5], fs * 0.9, 170, 178, 200, 255)
                ry = ry + 2.2 * u
            end
            for _, f in ipairs(w[7] or {}) do
                local own = f[1] == R.name
                local cr, cg, cb = 170, 178, 200
                if not own then cr, cg, cb = 225, 190, 120 end
                -- A part above your catch cap: dimmed (the line above says why).
                if SWSH.progress and f[3] > SWSH.progress.cap() then cr, cg, cb = cr * 0.5, cg * 0.5, cb * 0.5 end
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
    local L = layout(overlay.screenH())
    if not L then
        el.hidden = false
        el.x, el.y, el.w, el.h = 0, 0, 0, 0
        hoverRow = nil
        return
    end
    el.x, el.y, el.w, el.h = L.x, L.y, L.W, L.H
    hoverRow = nil
    if el.hovered then
        local i, row = rowAt(L.rows, L.y, L.u, overlay.mouseY())
        if i and (row.kind == "wild" or row.kind == "special" or row.kind == "req") then hoverRow = i end
    end
end)
