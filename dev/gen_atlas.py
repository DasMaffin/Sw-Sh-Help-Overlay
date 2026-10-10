#!/usr/bin/env python3
"""Build lua/autorun/05_atlas.lua from labelled screenshots, and check it.

Runs the addon's own workers/reader.lua (through lupa, `pip install lupa`), so
the fingerprints in the atlas are made by exactly the code that will match
against them in the engine.

    python3 dev/gen_atlas.py          # rebuild the atlas from dev/samples
                                      # + every dev/learned/*.txt
    python3 dev/gen_atlas.py --check  # read every sample with the atlas

Samples are 1920x1080 screenshots listed in dev/samples/truth.txt as
"<file>\t<line 1>|<line 2>[\t<speaker name>[\t<kind>]]", kind "box" (the
default) or "sub" (a cutscene subtitle: white text over the scene). dev/learned/*.txt are learned.txt files copied
out of an install's data folder (written by the DEV teaching layer); their
glyphs are baked in after the samples', up to PER_CHAR per character. The geometry below must match SWSH.BOX in
lua/autorun/10_mod.lua.
"""
import os, re, sys
import numpy as np
from PIL import Image
from lupa import lua54

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLES = os.path.join(ROOT, "dev", "samples")
OUT = os.path.join(ROOT, "lua", "autorun", "05_atlas.lua")

X0, X1 = 400, 1492                      # text columns, 1080p
LINES = [(889, 956), (967, 1034)]       # [top, bottom) rows of each line
NX0, NX1 = 345, 728                     # the name plate's text columns
NAME = (792, 859)                       # ... and rows (white on dark)
SX0, SX1 = 404, 1516                    # cutscene subtitles: columns (even)
SUBS = [(922, 989), (1000, 1067)]       # ... and rows of each line
# The fingerprint version, from lua/autorun/10_mod.lua.
FEATURES = int(re.search(r"SWSH\.FEATURES\s*=\s*(\d+)",
                         open(os.path.join(ROOT, "lua", "autorun", "10_mod.lua"),
                              encoding="utf-8").read()).group(1))
PER_CHAR = 8                            # distinct variants kept per character
SAME = 2.0      # closer than this to a kept variant: already readable, skipped


def dist(a, b):
    """The reader's match distance (workers/reader.lua: SHAPE_W = 30)."""
    _, w1, t1, b1, f1, _ = a
    _, w2, t2, b2, f2, _ = b
    return 30 * (abs(w1 - w2) + abs(t1 - t2) + abs(b1 - b2)) + sum(abs(x - y) for x, y in zip(f1, f2))


def add(entries, count, e):
    """Keep e unless its character already has PER_CHAR variants, or one
    almost exactly like it. The same letter renders a pixel differently
    depending on where it falls on the grid, and keeping the FIRST few
    samples once kept five of one variant and none of the other."""
    key = e[0]          # one atlas: the plate's bold cut is just more variants
    if count.get(key, 0) >= PER_CHAR:
        return
    if any(x[0] == e[0] and dist(x, e) < SAME for x in entries):
        return
    count[key] = count.get(key, 0) + 1
    entries.append(e)


def luma(path):
    """Limited-range BT.709 luma, which is what an HD capture's Y plane holds."""
    return nv12(path)[0]


# Every sample is also learned from at these sub-pixel offsets: a letter
# renders a little differently depending on where it falls on the pixel grid,
# and the game puts it anywhere. Learning a few in-between positions up front
# covers that instead of leaving it to in-game teaching.
OFFSETS = [(0, 0), (0.25, 0), (0.5, 0), (0.75, 0), (0, 0.5), (0.5, 0.5)]


