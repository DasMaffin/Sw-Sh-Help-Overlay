-- Who is fighting and their stats, drawn beside the HP panels while a battle
-- menu is up, in the look of pkmn_stats' YOURS / ENEMY panels.
--
-- Who: battle text (SWSH.onBattleText, every printed battle box) --
--   "Go! Scorbunny!", "You're in charge, X!" ...  -> yours
--   "Pokemon Trainer Hop sent out Wooloo!"         -> the opponent's
--   "You encountered a wild Skwovet!"              -> the opponent's
-- and the HP panels themselves (SWSH.onPanels, read while a menu is up):
-- name, "Lv.6", and on yours "8/23" -- the max HP, which is your HP stat.
--
-- Stats: Gen 8's formula over what isn't known. Yours: IV 0-31, EV 0-252,
-- nature x0.9-x1.1 (HP exact once the panel's max HP is read). The
-- opponent's: the same with no EVs -- in-game trainers' and wild Pokemon have
-- none. Before a level is read, base stats. A trainer's Pokemon, though, are
-- in SWSH.TRAINERS: the trainer comes from "<trainer> sent out ..." and
-- "You are challenged by <trainer>!", the species and level off the panel,
-- and their stats are then exact.

local B = {
    mine = nil,      -- { name = as read, dex = SWSH.DEX entry or nil, lv, hp, exact }
    foe  = nil,
    trainer = nil,   -- { name, teams = its SWSH.TRAINERS entries }; nil in the wild
}
SWSH.battle = B
----------------------------------------------------------------- names --
-- "Farfetch’d" -> "farfetchd": the DEX keys' folding.
function SWSH.dexKey(s)
    return (s:lower():gsub("[^%w]", ""))
end

local function distance(a, b)          -- Levenshtein, for OCR slips
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur, ai = { [0] = i }, a:byte(i)
        for j = 1, #b do
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1,
                              prev[j - 1] + (ai == b:byte(j) and 0 or 1))
        end
        prev = cur
    end
    return prev[#b]
end

-- The DEX entry for a name as read, or nil (a nickname, or unreadable).
-- One slip in a short name, two in a long one, and only if it is the single
-- closest species.
local function lookup(name)
    local k = SWSH.dexKey(name)
    if SWSH.DEX[k] then return SWSH.DEX[k] end
    if #k < 4 then return nil end
    local max = #k >= 8 and 2 or 1
    local best, bestD, tie = nil, max + 1, false
    for key, e in pairs(SWSH.DEX) do
        if math.abs(#key - #k) <= max then
            local d = distance(k, key)
            if d < bestD then best, bestD, tie = e, d, false
            elseif d == bestD then tie = true end
        end
    end
    return not tie and best or nil
end
SWSH.lookup = lookup

-------------------------------------------------------------- trainers --
-- SWSH.TRAINERS by key. "Pokémon" folds to "pokemon", as the OCR (ASCII
-- only) reads it.
local function trainerKey(s) return SWSH.dexKey((s:gsub("é", "e"))) end

local byKey
local function trainer(name)
    if not byKey then
        byKey = {}
        for _, t in ipairs(SWSH.TRAINERS or {}) do
            byKey[t[1]] = byKey[t[1]] or {}
            table.insert(byKey[t[1]], t)
        end
    end
    local k = trainerKey(name)
    if byKey[k] then return byKey[k] end
    if #k < 6 then return nil end
    -- OCR slips: up to two in a short name, three in a long one; the single
    -- closest only.
    local max = #k >= 12 and 3 or 2
    local best, bestD, tie = nil, max + 1, false
    for key, list in pairs(byKey) do
        if math.abs(#key - #k) <= max then
            local d = distance(k, key)
            if d < bestD then best, bestD, tie = list, d, false
            elseif d == bestD then tie = true end
        end
    end
    return not tie and best or nil
end

-- who.exact = { lo = {6}, hi = {6}, nature } from the trainer's team, when the
-- species and level are in it. The same trainer fought more than once (or
-- with a team per starter) can have it more than once: lo-hi over them all,
-- and the same numbers if they agree.
local function resolve(who)
    if not who then return end
    who.exact = nil
    if who ~= B.foe or not (B.trainer and who.dex and who.lv) then return end
    local k = SWSH.dexKey(who.dex[1])
    local lo, hi, nat
    for _, t in ipairs(B.trainer.teams) do
        for j = 3, #t do
            local p = t[j]
            if p[1] == k and p[2] == who.lv then
                lo, hi = lo or {}, hi or {}
                for i = 1, 6 do
                    lo[i] = math.min(lo[i] or math.huge, p[i + 2])
                    hi[i] = math.max(hi[i] or 0, p[i + 2])
                end
                if nat == nil then nat = p[9] elseif nat ~= p[9] then nat = false end
            end
        end
    end
    if not lo then return end
    who.exact = { lo = lo, hi = hi, nature = nat ~= "" and nat or nil }
    SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, "[foe] ", SWSH.C.text,
             who.dex[1] .. " Lv." .. who.lv .. " of " .. B.trainer.name .. ": exact stats"
             .. (who.exact.nature and (", " .. who.exact.nature) or ""))
end

local function setTrainer(name)
    local teams = name and trainer(name)
    if teams == (B.trainer and B.trainer.teams) then return end
    B.trainer = teams and { name = teams[1][2], teams = teams } or nil
    if B.trainer then
        SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, "[trainer] ", SWSH.C.text, B.trainer.name)
    end
    resolve(B.foe)
end

------------------------------------------------------------------ text --
-- The player's send-out lines: "<opener><name>!"
local MINE = { "^Go! ", "in charge, ", "Go for it, ", "Hang in there, ",
               "Get ’em, ", "Get 'em, " }

local function set(side, name, dex)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local who = { name = name, dex = dex or lookup(name) }
    B[side] = who
    SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, side == "mine" and "[you] " or "[foe] ",
             SWSH.C.text, who.dex and who.dex[1] or (name .. " (not in the Pokedex)"))
