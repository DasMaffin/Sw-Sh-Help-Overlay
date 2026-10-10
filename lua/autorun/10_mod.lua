-- Sword/Shield text reader: registration, settings, logging, and where the
-- game draws its text.
--
-- Everything lives under one global, SWSH: the mod sandbox is shared by every
-- mod, so each extra global is a name they all have to avoid.

SWSH = SWSH or {}

SWSH.mod = game.register({
    { handle = "pkmn_sword",  name = "Pokemon Sword"  },
    { handle = "pkmn_shield", name = "Pokemon Shield" },
})

------------------------------------------------------------------ logging --
-- Engines with log levels and colours (wiki "Globals") get a level of our own,
-- so Options -> Developer can show just what this mod read. Older engines take
-- one string: colour tables are dropped and the rest joined.
local RICH = type(LOG_LEVEL) == "table" and type(LOG_LEVEL.add) == "function"

SWSH.LV = {
    important = RICH and LOG_LEVEL.IMPORTANT or 2,
    dialogue  = RICH and LOG_LEVEL.add("Dialogue") or 1,
}

SWSH.C = {
    dim      = { 150, 150, 160 },   -- the "Sw-Sh-Help-Overlay:" prefix
    text     = { 235, 235, 240 },   -- what was read
    name     = { 255, 200, 120 },   -- the speaker's name
    system   = { 140, 190, 230 },   -- the [system] tag
    battle   = { 230, 150, 130 },   -- the [battle] tag
    cutscene = { 170, 150, 220 },   -- the [cutscene] tag
    error    = { 255,  90,  90 },
}

-- SWSH.log(level, ...) -- strings, numbers and colour tables, as log() takes
-- them, with the mod's name in front.
function SWSH.log(level, ...)
    if RICH then
        log(level, SWSH.C.dim, MOD_NAME .. ": ", ...)
        return
    end
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "table" then out[#out + 1] = tostring(v) end
    end
    log(MOD_NAME .. ": " .. table.concat(out))
end

----------------------------------------------------------------- settings --
SWSH.mod:addSetting("log_text", "Print what is read to the console", "bool", nil, true)
-- Off: only battle text is read. On: dialogue, system and cutscene text too.
SWSH.mod:addSetting("read_all", "Read text outside battles too", "bool", nil, false)
SWSH.mod:addSetting("show_stats", "Show both Pokemon's stats in battle", "bool", nil, true)
-- The checklist panel (45_dex.lua); its own X turns this back off.
-- What's met in the area the game's banner last named (50_route.lua).
SWSH.mod:addSetting("route_info", "Show route information", "choice",
                    { "on", "off", "overlay only" }, "on")
SWSH.mod:addSetting("pokedex", "Pokedex checklist", "bool", nil, false)
-- Outlines the lines being read and shows the latest reading over the picture.
SWSH.mod:addSetting("debug", "Show what the reader sees", "bool", nil, false)

----------------------------------------------------------- where the text is --
-- Measured off 1920x1080 captures and scaled to the frame's own size at read
-- time. Each entry of `lines` is ONE line of text: the OCR module reads it in
-- "line" mode (recognition only, no text detection), which is both faster
-- and more accurate than letting it find the text itself.
SWSH.REF_W, SWSH.REF_H = 1920, 1080

-- The white dialogue box.
SWSH.BOX = {
    x0 = 400, x1 = 1492,                         -- stops short of the "next" arrow
    lines = { { 889, 956 }, { 967, 1034 } },     -- [top, bottom) of each line
    -- Always the box's white paper while it is open: the margin left of the
    -- text, and the strip above the first line.
    paper = { { x = 388, y0 = 880, y1 = 1034 },
              { y = 878, x0 = 450, x1 = 1400 } },
}

-- The speaker's name plate above the box: white text on a dark plate. Not
-- every box has one (signs, the narrator).
SWSH.NAME = {
    x0 = 345, x1 = 728,
    band = { 792, 859 },
    plate = { { x = 350, y0 = 788, y1 = 858 },
              { y = 788, x0 = 352, x1 = 720 } },
}

-- The battle message box ("Your Pokemon gained Exp. Points!"): a dark band
-- across the whole bottom of the screen, white text at the dialogue's size and
-- on the dialogue's lines. Told from the system box by its ground running on
-- to the right edge, where the system box (centred, x ~480..1440) has ended.
SWSH.BATTLE = {
    x0 = 150, x1 = 1780,                         -- stops short of the "next" arrow
    lines = { { 889, 956 }, { 967, 1034 } },
    ground = { { y = 878, x0 = 200, x1 = 1780 },
               { y = 1040, x0 = 200, x1 = 1780 } },
    -- The player's HP panel (white, bottom left) while a battle menu is up.
    -- Its moves and buttons are white text too: not to be read as subtitles.
    panel  = { { y = 930, x0 = 200, x1 = 440 }, { y = 975, x0 = 200, x1 = 440 },
               { y = 1040, x0 = 200, x1 = 420 } },
}

-- What is read off the two HP panels while a battle menu is up (one text line
-- each): name (the gender sign comes along; the Pokedex lookup forgives it),
-- "Lv.6" (whole: a lone digit reads badly),
-- and on yours the HP as "8/23".
SWSH.HPBOX = {
    mine = { name = { x0 = 18,   x1 = 330,  y0 = 934, y1 = 978 },
             lv   = { x0 = 355,  x1 = 470,  y0 = 936, y1 = 982 },
             hp   = { x0 = 18,   x1 = 240,  y0 = 995, y1 = 1045 } },
    foe  = { name = { x0 = 1462, x1 = 1700, y0 = 44,  y1 = 92 },
             lv   = { x0 = 1800, x1 = 1915, y0 = 40,  y1 = 86 } },
}

-- The area banner, shown a few seconds on entering an area: the name in white
-- on a flat magenta band at the bottom right ("Rolling Fields"), the region
-- under it on grey ("Wild Area"). Told by the band's colour: magenta has a
-- chroma nothing else there has (V ~196 in the NV12 frame).
SWSH.AREA = {
    name = { x0 = 1180, x1 = 1910, y0 = 914, y1 = 990 },
    sub  = { x0 = 1240, x1 = 1910, y0 = 1004, y1 = 1054 },
    band = { { y = 900, x0 = 1400, x1 = 1910 }, { y = 987, x0 = 1400, x1 = 1910 } },
}

-- The dark system message box ("Scorbunny has been added to your party.").
SWSH.SYS = {
    x0 = 530, x1 = 1376,
    lines = { { 888, 939 }, { 948, 999 } },
    ground = { { y = 870, x0 = 600, x1 = 1300 },
               { y = 1004, x0 = 600, x1 = 1300 } },
}

-- Cutscene subtitles: white text straight over the scene, no box. Read only
-- while neither box is open.
SWSH.SUB = {
    x0 = 404, x1 = 1516,
    lines = { { 922, 989 }, { 1000, 1067 } },
}
