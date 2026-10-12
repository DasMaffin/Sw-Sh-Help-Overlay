#!/usr/bin/env python3
"""DEV ONLY. Run the addon against screenshots with a mocked engine.

    pip install lupa pillow numpy rapidocr_onnxruntime
    python3 dev/sim.py [--all] [--say "Go! Scorbunny!"] dev/samples/hop_1.webp [...]

--all turns on the "read_all" setting (dialogue, system and cutscene text, not
only battle text). --png DIR saves each picture with the overlays drawn on it (DIR/<name>.png).
--dex opens the Pokedex checklist and paints it too; --hover X,Y puts the
pointer there (over a row: its "where to get it" card). --progress opens the
progress editor and paints it. --area NAME acts as if its banner was read.
--lua CODE runs a Lua snippet after that (a wheel turn, a click, a setting).
--say feeds a battle line to SWSH.onBattleText (and onCatchText, the battle
state's and the catch odds' status reader) first, as if
it had been read. After each picture the stats overlay is painted and what it
would draw is printed as [draw] lines.

Loads lua/autorun/*.lua in order and feeds each picture to OnFrame for a
while as a real NV12 frame. require("ocr") is a stand-in for the native module
(bin/ocr.dll, DasMaffin/RapidOcrOnnx branch mccp) with the same API: read()
queues a job and returns at once, poll() hands back a finished one a few
frames later. It runs RapidOCR's Python package (its bundled Chinese+English
PP-OCR model) with the module's line-mode preprocessing, so readings are
close to, not identical with, the DLL's English model.
"""
import os, sys, glob
import numpy as np
from PIL import Image
from lupa import lua54

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r'''
function log(...)
    local out = {}
    for _, v in ipairs({ ... }) do
        if type(v) ~= "table" then out[#out + 1] = tostring(v) end
    end
    print("[mod] " .. table.concat(out))
end
local files = {}
data = { read = function(f) return files[f] end, write = function(f, s) files[f] = s end }
local mod = { settings = {} }
function mod:set(k, v) self.settings[k] = v end
function mod:addSetting(k, l, kind, o, def) if def == nil then def = (kind == "bool") end self.settings[k] = def return self end
function mod:get(k) return self.settings[k] end
game = { register = function() return mod end, isActive = function() return true end }
overlay = { elements = {}, mouse = { -1, -1 } }
function overlay.screenW() return 1920 end
function overlay.screenH() return 1080 end
function overlay.mouseX() return overlay.mouse[1] end
function overlay.mouseY() return overlay.mouse[2] end
function overlay.isOpen() return false end
function overlay.add(id, spec) spec.id = id overlay.elements[id] = spec return spec end
hook = { fns = {} }
function hook.Add(ev, name, fn) hook.fns[name] = fn end
camera = { pictureRect = function() return 0, 0, 1920, 1080 end }
-- Paints an overlay element, printing its text calls; returns every call.
function sim_paint(id)
    local texts, ops = {}, {}
    local d = { w = function() return 1920 end, h = function() return 1080 end }
    for _, m in ipairs({ "rect", "outline", "line", "image", "text" }) do
        d[m] = function(_, ...) ops[#ops + 1] = { m, ... } end
    end
    function d.text(_, x, y, str, ...)
        texts[#texts + 1] = str
        ops[#ops + 1] = { "text", x, y, str, ... }
    end
    for _, fn in pairs(hook.fns) do fn(overlay.elements[id]) end
    overlay.elements[id].paint(d, overlay.elements[id])
    if #texts > 0 then print("[draw] " .. table.concat(texts, " | ")) end
    return ops
end
MOD_NAME = "Sw-Sh-Help-Overlay"
'''


