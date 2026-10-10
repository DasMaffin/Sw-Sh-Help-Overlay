-- Reading the dialogue box: sample in OnFrame, recognise on the worker,
-- decide in Think.
--
-- OnFrame only checks whether the box is open and copies its text rows out of
-- the frame -- one frame:region per line, because every call into the engine
-- costs ~1.6us whatever it carries. The worker (workers/reader.lua) turns
-- them into text. Think picks the answers up and prints a box's text once it
-- has stopped changing, i.e. once the typewriter animation has finished.
--
-- Hooks for other files (the dev teaching layer uses them):
--   "SwSh.Result" (res)    every reading, as the worker returned it
--   "SwSh.Think"  ()       once per Think, after results are applied
-- and SWSH.reader.requestGlyphs() / SWSH.reader.reshare(); SWSH.logSuffix,
-- if someone defines it, is appended (in the "stat" colour) to each printed
-- text line.

local S = {
    lines   = { "", "" },  -- the latest reading
    name    = "",          -- the speaker, "" when the box has no name plate
    kind    = nil,         -- "box", "sub" (a cutscene subtitle) or nil
    open    = false,       -- is the box on screen right now
    pending = nil,         -- text seen but not yet stable
    stable  = 0,           -- how many reads in a row it has been the same
    logged  = nil,         -- the last text printed
}
SWSH.state = S

local EVERY  = 4           -- read every Nth frame
local STABLE = 2           -- identical reads before a text counts as final

local reader = worker.spawn("workers/reader.lua")
local wantGlyphs = false

SWSH.reader = {}
function SWSH.reader.reshare()
    if reader then reader:share("ATLAS", SWSH.fullAtlas()) end
end
-- Ask for every glyph's fingerprint on the next read, not only unknown ones.
function SWSH.reader.requestGlyphs() wantGlyphs = true end

local frameNo, seq, warned, shared = 0, 0, false, false

-- Luma range over a set of probes: { x, y0, y1 } columns and { y, x0, x1 }
-- rows, in 1080p pixels, every other sample.
local function probeRange(frame, probes, sx, sy)
    local lo, hi = 255, 0
    for _, p in ipairs(probes) do
        local s
        if p.x then
            local y0 = math.floor(p.y0 * sy)
            s = frame:region(math.floor(p.x * sx), y0, 1, math.floor(p.y1 * sy) - y0)
        else
            local x0 = math.floor(p.x0 * sx)
            s = frame:region(x0, math.floor(p.y * sy), math.floor(p.x1 * sx) - x0, 1)
        end
        for i = 1, #s, 2 do
            local v = s:byte(i)
            if v < lo then lo = v end
            if v > hi then hi = v end
        end
    end
    return lo, hi
end

-- Is the white box there? Every paper probe must be bright and flat.
local function boxOpen(frame, sx, sy)
    local lo, hi = probeRange(frame, SWSH.BOX.paper, sx, sy)
    return lo >= 170 and hi - lo <= 40
end

-- Is the name plate there? Its ground is dark and nearly flat.
local function plateOpen(frame, sx, sy)
    local lo, hi = probeRange(frame, SWSH.NAME.plate, sx, sy)
    return hi <= 80 and hi - lo <= 50
end

-- One band of text, as the worker wants it.
local function grab(frame, x0, x1, band, sx, sy)
    local xa = math.floor(x0 * sx)
    local w  = math.floor(x1 * sx) - xa
    local y0 = math.floor(band[1] * sy)
    local h  = math.floor(band[2] * sy) - y0
    local blob, rows = frame:region(xa, y0, w, h), {}
    for r = 0, h - 1 do rows[r + 1] = blob:sub(r * w + 1, (r + 1) * w) end
    return { rows = rows, w = w }
end

-- The same band plus the colour rows behind it. NV12's interleaved U,V plane
-- starts right after the luma rows (frame:region reads on into it), one U,V
-- pair per 2x2 pixels. x0 is even (SWSH.SUB), so the window starts a cell.
local function grabColour(frame, x0, x1, band, sx, sy)
    local L = grab(frame, x0, x1, band, sx, sy)
    local xa = math.floor(x0 * sx)
    xa = xa - xa % 2
    local y0 = math.floor(band[1] * sy)
    local y1 = math.floor(band[2] * sy)
    local uy0, uy1 = y0 // 2, (y1 + 1) // 2
    local blob, uv = frame:region(xa, frame:height() + uy0, L.w + 1, uy1 - uy0), {}
    local w = L.w + 1
    for r = 0, uy1 - uy0 - 1 do uv[r + 1] = blob:sub(r * w + 1, (r + 1) * w) end
    L.over = { uv = uv, ox = math.floor(x0 * sx) - xa, oy = y0 % 2 }
    return L
end

