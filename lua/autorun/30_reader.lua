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
-- and SWSH.reader.requestGlyphs() / SWSH.reader.reshare().

local S = {
    lines   = { "", "" },  -- the latest reading
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

-- Is the white box there? Every paper probe must be bright and flat.
local function boxOpen(frame, sx, sy)
    local B = SWSH.BOX
    local col = B.paper[1]
    local x = math.floor(col.x * sx)
    local y0, y1 = math.floor(col.y0 * sy), math.floor(col.y1 * sy)
    local c = frame:region(x, y0, 1, y1 - y0)
    local row = B.paper[2]
    local r = frame:region(math.floor(row.x0 * sx), math.floor(row.y * sy),
                           math.floor((row.x1 - row.x0) * sx), 1)
    local lo, hi = 255, 0
    for _, s in ipairs({ c, r }) do
        for i = 1, #s, 2 do
            local v = s:byte(i)
            if v < lo then lo = v end
            if v > hi then hi = v end
        end
    end
    return lo >= 170 and hi - lo <= 40
end

function SWSH.mod:OnFrame(frame)
    frameNo = frameNo + 1
    if frameNo % EVERY ~= 0 or not reader then return end

    if frame:format() ~= "SDL_PIXELFORMAT_NV12" then
        if not warned then
            log(MOD_NAME .. ": frame format " .. tostring(frame:format())
                .. " is not supported yet (NV12 only)")
            warned = true
        end
        return
    end

    local sx, sy = frame:width() / SWSH.REF_W, frame:height() / SWSH.REF_H
    S.open = boxOpen(frame, sx, sy)
    if not S.open then return end

    local B = SWSH.BOX
    local x0 = math.floor(B.x0 * sx)
    local w  = math.floor(B.x1 * sx) - x0
    local lines = {}
    for i, band in ipairs(B.lines) do
        local y0 = math.floor(band[1] * sy)
        local h  = math.floor(band[2] * sy) - y0
        local blob, rows = frame:region(x0, y0, w, h), {}
        for r = 0, h - 1 do rows[r + 1] = blob:sub(r * w + 1, (r + 1) * w) end
        lines[i] = rows
    end

    seq = seq + 1
    -- post refuses while the worker is busy; that frame is simply skipped.
    if reader:post({ seq = seq, w = w, lines = lines, learn = wantGlyphs }) then
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
        local text = S.lines[1] .. "\n" .. S.lines[2]
        if text == S.pending then
            S.stable = S.stable + 1
        else
            S.pending, S.stable = text, 1
        end
        if S.stable == STABLE and text ~= S.logged and text ~= "\n" then
            S.logged = text
            if SWSH.mod:get("log_text") then
                log(MOD_NAME .. ": " .. S.lines[1]
                    .. (S.lines[2] ~= "" and (" / " .. S.lines[2]) or ""))
            end
        end
    end
    -- The box closed: the next time the same words appear, print them again.
    if not S.open then S.pending, S.stable, S.logged = nil, 0, nil end
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
        d:rect(px + 8, py + 8, 900, 52, 0, 0, 0, 170)
        d:text(px + 16, py + 12, S.lines[1] or "", 18, 255, 255, 255)
        d:text(px + 16, py + 34, S.lines[2] or "", 18, 255, 255, 255)
    end,
})
