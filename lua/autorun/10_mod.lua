-- Sword/Shield text reader: registration, settings, and where the text is.
--
-- Everything lives under one global, SWSH: the mod sandbox is shared by every
-- mod, so each extra global is a name they all have to avoid.

SWSH = SWSH or {}

SWSH.mod = game.register({
    { handle = "pkmn_sword",  name = "Pokemon Sword"  },
    { handle = "pkmn_shield", name = "Pokemon Shield" },
})

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
