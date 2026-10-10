-- Sword/Shield text reader: registration, settings, and where the text is.
--
-- Everything lives under one global, SWSH: the mod sandbox is shared by every
-- mod, so each extra global is a name they all have to avoid.

SWSH = SWSH or {}

SWSH.mod = game.register({
    { handle = "pkmn_sword",  name = "Pokemon Sword"  },
    { handle = "pkmn_shield", name = "Pokemon Shield" },
})

------------------------------------------------------------------ logging --
-- Engines with the newer log() (colours, levels: wiki "Globals") get our own
-- level, so the user can filter the console down to just this mod's
-- dialogue, and a little colour. Older engines take one string: the colour
-- tables are dropped and the text is joined, so the same calls work there.
local RICH = type(LOG_LEVEL) == "table" and type(LOG_LEVEL.add) == "function"

SWSH.LV = {
    important = RICH and LOG_LEVEL.IMPORTANT or 2,
    dialogue  = RICH and LOG_LEVEL.add("Dialogue") or 1,
}

SWSH.C = {
    dim     = { 150, 150, 160 },   -- the "Sw-Sh-Help-Overlay:" prefix
    text    = { 235, 235, 240 },   -- what the box says
    unknown = { 255,  90,  90 },   -- a glyph it couldn't read: [?]
    stat    = { 120, 200, 255 },   -- [glyphs 42/109 en]
    good    = { 120, 220, 140 },   -- learned something
    letter  = { 255, 220, 100 },   -- the letter itself
    name    = { 255, 200, 120 },   -- the speaker's name
    cutscene = { 170, 150, 220 },  -- the [cutscene] tag
    system   = { 140, 190, 230 },  -- the [system] tag
    warn    = { 255, 170,  80 },   -- couldn't learn / something's off
    error   = { 255,  90,  90 },
}

-- SWSH.log(level, ...) -- strings, numbers and colour tables, as log() takes
-- them. The mod's name is put in front in the dim colour.
function SWSH.log(level, ...)
    local n = select("#", ...)
    if RICH then
        log(level, SWSH.C.dim, MOD_NAME .. ": ", ...)
        return
    end
    local out = {}
    for i = 1, n do
        local v = select(i, ...)
        if type(v) ~= "table" then out[#out + 1] = tostring(v) end
    end
    log(MOD_NAME .. ": " .. table.concat(out))
end

-- Text with its [?] markers picked out in the "unknown" colour, as a list
-- of log() arguments: SWSH.log(lv, table.unpack(SWSH.marked(s, SWSH.C.text))).
function SWSH.marked(s, base)
    local out, i = { base }, 1
    while true do
        local a, b = s:find("[?]", i, true)
        if not a then break end
        if a > i then out[#out + 1] = s:sub(i, a - 1) end
        out[#out + 1] = SWSH.C.unknown
        out[#out + 1] = "[?]"
        out[#out + 1] = base
        i = b + 1
    end
    if i <= #s then out[#out + 1] = s:sub(i) end
    return out
end

SWSH.mod:addSetting("log_text", "Print dialogue text to the console", "bool", nil, true)
-- Outlines the windows the reader samples and shows what it read, over the
-- picture. "Reading the wrong place" and "reading the right place wrongly"
-- look identical from the outside; this tells them apart.
SWSH.mod:addSetting("debug", "Show what the reader sees", "bool", nil, false)

-- The dialogue box, measured off 1920x1080 captures. Kept in 1080p pixels and
-- scaled by the frame's own size at read time, so other capture resolutions
-- land on the same places. dev/gen_atlas.py carries the same numbers.
SWSH.REF_W, SWSH.REF_H = 1920, 1080
SWSH.BOX = {
    x0 = 400, x1 = 1492,            -- text columns (the "next" arrow starts ~1493)
    lines = { { 889, 956 }, { 967, 1034 } },   -- [top, bottom) of each line
    -- Points that are always the box's white paper while it is open: the
    -- margin left of the text, and the strip above the first line.
    paper = { { x = 388, y0 = 880, y1 = 1034 },     -- a column
              { y = 878, x0 = 450, x1 = 1400 } },   -- a row
}

-- The system message box ("Scorbunny has been added to your party."): dark
-- grey, centred, white text. The type is smaller than the dialogue's, so
-- each line is 51 rows instead of the box's 67, which makes its glyphs reach
-- the atlas at the dialogue's size. 51 is measured, not estimated: it is
-- where this box's letters match the dialogue's best (52 or 50 already
-- loses letters). Baselines ~922 and ~982. x1 stops short of the "next"
-- arrow and the darker right stripe.
SWSH.SYS = {
    x0 = 530, x1 = 1376,
    lines = { { 888, 939 }, { 948, 999 } },
    -- Always the box's flat grey while it is up: strips above and below
    -- the text.
    ground = { { y = 870, x0 = 600, x1 = 1300 },
               { y = 1004, x0 = 600, x1 = 1300 } },
}

-- Cutscene subtitles: white text straight over the scene, no box, no
-- outline, a little lower and further right than the box's text (same font,
-- same size, same line spacing). x0 is even so the window starts on a
-- 2x2 colour cell -- the reader needs the colour to tell white from yellow.
SWSH.SUB = {
    x0 = 404, x1 = 1516,
    lines = { { 922, 989 }, { 1000, 1067 } },
}

-- The speaker's name plate above the box's top-left: white text, centred,
-- on a dark plate. Not every box has one (signs, the narrator).
SWSH.NAME = {
    x0 = 345, x1 = 728,
    -- 67 rows like a box line -- a line's height is the scale its glyphs are
    -- measured in, and the plate's type is the same size as the box's (caps
    -- 36px), just heavier. Baseline at ~840, as 935 in the box's first line.
    band = { 792, 859 },
    -- Always the plate's dark ground while it is there: the margin left of
    -- the name, and the strip above it.
    plate = { { x = 350, y0 = 788, y1 = 858 },
              { y = 788, x0 = 352, x1 = 720 } },
}

-- The version of the glyph fingerprint (workers/reader.lua). BUMP IT
-- whenever the reader measures glyphs differently (ink, baseline, weight,
-- grid...): fingerprints of two versions don't compare, and a learned glyph
-- from an older reader would fail to match, or match the wrong letter.
-- Learned glyphs carry it; dev/gen_atlas.py rebuilds the shipped atlas.
SWSH.FEATURES = 5

-- The atlas the worker matches against: the shipped glyphs, plus whatever
-- SWSH.extraGlyphs() returns. Only the dev teaching layer (lua/autorun/
-- 90_dev_teach.lua) defines that; the shipping build has the atlas alone.
function SWSH.fullAtlas()
    local a = {}
    for _, g in ipairs(SWSH.atlas or {}) do a[#a + 1] = g end
    if SWSH.extraGlyphs then
        for _, g in ipairs(SWSH.extraGlyphs()) do a[#a + 1] = g end
    end
    return a
end