end

-- A catch, in the game's own words (its battle and Pokedex text files):
--   "Gotcha! Wooloo was caught!"         "Wooloo’s data was added to the Pokédex."
--   "You caught Wooloo!"                 "Wooloo has been sent to a Box!"
-- Any box's text (the last is a system message, read with "read_all").
-- Ticks the species in the Pokedex checklist. Not "was caught in a sticky
-- web!", which doesn't end there.
local CATCH = { "([^!]-) was caught!", "^(.-)[’']s data was added to the Pok",
                "You caught ([^!]+)!", "^(.-) has been sent to a Box" }
function SWSH.onCatchText(lines)
    if not SWSH.caught then return end
    local s = table.concat(lines, " ")
    for _, pat in ipairs(CATCH) do
        local name = s:match(pat)
        local e = name and lookup((name:gsub("^Gotcha!%s*", ""):gsub("^%s+", "")))
        if e then SWSH.caught.mark(e, "caught") return end
    end
end

function SWSH.onBattleText(lines)
    local s = table.concat(lines, " ")
    for _, opener in ipairs(MINE) do
        local name = s:match(opener .. "([^!,]+)!")
        if name then set("mine", name) return end
    end
    local by = s:match("challenged by (.-)!")
    if by then setTrainer(by) return end
    -- "Pokemon Trainer Hop sent out Grookey!", "... sent out Wooloo and
    -- Grookey!" (doubles: the first)
    local who, name = s:match("^(.-) sent out ([^!]+)!")
    if who then setTrainer(who)
    else
        name = s:match("wild ([^!]+) appeared") or s:match("encountered a wild ([^!]+)!")
        if name then setTrainer(nil) end
    end
    if name then set("foe", (name:gsub(" and .*", ""))) end
end

----------------------------------------------------------------- stats --
-- Gen 3+ stats. Natures are x0.9 / x1.0 / x1.1, kept in tenths so the
-- rounding is the game's integer maths, not floating point's.
local function stat(base, iv, ev, lv, nat10, hp)
    if hp and base == 1 then return 1 end            -- Shedinja
    local core = math.floor((2 * base + iv + math.floor(ev / 4)) * lv / 100)
    if hp then return core + lv + 10 end
    return math.floor((core + 5) * nat10 / 10)
end

-- lo, hi of one stat (i = 1..6, HP first) for a side as known.
local function range(who, i)
    local base = who.dex[i + 2]
    local lv = who.lv
    if not lv then return base, base end
    if who.exact then return who.exact.lo[i], who.exact.hi[i] end
    if i == 1 and who.hp then return who.hp, who.hp end
    local ev = who == B.mine and 252 or 0
    return stat(base, 0, 0, lv, 9, i == 1), stat(base, 31, ev, lv, 11, i == 1)
end

