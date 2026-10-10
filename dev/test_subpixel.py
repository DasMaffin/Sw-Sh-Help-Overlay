#!/usr/bin/env python3
"""DEV ONLY. Sub-pixel robustness: every sample shifted by fractions of a
pixel (offsets gen_atlas does NOT train on) must read with almost no [?]
and never a wrong letter.

    python3 dev/test_subpixel.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import tempfile, numpy as np
from PIL import Image
import gen_atlas as G
L=G.runtime(); L.execute(open('lua/autorun/05_atlas.lua','rb').read()); L.execute(b'ATLAS = SWSH.atlas')
tmp=tempfile.mkdtemp(); unk=tot=wrong=0
for path,truth,kind in G.samples():
    im=Image.open(path).convert('RGB')
    for dx,dy in ((0.33,0),(0.5,0),(0.67,0),(0,0.5),(0.5,0.5),(-0.33,0.25)):
        sh=im.transform(im.size, Image.AFFINE, (1,0,-dx,0,1,-dy), resample=Image.BILINEAR)
        p=os.path.join(tmp,'s.png'); sh.save(p); Y,UV=G.nv12(p)
        j=G.job(L,Y,kind=kind,UV=UV); j[b'learn']=False
        r=L.globals().onJob(j)
        for i,want in zip((1,2,3), truth if kind=='box' else truth[:2]):
            ln=r[b'lines'][i]; t=ln[b'text'].decode() if ln else ''
            if not want: continue
            n=len([c for c in want if c!=' ']); tot+=n; unk+=t.count('[?]')
            if '[?]' not in t and t!=want: wrong+=1; print('WRONG', os.path.basename(path), dx,dy, t)
print(f'unknown glyphs after sub-pixel shifts: {unk} of {tot}; wrong lines: {wrong}')
