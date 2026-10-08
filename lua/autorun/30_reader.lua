-- Reading the dialogue box: sample in OnFrame, recognise on the worker,
-- decide in Think.
--
-- OnFrame only checks whether the box is open and copies its text rows out of
-- the frame -- one frame:region per line, because every call into the engine
-- costs ~1.6us whatever it carries. The worker (workers/reader.lua) turns
-- them into text. Think picks the answers up and prints a box's text once it
-- has stopped changing, i.e. once the typewriter animation has finished.

local S = {
    lines   = { "", "" },  -- the latest reading
    open    = false,       -- is the box on screen right now
    pending = nil,         -- text seen but not yet stable
    stable  = 0,           -- how many reads in a row it has been the same
    logged  = nil,         -- the last text printed
    teach   = nil,         -- { "line 1", "line 2" } waiting to be learned
    teachMsg = "",
}
SWSH.state = S

local EVERY  = 4           -- read every Nth frame
local STABLE = 2           -- identical reads before a text counts as final

local reader = worker.spawn("workers/reader.lua")
local function shareAtlas()
    if reader then reader:share("ATLAS", SWSH.fullAtlas()) end
end
shareAtlas()

local frameNo, seq, warned = 0, 0, false

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
    reader:post({ seq = seq, w = w, lines = lines, learn = S.teach ~= nil })
end

-- Count UTF-8 characters, skipping spaces: one per glyph the worker finds.
local function chars(s)
    local out = {}
    for _, cp in utf8.codes(s) do
        local c = utf8.char(cp)
        if c ~= " " then out[#out + 1] = c end
    end
    return out
end

local function learn(res)
    local want, added, msgs = S.teach, 0, {}
    S.teach = nil
    for i = 1, 2 do
        local typed = want[i] or ""
        local L = res.lines[i]
        local cs = chars(typed)
        if #cs > 0 then
            if not L.glyphs or #L.glyphs ~= #cs then
                msgs[#msgs + 1] = string.format("line %d: saw %d glyphs but you typed %d characters",
                                                i, L.glyphs and #L.glyphs or 0, #cs)
            else
                for k, g in ipairs(L.glyphs) do
                    SWSH.saveLearned({ ch = cs[k], w = g.w, t = g.t, b = g.b, f = g.f })
                    added = added + 1
                end
            end
        end
    end
    if added > 0 then shareAtlas() end
    S.teachMsg = (#msgs > 0 and (table.concat(msgs, "; ") .. ". ") or "")
                 .. "Learned " .. added .. " glyphs."
    log(MOD_NAME .. ": " .. S.teachMsg)
end

function SWSH.mod:Think()
    if not reader then return end
    for _, res in ipairs(reader:collect()) do
        do
            if S.teach and res.lines[1].glyphs then learn(res) end
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
    end
    -- The box closed: the next time the same words appear, print them again.
    if not S.open then S.pending, S.stable, S.logged = nil, 0, nil end
end

------------------------------------------------------------------ teaching --
-- Unknown glyphs read as "?". To teach them, open the overlay while a box is
-- on screen, type exactly what it says (lines separated by |) and press
-- Learn. Glyphs are matched to characters in order, so the count has to
-- agree; spaces don't count.
local teachPanel = overlay.add("swsh.teach", {
    mode = "menu", x = 40, y = 120, w = 560, h = 150,
    children = {
        { type = "label", x = 12, y = 10, text = "SwSh reader: teach glyphs (type the box's text, | between lines)" },
        { type = "textbox", x = 12, y = 36, w = 536, h = 28,
          placeholder = "How about it, Lucy? Let's race!|Bet I can make it..." },
        { type = "button", x = 12, y = 74, w = 120, h = 28, text = "Learn" },
        { type = "button", x = 142, y = 74, w = 160, h = 28, text = "Forget learned" },
        { type = "label", x = 12, y = 112, w = 536, h = 34, text = "" },
    },
})
teachPanel.children[3].onClick = function()
    local t = teachPanel.children[2].text or ""
    if not S.open then
        S.teachMsg = "No dialogue box on screen."
    elseif t == "" then
        S.teachMsg = "Type the text first."
    else
        local a, b = t:match("^([^|]*)|?(.*)$")
        S.teach = { a, b }
        S.teachMsg = "Learning from the next read..."
    end
end
teachPanel.children[4].onClick = function()
    SWSH.forgetLearned()
    shareAtlas()
    S.teachMsg = "Learned glyphs cleared."
end

hook.Add("OverlayElement", "swsh.teach", function(el)
    if el.id == "swsh.teach" then el.children[5].text = S.teachMsg end
end)

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
