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
-- Where the box goes, in 1080p pixels: just above the player's HP panel
-- (white, x 0..495, from y 925).
local PANEL = { x = 6, y = 815, w = 474, h = 104 }
local LABELS = { "HP", "Atk", "Def", "SpA", "SpD", "Spe", "Total" }

local function statColour(v)
    if v >= 110 then return 120, 220, 255 end
    if v >= 90  then return 120, 230, 120 end
    if v >= 60  then return 240, 220, 110 end
    return 245, 120, 100
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
        local x, y = px + PANEL.x * s, py + PANEL.y * s
        d:rect(x, y, PANEL.w * s, PANEL.h * s, 16, 20, 30, 215)

        local e = mine.dex
        if not e then
            d:text(x + 10 * s, y + 10 * s, mine.name, 22 * s, 255, 255, 255)
            d:text(x + 10 * s, y + 44 * s, "not in the Pokedex (a nickname?)", 16 * s, 190, 190, 200)
            return
        end
        d:text(x + 10 * s, y + 8 * s, e[1], 22 * s, 255, 255, 255)
        d:text(x + 260 * s, y + 12 * s, e[2] .. (e.galar and " (Galar)" or ""), 15 * s, 190, 200, 220)
        local total = 0
        for i = 1, 6 do total = total + e[i + 2] end
        local col = (PANEL.w - 20) / 7
        for i = 1, 7 do
            local v = i <= 6 and e[i + 2] or total
            local cx = x + (10 + (i - 1) * col) * s
            d:text(cx, y + 42 * s, LABELS[i], 15 * s, 170, 175, 190)
            if i <= 6 then
                local r, g, b = statColour(v)
                d:text(cx, y + 66 * s, tostring(v), 24 * s, r, g, b)
            else
                d:text(cx, y + 66 * s, tostring(v), 24 * s, 255, 255, 255)
            end
        end
    end,
})
