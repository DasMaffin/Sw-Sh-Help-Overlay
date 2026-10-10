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
