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
--              f = { ...GR*GC numbers 0..1 } }, ... }
--   (w, t, b are fractions of the line's height, so they hold at any
--   capture resolution)
--   (learned glyphs are appended and re-shared)

local GR, GC = 12, 6             -- fingerprint grid: rows x columns
local INK    = 0.5               -- fraction of the line's contrast that is ink
local MIN_RANGE = 60             -- less contrast than this: nothing to read
local SPACE  = 0.17              -- a gap wider than this * lineH is a space
local SHAPE_W = 30               -- weight of width/top/bottom differences
local UNKNOWN = 3.0              -- a best distance above this is unknown
-- What an unknown glyph prints as. Not a bare "?": the game prints plenty of
-- real question marks, and the two must not be confused in a log. `raw`
-- carries "\1" instead, one byte per unknown glyph, for code to work with.
local MISSING = "[?]"

-- One line: rows is an array of strings, each `w` bytes of luma.
-- Returns the glyphs found, left to right: { x0, x1, f, wn, gapBefore }.
local function segment(rows, w)
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

    -- Ink per pixel, 0 (paper) .. 1 (ink). Dark text on the white box.
    local span = hi - lo
    local ink = {}
    for y = 1, h do
        local r, row = rows[y], {}
        for x = 1, w do
            local t = (hi - r:byte(x)) / span
            row[x] = t < 0 and 0 or (t > 1 and 1 or t)
        end
        ink[y] = row
    end

    local colInk = {}
    for x = 1, w do
        local any = false
        for y = 1, h do if ink[y][x] >= INK then any = true; break end end
        colInk[x] = any
    end

    local glyphs, x, lastEnd = {}, 1, nil
    while x <= w do
        if colInk[x] then
            local x2 = x
            while x2 + 1 <= w and colInk[x2 + 1] do x2 = x2 + 1 end
            -- Fingerprint: area-average of ink over a GR x GC grid laid over
            -- the glyph's own columns and the whole line's rows.
            local gw = x2 - x + 1
            local f = {}
            for gy = 0, GR - 1 do
                local ya = math.floor(gy * h / GR) + 1
                local yb = math.max(ya, math.floor((gy + 1) * h / GR))
                for gx = 0, GC - 1 do
                    local xa = x + math.floor(gx * gw / GC)
                    local xb = math.max(xa, x + math.floor((gx + 1) * gw / GC) - 1)
                    local s, n = 0, 0
                    for yy = ya, yb do
                        local row = ink[yy]
                        for xx = xa, xb do s = s + row[xx]; n = n + 1 end
                    end
                    f[#f + 1] = s / n
                end
            end
            -- Where the ink starts and stops, to the pixel. The grid is too
            -- coarse to see that 'l' rises two pixels above 'I'; this isn't.
            local top, bot = nil, 1
            for yy = 1, h do
                local row = ink[yy]
                for xx = x, x2 do
                    if row[xx] >= INK then top = top or yy; bot = yy; break end
                end
            end
            glyphs[#glyphs + 1] = { x0 = x, x1 = x2, f = f, wn = gw / h,
                                    tn = (top - 1) / h, bn = bot / h,
                                    gap = lastEnd and (x - lastEnd - 1) / h or 0 }
            lastEnd = x2
            x = x2 + 1
        else
            x = x + 1
        end
    end
    return glyphs, lo, hi
end

local function match(g, atlas)
    local best, bestD = nil, math.huge
    for i = 1, #atlas do
        local a = atlas[i]
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
    end
    return best, bestD
end

local function readLine(rows, w, atlas)
    local glyphs = segment(rows, w)
    local out, raw, worst, missing = {}, {}, 0, 0
    for i, g in ipairs(glyphs) do
        if i > 1 and g.gap > SPACE then
            out[#out + 1] = " "; raw[#raw + 1] = " "
        end
        local ch, d = match(g, atlas)
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

-- job = { seq, w, lines = { {rows...}, {rows...} }, learn = bool }
-- Each line comes back as { text, raw, worst, missing, glyphs? }.
function onJob(job)
    local atlas = ATLAS or {}
    local res = { seq = job.seq, lines = {} }
    for i, rows in ipairs(job.lines) do
        local text, glyphs, worst, missing, raw = readLine(rows, job.w, atlas)
        local L = { text = text, raw = raw, worst = worst, missing = missing }
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
