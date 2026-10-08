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
hook = { Add = function() end }
camera = { pictureRect = function() return 0, 0, 0, 0 end }
MOD_NAME = "swsh_text"
'''

def main():
    path = sys.argv[1]
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    Y = luma(path)
    h, w = Y.shape
    blob = Y.tobytes()

    wk = lua54.LuaRuntime(encoding=None)
    wk.execute(open(os.path.join(ROOT, "workers", "reader.lua"), "rb").read())
    pending = []

    L = lua54.LuaRuntime(encoding=None)
    L.execute(MOCK)

    def tolua(rt, v):
        if lua54.lua_type(v) == "table":
            return rt.table_from({k: tolua(rt, x) for k, x in v.items()})
        return v

    class Worker:
        def share(self, name, value): wk.globals()[name] = tolua(wk, value)
        def post(self, job):
            pending.append(tolua(L, wk.globals().onJob(tolua(wk, job)))); return True
        def collect(self):
            out = L.table(*pending); pending.clear(); return out
    W = Worker()
    L.globals().worker = L.table_from({b"spawn": lambda p: L.table_from({
        b"share": lambda self, n, v: W.share(n, v),
        b"post": lambda self, j: W.post(j),
        b"collect": lambda self: W.collect()})})

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
    mod = L.globals().SWSH[b"mod"]
    for _ in range(frames):
        mod[b"Think"](mod)
        mod[b"OnFrame"](mod, frame)

if __name__ == "__main__":
    main()