function SWSH.mod:OnFrame(frame)
    frameNo = frameNo + 1
    if frameNo % EVERY ~= 0 or not reader then return end

    if frame:format() ~= "SDL_PIXELFORMAT_NV12" then
        if not warned then
            SWSH.log(SWSH.LV.important, SWSH.C.error, "frame format ",
                     tostring(frame:format()), " is not supported yet (NV12 only)")
            warned = true
        end
        return
    end

    local sx, sy = frame:width() / SWSH.REF_W, frame:height() / SWSH.REF_H
    S.open = boxOpen(frame, sx, sy)
    local B, N = SWSH.BOX, SWSH.NAME
    local lines = {}
    if not S.open then
        -- No box: maybe a cutscene subtitle. Whether there is one is for
        -- the worker to say, from the text itself.
        for i, band in ipairs(SWSH.SUB.lines) do
            local L = grabColour(frame, SWSH.SUB.x0, SWSH.SUB.x1, band, sx, sy)
            L.style = "s"
            lines[i] = L
        end
        seq = seq + 1
        if reader:post({ seq = seq, lines = lines, learn = wantGlyphs, kind = "sub" }) then
            wantGlyphs = false
        end
        return
    end

    for i, band in ipairs(B.lines) do
        local L = grab(frame, B.x0, B.x1, band, sx, sy)
        L.style = "d"
        lines[i] = L
    end
    -- The name plate is line 3, when there is one. `whole`: a name is all
    -- there is on its plate, which is what lets it be taught from the
    -- game's name lists.
    if plateOpen(frame, sx, sy) then
        local L = grab(frame, N.x0, N.x1, N.band, sx, sy)
        L.style, L.light, L.whole = "n", true, true
        lines[3] = L
    end

    seq = seq + 1
    -- post refuses while the worker is busy; that frame is simply skipped.
    if reader:post({ seq = seq, lines = lines, learn = wantGlyphs, kind = "box" }) then
        wantGlyphs = false
    end
end

function SWSH.mod:Think()
    if not reader then return end
    -- Shared here rather than at load so every autorun file (the dev layer's
    -- learned glyphs included) has had its say first.
    if not shared then shared = true; SWSH.reader.reshare() end

    for _, res in ipairs(reader:collect()) do
        hook.Run("SwSh.Result", res)
        S.lines = { res.lines[1].text, res.lines[2].text }
        S.name = res.lines[3] and res.lines[3].text or ""
        local shown = S.lines[1] ~= "" or S.lines[2] ~= ""
        S.kind = shown and res.kind or (res.kind == "box" and "box" or nil)
        local text = S.name .. "\n" .. S.lines[1] .. "\n" .. S.lines[2]
        if text == S.pending then
            S.stable = S.stable + 1
        else
            S.pending, S.stable = text, 1
        end
        if S.stable == STABLE and text ~= S.logged and (S.lines[1] ~= "" or S.lines[2] ~= "") then
            S.logged = text
            if SWSH.mod:get("log_text") then
                local line = S.lines[1]
                             .. (S.lines[2] ~= "" and (" / " .. S.lines[2]) or "")
                local args = SWSH.marked(line, SWSH.C.text)
                if res.kind == "sub" then
                    table.insert(args, 1, "[cutscene] ")
                    table.insert(args, 1, SWSH.C.cutscene)
                end
                if S.name ~= "" then
                    local named = SWSH.marked(S.name, SWSH.C.name)
                    named[#named + 1] = SWSH.C.name
                    named[#named + 1] = ": "
                    for _, v in ipairs(args) do named[#named + 1] = v end
                    args = named
                end
                local suffix = SWSH.logSuffix and SWSH.logSuffix(res) or ""
                if suffix ~= "" then
                    args[#args + 1] = SWSH.C.stat
                    args[#args + 1] = suffix
                end
                SWSH.log(SWSH.LV.dialogue, table.unpack(args))
            end
        end
        -- Nothing on screen any more (box closed, subtitle gone): the next
        -- time the same words appear, print them again.
        if not shown and res.kind ~= "box" then S.pending, S.stable, S.logged = nil, 0, nil end
    end
    hook.Run("SwSh.Think")
end

--------------------------------------------------------------------- debug --
overlay.add("swsh.debug", {
    mode = "pinned", lockMode = true, passThrough = true,
    paint = function(d)
        if not (SWSH.mod:get("debug") and (game.isActive("pkmn_sword")
                or game.isActive("pkmn_shield"))) then return end
        local px, py, pw, ph = camera.pictureRect()
        if pw <= 0 then return end
        local sx, sy = pw / SWSH.REF_W, ph / SWSH.REF_H
        local B = SWSH.BOX
        local r, g = S.open and 60 or 230, S.open and 230 or 60
        for _, band in ipairs(B.lines) do
            d:outline(px + B.x0 * sx, py + band[1] * sy, (B.x1 - B.x0) * sx,
                      (band[2] - band[1]) * sy, r, g, 60)
        end
        if S.kind == "sub" then
            for _, band in ipairs(SWSH.SUB.lines) do
                d:outline(px + SWSH.SUB.x0 * sx, py + band[1] * sy,
                          (SWSH.SUB.x1 - SWSH.SUB.x0) * sx,
                          (band[2] - band[1]) * sy, 170, 150, 220)
            end
        end
        local N = SWSH.NAME
        d:outline(px + N.x0 * sx, py + N.band[1] * sy, (N.x1 - N.x0) * sx,
                  (N.band[2] - N.band[1]) * sy, 230, 200, 60)
        d:rect(px + 8, py + 8, 900, 52, 0, 0, 0, 170)
        d:text(px + 16, py + 12, ((S.name ~= "" and (S.name .. ": ")) or "")
               .. (S.lines[1] or ""), 18, 255, 255, 255)
        d:text(px + 16, py + 34, S.lines[2] or "", 18, 255, 255, 255)
    end,
})
