-- The reader: find which text is on screen, have the OCR module read it, print
-- what it says.
--
-- ASYNCHRONOUS. OCR takes ~20-40ms a line, far too long for the frame loop.
-- The OCR module (bin/ocr.dll, the native mod "ocr" -- a fork of RapidOcrOnnx)
-- does it on its own thread:
--   OnFrame  checks a few pixels to see which box is up, and hands that box's
--            lines to ocr.read(frame, regions) -- which only copies them and
--            returns. If the module is still busy, this frame is skipped.
--   Think    collects a finished job with ocr.poll() and prints a box's text
--            once it has stopped changing (the typewriter animation is done).

local S = {
    kind  = nil,     -- what is on screen: "box", "sys", "sub" or nil
    lines = {},      -- the latest reading, line by line
    name  = "",      -- the speaker, "" without a name plate
    pending = nil,   -- the latest text, until it has been seen twice
    logged  = nil,   -- the last text printed
}
SWSH.state = S

local EVERY     = 6      -- offer a job every Nth frame (the module may still be busy)
local MIN_SCORE = 0.6    -- below this a line is noise, not text
local SUB_SCORE = 0.85   -- subtitles have no box to prove they're there: stricter

-------------------------------------------------------------- the module --
local ok, ocr = pcall(require, "ocr")
if not ok then
    SWSH.log(SWSH.LV.important, SWSH.C.error,
             "the OCR module isn't available (install the native mod \"ocr\"): ", tostring(ocr))
    ocr = nil
end

------------------------------------------------------------ what's up? --
-- Luma range over probe strips: { x, y0, y1 } columns and { y, x0, x1 } rows,
-- in 1080p pixels.
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

local function boxOpen(frame, sx, sy)     -- white and flat
    local lo, hi = probeRange(frame, SWSH.BOX.paper, sx, sy)
    return lo >= 170 and hi - lo <= 40
end
local function plateOpen(frame, sx, sy)   -- dark and nearly flat
    local lo, hi = probeRange(frame, SWSH.NAME.plate, sx, sy)
    return hi <= 80 and hi - lo <= 50
end
local function battleOpen(frame, sx, sy)  -- dark grey, flat, edge to edge
    local lo, hi = probeRange(frame, SWSH.BATTLE.ground, sx, sy)
    return hi <= 90 and lo >= 25 and hi - lo <= 25
end
local function menuOpen(frame, sx, sy)    -- the battle menu's HP panel: white
    local lo, hi = probeRange(frame, SWSH.BATTLE.panel, sx, sy)
    return lo >= 200 and hi - lo <= 40
end
local function sysOpen(frame, sx, sy)     -- mid-dark grey and flat
    local lo, hi = probeRange(frame, SWSH.SYS.ground, sx, sy)
    return hi <= 90 and lo >= 25 and hi - lo <= 25
end

-- A line region for ocr.read, from 1080p coordinates.
local function region(key, x0, x1, band, sx, sy)
    local x, y = math.floor(x0 * sx), math.floor(band[1] * sy)
    return { key = key, mode = "line", x = x, y = y,
             w = math.floor(x1 * sx) - x, h = math.floor(band[2] * sy) - y }
end

-------------------------------------------------------------------- read --
local frameNo, warned = 0, false
local jobKind = {}       -- job id -> what it read ("box", "sys", "sub")

