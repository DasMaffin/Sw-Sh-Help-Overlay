#!/usr/bin/env python3
"""Run the addon against a screenshot with a mocked engine.

    python3 dev/sim.py dev/samples/hop_1.webp [frames]

Loads lua/autorun/*.lua in order, feeds the picture to OnFrame as an NV12
frame, runs the worker synchronously and prints what the mod logs.
"""
import os, sys, glob
from lupa import lua54
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_atlas import luma, ROOT

MOCK = r'''
local logs = {}
function log(m) print(m) end
data = { files = {} }
function data.read(n) return data.files[n] end
function data.append(n, s) data.files[n] = (data.files[n] or "") .. s return true end
function data.delete(n) data.files[n] = nil return true end
local mod = { settings = {} }
function mod:addSetting(k, l, kind, o, def) if def == nil then def = (kind == "bool") end self.settings[k] = def return self end
function mod:get(k) return self.settings[k] end
game = { register = function() return mod end, isActive = function() return true end }
overlay = { els = {} }
function overlay.add(id, spec) spec.id = id overlay.els[id] = spec return spec end
hook = { h = {} }
function hook.Add(ev, name, fn) hook.h[ev] = hook.h[ev] or {} hook.h[ev][name] = fn end
function hook.Run(ev, ...) for _, fn in pairs(hook.h[ev] or {}) do fn(...) end end
camera = { pictureRect = function() return 0, 0, 0, 0 end }
MOD_NAME = "swsh_text"
'''

# SIM_RICH=1: the newer engine log() -- levels and colour tables (ANSI here).
RICH = r'''
local names = { [1] = "Verbose", [2] = "Important" }
LOG_LEVEL = { VERBOSE = 1, IMPORTANT = 2, next = 16 }
function LOG_LEVEL.add(n) local v = LOG_LEVEL.next LOG_LEVEL.next = v + 1 names[v] = n return v end
function log(...)
    local a, lv, out = { ... }, 1, {}
    local i = 1
    if math.type(a[1]) == "integer" and names[a[1]] and #a > 1 then lv = a[1]; i = 2 end
    for k = i, #a do
        local v = a[k]
        if type(v) == "table" then
            out[#out + 1] = string.format("\27[38;2;%d;%d;%dm", v[1] or v.r, v[2] or v.g, v[3] or v.b)
        else out[#out + 1] = tostring(v) end
    end
    print("[mod] <" .. names[lv] .. "> " .. table.concat(out) .. "\27[0m")
end
'''

def main():
    path = sys.argv[1]
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    Y = luma(path)
    h, w = Y.shape
    blob = Y.tobytes()

    def tolua(rt, v):
        if lua54.lua_type(v) == "table":
            return rt.table_from({k: tolua(rt, x) for k, x in v.items()})
        return v

    def spawn(path):
        p = os.path.join(ROOT, path.decode())
        if not os.path.exists(p):
            print("worker missing:", path.decode()); return None
        wk = lua54.LuaRuntime(encoding=None)
        wk.execute(open(p, "rb").read())
        pending = []
        def post(self, job):
            pending.append(tolua(L, wk.globals().onJob(tolua(wk, job)))); return True
        def collect(self):
            out = L.table(*pending); pending.clear(); return out
        def share(self, n, v): wk.globals()[n] = tolua(wk, v)
        return L.table_from({b"share": share, b"post": post, b"collect": collect})

    L = lua54.LuaRuntime(encoding=None)
    L.execute(MOCK)
    if os.environ.get("SIM_RICH"):
        L.execute(RICH)
    L.globals().worker = L.table_from({b"spawn": spawn})

    class Frame:
        pass
    def region(self, x, y, rw, rh):
        x, y, rw, rh = int(x), int(y), int(rw), int(rh)
        return b"".join(blob[(y + r) * w + x:(y + r) * w + x + rw] for r in range(rh))
    frame = L.table_from({
        b"width": lambda s: w, b"height": lambda s: h,
        b"format": lambda s: b"SDL_PIXELFORMAT_NV12", b"region": region})

    for f in sorted(glob.glob(os.path.join(ROOT, "lua", "autorun", "*.lua"))):
        L.execute(open(f, "rb").read())
    drop = os.environ.get("SIM_DROP", "")    # pretend these aren't in the atlas
    if drop:
        L.execute(('local d = "%s" local a = {} for _, g in ipairs(SWSH.atlas) do '
                   'if not d:find(g.ch, 1, true) then a[#a+1] = g end end SWSH.atlas = a'
                   % drop).encode())
    mod = L.globals().SWSH[b"mod"]
    for _ in range(frames):
        mod[b"Think"](mod)
        mod[b"OnFrame"](mod, frame)

if __name__ == "__main__":
    main()