------------------------------------------------------------ hp panels --
-- A panel reading changes what is shown only once it has been read the same
-- twice running: one OCR slip ("Lv.8" for "Lv.6") is not enough.
local last = {}
local function steady(key, v)
    local ok = v ~= nil and last[key] == v
    last[key] = v
    return ok
end

function SWSH.onPanels(got)
    for _, side in ipairs({ "mine", "foe" }) do
        local name = got[side .. ".name"]
        local dex
        if name then
            -- The gender sign after the name reads as a stray letter or two.
            dex = lookup(name) or lookup(name:gsub("[^%w]*%w?[^%w]*$", ""))
            if steady(side .. ".name", dex) and not (B[side] and B[side].dex == dex) then
                set(side, dex[1], dex)
                resolve(B[side])
            end
        end
        local who = B[side]
        -- The ball by a wild opponent's HP bar: you have its species. Taken
        -- only with its name read off the same panel, twice.
        if side == "foe" and SWSH.caught and steady("foe.ball", got.ball and dex or nil)
           and who and who.dex == dex then
            SWSH.caught.mark(dex, "ball by the HP bar")
        end
        local lv = tonumber((got[side .. ".lv"] or ""):match("(%d+)%D*$"))
        if lv and (lv < 1 or lv > 100) then lv = nil end
        if who and steady(side .. ".lv", lv) and who.lv ~= lv then
            who.lv, who.hp = lv, nil
            SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, side == "mine" and "[you] " or "[foe] ",
                     SWSH.C.text, (who.dex and who.dex[1] or who.name) .. " Lv." .. lv)
            resolve(who)
        end
        -- "8/23": the max HP is the HP stat, if it fits the level.
        local hp = tonumber((got[side .. ".hp"] or ""):match("/%s*(%d+)"))
        if who and who.dex and who.lv and hp and steady(side .. ".hp", hp) then
            local lo, hi = stat(who.dex[3], 0, 0, who.lv, 10, true),
                           stat(who.dex[3], 31, 252, who.lv, 10, true)
            if hp >= lo and hp <= hi then who.hp = hp end
        end
    end
end

------------------------------------------------------------------ draw --
-- The look of pkmn_stats' battle panels (its 60_ui_battle.lua), sized in the
-- same unit u: a GBA pixel there, 6.75 px of a 1080p picture here. No stage
-- arrows, Acc/Eva or ability: those aren't read.
local U       = 6.75          -- 1080p pixels per unit
local W       = 46            -- panel width, units
local ROWS    = 13.4          -- first stat row, from the panel's top
local ROW_H   = 3.1
local LABELS  = { "HP", "Atk", "Def", "SpA", "SpD", "Spe" }
-- Where each panel goes, in 1080p pixels: yours ends just above your HP panel
-- (white from y 925, x 0..495); the opponent's hangs under theirs (top right,
-- down to y ~125).
local PLACE = {
    mine = { title = "YOURS", left = 6,           bottom = 919 },
    foe  = { title = "ENEMY", right = 1920 - 6,   top = 131 },
}

-- pkmn_stats' type palette (lifted for dark panels), plus Fairy.
local TYPE_COLOR = {
    Normal   = { 190, 190, 150 }, Fire     = { 255, 140, 70 },
    Water    = { 120, 155, 255 }, Electric = { 250, 215, 70 },
    Grass    = { 130, 210, 95 },  Ice      = { 160, 225, 225 },
    Fighting = { 225, 90, 70 },   Poison   = { 195, 95, 195 },
    Ground   = { 230, 205, 120 }, Flying   = { 175, 150, 250 },
    Psychic  = { 255, 110, 150 }, Bug      = { 180, 195, 65 },
    Rock     = { 200, 180, 90 },  Ghost    = { 150, 125, 200 },
    Dragon   = { 145, 95, 255 },  Dark     = { 165, 135, 115 },
    Steel    = { 190, 190, 215 }, Fairy    = { 240, 150, 200 },
}