function SWSH.mod:OnFrame(frame)
    frameNo = frameNo + 1
    if not ocr or frameNo % EVERY ~= 0 then return end
    if frame:format() ~= "SDL_PIXELFORMAT_NV12" then
        if not warned then
            warned = true
            SWSH.log(SWSH.LV.important, SWSH.C.error, "frame format ",
                     tostring(frame:format()), " is not supported (NV12 only)")
        end
        return
    end

    local sx, sy = frame:width() / SWSH.REF_W, frame:height() / SWSH.REF_H
    local kind, regions = nil, {}
    if boxOpen(frame, sx, sy) then
        kind = "box"
        for i, band in ipairs(SWSH.BOX.lines) do
            regions[#regions + 1] = region(i, SWSH.BOX.x0, SWSH.BOX.x1, band, sx, sy)
        end
        if plateOpen(frame, sx, sy) then
            regions[#regions + 1] = region("name", SWSH.NAME.x0, SWSH.NAME.x1, SWSH.NAME.band, sx, sy)
        end
    elseif battleOpen(frame, sx, sy) then
        -- Before the system box: its probes would match the battle band too.
        kind = "battle"
        for i, band in ipairs(SWSH.BATTLE.lines) do
            regions[#regions + 1] = region(i, SWSH.BATTLE.x0, SWSH.BATTLE.x1, band, sx, sy)
        end
    elseif sysOpen(frame, sx, sy) then
        kind = "sys"
        for i, band in ipairs(SWSH.SYS.lines) do
            regions[#regions + 1] = region(i, SWSH.SYS.x0, SWSH.SYS.x1, band, sx, sy)
        end
    elseif menuOpen(frame, sx, sy) then
        -- A battle menu: nothing to read, and its white move names would
        -- pass for a subtitle.
        S.kind, S.lines, S.name, S.pending, S.logged = nil, {}, "", nil, nil
        return
    else
        -- No box: maybe a cutscene subtitle. Only the OCR's confidence can
        -- tell (see Think), so its lines are always read while nothing else is.
        kind = "sub"
        for i, band in ipairs(SWSH.SUB.lines) do
            regions[#regions + 1] = region(i, SWSH.SUB.x0, SWSH.SUB.x1, band, sx, sy)
        end
    end

    local id = ocr.read(frame, regions)     -- nil, "busy": try again next time
    if id then jobKind[id] = kind end
end

----------------------------------------------------------------- collect --
-- The game draws ’ and —; the English model only knows ASCII.
local function tidy(s)
    return (s:gsub("%-%-", "—"):gsub("'", "’"))
end

local function format(kind, name, lines)
    local args = {}
    if kind == "sys" then
        args[#args + 1] = SWSH.C.system;   args[#args + 1] = "[system] "
    elseif kind == "battle" then
        args[#args + 1] = SWSH.C.battle;   args[#args + 1] = "[battle] "
    elseif kind == "sub" then
        args[#args + 1] = SWSH.C.cutscene; args[#args + 1] = "[cutscene] "
    end
    if name ~= "" then
        args[#args + 1] = SWSH.C.name; args[#args + 1] = name .. ": "
    end
    args[#args + 1] = SWSH.C.text
    args[#args + 1] = table.concat(lines, " / ")
    return args
end

local function apply(res)
    local kind = jobKind[res.id]
    jobKind[res.id] = nil
    if res.error then
        SWSH.log(SWSH.LV.important, SWSH.C.error, "OCR failed: ", res.error)
        return
    end
    local min = kind == "sub" and SUB_SCORE or MIN_SCORE
    local lines, name = {}, ""
    for _, r in ipairs(res.regions) do
        local l = r.lines[1]
        -- A line needs a letter or digit: an empty line reads as stray
        -- punctuation (":"), which is not text.
        if l and l.text:find("[%w\128-\255]") and l.score >= min then
            if r.key == "name" then name = tidy(l.text)
            else lines[r.key] = tidy(l.text) end
        end
    end
    local out = {}
    for i = 1, 2 do if lines[i] then out[#out + 1] = lines[i] end end
    -- A subtitle needs real words: a confident read of scenery is still rare,
    -- but a single stray "I" or "." is not a subtitle.
    if kind == "sub" and not table.concat(out, " "):find("%a%a") then out = {} end

    S.kind  = #out > 0 and kind or nil
    S.lines, S.name = out, name
    if #out == 0 then
        -- Nothing on screen: the next time the same words appear, print them.
        S.pending, S.logged = nil, nil
        return
    end

    -- Print once the text is the same twice running: the typewriter is done.
    local text = (kind or "") .. "\n" .. name .. "\n" .. table.concat(out, "\n")
    if text ~= S.pending then
        S.pending = text
    elseif text ~= S.logged then
        S.logged = text
        if SWSH.mod:get("log_text") then
            SWSH.log(SWSH.LV.dialogue, table.unpack(format(kind, name, out)))
        end
    end
end

function SWSH.mod:Think()
    if not ocr then return end
    local res = ocr.poll()
    if res then apply(res) end
end

------------------------------------------------------------------- debug --
overlay.add("swsh.debug", {
    mode = "pinned", lockMode = true, passThrough = true,
    paint = function(d)
        if not (SWSH.mod:get("debug") and (game.isActive("pkmn_sword")
                or game.isActive("pkmn_shield"))) then return end
        local px, py, pw, ph = camera.pictureRect()
        if pw <= 0 then return end
        local sx, sy = pw / SWSH.REF_W, ph / SWSH.REF_H
        local function box(x0, x1, band, r, g, b)
            d:outline(px + x0 * sx, py + band[1] * sy, (x1 - x0) * sx,
                      (band[2] - band[1]) * sy, r, g, b)
        end
        if S.kind == "box" then
            for _, band in ipairs(SWSH.BOX.lines) do box(SWSH.BOX.x0, SWSH.BOX.x1, band, 60, 230, 60) end
            if S.name ~= "" then box(SWSH.NAME.x0, SWSH.NAME.x1, SWSH.NAME.band, 255, 200, 120) end
        elseif S.kind == "battle" then
            for _, band in ipairs(SWSH.BATTLE.lines) do box(SWSH.BATTLE.x0, SWSH.BATTLE.x1, band, 230, 150, 130) end
        elseif S.kind == "sys" then
            for _, band in ipairs(SWSH.SYS.lines) do box(SWSH.SYS.x0, SWSH.SYS.x1, band, 140, 190, 230) end
        elseif S.kind == "sub" then
            for _, band in ipairs(SWSH.SUB.lines) do box(SWSH.SUB.x0, SWSH.SUB.x1, band, 170, 150, 220) end
        end
        d:rect(px + 8, py + 8, 900, 52, 0, 0, 0, 170)
        d:text(px + 16, py + 12, ((S.name ~= "" and (S.name .. ": ")) or "")
               .. (S.lines[1] or ""), 18, 255, 255, 255)
        d:text(px + 16, py + 34, S.lines[2] or "", 18, 255, 255, 255)
    end,
})