def nv12(path):
    """(Y, UV) as an HD capture's NV12 frame holds them (limited-range BT.709)."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(float)
    R, G, B = im[..., 0], im[..., 1], im[..., 2]
    y = 16 + 0.1826 * R + 0.6142 * G + 0.0620 * B
    u = 128 - 0.1006 * R - 0.3386 * G + 0.4392 * B
    v = 128 + 0.4392 * R - 0.3989 * G - 0.0403 * B
    h, w = y.shape
    h2, w2 = h // 2 * 2, w // 2 * 2
    sub = lambda c: c[:h2, :w2].reshape(h2 // 2, 2, w2 // 2, 2).mean(axis=(1, 3))
    uv = np.zeros((h2 // 2, w), float)
    uv[:, 0:w2:2], uv[:, 1:w2:2] = sub(u), sub(v)
    c = lambda a: np.clip(a, 0, 255).astype(np.uint8)
    return c(y), c(uv)


class FakeOcr:
    """The ocr module's API, run synchronously but delivered a few polls late."""
    DELAY = 3          # polls before a job is "finished"

    def __init__(self, L):
        from rapidocr_onnxruntime import RapidOCR
        self.engine = RapidOCR()
        self.L, self.frame, self.job, self.done, self.next = L, None, None, None, 1

    def read_line(self, grey):
        # Line mode: pad with the median, recognition only. (The module also
        # trims the crop to the columns with text, which helps its English
        # model; this package's model reads worse trimmed, so the stand-in
        # doesn't. Readings here are for testing the Lua side, not the OCR.)
        med = int(np.median(grey))
        p = np.pad(grey, ((8, 8), (16, 16)), constant_values=med)
        # The recogniser itself: this package ignores use_det=False and runs
        # detection on any crop that isn't long and thin.
        r = self.engine.text_recognizer([np.stack([p] * 3, -1)])
        r = r[0] if isinstance(r, tuple) else r
        if not r or not r[0][0].strip():
            return "", 0.0
        return r[0][0].strip(), float(r[0][1])

    def read(self, frame, regions, opts=None):
        if self.job is not None:
            return None, "busy"
        Y = self.frame
        out = []
        for reg in regions.values():
            x, y, w, h = int(reg["x"]), int(reg["y"]), int(reg["w"]), int(reg["h"])
            text, score = self.read_line(Y[y:y + h, x:x + w])
            lines = [{"text": text, "score": score, "x0": x, "y0": y, "x1": x + w, "y1": y + h}] if text else []
            out.append({"key": reg["key"], "lines": lines})
        jid = self.next
        self.next += 1
        self.job = (jid, out, self.DELAY)
        return jid

    def poll(self):
        if self.job is None:
            return None
        jid, out, wait = self.job
        if wait > 0:
            self.job = (jid, out, wait - 1)
            return None
        self.job = None
        t = self.L.table_from
        regions = [t({"key": r["key"], "lines": self.L.table(*[t(l) for l in r["lines"]])}) for r in out]
        return t({"id": jid, "ms": 30, "regions": self.L.table(*regions)})


def render(path, ops, outdir):
    """Draws recorded DrawContext calls over the picture. The engine's font is
    monospaced, each character `size` wide: here each one is centred in its
    size x size cell, close enough to judge a layout."""
    from PIL import ImageDraw, ImageFont
    im = Image.open(path).convert("RGB").resize((1920, 1080))
    lay = Image.new("RGBA", im.size)
    g = ImageDraw.Draw(lay)
    fonts = {}
    def font(sz):
        if sz not in fonts:
            try: fonts[sz] = ImageFont.truetype("consola.ttf", sz)
            except OSError: fonts[sz] = ImageFont.load_default()
        return fonts[sz]
    for op in ops:
        kind, a = op[0], op[1:]
        col = lambda i: tuple(int(v) for v in a[i:i + 3]) + (int(a[i + 3]) if len(a) > i + 3 else 255,)
        if kind == "rect":
            x, y, w, h = a[:4]
            g.rectangle([x, y, x + w - 1, y + h - 1], fill=col(4))
        elif kind == "outline":
            x, y, w, h = a[:4]
            g.rectangle([x, y, x + w - 1, y + h - 1], outline=col(4))
        elif kind == "text":
            x, y, text, sz = a[0], a[1], str(a[2]), int(round(a[3]))
            f = font(max(6, int(sz * 1.15)))
            for i, ch in enumerate(text):
                g.text((x + i * sz + sz / 2, y + sz / 2), ch, font=f, fill=col(4), anchor="mm")
    im = Image.alpha_composite(im.convert("RGBA"), lay).convert("RGB")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, os.path.splitext(os.path.basename(path))[0] + ".png")
    im.save(out)
    print("[png]", out)


