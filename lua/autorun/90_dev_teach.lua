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
local PER_CHAR  = 5          -- samples kept per character; more adds nothing
local LANGS     = { "en", "de", "fr", "it", "es", "ko", "ja-hiragana",
                    "ja-katakana", "ch-simplified", "ch-traditional" }

SWSH.mod:addSetting("dev_selfteach", "DEV: learn unknown letters from the game's text",
                    "bool", nil, true)
SWSH.mod:addSetting("dev_lang", "DEV: game language (restart to apply)",
                    "choice", LANGS, "en")

------------------------------------------------------------ learned.txt --
-- One glyph per line: char <TAB> w <TAB> t <TAB> b <TAB> f1,f2,...
-- (no load() in the sandbox, so a format simple enough to parse by hand).
local learned, perChar = {}, {}

local function parse(s)
    for line in s:gmatch("[^\n]+") do
        local ch, w, t, b, fs = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
        if ch then
            local f = {}
            for v in fs:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
            learned[#learned + 1] = { ch = ch, w = tonumber(w), t = tonumber(t),
                                      b = tonumber(b), f = f }
            perChar[ch] = (perChar[ch] or 0) + 1
        end
    end
end
parse(data.read(LEARNED) or "")

function SWSH.extraGlyphs() return learned end

-- Save one glyph. Returns false when that character already has enough.
local function keep(ch, g)
    if (perChar[ch] or 0) >= PER_CHAR then return false end
    local f = {}
    for i, v in ipairs(g.f) do f[i] = string.format("%.3g", v) end
    data.append(LEARNED, string.format("%s\t%.4f\t%.4f\t%.4f\t%s\n",
        ch, g.w, g.t, g.b, table.concat(f, ",")))
    learned[#learned + 1] = { ch = ch, w = g.w, t = g.t, b = g.b, f = g.f }
    perChar[ch] = (perChar[ch] or 0) + 1
    return true
end

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
    log(MOD_NAME .. ": DEV self-teaching is off -- no dev/teach/teach_" .. lang
        .. ".lua (build it with dev/gen_teach.py)")
end

local tried   = {}           -- raw line -> true: asked already, don't repeat
local waiting = {}           -- raw line -> the unknown glyphs' fingerprints
local lastRaw = { "", "" }   -- per line, to only ask about a stable reading

hook.Add("SwSh.Result", "swsh.dev.selfteach", function(res)
    if not teacher or not SWSH.mod:get("dev_selfteach") then return end
    for i, L in ipairs(res.lines) do
        local raw = L.raw or ""
        local stable = raw == lastRaw[i]
        lastRaw[i] = raw
        if stable and L.missing > 0 and L.glyphs and not tried[raw] then
            -- Glyphs line up with the non-space characters of `raw`.
            local unknown, k = {}, 0
            for _, c in ipairs(chars(raw)) do
                k = k + 1
                if c == "\1" then unknown[#unknown + 1] = L.glyphs[k] end
            end
            if teacher:post({ key = raw, raw = raw }) then
                tried[raw] = true
                waiting[raw] = unknown
            end
        end
    end
end)

hook.Add("SwSh.Think", "swsh.dev.selfteach", function()
    if not teacher then return end
    for _, ans in ipairs(teacher:collect()) do
        local glyphs = waiting[ans.key]
        waiting[ans.key] = nil
        if ans.chars and glyphs and #ans.chars == #glyphs then
            local line, n = ans.key, 0
            for _, c in ipairs(ans.chars) do
                line = line:gsub("\1", c, 1)
            end
            for j, c in ipairs(ans.chars) do
                if keep(c, glyphs[j]) then
                    n = n + 1
                    log(string.format("%s: DEV learned new letter '%s' from \"%s\" (read as \"%s\")",
                                      MOD_NAME, c, line, show(ans.key)))
                end
            end
            if n > 0 then SWSH.reader.reshare() end
        elseif ans.why then
            log(string.format("%s: DEV could not learn from \"%s\": %s",
                              MOD_NAME, show(ans.key), ans.why))
        end
    end
end)

------------------------------------------------------------ manual teach --
local teachText, teachMsg = nil, ""

local panel = overlay.add("swsh.dev.teach", {
    mode = "menu", x = 40, y = 120, w = 560, h = 150,
    children = {
        { type = "label", x = 12, y = 10, text = "DEV: teach glyphs (type the box's text, | between lines)" },
        { type = "textbox", x = 12, y = 36, w = 536, h = 28,
          placeholder = "How about it, Lucy? Let's race!|Bet I can make it..." },
        { type = "button", x = 12, y = 74, w = 120, h = 28, text = "Learn" },
        { type = "button", x = 142, y = 74, w = 160, h = 28, text = "Forget learned" },
        { type = "label", x = 12, y = 112, w = 536, h = 34, text = "" },
    },
})
panel.children[3].onClick = function()
    local t = panel.children[2].text or ""
    if not SWSH.state.open then
        teachMsg = "No dialogue box on screen."
    elseif t == "" then
        teachMsg = "Type the text first."
    else
        local a, b = t:match("^([^|]*)|?(.*)$")
        teachText = { a, b }
        SWSH.reader.requestGlyphs()
        teachMsg = "Learning from the next read..."
    end
end
panel.children[4].onClick = function()
    data.delete(LEARNED)
    learned, perChar, tried = {}, {}, {}
    SWSH.reader.reshare()
    teachMsg = "Learned glyphs cleared."
    log(MOD_NAME .. ": DEV learned glyphs cleared")
end

hook.Add("SwSh.Result", "swsh.dev.manual", function(res)
    if not teachText then return end
    -- Wait for the read that carries every line's fingerprints.
    for i = 1, 2 do
        if (teachText[i] or "") ~= "" and not res.lines[i].glyphs then return end
    end
    local want, added, msgs = teachText, 0, {}
    teachText = nil
    for i = 1, 2 do
        local cs, L = chars(want[i] or ""), res.lines[i]
        if #cs > 0 then
            if #L.glyphs ~= #cs then
                msgs[#msgs + 1] = string.format("line %d: saw %d glyphs but you typed %d characters",
                                                i, #L.glyphs, #cs)
            else
                -- Only glyphs it got wrong or didn't know: one it already
                -- reads correctly teaches nothing.
                local was = chars(L.raw or "")
                for k, g in ipairs(L.glyphs) do
                    if was[k] ~= cs[k] and keep(cs[k], g) then
                        added = added + 1
                        log(string.format("%s: DEV learned new letter '%s' (typed in; was read as \"%s\")",
                                          MOD_NAME, cs[k], show(was[k] or "")))
                    end
                end
            end
        end
    end
    if added > 0 then SWSH.reader.reshare() end
    teachMsg = (#msgs > 0 and (table.concat(msgs, "; ") .. ". ") or "")
               .. "Learned " .. added .. " glyphs."
    log(MOD_NAME .. ": DEV " .. teachMsg)
end)

hook.Add("OverlayElement", "swsh.dev.teach", function(el)
    if el.id == "swsh.dev.teach" then el.children[5].text = teachMsg end
end)
