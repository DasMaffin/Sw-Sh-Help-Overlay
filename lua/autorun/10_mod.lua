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

--------------------------------------------------------- learned glyphs --
-- Glyphs taught in game are kept in data/<MOD_NAME>/learned.txt, one per
-- line: char <TAB> w <TAB> t <TAB> b <TAB> f1,f2,...  (no load() in the
-- sandbox, so it is a format simple enough to parse by hand).
local LEARNED = "learned.txt"

function SWSH.loadLearned()
    local out, s = {}, data.read(LEARNED)
    if not s then return out end
    for line in s:gmatch("[^\n]+") do
        local ch, w, t, b, fs = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
        if ch then
            local f = {}
            for v in fs:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
            out[#out + 1] = { ch = ch, w = tonumber(w), t = tonumber(t),
                              b = tonumber(b), f = f }
        end
    end
    return out
end

function SWSH.saveLearned(g)
    local f = {}
    for i, v in ipairs(g.f) do f[i] = string.format("%.3g", v) end
    data.append(LEARNED, string.format("%s\t%.4f\t%.4f\t%.4f\t%s\n",
        g.ch, g.w, g.t, g.b, table.concat(f, ",")))
end

function SWSH.forgetLearned() data.delete(LEARNED) end

-- The atlas the worker matches against: shipped glyphs plus learned ones.
function SWSH.fullAtlas()
    local a = {}
    for _, g in ipairs(SWSH.atlas or {}) do a[#a + 1] = g end
    for _, g in ipairs(SWSH.loadLearned()) do a[#a + 1] = g end
    return a
end