def main():
    args, say, read_all, png, dex, hover, area = sys.argv[1:], [], False, None, False, None, None
    lua, progress = [], False
    while args and args[0].startswith("--"):
        a = args.pop(0)
        if a == "--all": read_all = True
        elif a == "--say": say.append(args.pop(0))
        elif a == "--png": png = args.pop(0)
        elif a == "--dex": dex = True
        elif a == "--progress": progress = True
        elif a == "--lua": lua.append(args.pop(0))
        elif a == "--area": area = args.pop(0)
        elif a == "--hover": hover = [float(v) for v in args.pop(0).split(",")]
    paths = args or sorted(p for p in glob.glob(os.path.join(ROOT, "dev", "samples", "*.*"))
                                   if not p.endswith(".txt"))
    L = lua54.LuaRuntime(encoding="utf-8")
    L.execute(MOCK)
    fake = FakeOcr(L)
    L.globals().require = lambda name: L.table_from({
        "read": lambda frame, regions, opts=None: fake.read(frame, regions, opts),
        "poll": lambda: fake.poll(),
        "languages": lambda: L.table("en"),
        "version": lambda: "fake ocr (dev/sim.py)"})
    for f in sorted(glob.glob(os.path.join(ROOT, "lua", "autorun", "*.lua"))):
        L.execute(open(f, encoding="utf-8").read())
    mod = L.globals().SWSH["mod"]
    mod.settings["read_all"] = read_all
    mod.settings["pokedex"] = dex
    if hover:
        L.globals().overlay.mouse = L.table(*hover)
        for el in ("swsh.dex", "swsh.route", "swsh.progress"):
            L.globals().overlay.elements[el].hovered = True
    if area:                                              # as if its banner was read (twice)
        for _ in range(2): L.globals().SWSH.onArea(area, "")
    mod.settings["progress_editor"] = progress
    for code in lua:                                      # e.g. a wheel turn or a click, after the area
        L.execute(code)
    for line in say:
        print("== say:", line)
        L.globals().SWSH.onBattleText(L.table(line))
        L.globals().SWSH.onCatchText(L.table(line))       # as the reader's emit() does
        L.globals().SWSH.onProgressText(L.table(line))
        L.globals().SWSH.onBattleStateText(L.table(line))
        L.globals().SWSH.onStatusText(L.table(line))

    for path in paths:
        print("==", os.path.basename(path))
        Y, UV = nv12(path)
        h, w = Y.shape
        blob = Y.tobytes() + UV.tobytes()
        fake.frame = Y

        def region(self, x, y, rw, rh):
            x, y, rw, rh = int(x), int(y), int(rw), int(rh)
            return b"".join(blob[(y + r) * w + x:(y + r) * w + x + rw] for r in range(rh))
        frame = L.table_from({"width": lambda s: w, "height": lambda s: h,
                              "format": lambda s: "SDL_PIXELFORMAT_NV12", "region": region})
        L.globals().string_dummy = None
        for _ in range(60):
            mod.Think(mod)
            mod.OnFrame(mod, frame)
        ops = [list(o.values()) for o in L.globals().sim_paint("swsh.stats").values()]
        for el in ("swsh.route", "swsh.routeinfo", "swsh.catch"):
            ops += [list(o.values()) for o in L.globals().sim_paint(el).values()]
        if dex:
            ops += [list(o.values()) for o in L.globals().sim_paint("swsh.dex").values()]
        if progress:
            ops += [list(o.values()) for o in L.globals().sim_paint("swsh.progress").values()]
        if mod.settings["evolutions"]:
            ops += [list(o.values()) for o in L.globals().sim_paint("swsh.evos").values()]
        if png:
            render(path, ops, png)
        # The picture goes away (a blank frame), so the next one prints afresh.
        # Mid grey: dark grey would pass for the battle box's ground.
        blank = Y * 0 + 128
        fake.frame = blank
        blob = blank.tobytes() + UV.tobytes()
        for _ in range(30):
            mod.Think(mod)
            mod.OnFrame(mod, frame)


if __name__ == "__main__":
    main()