def nv12(path, dx=0, dy=0):
    """(Y, UV) as an HD capture's NV12 frame holds them: limited-range BT.709
    luma, and a half-size plane of interleaved U,V (one pair per 2x2).
    dx, dy shift the picture by a fraction of a pixel first."""
    img = Image.open(path).convert("RGB")
    if dx or dy:
        img = img.transform(img.size, Image.AFFINE, (1, 0, -dx, 0, 1, -dy),
                            resample=Image.BILINEAR)
    im = np.asarray(img).astype(float)
    R, G, B = im[..., 0], im[..., 1], im[..., 2]
    y = 16 + 0.1826 * R + 0.6142 * G + 0.0620 * B
    u = 128 - 0.1006 * R - 0.3386 * G + 0.4392 * B
    v = 128 + 0.4392 * R - 0.3989 * G - 0.0403 * B
    h, w = y.shape
    h2, w2 = h // 2 * 2, w // 2 * 2
    sub = lambda c: c[:h2, :w2].reshape(h2 // 2, 2, w2 // 2, 2).mean(axis=(1, 3))
    uv = np.empty((h2 // 2, w2), float)
    uv[:, 0::2], uv[:, 1::2] = sub(u), sub(v)
    c = lambda a: np.clip(a, 0, 255).astype(np.uint8)
    return c(y), c(uv)


def runtime():
    L = lua54.LuaRuntime(encoding=None)
    with open(os.path.join(ROOT, "workers", "reader.lua"), "rb") as f:
        L.execute(f.read())
    return L


def job(L, Y, name=True, kind="box", UV=None):
    def line(x0, x1, a, b, **kw):
        d = {b"rows": L.table(*[Y[y, x0:x1].tobytes() for y in range(a, b)]), b"w": x1 - x0}
        d.update({k.encode(): v for k, v in kw.items()})
        return L.table_from(d)
    if kind == "sub":
        def over(a, b):
            rows = [UV[y, SX0:SX1].tobytes() for y in range(a // 2, (b + 1) // 2)]
            return L.table_from({b"uv": L.table(*rows), b"ox": SX0 % 2, b"oy": a % 2})
        lines = [line(SX0, SX1, a, b, style=b"s", over=over(a, b)) for a, b in SUBS]
    else:
        lines = [line(X0, X1, a, b, style=b"d") for a, b in LINES]
        if name:
            lines.append(line(NX0, NX1, *NAME, style=b"n", light=True, whole=True))
    return L.table_from({b"seq": 1, b"lines": L.table(*lines), b"learn": True})


def atlas_table(L, entries):
    return L.table(*[L.table_from({b"ch": c.encode(), b"w": w, b"t": t, b"b": b,
                                   b"f": L.table(*f), b"s": st.encode()})
                     for c, w, t, b, f, st in entries])


def read(L, path, kind="box", dx=0, dy=0):
    Y, UV = nv12(path, dx, dy)
    r = L.globals().onJob(job(L, Y, kind=kind, UV=UV))
    out = []
    for i in (1, 2, 3):
        ln = r[b"lines"][i]
        if ln is None:
            out.append(("", []))
            continue
        gl = [(g[b"w"], g[b"t"], g[b"b"], list(g[b"f"].values()))
              for g in ln[b"glyphs"].values()]
        out.append((ln[b"text"].decode("utf-8", "replace"), gl))
    return out


def samples():
    with open(os.path.join(SAMPLES, "truth.txt"), encoding="utf-8") as f:
        for line in f:
            if line.strip():
                f = line.rstrip("\n").split("\t")
                lines = f[1].split("|")
                lines.append(f[2] if len(f) > 2 else "")      # the name plate
                kind = f[3] if len(f) > 3 and f[3] else "box"
                yield os.path.join(SAMPLES, f[0]), lines, kind


def build():
    entries, count = [], {}
    for path, truth, kind in samples():
        for dx, dy in OFFSETS:
            for i, ((text, glyphs), want) in enumerate(
                    zip(read(runtime(), path, kind, dx, dy), truth)):
                st = "n" if i == 2 else "d"
                chars = [c for c in want if c != " "]
                if len(chars) != len(glyphs):
                    print(f"skip {os.path.basename(path)} {want!r} at +{dx},{dy}: "
                          f"{len(glyphs)} glyphs for {len(chars)} characters")
                    continue
                for c, (w, t, b, f) in zip(chars, glyphs):
                    add(entries, count, (c, w, t, b, f, st))
    stale = 0
    learned_dir = os.path.join(ROOT, "dev", "learned")
    for name in sorted(os.listdir(learned_dir)) if os.path.isdir(learned_dir) else []:
        if not name.endswith(".txt"):
            continue
        with open(os.path.join(learned_dir, name), encoding="utf-8") as lf:
            for line in lf:
                p = line.rstrip("\n").split("\t")
                # Only glyphs measured by the current reader (7th column =
                # SWSH.FEATURES); older ones don't compare with these.
                if len(p) != 7 or int(p[6] or 0) != FEATURES:
                    stale += 1
                    continue
                c, st = p[0], p[5] or "d"
                add(entries, count, (c, float(p[1]), float(p[2]), float(p[3]),
                                     [float(v) for v in p[4].split(",")], st))
    if stale:
        print(f"ignored {stale} learned glyphs from an older reader (not v{FEATURES})")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("-- GENERATED by dev/gen_atlas.py from dev/samples -- do not edit.\n")
        f.write("-- Glyph fingerprints of the Sword/Shield dialogue font; see\n")
        f.write("-- workers/reader.lua for what the numbers mean.\n")
        f.write("SWSH = SWSH or {}\nSWSH.atlas = {\n")
        for c, w, t, b, fv, st in entries:
            q = c.replace("\\", "\\\\").replace('"', '\\"')
            f.write('    { ch = "%s", w = %.4f, t = %.4f, b = %.4f, f = { %s } },  -- %s\n'
                    % (q, w, t, b, ", ".join("%.3g" % v for v in fv),
                       "name plate" if st == "n" else "dialogue"))
        f.write("}\n")
    print(f"wrote {len(entries)} glyphs, {len(count)} characters: " + "".join(sorted(count)))
    return entries


def check(entries):
    for path, truth, kind in samples():
        L = runtime()
        L.globals().ATLAS = atlas_table(L, entries)
        for (text, _), want in zip(read(L, path, kind), truth):
            if want or text:
                print(("ok  " if text == want else "BAD ") + text)


if __name__ == "__main__":
    e = build()
    if "--check" in sys.argv:
        check(e)
