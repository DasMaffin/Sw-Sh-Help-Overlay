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
    kind  = nil,     -- what is on screen: "box", "battle", "sys", "sub" or nil
    menu  = false,   -- a battle menu is up (the player's HP panel shows)
    battleFrame = nil, -- the last frame with a battle box or menu up
    lines = {},      -- the latest reading, line by line
    name  = "",      -- the speaker, "" without a name plate
    pending = nil,   -- the latest reading { kind, name, lines, text, body }
    logged  = nil,   -- the last reading printed
}
SWSH.state = S

local EVERY     = 1      -- offer a job every Nth frame (the module may still be busy)
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
local function gameMenu(frame, sx, sy)   -- the hint bar: black and flat, the menu above it not
    local lo, hi = probeRange(frame, SWSH.MENU.bar, sx, sy)
    if not (hi <= 30 and hi - lo <= 12) then return false end
    local _, above = probeRange(frame, SWSH.MENU.above, sx, sy)
    return above >= 45                       -- a fade to black is no menu
end
local function sysOpen(frame, sx, sy)     -- mid-dark grey and flat
    local lo, hi = probeRange(frame, SWSH.SYS.ground, sx, sy)
    return hi <= 90 and lo >= 25 and hi - lo <= 25
end
-- The area banner's magenta band: flat in luma, and magenta in chroma -- the
-- chroma plane's rows follow the luma's, U,V interleaved at half size.
-- The owned-species ball by the opponent's HP bar: red chroma on both rows.
local function ownedBall(frame, sx, sy)
    local o = SWSH.OWNED
    local x0 = math.floor(o.x0 * sx / 2) * 2
    local w = math.floor((o.x1 - o.x0) * sx / 2) * 2
    for _, y in ipairs(o.rows) do
        local s = frame:region(x0, frame:height() + math.floor(y * sy / 2), w, 1)
        local red = 0
        for i = 2, #s, 2 do
            if s:byte(i) >= 165 then red = red + 1 end
        end
        if red < 3 then return false end
    end
    return true
end

local function bannerOpen(frame, sx, sy)
    local lo, hi = probeRange(frame, SWSH.AREA.band, sx, sy)
    if not (lo >= 50 and hi <= 115 and hi - lo <= 35) then return false end
    for _, p in ipairs(SWSH.AREA.band) do
        local x0 = math.floor(p.x0 * sx / 2) * 2
        local s = frame:region(x0, frame:height() + math.floor(p.y * sy / 2),
                               math.floor((p.x1 - p.x0) * sx / 2) * 2, 1)
        for i = 1, #s - 1, 16 do
            local u, v = s:byte(i), s:byte(i + 1)
            if v < 175 or u < 115 or u > 165 then return false end
        end
    end
    return true
end

-- A line region for ocr.read, from 1080p coordinates.
local function region(key, x0, x1, band, sx, sy)
    local x, y = math.floor(x0 * sx), math.floor(band[1] * sy)
    return { key = key, mode = "line", x = x, y = y,
             w = math.floor(x1 * sx) - x, h = math.floor(band[2] * sy) - y }
end

-------------------------------------------------------------------- read --
local frameNo, warned = 0, false
local see                -- see(reading or nil), under "collect"
local jobKind = {}       -- job id -> what it read ("box", "battle", "sys", "sub", "panel")
local jobBall = {}       -- job id -> the owned ball was by the opponent's HP bar (panels)

--------------------------------------------------------- battle state --
-- "general" or "battle". Into battle on the game's opening lines (or any
-- battle box / menu seen); out on its closing ones, once the box has been
-- gone a moment (the EXP lines come after "fainted"). An area banner or a
-- game menu can't be in a battle, so they end it too, and so does a long
-- stretch with no battle box at all (a closing line missed).
-- Phrases: commontl_std, btl_app (`pknx-export text`).
S.state = "general"
local END_GAP, STALE = 120, 1800          -- frames: 2 s without the box after the end, 30 s without any
local function setState(st, why)
    if S.state == st then return end
    S.state = st
    S.endFrame, S.startFrame = nil, frameNo
    if st == "general" then S.foe = nil end
    SWSH.log(SWSH.LV.dialogue, SWSH.C.system, "[state] ", SWSH.C.text, st .. " (" .. why .. ")")
