-- DEV ONLY -- the self-teaching worker. Not part of the shipping mod.
--
-- dev/gen_teach.py prepends `CHARSET` (every distinct character), `DICT` (every message of one language, one per
-- line, with [VAR ...] placeholders turned into line breaks) and `SPACED`
-- (whether the language puts spaces between words) to this file and writes
-- dev/teach/teach_<lang>.lua, which 90_dev_teach.lua spawns as a worker.
--
-- One job is one line as the reader saw it, with "\1" standing for each
-- glyph it didn't know. We look for that line in the game's own text with
-- each "\1" as a wildcard for one character. If every place it fits agrees
-- on what the wildcards are, those are the letters -- and the answer comes
-- back. Anything ambiguous comes back as a reason instead, never a guess.

local MIN_KNOWN = 4          -- fewer known characters than this: too vague
local MAX_UNKNOWN = 3        -- more unknowns than this: wait for a better box
local MAX_HITS = 2000        -- stop scanning after this many candidate places

-- One character that isn't a space: a lead byte and its continuation bytes.
local CHAR = "[^%s\128-\191][\128-\191]*"
-- What an unknown glyph may stand for. Usually one character -- but where the
-- font kerns two of them into each other ("w." in "you know.") the reader cuts
-- them out as ONE shape, so an unknown may also be a touching pair. That pair
-- is then learned as a unit, which reads back correctly.
local WIDTH = { "(" .. CHAR .. ")", "(" .. CHAR .. CHAR .. ")" }

local function escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

local function boundary(c) return c == "" or c == " " or c == "\n" end

-- Every place `pat` fits as whole words (or, with `whole`, as one whole
-- entry: the name plate's text is a name and nothing else). Returns the one
-- answer they agree on, false if they disagree, nil if there is none.
local function search(pat, whole)
    local answer, hits, init = nil, 0, 1
    while hits < MAX_HITS do
        local found = { DICT:find(pat, init) }
        local s, e = found[1], found[2]
        if not s then break end
        init = s + 1
        -- A displayed line is whole words: the game only wraps at spaces.
        local before, after = DICT:sub(s - 1, s - 1), DICT:sub(e + 1, e + 1)
        local fits
        if whole then
            fits = (before == "" or before == "\n") and (after == "" or after == "\n")
        else
            fits = not SPACED or (boundary(before) and boundary(after))
        end
        if fits then
            hits = hits + 1
            local key = table.concat(found, "\0", 3)
            if answer == nil then
                answer = { key = key, chars = { table.unpack(found, 3) }, hits = 1 }
            elseif answer.key ~= key then
                return false
            else
                answer.hits = hits
            end
        end
    end
    return answer
end

local solve

function onJob(job)
    -- { charset = true }: every character this language's text uses.
    if job.charset then return { charset = CHARSET } end
    local res = solve(job.raw, job.whole)
    if res.chars or res.why ~= "not in the game text" then
        res.key = job.key
        return res
    end
    -- Not found as it reads. The screen may be showing a name (or number)
    -- where the game text has a placeholder: retry with each distinct whole
    -- word of the reading standing in for "\3" -- every occurrence of it,
    -- since a name is the same each time. All words that fit must agree.
    local found, seen = nil, {}
    for word in job.raw:gmatch("%w+") do
        if not seen[word] then
            seen[word] = true
            local sub = (" " .. job.raw .. " "):gsub("(%W)" .. word .. "(%W)", "%1\3%2")
            sub = sub:gsub("(%W)" .. word .. "(%W)", "%1\3%2"):sub(2, -2)
            local r = solve(sub, job.whole)
            if r.chars then
                local key = table.concat(r.chars, "\0")
                if found and found.key ~= key then
                    return { key = job.key, why = "ambiguous" }
                end
                found = found or { key = key, chars = r.chars, hits = r.hits, word = word }
            end
        end
    end
    if found then
        return { key = job.key, chars = found.chars, hits = found.hits,
                 placeholder = found.word }
    end
    return { key = job.key, why = "not in the game text" }
end

function solve(raw, whole)
    local pieces, unknown, known = {}, 0, 0
    for piece, mark in (raw .. "\2"):gmatch("([^\1\2]*)([\1\2])") do
        pieces[#pieces + 1] = escape(piece)
        known = known + utf8.len((piece:gsub(" ", "")))
        if mark == "\1" then unknown = unknown + 1 end
    end
    if unknown == 0 then return { why = "nothing unknown" } end
    if unknown > MAX_UNKNOWN then return { why = "too many unknowns" } end
    -- A name is short ("Hop" is 3), but as a whole entry it is pinned at
    -- both ends, which is what a long known stretch buys a dialogue line.
    if known < (whole and 1 or MIN_KNOWN) then return { why = "too little known text" } end

    -- Fewest pairs first: a reading where every unknown is one character is
    -- the likely one, and only if none fits are touching pairs considered.
    -- Within one level, every fitting reading must agree.
    for pairs = 0, unknown do
        local answer = nil
        for combo = 0, (1 << unknown) - 1 do
            local n, c = 0, combo
            while c > 0 do n = n + (c & 1); c = c >> 1 end
            if n == pairs then
                local parts = {}
                for k = 1, unknown do
                    parts[#parts + 1] = pieces[k]
                    parts[#parts + 1] = WIDTH[((combo >> (k - 1)) & 1) + 1]
                end
                parts[#parts + 1] = pieces[unknown + 1]
                local a = search(table.concat(parts), whole)
                if a == false or (a and answer and a.key ~= answer.key) then
                    return { why = "ambiguous" }
                end
                answer = answer or a
            end
        end
        if answer then
            return { chars = answer.chars, hits = answer.hits }
        end
    end
    return { why = "not in the game text" }
end
