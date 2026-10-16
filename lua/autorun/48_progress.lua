-- Story progress the panels need: Gym Badges (the catch level cap) and the
-- key items that open ways of meeting Pokemon (the Rotom Bike's Water Mode,
-- Sword/Shield's Surf) or help catching them (the Catching Charm: more
-- critical captures, 55_catch). The Fishing Rod is yours from the start of
-- the game: fishing is always open. Kept in two of the mod's own
-- settings ("multi", saved by the engine), ticked here from what the game
-- says -- in its own words, from its text files -- and fixable by hand there:
--   "You defeated Gym Leader Milo!"                        (battle text)
--   "...present you with your very own Grass Badge!"       (dialogue)
--   "You can now catch Pokémon of up to Lv. 25!"           (after a badge)
--   "You obtained a Catching Charm!"                       (system box)
--   "With the Rotom Bike "Water Mode," you'll cruise..."   (dialogue)
-- Nothing ever unticks one but the settings.

SWSH = SWSH or {}

-- In Gym order; the 4th and 6th differ by version.
SWSH.BADGES = { "Grass", "Water", "Fire", "Fighting", "Ghost", "Fairy", "Rock", "Ice", "Dark", "Dragon" }
local TIER = { Grass = 1, Water = 2, Fire = 3, Fighting = 4, Ghost = 4, Fairy = 5, Rock = 6, Ice = 6,
               Dark = 7, Dragon = 8 }
local LEADER = { milo = "Grass", nessa = "Water", kabu = "Fire", bea = "Fighting", allister = "Ghost",
                 opal = "Fairy", gordie = "Rock", melony = "Ice", piers = "Dark", raihan = "Dragon" }
SWSH.ITEMS = { "Rotom Bike Water Mode", "Catching Charm" }