end
-- How it starts: wild or Trainer, and who.
local START = {
    { "You encountered a very strong%-looking (.-)!", "wild" },
    { "You encountered a wild (.-)!", "wild" },
    { "A very strong%-looking (.-) appeared!", "wild" },
    { "A wild (.-) appeared!", "wild" },
    { "You are challenged by (.-)!", "trainer" },
    { "(.-) would like to battle!", "trainer" },
}
-- How it ends (the first match). Not the end: your own Pokemon or a Trainer's
-- fainting ("Grookey fainted!", "The opposing Wooloo fainted!"), "You
-- couldn't get away!", "There's no running from a Trainer battle!".
local FINISH = {
    { "Gotcha! (.-) was caught!", "caught %s" },
    { "(.-) was caught!", "caught %s" },
    { "You got away safely!", "you ran away" },
    { "The wild (.-) fled!", "the wild %s fled" },
    { "The wild (.-) fainted!", "the wild %s fainted" },
    { "You defeated (.-)!", "beat %s" },
    { "You lost to (.-)!", "lost to %s" },
    { "You have no more Pok.-mon that can fight", "lost: none of yours can fight" },
    { "You panicked and dropped", "lost: none of yours can fight" },
    { "was blown out of the den", "blown out of the den" },
}
local function battleText(lines)
    local s = table.concat(lines, " "):gsub("’", "'"):gsub("%s+", " ")
    for _, p in ipairs(START) do
        local who = s:match(p[1])
        if who then
            S.foe = { kind = p[2], name = who }
            if S.state ~= "battle" then
                setState("battle", (p[2] == "wild" and "a wild " or "Trainer ") .. who)
            end
            S.endFrame = nil
            return
        end
    end
    if S.state ~= "battle" then return end
    for _, p in ipairs(FINISH) do
        local who = s:match(p[1])
        if who then
            S.endFrame, S.endWhy = frameNo, p[2]:format(who)
            return
        end
    end
end

SWSH.onBattleStateText = battleText      -- for dev/sim.py's --say