-- The built-in font is monospaced, each character `size` wide.
local function rightText(d, xr, y, str, size, r, g, b)
    str = tostring(str)
    d:text(xr - #str * size, y, str, size, r, g, b, 255)
end

local function typeText(d, x, y, types, size)
    for part, slash in types:gmatch("([^/]+)(/?)") do
        local c = TYPE_COLOR[part] or { 150, 200, 255 }
        d:text(x, y, part, size, c[1], c[2], c[3], 255)
        x = x + #part * size
        if slash == "/" then
            d:text(x, y, "/", size, 150, 156, 175, 255)
            x = x + size
        end
    end
    return x
end
SWSH.typeText, SWSH.rightText = typeText, rightText

local function drawPanel(d, side, s, px, py, scale)
    local who, at = B[side], PLACE[side]
    local u, e = U * s, who.dex
    local w, h = W * u, (e and ROWS + #LABELS * ROW_H + 0.8 or ROWS) * u
    local x = at.left and px + at.left * s or px + at.right * s - w
    local y = at.top and py + at.top * s or py + at.bottom * s - h

    d:rect(x, y, w, h, 20, 22, 32, 224)
    d:outline(x, y, w, h, 120, 130, 165, 255)
    d:rect(x, y, w, 5 * u, 40, 44, 60, 236)
    d:text(x + 1.5 * u, y + 1.3 * u, at.title, 2.4 * u, 150, 170, 210, 255)
    d:text(x + 1.5 * u, y + 6.2 * u, e and e[1] or SWSH.overlayText(who.name), 2.9 * u, 240, 242, 255, 255)
    if who.lv then
        rightText(d, x + w - 1.5 * u, y + 6.6 * u, "Lv" .. who.lv, 2.2 * u, 170, 200, 240)
    end
    if not e then
        d:text(x + 1.5 * u, y + 10 * u, "not in the Pokedex", 2.0 * u, 150, 158, 180, 255)
        return
    end

    local total = 0
    for i = 1, 6 do total = total + e[i + 2] end
    -- Before the level is read the rows are base stats: say so where the
    -- level goes.
    rightText(d, x + w - 1.5 * u, y + 1.6 * u, (who.lv and "BST " or "base stats, BST ") .. total,
              1.8 * u, 170, 200, 240)
    local tx = typeText(d, x + 1.5 * u, y + 10 * u, e[2], 2.0 * u)
    if e.galar then d:text(tx + 2.0 * u, y + 10 * u, "Galar", 2.0 * u, 150, 158, 180, 255) end
    -- A trainer's Pokemon: its nature, from the game's data.
    if who.exact and who.exact.nature then
        rightText(d, x + w - 1.5 * u, y + 10 * u, who.exact.nature, 2.0 * u, 230, 200, 140)
    end

    local bx = x + 9 * u              -- after a 3-letter label
    local bw = w - 26 * u             -- stops short of the value ("100-200")
    for i, label in ipairs(LABELS) do
        local lo, hi = range(who, i)
        local base = e[i + 2]
        local ry = y + (ROWS + (i - 1) * ROW_H) * u
        local top, bh = ry + 0.2 * u, 1.9 * u
        d:text(x + 1.5 * u, ry, label, 2.0 * u, 200, 206, 220, 255)
        d:rect(bx, top, bw, bh, 45, 48, 62, 255)
        -- Colour by the base stat, as pkmn_stats does; solid up to what it is
        -- at the least, faint on to what it can be at the most.
        local r, g, b = 90, 200, 165
        if base >= 100 then r, g, b = 120, 210, 120
        elseif base < 50 then r, g, b = 210, 150, 90 end
        local x0 = bw * math.min(1.0, lo / scale)
        local x1 = bw * math.min(1.0, hi / scale)
        d:rect(bx, top, x0, bh, r, g, b, 255)
        if x1 > x0 then d:rect(bx + x0, top, x1 - x0, bh, r, g, b, 110) end
        rightText(d, x + w - 1.5 * u, ry, lo == hi and lo or (lo .. "-" .. hi), 2.0 * u,
                  235, 235, 240)
    end
end

overlay.add("swsh.stats", {
    mode = "pinned", lockMode = true, passThrough = true,
    paint = function(d)
        if not (SWSH.state.menu and SWSH.mod:get("show_stats") and (B.mine or B.foe)
                and (game.isActive("pkmn_sword") or game.isActive("pkmn_shield"))) then
            return
        end
        local px, py, pw, ph = camera.pictureRect()
        if pw <= 0 then return end
        -- One bar scale for both panels, so the bars compare across them.
        local scale = 1
        for _, side in ipairs({ "mine", "foe" }) do
            local who = B[side]
            if who and who.dex then
                for i = 1, 6 do scale = math.max(scale, select(2, range(who, i))) end
            end
        end
        for _, side in ipairs({ "mine", "foe" }) do
            if B[side] then drawPanel(d, side, ph / SWSH.REF_H, px, py, scale) end
        end
    end,
})
