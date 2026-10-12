-- Story progress the panels need: Gym Badges (the catch level cap) and the
-- key items that open ways of meeting Pokemon (the Fishing Rod; the Rotom
-- Bike's Water Mode, Sword/Shield's Surf). Kept in two of the mod's own
-- settings ("multi", saved by the engine), ticked here from what the game
-- says -- in its own words, from its text files -- and fixable by hand there:
--   "You defeated Gym Leader Milo!"                        (battle text)
--   "...present you with your very own Grass Badge!"       (dialogue)
--   "You obtained a Fishing Rod!"                          (system box)
--   "With the Rotom Bike "Water Mode," you'll cruise..."   (dialogue)
-- Nothing ever unticks one but the settings.

SWSH = SWSH or {}

-- In Gym order; the 4th and 6th differ by version.
SWSH.BADGES = { "Grass", "Water", "Fire", "Fighting", "Ghost", "Fairy", "Rock", "Ice", "Dark", "Dragon" }
local TIER = { Grass = 1, Water = 2, Fire = 3, Fighting = 4, Ghost = 4, Fairy = 5, Rock = 6, Ice = 6,
               Dark = 7, Dragon = 8 }
local LEADER = { milo = "Grass", nessa = "Water", kabu = "Fire", bea = "Fighting", allister = "Ghost",
                 opal = "Fairy", gordie = "Rock", melony = "Ice", piers = "Dark", raihan = "Dragon" }
SWSH.ITEMS = { "Fishing Rod", "Rotom Bike Water Mode" }

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
function P.hasRod() return has(SWSH.mod:get("key_items"), "Fishing Rod") end
function P.hasWater() return has(SWSH.mod:get("key_items"), "Rotom Bike Water Mode") end

-- Why a way of meeting a Pokemon isn't open to you yet ({ how, ..., lo }),
-- or nil.
function P.blocked(how, lo)
    if how == "fishing" and not P.hasRod() then return "needs the Fishing Rod" end
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
    if s:find("Fishing Rod") and (s:find("obtained") or s:find("received")) then
        tick("key_items", "Fishing Rod", "obtained")
    elseif s:find("Water Mode") and (s:find("cruise") or s:find("across the water")) then
        tick("key_items", "Rotom Bike Water Mode", "Rotom Bike upgraded")
    elseif s:find("enough Gym Badges to catch") then
        SWSH.log(SWSH.LV.important, SWSH.C.system, "[progress] ", SWSH.C.text,
                 "too strong to catch with " .. P.badges() .. " badges (catch up to Lv" .. P.cap() .. ")")
    end
end
