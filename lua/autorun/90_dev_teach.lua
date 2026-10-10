-- DEV ONLY -- glyph teaching. DELETE THIS FILE (and dev/) FOR THE SHIPPING
-- BUILD; the reader works without it. See CLAUDE.md.
--
-- Two ways of learning glyphs the atlas doesn't have:
--   * self-teaching: a line read with unknown glyphs is looked up in the
--     game's own text (dev/teach/teach_<lang>.lua). If exactly one answer
--     fits, the unknown glyphs are those letters.
--   * manual: type what the box says into the overlay panel and press Learn.
-- Either way the glyphs go to data/<MOD_NAME>/learned.txt and are used at
-- once. They are BAKED into the shipped atlas by copying that file into
-- dev/learned/ and running dev/gen_atlas.py -- so every glyph only has to be
-- found once, by whoever meets it first.

local LEARNED   = "learned.txt"
-- Teaching chatter gets a level of its own, so it can be filtered apart from
-- the dialogue. (Older engines: plain lines, see SWSH.log.)
local LV = (type(LOG_LEVEL) == "table" and LOG_LEVEL.add)
           and LOG_LEVEL.add("Teaching") or 1
local C = SWSH.C
local PER_CHAR  = 8          -- distinct variants kept per character
local SAME      = 1.0        -- closer than this to a kept variant: skipped
local LANGS     = { "en", "de", "fr", "it", "es", "ko", "ja-hiragana",
                    "ja-katakana", "ch-simplified", "ch-traditional" }

SWSH.mod:addSetting("dev_selfteach", "DEV: learn unknown letters from the game's text",
                    "bool", nil, true)
SWSH.mod:addSetting("dev_lang", "DEV: game language (restart to apply)",
                    "choice", LANGS, "en")

------------------------------------------------------------ learned.txt --
-- One glyph per line: char <TAB> w <TAB> t <TAB> b <TAB> f1,f2,... [<TAB> style]
-- (no load() in the sandbox, so a format simple enough to parse by hand).
-- The last column says where the glyph was seen ("d" dialogue box, "n" name
-- plate) -- for reference only: there is ONE atlas, whatever the colours.
local learned, perChar = {}, {}

local function parse(s)
    for line in s:gmatch("[^\n]+") do
        local ch, w, t, b, fs, st = line:match(
            "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t?([^\t]*)$")
        if ch then
            st = st ~= "" and st or "d"
            local f = {}
            for v in fs:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
            learned[#learned + 1] = { ch = ch, s = st, w = tonumber(w), t = tonumber(t),
                                      b = tonumber(b), f = f }
            perChar[ch] = (perChar[ch] or 0) + 1
        end
    end
end
parse(data.read(LEARNED) or "")

function SWSH.extraGlyphs() return learned end

