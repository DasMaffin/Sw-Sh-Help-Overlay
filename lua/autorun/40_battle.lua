-- Who is fighting, from the battle text, and the player's Pokemon's base stats
-- drawn above its HP panel while a battle menu is up.
--
-- The reader hands every printed battle box to SWSH.onBattleText(lines):
--   "Go! Scorbunny!", "You're in charge, X!" ...  -> the player's Pokemon
--   "Pokemon Trainer Hop sent out Wooloo!"         -> the opponent's
--   "You encountered a wild Skwovet!"              -> the opponent's

local B = {
    mine = nil,      -- { name = as read, dex = SWSH.DEX entry or nil }
    foe  = nil,
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

------------------------------------------------------------------ text --
-- The player's send-out lines: "<opener><name>!"
local MINE = { "^Go! ", "in charge, ", "Go for it, ", "Hang in there, ",
               "Get ’em, ", "Get 'em, " }

local function set(side, name)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local who = { name = name, dex = lookup(name) }
    B[side] = who
    SWSH.log(SWSH.LV.dialogue, SWSH.C.battle, side == "mine" and "[you] " or "[foe] ",
             SWSH.C.text, who.dex and who.dex[1] or (name .. " (not in the Pokedex)"))
end

function SWSH.onBattleText(lines)
    local s = table.concat(lines, " ")
    for _, opener in ipairs(MINE) do
        local name = s:match(opener .. "([^!,]+)!")
        if name then set("mine", name) return end
    end
    -- "sent out Grookey!", "sent out Wooloo and Grookey!" (doubles: the first)
    local name = s:match("sent out ([^!]+)!")
              or s:match("wild ([^!]+) appeared")
              or s:match("encountered a wild ([^!]+)!")
    if name then set("foe", (name:gsub(" and .*", ""))) end
end

------------------------------------------------------------------ draw --
-- The look of pkmn_stats' YOURS panel (its 60_ui_battle.lua), sized in the
-- same unit u: a GBA pixel there, 6.75 px of a 1080p picture here. Only base
-- stats are known, so it is that panel's "no level" layout -- one full bar
-- and the base value per row -- without stage arrows, Acc/Eva or ability.
local U       = 6.75          -- 1080p pixels per unit
local W       = 46            -- panel width, units
local ROWS    = 13.4          -- first stat row, from the panel's top
local ROW_H   = 3.1
local BOTTOM  = 919           -- 1080p y the panel ends at: the HP panel is at 925
local LEFT    = 6
local STATS   = { { "HP", 3 }, { "Atk", 4 }, { "Def", 5 },
                  { "SpA", 6 }, { "SpD", 7 }, { "Spe", 8 } }

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

overlay.add("swsh.stats", {
    mode = "pinned", lockMode = true, passThrough = true,
    paint = function(d)
        local mine = B.mine
        if not (mine and SWSH.state.menu and SWSH.mod:get("show_stats")
                and (game.isActive("pkmn_sword") or game.isActive("pkmn_shield"))) then
            return
        end
        local px, py, pw, ph = camera.pictureRect()
        if pw <= 0 then return end
        local s = ph / SWSH.REF_H
        local u = U * s
        local e = mine.dex
        local w, h = W * u, (e and ROWS + #STATS * ROW_H + 0.8 or ROWS) * u
        local x, y = px + LEFT * s, py + BOTTOM * s - h

        d:rect(x, y, w, h, 20, 22, 32, 224)
        d:outline(x, y, w, h, 120, 130, 165, 255)
        d:rect(x, y, w, 5 * u, 40, 44, 60, 236)
        d:text(x + 1.5 * u, y + 1.3 * u, "YOURS", 2.4 * u, 150, 170, 210, 255)
        d:text(x + 1.5 * u, y + 6.2 * u, e and e[1] or mine.name, 2.9 * u, 240, 242, 255, 255)
        if not e then
            d:text(x + 1.5 * u, y + 10 * u, "not in the Pokedex", 2.0 * u, 150, 158, 180, 255)
            return
        end

        local total = 0
        for _, st in ipairs(STATS) do total = total + e[st[2]] end
        rightText(d, x + w - 1.5 * u, y + 1.6 * u, "BST " .. total, 1.8 * u, 170, 200, 240)
        local tx = typeText(d, x + 1.5 * u, y + 10 * u, e[2], 2.0 * u)
        if e.galar then d:text(tx + 2.0 * u, y + 10 * u, "Galar", 2.0 * u, 150, 158, 180, 255) end

        local bx = x + 9 * u             -- after a 3-letter label
        local bw = w - 17.5 * u          -- stops short of the value ("255")
        for i, st in ipairs(STATS) do
            local v  = e[st[2]]
            local ry = y + (ROWS + (i - 1) * ROW_H) * u
            d:text(x + 1.5 * u, ry, st[1], 2.0 * u, 200, 206, 220, 255)
            d:rect(bx, ry + 0.2 * u, bw, 1.9 * u, 45, 48, 62, 255)
            local r, g, b = 90, 200, 165
            if v >= 100 then r, g, b = 120, 210, 120
            elseif v < 50 then r, g, b = 210, 150, 90 end
            d:rect(bx, ry + 0.2 * u, bw * math.min(1.0, v / 180), 1.9 * u, r, g, b, 255)
            rightText(d, x + w - 1.5 * u, ry, v, 2.0 * u, 235, 235, 240)
        end
    end,
})
