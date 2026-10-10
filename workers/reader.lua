-- Turning the dialogue box's pixels back into text, on a worker thread.
--
-- The main thread (lua/autorun/30_reader.lua) copies the box's luma rows out
-- of the frame and posts them here. Everything after that -- finding the
-- glyphs, measuring them and matching them against the atlas -- is arithmetic
-- that costs the picture nothing on this core.
--
-- WHY NOT EXACT MATCHING. The FireRed reader compares 1-bit glyph bitmaps for
-- equality, which works because the GBA font is a pixel font scaled by whole
-- steps. Sword/Shield draws a smooth, anti-aliased, proportional font at the
-- console's own resolution, and the capture card adds its own blur. So every
-- glyph is turned into a small grey-level fingerprint, normalised to the
-- line's height, and the closest fingerprint in the atlas wins. Normalising
-- to the line (not to the glyph's own ink) keeps the vertical position in the
-- fingerprint: that is what tells ',' from an apostrophe and 'p' from 'P'.
--
-- Shared once by the main thread:
--   ATLAS  { { ch = "a", w = <width>, t = <ink top>, b = <ink bottom>,
--              f = { ...GR*GC numbers 0..1 }, s = <style> }, ... }
--   (s: "d" dialogue -- the default when absent -- or "n" the name plate)
--   (w, t, b are fractions of the line's height, so they hold at any
--   capture resolution)
--   (learned glyphs are appended and re-shared)

local GR, GC = 12, 6             -- fingerprint grid: rows x columns
local INK    = 0.5               -- fraction of the line's contrast that is ink
local MIN_RANGE = 60             -- less contrast than this: nothing to read
local ABOVE  = 0.69               -- baseline window: this * lineH above it
local SPACE  = 0.17              -- a gap wider than this * lineH is a space
local SHAPE_W = 30               -- weight of width/top/bottom differences
local UNKNOWN = 3.0              -- a best distance above this is unknown
-- What an unknown glyph prints as. Not a bare "?": the game prints plenty of
-- real question marks, and the two must not be confused in a log. `raw`
-- carries "\1" instead, one byte per unknown glyph, for code to work with.
local MISSING = "[?]"

-- One line: rows is an array of strings, each `w` bytes of luma.
-- Returns the glyphs found, left to right: { x0, x1, f, wn, gapBefore }.
local function segment(rows, w, light)
    local h = #rows
    local lo, hi = 255, 0
    for y = 1, h do
        local r = rows[y]
        for x = 1, w do
            local v = r:byte(x)
            if v < lo then lo = v end
            if v > hi then hi = v end
        end
    end
    if hi - lo < MIN_RANGE then return {}, lo, hi end

    -- Ink per pixel, 0 (paper) .. 1 (ink). Dark text on the white box;
    -- with `light`, white text on a dark plate (the speaker's name).
    local span = hi - lo
    local ink = {}
    for y = 1, h do
        local r, row = rows[y], {}
        for x = 1, w do
            local v = r:byte(x)
            local t = (light and (v - lo) or (hi - v)) / span
            row[x] = t < 0 and 0 or (t > 1 and 1 or t)
        end
        ink[y] = row
    end

    -- Cut the line into glyphs by CONNECTED INK, not by empty columns. The
    -- font kerns: a comma tucks under an 'r', a full stop under a 'w', so
    -- there is often no blank column between two characters even though
    -- their ink never touches. 4-connectivity, so two glyphs that only meet
    -- at a corner of anti-aliasing stay apart.
    local label, comps = {}, {}
    for y = 1, h do label[y] = {} end
    for y = 1, h do
        local irow, lrow = ink[y], label[y]
        for x = 1, w do
            if irow[x] >= INK and not lrow[x] then
                local id = #comps + 1
                local c = { id = id, x0 = x, x1 = x, y0 = y, y1 = y, n = 0 }
                comps[id] = c
                local stack = { x, y }
                lrow[x] = id
                while #stack > 0 do
                    local cy = table.remove(stack)
                    local cx = table.remove(stack)
                    c.n = c.n + 1
                    if cx < c.x0 then c.x0 = cx end
                    if cx > c.x1 then c.x1 = cx end
                    if cy < c.y0 then c.y0 = cy end
                    if cy > c.y1 then c.y1 = cy end
                    for k = 1, 4 do
                        local nx = cx + (k == 1 and 1 or (k == 2 and -1 or 0))
                        local ny = cy + (k == 3 and 1 or (k == 4 and -1 or 0))
                        if nx >= 1 and nx <= w and ny >= 1 and ny <= h
                           and not label[ny][nx] and ink[ny][nx] >= INK then
                            label[ny][nx] = id
                            stack[#stack + 1] = nx
                            stack[#stack + 1] = ny
                        end
                    end
                end
            end
        end
    end

    -- Pieces of one character: the dot of an i/j/!/?, an accent, the two
    -- dots of a colon. They share their columns with the rest of it, where
    -- a kerned neighbour only grazes them -- so a blob joins a group when
    -- most of the narrower of the two lies within the other's columns.
    table.sort(comps, function(p, q) return p.x0 < q.x0 end)
    local groups = {}
    for _, c in ipairs(comps) do
        -- Smaller than 4 pixels is capture noise. Anything touching the
        -- window's right edge is cut off, so it can't be read -- in practice
        -- that's the box's "next" arrow, when the picture sits a pixel or
        -- two off and the arrow's tip reaches into the text columns.
        if c.n >= 4 and c.x1 < w then
            local joined = false
            for gi = #groups, math.max(1, #groups - 2), -1 do
                local g = groups[gi]
                local ov = math.min(c.x1, g.x1) - math.max(c.x0, g.x0) + 1
                local narrow = math.min(c.x1 - c.x0, g.x1 - g.x0) + 1
                if ov >= 0.6 * narrow then
                    g.x0, g.x1 = math.min(g.x0, c.x0), math.max(g.x1, c.x1)
                    g.y0, g.y1 = math.min(g.y0, c.y0), math.max(g.y1, c.y1)
                    g.ids[c.id] = true
                    joined = true
                    break
                end
            end
            if not joined then
                groups[#groups + 1] = { x0 = c.x0, x1 = c.x1, y0 = c.y0,
                                        y1 = c.y1, ids = { [c.id] = true } }
            end
        end
    end
    table.sort(groups, function(p, q) return p.x0 < q.x0 end)

    -- THE BASELINE, not the band, is what fingerprints are measured from.
    -- Most glyphs sit on it, so it is the median of their bottoms. Measured
    -- from the band's top edge instead, a capture one pixel off (scaling,
    -- a different card, a 1919x1079 screenshot) moved every glyph within
    -- its window and nothing matched. The window runs from ABOVE of a line
    -- height above the baseline to BELOW under it -- room for ascenders,
    -- accents and descenders, as the dialogue's own band has.
    local bottoms = {}
    for i, gr in ipairs(groups) do bottoms[i] = gr.y1 end
    table.sort(bottoms)
    local base = bottoms[math.max(1, (#bottoms + 1) // 2)] or h
    local top = base - math.floor(ABOVE * h + 0.5)    -- window row 1 - 1

    local glyphs, lastEnd = {}, nil
    for _, gr in ipairs(groups) do
        local x, x2 = gr.x0, gr.x1
        -- Fingerprint: area-average of ink over a GR x GC grid laid over
        -- the glyph's own columns and the baseline window's rows. Only this
        -- glyph's ink counts (plus the faint anti-aliasing no blob owns), so
        -- a neighbour reaching into these columns doesn't leak in.
        local gw = x2 - x + 1
        local ids, f = gr.ids, {}
        for gy = 0, GR - 1 do
            local ya = top + math.floor(gy * h / GR) + 1
            local yb = math.max(ya, top + math.floor((gy + 1) * h / GR))
            for gx = 0, GC - 1 do
                local xa = x + math.floor(gx * gw / GC)
                local xb = math.max(xa, x + math.floor((gx + 1) * gw / GC) - 1)
                local sum, n = 0, 0
                for yy = ya, yb do
                    local row, lrow = ink[yy], label[yy]
                    if row then
                        for xx = xa, xb do
                            local l = lrow[xx]
                            if not l or ids[l] then sum = sum + row[xx] end
                        end
                    end
                    n = n + (xb - xa + 1)
                end
                f[#f + 1] = sum / n
            end
        end
        glyphs[#glyphs + 1] = { x0 = x, x1 = x2, f = f, wn = gw / h,
                                tn = (gr.y0 - top - 1) / h, bn = (gr.y1 - top) / h,
                                gap = lastEnd and (x - lastEnd - 1) / h or 0 }
        lastEnd = lastEnd and math.max(lastEnd, x2) or x2
    end
    return glyphs, lo, hi
end

-- Only glyphs of the line's own style compete: the name plate's text is a
-- heavier, slightly smaller cut than the dialogue's, and its fingerprints
-- would only blur the dialogue's matches (and the other way round).
local function match(g, atlas, style)
    local best, bestD = nil, math.huge
    for i = 1, #atlas do
        local a = atlas[i]
        if (a.s or "d") ~= style then goto skip end
        local d = SHAPE_W * (math.abs(a.w - g.wn) + math.abs(a.t - g.tn)
                             + math.abs(a.b - g.bn))
        if d < bestD then
            local af, gf = a.f, g.f
            for k = 1, #gf do
                d = d + math.abs(af[k] - gf[k])
                if d >= bestD then break end
            end
            if d < bestD then best, bestD = a.ch, d end
        end
        ::skip::
    end
    return best, bestD
end

local function readLine(rows, w, atlas, light, style)
    local glyphs = segment(rows, w, light)
    local out, raw, worst, missing = {}, {}, 0, 0
    for i, g in ipairs(glyphs) do
        if i > 1 and g.gap > SPACE then
            out[#out + 1] = " "; raw[#raw + 1] = " "
        end
        local ch, d = match(g, atlas, style)
        if d > worst then worst = d end
        if not ch or d > UNKNOWN then
            missing = missing + 1
            out[#out + 1] = MISSING; raw[#raw + 1] = "\1"
        else
            out[#out + 1] = ch; raw[#raw + 1] = ch
        end
    end
    return table.concat(out), glyphs, worst, missing, table.concat(raw)
end

-- job = { seq, learn = bool,
--         lines = { { rows = {...}, w = <bytes per row>, light = bool,
--                     style = "d" | "n", whole = bool }, ... } }
-- Each line comes back as { text, raw, worst, missing, style, whole,
-- glyphs? }; style and whole are echoed for whoever learns from it.
function onJob(job)
    local atlas = ATLAS or {}
    local res = { seq = job.seq, lines = {} }
    for i, line in ipairs(job.lines) do
        local style = line.style or "d"
        local text, glyphs, worst, missing, raw =
            readLine(line.rows, line.w, atlas, line.light, style)
        local L = { text = text, raw = raw, worst = worst, missing = missing,
                    style = style, whole = line.whole }
        -- Fingerprints come back when asked for, or when something was
        -- unknown -- so whoever wants to learn it has the shape in hand.
        if job.learn or missing > 0 then
            L.glyphs = {}
            for k, g in ipairs(glyphs) do L.glyphs[k] = { w = g.wn, t = g.tn, b = g.bn, f = g.f } end
        end
        res.lines[i] = L
    end
    return res
end