-- Save one glyph (st: where it was seen, for the record). Returns false when
-- that character already has enough variants, or one just like it.
local function keep(ch, g, st)
    st = st or "d"
    if (perChar[ch] or 0) >= PER_CHAR then return false end
    -- A near-copy of a variant we already have teaches nothing (same
    -- distance as the reader's match, workers/reader.lua).
    for _, a in ipairs(SWSH.fullAtlas()) do
        if a.ch == ch then
            local d = 30 * (math.abs(a.w - g.w) + math.abs(a.t - g.t) + math.abs(a.b - g.b))
            for k = 1, #g.f do d = d + math.abs(a.f[k] - g.f[k]) end
            if d < SAME then return false end
        end
    end
    local f = {}
    for i, v in ipairs(g.f) do f[i] = string.format("%.3g", v) end
    data.append(LEARNED, string.format("%s\t%.4f\t%.4f\t%.4f\t%s\t%s\n",
        ch, g.w, g.t, g.b, table.concat(f, ","), st))
    learned[#learned + 1] = { ch = ch, s = st, w = g.w, t = g.t, b = g.b, f = g.f }
    perChar[ch] = (perChar[ch] or 0) + 1
    return true
end

local STYLE_NAME = { d = "", n = " (name plate)" }

-- Count the characters of a known-text string the way the reader counts
-- glyphs: one per character, spaces skipped.
local function chars(s)
    local out = {}
    for _, cp in utf8.codes(s) do
        local c = utf8.char(cp)
        if c ~= " " then out[#out + 1] = c end
    end
    return out
end

local function show(s) return (s:gsub("\1", "[?]")) end

----------------------------------------------------------- self-teaching --
local lang = SWSH.mod:get("dev_lang") or "en"
local teacher = worker.spawn("dev/teach/teach_" .. lang .. ".lua")
if not teacher then
    SWSH.log(SWSH.LV.important, C.warn, "DEV self-teaching is off -- no dev/teach/teach_",
             lang, ".lua (build it with dev/gen_teach.py)")
end

-- How many of the language's characters the reader knows, for the line
-- printed after something was learned: "[glyphs 34/97 en]".
local charset, statDue = nil, false
if teacher then teacher:post({ charset = true }) end

local function knownStat()
    if not charset then return "" end
    local have = {}
    for _, g in ipairs(SWSH.fullAtlas()) do have[g.ch] = true end
    local n, total = 0, 0
    for _, cp in utf8.codes(charset) do
        total = total + 1
        if have[utf8.char(cp)] then n = n + 1 end
    end
    return string.format("  [glyphs %d/%d %s]", n, total, lang)
end

function SWSH.logSuffix(res)
    -- Only once everything in the box is known, and only after learning.
    if not statDue then return "" end
    for _, L in ipairs(res.lines) do
        if L.missing > 0 then return "" end
    end
    statDue = false
    return knownStat()
end

-- Keyed by style .. "\0" .. raw line: the same text on the name plate and in
-- the box are different glyphs.
local tried   = {}           -- key -> true: asked already, don't repeat
local waiting = {}           -- key -> { raw, style, glyphs = the unknowns' }
local lastRaw = {}           -- per line, to only ask about a stable reading

hook.Add("SwSh.Result", "swsh.dev.selfteach", function(res)
    if not teacher or not SWSH.mod:get("dev_selfteach") then return end
    for i, L in ipairs(res.lines) do
        local raw = L.raw or ""
        local key = L.style .. "\0" .. raw
        local stable = raw == lastRaw[i]
        lastRaw[i] = raw
        if stable and L.missing > 0 and L.glyphs and not tried[key] then
            -- Glyphs line up with the non-space characters of `raw`.
            local unknown, k = {}, 0
            for _, c in ipairs(chars(raw)) do
                k = k + 1
                if c == "\1" then unknown[#unknown + 1] = L.glyphs[k] end
            end
            -- whole: the name plate holds a name and nothing else, so it
            -- has to be one whole entry of the game text, not part of one.
            if teacher:post({ key = key, raw = raw, whole = L.whole }) then
                tried[key] = true
                waiting[key] = { raw = raw, style = L.style, glyphs = unknown }
            end
        end
    end
end)

hook.Add("SwSh.Think", "swsh.dev.selfteach", function()
    if not teacher then return end
    for _, ans in ipairs(teacher:collect()) do
        if ans.charset then charset = ans.charset; goto continue end
        local wt = waiting[ans.key] or {}
        waiting[ans.key] = nil
        local glyphs, raw, st = wt.glyphs, wt.raw or "", wt.style or "d"
        if ans.chars and glyphs and #ans.chars == #glyphs then
            local line, n = raw, 0
            for _, c in ipairs(ans.chars) do
                line = line:gsub("\1", c, 1)
            end
            for j, c in ipairs(ans.chars) do
                if keep(c, glyphs[j], st) then
                    n = n + 1
                    local args = { C.good, "DEV learned new letter '", C.letter, c,
                                   C.good, "'" .. STYLE_NAME[st] .. " from \"", C.text, line,
                                   C.good, "\" (read as \"" }
                    for _, v in ipairs(SWSH.marked(show(raw), C.text)) do
                        args[#args + 1] = v
                    end
                    args[#args + 1] = C.good
                    args[#args + 1] = "\"" .. (ans.placeholder and ("; \"" .. ans.placeholder
                                          .. "\" taken as a name") or "") .. ")"
                    SWSH.log(LV, table.unpack(args))
                end
            end
            if n > 0 then SWSH.reader.reshare(); statDue = true end
        elseif ans.why then
            local args = { C.warn, "DEV could not learn from \"" }
            for _, v in ipairs(SWSH.marked(show(raw), C.text)) do
                args[#args + 1] = v
            end
            args[#args + 1] = C.warn
            args[#args + 1] = "\": " .. ans.why
            SWSH.log(LV, table.unpack(args))
        end
        ::continue::
    end
end)

------------------------------------------------------------ manual teach --
local teachText, teachMsg = nil, ""

-- The engine's font is about as wide as it is tall (DrawContext: "each glyph
-- is ~size wide"), so everything is sized from F rather than guessed.
local F = 14
local panel = overlay.add("swsh.dev.teach", {
    mode = "menu", x = 40, y = 120, w = 640, h = 196,
    children = {
        { type = "label", x = 12, y = 10, w = 616, h = 2 * (F + 3),
          text = "DEV: teach glyphs. Type exactly what the box says: line 1|line 2|name (name optional).",
          style = { font = F } },
        { type = "textbox", x = 12, y = 48, w = 616, h = 28, style = { font = F },
          placeholder = "How about it, Lucy?|Bet I can..." },
        { type = "button", x = 12, y = 86, w = 7 * F, h = 28, text = "Learn",
          style = { font = F } },
        { type = "button", x = 12 + 7 * F + 12, y = 86, w = 16 * F, h = 28,
          text = "Forget learned", style = { font = F } },
        { type = "label", x = 12, y = 124, w = 616, h = 4 * (F + 3), text = "",
          style = { font = F } },
    },
})
panel.children[3].onClick = function()
    local t = panel.children[2].text or ""
    if not SWSH.state.open then
        teachMsg = "No dialogue box on screen."
    elseif t == "" then
        teachMsg = "Type the text first."
    else
        local parts = {}
        for p in (t .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
        teachText = { parts[1], parts[2], parts[3] }
        SWSH.reader.requestGlyphs()
        teachMsg = "Learning from the next read..."
    end
end
panel.children[4].onClick = function()
    data.delete(LEARNED)
    learned, perChar, tried = {}, {}, {}
    SWSH.reader.reshare()
    teachMsg = "Learned glyphs cleared."
    SWSH.log(LV, C.warn, "DEV learned glyphs cleared")
end

hook.Add("SwSh.Result", "swsh.dev.manual", function(res)
    if not teachText then return end
    -- Wait for the read that carries every line's fingerprints.
    for i = 1, 3 do
        if (teachText[i] or "") ~= "" and not (res.lines[i] and res.lines[i].glyphs) then
            if i == 3 and not res.lines[3] then
                teachText[3] = nil      -- no name plate on screen: skip the name
            else
                return
            end
        end
    end
    local want, added, msgs = teachText, 0, {}
    teachText = nil
    for i = 1, 3 do
        local cs, L = chars(want[i] or ""), res.lines[i]
        if #cs > 0 and L then
            if #L.glyphs ~= #cs then
                msgs[#msgs + 1] = string.format("line %d: saw %d glyphs but you typed %d characters",
                                                i, #L.glyphs, #cs)
            else
                -- Only glyphs it got wrong or didn't know: one it already
                -- reads correctly teaches nothing.
                local was = chars(L.raw or "")
                for k, g in ipairs(L.glyphs) do
                    if was[k] ~= cs[k] and keep(cs[k], g, L.style) then
                        added = added + 1
                        local args = { C.good, "DEV learned new letter '", C.letter, cs[k],
                                       C.good, "'" .. STYLE_NAME[L.style or "d"]
                                       .. " (typed in; was read as \"" }
                        for _, v in ipairs(SWSH.marked(show(was[k] or ""), C.text)) do
                            args[#args + 1] = v
                        end
                        args[#args + 1] = C.good
                        args[#args + 1] = "\")"
                        SWSH.log(LV, table.unpack(args))
                    end
                end
            end
        end
    end
    if added > 0 then SWSH.reader.reshare(); statDue = true end
    teachMsg = (#msgs > 0 and (table.concat(msgs, "; ") .. ". ") or "")
               .. "Learned " .. added .. " glyphs."
    SWSH.log(LV, #msgs > 0 and C.warn or C.good, "DEV ", teachMsg)
end)

hook.Add("OverlayElement", "swsh.dev.teach", function(el)
    if el.id == "swsh.dev.teach" then el.children[5].text = teachMsg end
end)