-- The battle under way: { kind = "wild" | "trainer", name } (nil when its
-- opening line wasn't read), or nil outside one.
function SWSH.battle() return S.state == "battle" and (S.foe or {}) or nil end


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
    local all = SWSH.mod:get("read_all")    -- off: battle text only
    S.menu = menuOpen(frame, sx, sy)
    if gameMenu(frame, sx, sy) then
        S.gameMenuFrame = frameNo
        setState("general", "menu")
    end
    local kind, regions, ball = nil, {}, false
    if SWSH.mod:get("route_info") ~= "off" and bannerOpen(frame, sx, sy) then
        -- Entering an area: its name (50_route.lua).
        see(nil)
        kind = "area"
        for what, r in pairs({ name = SWSH.AREA.name, sub = SWSH.AREA.sub }) do
            regions[#regions + 1] = region(what, r.x0, r.x1, { r.y0, r.y1 }, sx, sy)
        end
    -- Dialogue and system boxes are always read (badges, key items and
    -- catches are said there: 48_progress, 40_battle) -- printed only with
    -- read_all.
    elseif boxOpen(frame, sx, sy) then
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
        S.battleFrame = frameNo
        setState("battle", "battle box")
        for i, band in ipairs(SWSH.BATTLE.lines) do
            regions[#regions + 1] = region(i, SWSH.BATTLE.x0, SWSH.BATTLE.x1, band, sx, sy)
        end
    elseif sysOpen(frame, sx, sy) then
        kind = "sys"
        for i, band in ipairs(SWSH.SYS.lines) do
            regions[#regions + 1] = region(i, SWSH.SYS.x0, SWSH.SYS.x1, band, sx, sy)
        end
    elseif S.menu then
        -- A battle menu: no text box, but the HP panels say who is fighting
        -- and at what level (40_battle.lua). Its white move names would pass
        -- for a subtitle, so no subtitles here.
        see(nil)
        kind = "panel"
        S.battleFrame = frameNo
        setState("battle", "battle menu")
        ball = ownedBall(frame, sx, sy)
        for side, p in pairs(SWSH.HPBOX) do
            for what, r in pairs(p) do
                regions[#regions + 1] = region(side .. "." .. what, r.x0, r.x1, { r.y0, r.y1 }, sx, sy)
            end
        end
    elseif not all then
        see(nil)                            -- nothing to read
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
    if id then jobKind[id], jobBall[id] = kind, ball end
end

----------------------------------------------------------------- collect --
-- The game draws ’, — and ₽; the English model only knows ASCII. ₽ is left
-- out (or read as P), so it goes back where the game writes money: only in
-- these phrases -- other numbers ("gained 123 Exp. Points") have none.
local MONEY = {                     -- { before, after } the amount
    { "got ",      " for winning" },
    { "paid out ", "" },
    { "picked up ", "!" },
    { "received ", "[.!]" },
}
local function tidy(s)
    s = s:gsub("%-%-", "—"):gsub("'", "’")
    for _, m in ipairs(MONEY) do
        s = s:gsub("(" .. m[1] .. ")P? ?([%d,]+" .. m[2] .. ")", "%1₽%2")
    end
    return s
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

-- Two readings of the same box: the typewriter grew it, or the OCR read it a
-- little differently. They share most of their start.
local function sameBox(a, b)
    local n, i = math.min(#a, #b), 0
    while i < n and a:byte(i + 1) == b:byte(i + 1) do i = i + 1 end
    return i >= n / 2
end

local function emit(r)
    if S.logged and S.logged.text == r.text then return end
    S.logged = r
    if r.kind == "battle" then battleText(r.lines) end
    if r.kind == "battle" and SWSH.onBattleText then SWSH.onBattleText(r.lines) end
    if SWSH.onCatchText then SWSH.onCatchText(r.lines) end
    if SWSH.onProgressText then SWSH.onProgressText(r.lines) end
    if SWSH.mod:get("log_text") and (r.kind == "battle" or SWSH.mod:get("read_all")) then
        SWSH.log(SWSH.LV.dialogue, table.unpack(format(r.kind, r.name, r.lines)))
    end
end

local function apply(res)
    local kind, ball = jobKind[res.id], jobBall[res.id]
    jobKind[res.id], jobBall[res.id] = nil, nil
    if res.error then
        SWSH.log(SWSH.LV.important, SWSH.C.error, "OCR failed: ", res.error)
        return
    end
    if kind == "area" then               -- the area banner, for 50_route
        setState("general", "area banner")
        local got = {}
        for _, r in ipairs(res.regions) do
            local l = r.lines[1]
            if l and l.score >= MIN_SCORE then got[r.key] = l.text end
        end
        if SWSH.onArea then SWSH.onArea(got.name, got.sub) end
        return
    end
    if kind == "panel" then              -- HP panels: key -> text, for 40_battle
        local got = {}
        for _, r in ipairs(res.regions) do
            local l = r.lines[1]
            if l and l.score >= MIN_SCORE then got[r.key] = l.text end
        end
        got.ball = ball
        if SWSH.onPanels then SWSH.onPanels(got) end
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

    local cur = nil
    if #out > 0 then
        local body = table.concat(out, "\n")
        cur = { kind = kind, name = name, lines = out, body = body,
                text = (kind or "") .. "\n" .. name .. "\n" .. body }
    end
    see(cur)
end

-- The latest reading (nil: nothing on screen) -> print it once it's settled.
see = function(cur)
    S.kind  = cur and cur.kind
    S.lines = cur and cur.lines or {}
    S.name  = cur and cur.name or ""
    local p = S.pending

    -- Print once the text is the same twice running: the typewriter is done.
    if cur and p and cur.text == p.text then
        emit(cur)
        return
    end
    -- Mashing through text can close a box before it was read twice. When it
    -- closes, or other text takes its place, print its last reading -- unless
    -- that is only the typewriter or OCR noise on what was printed.
    if p and not (cur and sameBox(p.body, cur.body)) then
        local l = S.logged
        if not (l and sameBox(l.body, p.body) and #p.body <= #l.body) then emit(p) end
    end
    S.pending = cur
    if not cur then S.logged = nil end   -- the same words again later are new
end

-- A battle is on: its box or menu was up in the last ~4 s (the move
-- animations between them show neither).
function SWSH.inBattle()
    if S.state == "battle" then
        local since = frameNo - math.max(S.battleFrame or 0, S.startFrame or 0)
        if (S.endFrame and since >= END_GAP) or since >= STALE then
            setState("general", S.endFrame and S.endWhy or "no battle box for a while")
        end
    end
    return S.state == "battle" or (S.battleFrame ~= nil and frameNo - S.battleFrame < 240)
end

-- A game menu is up (its hint bar seen just now): the overlays step aside,
-- unless MCCP's own overlay is open (then you're using them).
function SWSH.inMenu()
    return S.gameMenuFrame ~= nil and frameNo - S.gameMenuFrame <= 2 * EVERY + 2
end
function SWSH.hideForMenu()
    return SWSH.inMenu() and not (overlay.isOpen and overlay.isOpen())
end

function SWSH.mod:Think()
    if not ocr then return end
    local res = ocr.poll()
    if res then apply(res) end
end

------------------------------------------------------------------- debug --
-- The console draws ’ — ₽, the overlay's font doesn't (ASCII and a few
-- accents; anything else is a hollow box): back to ASCII for it.
function SWSH.overlayText(s)
    return (s:gsub("’", "'"):gsub("‘", "'"):gsub("“", '"'):gsub("”", '"')
             :gsub("—", "--"):gsub("₽", "P"))
end

local overlayText = SWSH.overlayText

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
        if #S.lines == 0 then return end     -- nothing read: no empty bar
        d:rect(px + 8, py + 8, 900, 52, 0, 0, 0, 170)
        d:text(px + 16, py + 12, overlayText(((S.name ~= "" and (S.name .. ": ")) or "")
               .. (S.lines[1] or "")), 18, 255, 255, 255)
        d:text(px + 16, py + 34, overlayText(S.lines[2] or ""), 18, 255, 255, 255)
    end,
})
