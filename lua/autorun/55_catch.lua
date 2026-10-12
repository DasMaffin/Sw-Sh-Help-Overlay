-- Catch odds over the ball menu (X in a wild battle): the chance the ball
-- shown catches the wild Pokemon, as a range over what isn't known exactly.
--
-- Gen 8's capture formula (the game's code, not its data; as worked out by
-- the research community, e.g. Dragonfly Cave's write-up):
--   X = (3M - 2H) * C * B / 3M * L * S * D
--     M, H  the foe's max and current HP: M from its level and base HP over
--           IV 0-31 (wild Pokemon have no EVs), H from its HP bar's fill
--     C     its catch rate (09_catch.lua, the game's data)
--     B     the ball: Great 1.5, Ultra 2, Nest, Net, Dusk, ... (BALLS below)
--     L     low level: (30 - lv) / 10 under Lv20
--     S     status: x2.5 asleep / frozen, x1.5 poisoned / paralyzed / burned
--           (read off the battle text: "The wild X was poisoned!" ...)
--     D     x410/4096 while you have under 8 badges and yours is the lower
--           level
--   X >= 255 catches. Else each of 4 shake checks passes with Y / 65536,
--   Y = 65536 / (255 / X)^(3/16); a critical capture (more likely the more
--   species you have: caught.txt's count) needs one.
-- Above the badges' level cap it can't be caught at all (48_progress).

SWSH = SWSH or {}

local U = 6.75          -- 1080p pixels per unit, as the other panels

------------------------------------------------------------------ status --
-- The wild foe's status, from the game's own lines (btl_set), this battle
-- only. "cannot be poisoned!" and the like change nothing.
local status = { no = nil, st = nil }
local STATUS = {
    { "badly poisoned", "poisoned" }, { "was poisoned", "poisoned" }, { "hurt by poison", "poisoned" },
    { "already poisoned", "poisoned" },
    { "was burned", "burned" }, { "hurt by its burn", "burned" }, { "already burned", "burned" },
    { "is paralyzed", "paralyzed" }, { "already paralyzed", "paralyzed" },
    { "frozen solid", "frozen" },
    { "fell asleep", "asleep" }, { "fast asleep", "asleep" }, { "already asleep", "asleep" },
    { "slept and became healthy", "asleep" },
    { "thawed out", false }, { "woke up", false }, { "cured of", false }, { "burn was healed", false },
    { "status returned to normal", false }, { "cured its", false },
}
local S_MULT = { asleep = 2.5, frozen = 2.5, poisoned = 1.5, paralyzed = 1.5, burned = 1.5 }

local function battleNo() return SWSH.state and SWSH.state.battleNo end
local function foeStatus()
    return status.no == battleNo() and status.st or nil
end

function SWSH.onStatusText(lines)
    local s = table.concat(lines, " "):gsub("’", "'"):gsub("%s+", " ")
    if not s:find("The wild") or s:find("cannot be") then return end
    for _, p in ipairs(STATUS) do
        if s:find(p[1], 1, true) then
            local st = p[2] or nil
            if st ~= foeStatus() then
                status.no, status.st = battleNo(), st
                SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, "[foe] ", SWSH.C.text, "status: " .. (st or "none"))
            end
            return
        end
    end
end

------------------------------------------------------------------ balls --
-- Each ball: its multipliers B as a list of what it can be (more than one
-- when something it depends on isn't known), a short note why, and for the
-- Heavy Ball a changed catch rate instead.
local function list(...) return { ... } end
local function waysHere(key)
    -- How the species is met where you are: water (surfing / fishing) or
    -- not, fishing or not -- "yes", "no" or "maybe".
    local _, area = SWSH.where and SWSH.where()
    local ver = game.isActive("pkmn_shield") and "sh" or "sw"
    local water, land, fish, nofish = false, false, false, false
    for _, row in ipairs(area and area[ver] or {}) do
        if row[1] == key then
            for _, w in ipairs(row[3]) do
                local how = w[1]
                local wet = how == "fishing" or how == "surfing" or how:find("Sharpedo") ~= nil
                if wet then water = true else land = true end
                if how == "fishing" then fish = true else nofish = true end
            end
        end
    end
    local function yn(a, b) return a and not b and "yes" or (b and not a and "no" or "maybe") end
    return yn(water, land), yn(fish, nofish)
end
local function maybe(state, x, what)
    if state == "yes" then return list(x), what .. " x" .. x end
    if state == "no" then return list(1), "not " .. what end
    return list(1, x), "x" .. x .. " if " .. what
end
local CAVES = { "Mine", "Cave", "Tunnel" }

local BALLS = {
    pokeball    = { "Poke Ball" },
    greatball   = { "Great Ball",   function() return list(1.5), "x1.5" end },
    ultraball   = { "Ultra Ball",   function() return list(2), "x2" end },
    masterball  = { "Master Ball",  master = true },
    premierball = { "Premier Ball" }, luxuryball = { "Luxury Ball" }, healball = { "Heal Ball" },
    friendball  = { "Friend Ball" },  cherishball = { "Cherish Ball" }, sportball = { "Sport Ball" },
    safariball  = { "Safari Ball" },  parkball = { "Park Ball" },
    netball     = { "Net Ball", function(c)
        if c.types:find("Water") or c.types:find("Bug") then return list(3.5), "Water/Bug x3.5" end
        return list(1), "not Water or Bug"
    end },
    nestball    = { "Nest Ball", function(c)
        if c.lv < 30 then local b = (41 - c.lv) / 10 return list(b), ("Lv%d x%.1f"):format(c.lv, b) end
        return list(1), "Lv30+: x1"
    end },
    diveball    = { "Dive Ball", function(c) return maybe(c.water, 3.5, "on water") end },
    lureball    = { "Lure Ball", function(c) return maybe(c.fishing, 4, "fished") end },
    repeatball  = { "Repeat Ball", function(c)
        if c.caught then return list(3.5), "caught before x3.5" end
        return list(1), "not caught before"
    end },
    timerball   = { "Timer Ball", function(c)
        local function b(t) return math.min(4, 1 + (t - 1) * 1229 / 4096) end
        if c.turn then return list(b(c.turn)), ("turn %d x%.1f"):format(c.turn, b(c.turn)) end
        return list(1, 4), "turn not known"
    end },
    quickball   = { "Quick Ball", function(c)
        if c.turn == 1 then return list(5), "turn 1 x5" end
        if c.turn then return list(1), "not turn 1" end
        return list(1, 5), "x5 on turn 1"
    end },
    duskball    = { "Dusk Ball", function(c)
        if c.cave then return list(3), "cave x3" end
        if c.night then return list(3), "night x3" end
        return list(1), "daytime, not a cave"
    end },
    fastball    = { "Fast Ball", function(c)
        if c.spe >= 100 then return list(4), "Speed " .. c.spe .. " x4" end
        return list(1), "Speed " .. c.spe .. " < 100"
    end },
    levelball   = { "Level Ball", function(c)
        local function b(m)
            if math.floor(m / 4) >= c.lv then return 8 elseif math.floor(m / 2) >= c.lv then return 4
            elseif m > c.lv then return 2 end
            return 1
        end
        if c.mylv then return list(b(c.mylv)), ("yours Lv%d x%d"):format(c.mylv, b(c.mylv)) end
        return list(1, 2, 4, 8), "your level not read"
    end },
    loveball    = { "Love Ball", function(c)
        if not c.same then return list(1), "not your species" end
        local a, b = c.myGender, c.foeGender
        if a and b then
            if a ~= b then return list(8), "same species, " .. a .. " vs " .. b .. " x8" end
            return list(1), "same gender"
        end
        return list(1, 8), "x8 if the other gender (not read)"
    end },
    moonball    = { "Moon Ball", function(c)
        if c.moon then return list(4), "Moon Stone line x4" end
        return list(1), "no Moon Stone evolution"
    end },
    heavyball   = { "Heavy Ball", heavy = true },
    dreamball   = { "Dream Ball", function(c)
        if c.status == "asleep" then return list(4), "asleep x4" end
        return list(1), "not asleep"
    end },
    beastball   = { "Beast Ball", function() return list(410 / 4096), "x0.1 (not an Ultra Beast)" end },
}

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
-- "Poke Balls" (the header says the plural) -> BALLS entry; OCR slips forgiven.
local function ballOf(text)
    local k = SWSH.dexKey(text or ""):gsub("s$", "")
    if BALLS[k] then return BALLS[k] end
    if #k < 6 then return nil end
    local best, bestD, tie = nil, 3, false
    for key, b in pairs(BALLS) do
        local d = distance(k, key)
        if d < bestD then best, bestD, tie = b, d, false elseif d == bestD then tie = true end
    end
    return not tie and best or nil
end

-------------------------------------------------------------------- odds --
local function chance(M, H, C, B, L, S, D, P)
    local X = math.floor((3 * M - 2 * H) * C * B / (3 * M) * L * S * D)
    if X >= 255 then return 1 end
    if X < 1 then X = 1 end
    local p = math.floor(65536 / (255 / X) ^ (3 / 16)) / 65536
    local cc = math.floor(X * P / 6) / 256
    return cc * p + (1 - cc) * p ^ 4
end

local function hpStat(base, iv, lv)
    if base == 1 then return 1 end                    -- Shedinja
    return math.floor((2 * base + iv) * lv / 100) + lv + 10
end

local function dexMult(n)        -- critical captures: by species caught
    if n > 600 then return 2.5 elseif n > 450 then return 2 elseif n > 300 then return 1.5
    elseif n > 150 then return 1 elseif n > 30 then return 0.5 end
    return 0
end

local moonKeys
local function isMoon(key)
    if not moonKeys then
        moonKeys = {}
        for _, e in ipairs(SWSH.EVOS or {}) do
            if e[5]:find("Moon Stone") then moonKeys[e[1]] = true end
        end
    end
    return moonKeys[key] == true
end

-- What the panel shows: { ball = name, lo, hi (0..1), notes = {...} } or
-- { ball, msg } when it can't say.
local function odds(text)
    local ball = ballOf(text)
    if not ball then return { msg = "Reading the ball..." } end
    local res = { ball = ball[1], notes = {} }
    local B = SWSH.battle
    local foe, mine = B and B.foe, B and B.mine
    if ball.master then res.lo, res.hi = 1, 1 return res end
    if not (foe and foe.dex and foe.lv) then res.msg = "The wild Pokemon's name and level aren't read yet" return res end
    local key = SWSH.dexKey(foe.dex[1])
    local P = SWSH.progress
    if P and foe.lv > P.cap() then
        local n = P.needs(foe.lv)
        res.msg = "Too strong to catch: needs " .. n .. " badge" .. (n == 1 and "" or "s")
        return res
    end
    local data = SWSH.CATCH and SWSH.CATCH[key]
    if not data then res.msg = "No catch rate for " .. foe.dex[1] return res end
    local C = data[1]
    local hour = os.date and tonumber(os.date("%H"))
    local where = SWSH.where and SWSH.where() or ""
    local cave = false
    for _, c in ipairs(CAVES) do if where:find(c) then cave = true end end
    local water, fishing = waysHere(key)
    local ctx = {
        lv = foe.lv, mylv = mine and mine.lv, types = foe.dex[2], spe = foe.dex[8],
        turn = SWSH.battleTurn and SWSH.battleTurn(), status = foeStatus(),
        caught = SWSH.caught and SWSH.caught.has(key), same = mine and mine.dex == foe.dex,
        moon = isMoon(key),
        myGender = SWSH.state and SWSH.state.gender and SWSH.state.gender.mine,
        foeGender = SWSH.state and SWSH.state.gender and SWSH.state.gender.foe, water = water, fishing = fishing, cave = cave,
        night = hour ~= nil and (hour >= 19 or hour < 5),
    }
    local Bs, why = { 1 }, nil
    if ball.heavy then
        local w = data[2]
        local add = w >= 3000 and 30 or w >= 2000 and 20 or w >= 1000 and 0 or -20
        C = math.max(1, C + add)
        why = ("%.1f kg: catch rate %+d"):format(w / 10, add)
    elseif ball[2] then
        Bs, why = ball[2](ctx)
    end
    -- HP: max over IVs 0-31, current from the bar.
    local Mlo, Mhi = hpStat(foe.dex[3], 0, foe.lv), hpStat(foe.dex[3], 31, foe.lv)
    local bar = SWSH.state and SWSH.state.foeBar
    local fLo, fHi = bar and bar.lo or 0, bar and bar.hi or 1
    local L = foe.lv < 20 and (30 - foe.lv) / 10 or 1
    local S = S_MULT[ctx.status or ""] or 1
    local Ds = { 1 }
    if P and P.badges() < 8 then
        if not ctx.mylv then Ds = { 1, 410 / 4096 }
        elseif ctx.mylv < foe.lv then Ds = { 410 / 4096 } end
    end
    local crit = dexMult(SWSH.caught and SWSH.caught.count and SWSH.caught.count() or 0)
    local charm = P and P.hasCharm and P.hasCharm()
    if charm then crit = crit * 2 end
    local lo, hi = 1, 0
    for M = Mlo, Mhi do
        local Hlo = math.max(1, math.floor(fLo * M))
        local Hhi = math.max(Hlo, math.min(M, math.ceil(fHi * M)))
        for _, H in ipairs({ Hlo, Hhi }) do
            for _, b in ipairs(Bs) do
                for _, d in ipairs(Ds) do
                    local p = chance(M, H, C, b, L, S, d, crit)
                    lo, hi = math.min(lo, p), math.max(hi, p)
                end
            end
        end
    end
    res.lo, res.hi = lo, hi
    local n = res.notes
    if why then n[#n + 1] = why end
    n[#n + 1] = bar and ("HP %d-%d%%"):format(math.floor(fLo * 100 + 0.5), math.floor(fHi * 100 + 0.5)) or "HP bar not read: any HP"
    if ctx.status then n[#n + 1] = ctx.status .. " x" .. S end
    if L > 1 then n[#n + 1] = ("low level x%.1f"):format(L) end
    if Ds[#Ds] < 1 then n[#n + 1] = #Ds == 1 and "yours is lower level x0.1" or "x0.1 if yours is lower level" end
    if charm then n[#n + 1] = "Catching Charm" end
    n[#n + 1] = "catch rate " .. C
    return res
end
SWSH.catchOdds = odds

------------------------------------------------------------------- draw --
local function pct(p)
    if p >= 1 then return "100" end
    local v = p * 100
    return v < 10 and ("%.1f"):format(v) or ("%d"):format(math.floor(v + 0.5))
end

local function visible()
    if not (SWSH.mod:get("catch_calc") and (game.isActive("pkmn_sword") or game.isActive("pkmn_shield"))) then return nil end
    local name = SWSH.ballMenu and SWSH.ballMenu()
    if not name then return nil end
    local st = SWSH.battleState and SWSH.battleState()
    if (st and st.kind == "trainer") or (SWSH.battle and SWSH.battle.trainer) then return nil end
    return name
end

overlay.add("swsh.catch", {
    mode = "pinned", lockMode = true, passThrough = true,
    paint = function(d)
        local name = visible()
        if not name then return end
        local px, py, pw, ph = camera.pictureRect()
        if pw <= 0 then return end
        local s = ph / SWSH.REF_H
        local u = U * s
        local r = odds(name)
        -- Right above the menu's black header (1080p x 1140..1919, y 668).
        local x, w = px + 1140 * s, 779 * s
        local h = 9.6 * u
        local y = py + 668 * s - h - 0.8 * u
        d:rect(x, y, w, h, 20, 22, 32, 236)
        d:outline(x, y, w, h, 120, 130, 165, 255)
        d:text(x + 1.5 * u, y + 1.0 * u, r.ball or "Catch odds", 1.8 * u, 150, 170, 210, 255)
        if r.msg then
            d:text(x + 1.5 * u, y + 4.6 * u, r.msg, 1.8 * u, 245, 190, 185, 255)
            return
        end
        local big = pct(r.lo) == pct(r.hi) and (pct(r.lo) .. "%") or (pct(r.lo) .. " - " .. pct(r.hi) .. "%")
        local g = math.floor(120 + 120 * r.lo)
        d:text(x + 1.5 * u, y + 3.4 * u, big, 3.4 * u, 255 - math.floor(80 * r.lo), g, 140, 255)
        -- Why, to the right of the number, wrapped onto two lines.
        local nx = x + 1.5 * u + math.max(#big * 3.4, #r.ball * 1.8) * u + 2.4 * u
        local maxc = math.floor((x + w - 1.2 * u - nx) / (1.4 * u))
        local lines, cur = {}, ""
        for _, part in ipairs(r.notes) do
            local try = cur == "" and part or (cur .. ", " .. part)
            if #try > maxc and cur ~= "" then lines[#lines + 1] = cur cur = part else cur = try end
        end
        if cur ~= "" then lines[#lines + 1] = cur end
        for i = 1, math.min(3, #lines) do
            d:text(nx, y + (1.2 + (i - 1) * 2.4) * u, lines[i], 1.4 * u, 170, 180, 205, 255)
        end
    end,
})