-- The highest level a wild Pokemon may be to be caught, by badges held
-- (common\btl_std: "You don't have enough Gym Badges to catch a Pokémon
-- this strong!"). 8 badges: anything.
local CAP = { [0] = 20, 25, 30, 35, 40, 45, 50, 55, 100 }

local P = {}
SWSH.progress = P

local function has(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- Badges held, as a count: the highest Gym among the ticked ones, so a
-- missed read never lowers it (the Dark Badge means seven, whatever else is
-- ticked).
function P.badges()
    local n = 0
    for _, b in ipairs(SWSH.mod:get("badges") or {}) do n = math.max(n, TIER[b] or 0) end
    return n
end
function P.cap() return CAP[P.badges()] end
-- Badges needed to catch one at this level (nil: no badge needed).
function P.needs(lv)
    for n = 0, 8 do if lv <= CAP[n] then return n > 0 and n or nil end end
    return 8
end
function P.hasCharm() return has(SWSH.mod:get("key_items"), "Catching Charm") end
function P.hasRod() return true end          -- given at the start
function P.hasWater() return has(SWSH.mod:get("key_items"), "Rotom Bike Water Mode") end

-- Why a way of meeting a Pokemon isn't open to you yet ({ how, ..., lo }),
-- or nil.
function P.blocked(how, lo)
    if (how == "surfing" or how == "Sharpedo spots") and not P.hasWater() then
        return "needs the bike's Water Mode"
    end
    if lo and lo > P.cap() then
        local n = P.needs(lo)
        return "needs " .. n .. " badge" .. (n == 1 and "" or "s") .. " to catch"
    end
end

local function tick(key, value, why)
    local list = SWSH.mod:get(key) or {}
    if has(list, value) then return end
    local out = {}
    for _, v in ipairs(list) do out[#out + 1] = v end
    out[#out + 1] = value
    SWSH.mod:set(key, out)
    local n = P.badges()
    local extra = key == "badges" and (": " .. n .. (n == 1 and " badge" or " badges") .. ", catch up to "
                                       .. (n == 8 and "any level" or ("Lv" .. P.cap()))) or ""
    SWSH.log(SWSH.LV.important, SWSH.C.system, "[progress] ", SWSH.C.text,
             value .. (key == "badges" and " Badge" or "") .. extra .. " (" .. why .. ")")
end

function SWSH.onProgressText(lines)
    local s = table.concat(lines, " "):gsub("’", "'")
    local leader = s:match("You defeated Gym Leader (%a+)")
    if leader and LEADER[leader:lower()] then tick("badges", LEADER[leader:lower()], "beat " .. leader) return end
    local badge = s:match("(%a+) Badge!")
    if badge and TIER[badge] and (s:find("present you") or s:find("obtained") or s:find("received")) then
        tick("badges", badge, "given")
        return
    end
    -- Said right after each badge (the start of the line can be cut off).
    if s:find("atch Pok%S* of any level") then tick("badges", "Dragon", "the catch level went up") return end
    local lv = tonumber(s:match("atch Pok%S* of up to Lv%.? ?(%d+)") or "")
    if lv then
        for n = 1, 7 do
            if CAP[n] == lv then
                local sword = game.isActive("pkmn_sword")
                local b = n == 4 and (sword and "Fighting" or "Ghost") or n == 6 and (sword and "Rock" or "Ice")
                for k, t in pairs(TIER) do if not b and t == n then b = k end end
                tick("badges", b, "the catch level went up")
            end
        end
        return
    end
    if s:find("Catching Charm") and (s:find("obtained") or s:find("received")) then
        tick("key_items", "Catching Charm", "obtained")
    elseif s:find("Water Mode") and (s:find("cruise") or s:find("across the water")) then
        tick("key_items", "Rotom Bike Water Mode", "Rotom Bike upgraded")
    elseif s:find("enough Gym Badges to catch") then
        SWSH.log(SWSH.LV.important, SWSH.C.system, "[progress] ", SWSH.C.text,
                 "too strong to catch with " .. P.badges() .. " badges (catch up to Lv" .. P.cap() .. ")")
    end
end

--------------------------------------------------------- the editor --
-- The setting "Progress editor" opens a panel in the middle of the screen:
-- every badge and key item as a box to click, for when a read was missed (or
-- a wrong one ticked). Its X turns the setting back off.
local U = 6.75
local function width(s, size) return #tostring(s) * size end
local function editorOpen()
    return SWSH.mod:get("progress_editor") == true and (game.isActive("pkmn_sword") or game.isActive("pkmn_shield"))
           and not (SWSH.hideForMenu and SWSH.hideForMenu())
end
local function toggle(key, value)
    local out, found = {}, false
    for _, v in ipairs(SWSH.mod:get(key) or {}) do
        if v == value then found = true else out[#out + 1] = v end
    end
    if not found then out[#out + 1] = value end
    SWSH.mod:set(key, out)
end

-- Where it opens: left of MCCP's settings window (620 px, centred, and
-- drawn over paint elements like this one -- in the middle it was hidden
-- behind it), or where it was dragged to last time (progresspos.txt).
local POS_FILE = "progresspos.txt"
local saved
do
    local body = data and data.read and data.read(POS_FILE)
    local a, b = (body or ""):match("^(-?[%d.]+)%s+(-?[%d.]+)")
    if a then saved = { tonumber(a), tonumber(b) } end
end
local function editorHome(sw, sh)
    local u = U * sh / SWSH.REF_H
    local W, H = 58 * u, 39.6 * u
    if saved then return saved[1], saved[2], W, H end
    return math.max(2 * u, sw / 2 - 310 - W - 2 * u), (sh - H) / 2, W, H
end

-- Boxes: { key, value, label, x, y, w, h } in screen pixels, plus the X.
local function editorLayout(x, y)
    local u = U * overlay.screenH() / SWSH.REF_H
    local W, H = 58 * u, 39.6 * u
    local boxes = {}
    for i, b in ipairs(SWSH.BADGES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        boxes[#boxes + 1] = { "badges", b, b .. " Badge", x + (1.4 + col * 28) * u, y + (10.4 + row * 2.8) * u, 26 * u, 2.4 * u }
    end
    for i, it in ipairs(SWSH.ITEMS) do
        boxes[#boxes + 1] = { "key_items", it, it, x + 1.4 * u, y + (28.4 + (i - 1) * 2.8) * u, 54 * u, 2.4 * u }
    end
    return { x = x, y = y, W = W, H = H, u = u, boxes = boxes, close = { x + W - 3.8 * u, y + 1.0 * u, 2.4 * u, 2.4 * u } }
end
local function hit(r, mx, my) return mx >= r[1] and mx < r[1] + r[3] and my >= r[2] and my < r[2] + r[4] end
local function rectOf(b) return { b[4], b[5], b[6], b[7] } end

local function at(self)
    local hx, hy = editorHome(overlay.screenW(), overlay.screenH())
    return (self and self.x) or hx, (self and self.y) or hy
end

overlay.add("swsh.progress", {
    mode = "pinned",
    movable = true,
    OnDragEnd = function(self)                 -- for the next run
        if data and data.write then data.write(POS_FILE, ("%.0f %.0f"):format(self.x, self.y)) end
    end,
    OnMouseDown = function(self, lx, ly, btn)
        if btn ~= 1 or not editorOpen() then return end
        local L = editorLayout(at(self))
        local mx, my = lx + L.x, ly + L.y
        if hit(L.close, mx, my) then SWSH.mod:set("progress_editor", false) return end
        for _, b in ipairs(L.boxes) do
            if hit(rectOf(b), mx, my) then toggle(b[1], b[2]) return end
        end
    end,
    paint = function(d, self)
        if not editorOpen() then return end
        local L = editorLayout(at(self))
        local x, y, W, H, u = L.x, L.y, L.W, L.H, L.u
        local mx, my = overlay.mouseX and overlay.mouseX() or -1, overlay.mouseY and overlay.mouseY() or -1
        d:rect(x, y, W, H, 20, 22, 32, 240)
        d:outline(x, y, W, H, 120, 130, 165, 255)
        d:rect(x, y, W, 4.4 * u, 40, 46, 64, 240)
        d:text(x + 1.4 * u, y + 1.1 * u, "Story progress", 2.2 * u, 238, 242, 252, 255)
        local hotX = hit(L.close, mx, my)
        d:text(L.close[1] + 0.6 * u, L.close[2] + 0.2 * u, "X", 2.0 * u, hotX and 255 or 190, 200, hotX and 200 or 215, 255)
        d:text(x + 1.4 * u, y + 5.4 * u, "Click to fix what the reader missed.", 1.5 * u, 150, 158, 180, 255)
        d:text(x + 1.4 * u, y + 8.0 * u, "Gym Badges", 1.6 * u, 225, 205, 150, 255)
        d:text(x + 1.4 * u, y + 26.0 * u, "Key items", 1.6 * u, 225, 205, 150, 255)
        local have = {}
        for _, k in ipairs({ "badges", "key_items" }) do
            for _, v in ipairs(SWSH.mod:get(k) or {}) do have[k .. v] = true end
        end
        for _, b in ipairs(L.boxes) do
            local on, hot = have[b[1] .. b[2]], hit(rectOf(b), mx, my)
            if hot then d:rect(b[4] - 0.4 * u, b[5] - 0.3 * u, b[6], b[7], 58, 66, 92, 255) end
            local s = 1.6 * u
            d:outline(b[4], b[5] + 0.1 * u, s, s, 150, 165, 205, 255)
            if on then d:rect(b[4] + 0.35 * u, b[5] + 0.45 * u, s - 0.7 * u, s - 0.7 * u, 140, 215, 160, 255) end
            local c = on and 232 or 160
            d:text(b[4] + 2.6 * u, b[5], b[3], 1.6 * u, c - 6, c, math.min(255, c + 20), 255)
        end
        -- What it adds up to.
        local n = P.badges()
        d:text(x + 1.4 * u, y + 35.8 * u, n .. (n == 1 and " badge" or " badges") .. ": catch up to "
               .. (n == 8 and "any level" or ("Lv" .. P.cap())), 1.6 * u, 200, 206, 220, 255)
    end,
})

hook.Add("OverlayElement", "swsh.progressRegion", function(el)
    if el.id ~= "swsh.progress" then return end
    if not editorOpen() then el.hidden = true return end
    el.hidden = false
    el.x, el.y, el.w, el.h = editorHome(overlay.screenW(), overlay.screenH())
end)
