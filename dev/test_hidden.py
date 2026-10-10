#!/usr/bin/env python3
"""DEV ONLY. No guessing: hide each letter from the atlas in turn and read
every sample. Each position must come out as the right letter or [?] --
never another letter (an unseen N once read as H: "Hice one!").

    python3 dev/test_hidden.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import re
import gen_atlas as G
src=open('lua/autorun/05_atlas.lua',encoding='utf-8').read()
chars=sorted(set(re.findall(r'ch = "(.*?)"',src)))
data=[(G.nv12(p),t,k) for p,t,k in G.samples()]
wrong=0
for c in chars:
    if c in '\\"': continue
    L=G.runtime(); L.execute(src.encode()); L.execute(('local a={} for _,g in ipairs(SWSH.atlas) do if g.ch~=%r then a[#a+1]=g end end ATLAS=a' % c).encode())
    for (Y,UV),truth,kind in data:
        j=G.job(L,Y,kind=kind,UV=UV); j[b'learn']=False; r=L.globals().onJob(j)
        for i,want in zip((1,2,3),truth):
            ln=r[b'lines'][i]; t=ln[b'text'].decode() if ln else ''
            if not want: continue
            got=t.replace('[?]','\0')
            if len(got)!=len(want) or any(g!='\0' and g!=w for g,w in zip(got,want)):
                wrong+=1; print('MISREAD with',repr(c),'hidden:',t)
print('hidden-letter misreads:',wrong)
