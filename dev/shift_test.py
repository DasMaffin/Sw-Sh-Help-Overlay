#!/usr/bin/env python3
"""DEV ONLY. Robustness: every sample, shifted up to +-3 px, must still read
exactly; scenery strips must never read as subtitles.

    python3 dev/shift_test.py

Shifts the RGB picture and converts it to NV12 afterwards, as a capture
would -- shifting the NV12 planes themselves misaligns U and V.
"""
import glob, os, sys, tempfile
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_atlas as G

L = G.runtime()
L.execute(open(os.path.join(G.ROOT, "lua", "autorun", "05_atlas.lua"), "rb").read())
L.execute(b"ATLAS = SWSH.atlas")
tmp = tempfile.mkdtemp()


def shifted(path, dy, dx):
    im = np.asarray(Image.open(path).convert("RGB"))
    out = os.path.join(tmp, "s.png")
    Image.fromarray(np.roll(np.roll(im, dy, 0), dx, 1)).save(out)
    return G.nv12(out)


def read(Y, UV, kind, subs=None):
    old = G.SUBS
    if subs:
        G.SUBS = subs
    j = G.job(L, Y, kind=kind, UV=UV)
    G.SUBS = old
    j[b"learn"] = False
    r = L.globals().onJob(j)
    return [(r[b"lines"][i][b"text"].decode() if r[b"lines"][i] else "") for i in (1, 2, 3)]


bad = n = 0
for path, truth, kind in G.samples():
    want = truth if kind == "box" else truth[:2] + [""]
    for dy in (-3, -2, 0, 2, 3):
        for dx in (-3, -2, 0, 2, 3):
            got = read(*shifted(path, dy, dx), kind)
            n += 1
            if got != want:
                bad += 1
                print("FAIL", os.path.basename(path), dy, dx, got)
print(f"shifted reads wrong: {bad} of {n}")

fp = m = 0
for path in sorted(glob.glob(os.path.join(G.SAMPLES, "*.*"))):
    if path.endswith(".txt"):
        continue
    Y, UV = G.nv12(path)
    for dy in range(-900, -260, 40):
        got = read(Y, UV, "sub", [(a + dy, b + dy) for a, b in G.SUBS])
        m += 1
        if any(got):
            fp += 1
            print("SCENERY READ AS TEXT", os.path.basename(path), dy, got)
print(f"scenery false positives: {fp} of {m}")
