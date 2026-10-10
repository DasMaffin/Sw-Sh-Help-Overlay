"""DEV ONLY. Writes lua/autorun/05_dex.lua from Showdown's pokedex.json.

    curl -o pokedex.json https://play.pokemonshowdown.com/data/pokedex.json
    python3 dev/gen_dex.py pokedex.json lua/autorun/05_dex.lua
"""
import json, sys, unicodedata, re
src, out = sys.argv[1], sys.argv[2]
dex = json.load(open(src, encoding='utf-8'))
def key(n):
    n = unicodedata.normalize('NFKD', n).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]', '', n)
base, galar = {}, {}
for e in dex.values():
    if not (1 <= e.get('num', 0) <= 898) or e.get('isNonstandard') in ('CAP', 'Custom'):
        continue
    f = e.get('forme')
    if f is None: base[key(e['name'])] = e
    elif f == 'Galar': galar[key(e['baseSpecies'])] = e
rows = []
for k, e in sorted(base.items(), key=lambda kv: kv[1]['num']):
    g = galar.get(k)
    use = g or e
    s = use['baseStats']
    name = unicodedata.normalize('NFKD', e['name'].replace('’', "'")).encode('ascii', 'ignore').decode()
    rows.append('    %-14s = { %-22s %-20s %3d, %3d, %3d, %3d, %3d, %3d%s },' % (
        k if re.match(r'^[a-z]\w*$', k) else '["%s"]' % k,
        json.dumps(name) + ',',
        json.dumps('/'.join(use['types'])) + ',',
        s['hp'], s['atk'], s['def'], s['spa'], s['spd'], s['spe'],
        ', galar = true' if g else ''))
hdr = '''-- Base stats for every Pokemon up to Gen 8 (#1-898), from Pokemon Showdown's
-- data (play.pokemonshowdown.com/data/pokedex.json). Generated -- don't edit
-- by hand.
--
-- Keyed by the name in lower case, letters and digits only ("farfetchd",
-- "mrmime", "flabebe"), so an OCR reading is a direct lookup after the same
-- folding (SWSH.dexKey). Where a species has a Galarian form, that form's
-- types and stats are used (galar = true): it's the one met in Galar. Names
-- are plain ASCII for the overlay's built-in font.
--   key = { name, types, hp, atk, def, spa, spd, spe [, galar = true] }

SWSH = SWSH or {}

SWSH.DEX = {
'''
open(out, 'w', encoding='utf-8', newline='\n').write(hdr + '\n'.join(rows) + '\n}\n')
print(len(rows), 'species,', len(galar), 'galar')
