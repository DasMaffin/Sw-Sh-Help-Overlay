-- The evolutions panel: every Pokemon you can still get by evolving one you
-- have caught (45_dex's marks) -- level, stone, trade, held item, friendship,
-- whatever the game wants, in its words from SWSH.EVOS (09_evolutions.lua,
-- the game's own evolution table). Further steps count too: with Charmander
-- caught and Charmeleon not, Charizard is listed "via Charmeleon".
--
-- Opened by the setting "Evolutions you can get"; its X turns it off. Wheel
-- scrolls, a click opens the Bulbapedia page, the ball marks it caught (and
-- so takes it off the list).

SWSH = SWSH or {}

local U      = 6.75      -- 1080p pixels per unit, as the other panels
local W_N    = 76
local HEAD_N = 7.4
local LINE_N = 2.0       -- one line of a row's "how"
local top    = 1         -- first row shown

local function width(s, size) return #tostring(s) * size end
local function wrap(str, maxc)
    local lines, cur = {}, ""
    for word in tostring(str):gmatch("%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if #try > maxc and cur ~= "" then lines[#lines + 1] = cur; cur = word else cur = try end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

local function active() return game.isActive("pkmn_sword") or game.isActive("pkmn_shield") end
local function isOpen()
    return SWSH.mod:get("evolutions") == true and active() and not (SWSH.hideForMenu and SWSH.hideForMenu())
end
local function version() return game.isActive("pkmn_shield") and "Shield" or "Sword" end

-- { from = "Charmander", to = "Charizard", toKey, how = "via Charmeleon: ..." },
-- each Pokemon you don't have once, from the closest one you do.
local function build()
    local owned = SWSH.caught.has
    local byFrom, order = {}, {}
    for _, e in ipairs(SWSH.EVOS or {}) do
        if e[6] == "" or e[6] == version() then
            if not byFrom[e[1]] then byFrom[e[1]] = {}; order[#order + 1] = e[1] end
            table.insert(byFrom[e[1]], e)
        end
    end
    local best, list = {}, {}
    for _, k in ipairs(order) do
        if owned(k) then
            -- Walk on through what you don't have yet: each step's how kept.
            local queue = { { key = k, path = {} } }
            local seen = { [k] = true }
            while #queue > 0 do
                local cur = table.remove(queue, 1)
                for _, e in ipairs(byFrom[cur.key] or {}) do
                    if not owned(e[3]) then
                        local path = {}
                        for i, p in ipairs(cur.path) do path[i] = p end
                        path[#path + 1] = e
                        local b = best[e[4]]
                        if not b or #path < #b.path then
                            if not b then b = {}; best[e[4]] = b; list[#list + 1] = b end
                            b.path, b.to, b.toKey = path, e[4], e[3]
                        end
                        if not seen[e[3]] then
                            seen[e[3]] = true
                            queue[#queue + 1] = { key = e[3], path = path }
                        end
                    end
                end
            end
        end
    end
    for _, b in ipairs(list) do
        local p = b.path
        b.from = p[1][2]
        if #p == 1 then
            b.how = p[1][5]
        else
            local via, steps = {}, {}
            for i, e in ipairs(p) do
                steps[i] = e[5]
                if i < #p then via[#via + 1] = e[4] end
            end
            b.how = "via " .. table.concat(via, ", ") .. ": " .. table.concat(steps, ", then ")
        end
    end
    return list
end

-- Rows with their heights (the how wraps), and what fits from `top`.
local function layout(sw, sh)
    local u = U * sh / SWSH.REF_H
    local W = W_N * u
    local x, y = (sw - W) / 2, 2 * u
    local maxH = sh - 4 * u
    local list = build()
    local maxc = math.floor((W - 2.8 * u - 4.0 * u) / (1.4 * u))
    for _, r in ipairs(list) do
        r.lines = wrap(r.how, maxc)
        r.h = 2.6 + #r.lines * LINE_N + 0.8
    end
    -- The last top that still fills the panel.
    local room, sum, last = maxH / u - HEAD_N - 1.0, 0, #list
    for i = #list, 1, -1 do
        sum = sum + list[i].h
        if sum > room then break end
        last = i
    end
    top = math.max(1, math.min(top, math.max(1, last)))
    local rows, yy = {}, HEAD_N
    for i = top, #list do
        local r = list[i]
        if yy + r.h - HEAD_N > room then break end
        r.y = yy
        rows[#rows + 1] = r
        yy = yy + r.h
    end
    local H = math.max(yy, HEAD_N + 3.2) + 1.0
    return { x = x, y = y, W = W, H = H * u, u = u, rows = rows, n = #list, last = last,
             close = { x + W - 3.8 * u, y + 1.0 * u, 2.4 * u, 2.4 * u } }
end

local function hit(r, mx, my) return mx >= r[1] and mx < r[1] + r[3] and my >= r[2] and my < r[2] + r[4] end
local function ballRect(L, r) return { L.x + L.W - 1.4 * L.u - 2.2 * L.u, L.y + (r.y - 0.1) * L.u, 2.2 * L.u, 2.2 * L.u } end
local function rowAt(L, my)
    for _, r in ipairs(L.rows) do
        local ry = L.y + r.y * L.u
        if my >= ry - 0.4 * L.u and my < ry + (r.h - 0.4) * L.u then return r end
    end
end

overlay.add("swsh.evos", {
    mode = "pinned",
    OnWheel = function(_, _, _, dy)
        if not isOpen() then return end
        top = math.max(1, top - (dy > 0 and 2 or -2))
    end,
    OnMouseDown = function(self, lx, ly, btn)
        if btn ~= 1 or not isOpen() then return end
        local L = layout(overlay.screenW(), overlay.screenH())
        local mx, my = lx + (self.x or 0), ly + (self.y or 0)
        if hit(L.close, mx, my) then SWSH.mod:set("evolutions", false) return end
        local r = rowAt(L, my)
        if not r then return end
        if hit(ballRect(L, r), mx, my) then SWSH.caught.toggle(r.toKey) return end
        if SWSH.openWiki then SWSH.openWiki(SWSH.DEX[r.toKey]) end
    end,
    paint = function(d)
        if not isOpen() then return end
        local L = layout(d:w(), d:h())
        local x, y, W, H, u = L.x, L.y, L.W, L.H, L.u
        local mx, my = overlay.mouseX and overlay.mouseX() or -1, overlay.mouseY and overlay.mouseY() or -1
        d:rect(x, y, W, H, 20, 22, 32, 236)
        d:outline(x, y, W, H, 120, 130, 165, 255)
        d:rect(x, y, W, 6.0 * u, 40, 46, 64, 240)
        d:text(x + 1.4 * u, y + 1.0 * u, "Evolutions you can get", 2.2 * u, 238, 242, 252, 255)
        d:text(x + 1.4 * u, y + 3.9 * u, L.n .. " from the Pokemon you've caught", 1.3 * u, 150, 160, 190, 255)
        local hotX = hit(L.close, mx, my)
        d:text(L.close[1] + 0.6 * u, L.close[2] + 0.2 * u, "X", 2.0 * u, hotX and 255 or 190, 200, hotX and 200 or 215, 255)

        if L.n == 0 then
            d:text(x + 1.4 * u, y + HEAD_N * u, "Nothing yet: mark what you've caught.", 1.6 * u, 150, 156, 175, 255)
            return
        end
        local over = hit({ x, y, W, H }, mx, my) and rowAt(L, my)
        for _, r in ipairs(L.rows) do
            local ry = y + r.y * u
            if over == r then d:rect(x + 0.6 * u, ry - 0.4 * u, W - 1.2 * u, (r.h - 0.2) * u, 58, 66, 92, 255) end
            -- "From > To" up to the ball; a long From is cut, never the To.
            local fit = math.floor((W - 2.8 * u - 3.2 * u - 3.4 * u) / (1.8 * u)) - #r.to
            local from = #r.from > fit and (r.from:sub(1, math.max(1, fit - 2)) .. "..") or r.from
            d:text(x + 1.4 * u, ry, from, 1.8 * u, 190, 198, 220, 255)
            local ax = x + 1.4 * u + width(from, 1.8 * u) + 0.8 * u
            d:text(ax, ry, ">", 1.8 * u, 150, 160, 190, 255)
            d:text(ax + 2.6 * u, ry, r.to, 1.8 * u, 238, 242, 252, 255)
            for i, ln in ipairs(r.lines) do
                d:text(x + 3.4 * u, ry + (2.6 + (i - 1) * LINE_N) * u, ln, 1.4 * u, 150, 200, 175, 255)
            end
            local b = ballRect(L, r)
            SWSH.drawBall(d, b[1], b[2], b[3], SWSH.caught.has(r.toKey))
        end
        -- A scroll bar when it doesn't all fit.
        if L.last > 1 then
            local tx, ty, th = x + W - 0.75 * u, y + (HEAD_N - 0.4) * u, H - (HEAD_N + 0.6) * u
            d:rect(tx, ty, 0.45 * u, th, 44, 50, 68, 255)
            local bh = math.max(1.5 * u, th * #L.rows / L.n)
            d:rect(tx, ty + (th - bh) * ((top - 1) / (L.last - 1)), 0.45 * u, bh, 120, 140, 190, 255)
        end
    end,
})

hook.Add("OverlayElement", "swsh.evosRegion", function(el)
    if el.id ~= "swsh.evos" then return end
    if not isOpen() then el.hidden = true return end
    local L = layout(overlay.screenW(), overlay.screenH())
    el.hidden = false
    el.x, el.y, el.w, el.h = L.x, L.y, L.W, L.H
end)
