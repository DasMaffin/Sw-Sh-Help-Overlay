"""DEV ONLY. Writes lua/autorun/06_trainers.lua and docs/wild.md from the
JSON that dev/pknx-export dumps out of your own Sword/Shield romfs:

    dotnet run -c Release --project dev/pknx-export -- ROMs/out ROMs/export
    python3 dev/gen_romdata.py ROMs/export

Trainers: every Pokemon's stats at its level, worked out here from the ROM's
base stats (right form included) and the trainer's fixed IVs, EVs and nature,
so the addon only looks them up. Wilds: which species are where, by area and
how they're met, with each version's exclusives marked.
"""
import json, os, re, sys, unicodedata
from collections import defaultdict

src = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load = lambda n: json.load(open(os.path.join(src, n), encoding='utf-8'))

def key(n):                       # gen_dex.py's folding: "Pokémon Trainer" -> "pokemontrainer"
    n = n.replace('♀', 'f').replace('♂', 'm')      # Nidoran: the sign is the species
    n = unicodedata.normalize('NFKD', n).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]', '', n)

def ascii(n):                     # for the overlay's built-in font
    n = n.replace('’', "'").replace('♀', ' F').replace('♂', ' M')
    return unicodedata.normalize('NFKD', n).encode('ascii', 'ignore').decode()

def lua(s): return json.dumps(s)

# ------------------------------------------------------------- trainers --
# Natures in the game's order: up = n // 5, down = n % 5, over
# Atk, Def, Spe, SpA, SpD (index into our HP, Atk, Def, SpA, SpD, Spe).
NAT_STAT = [1, 2, 5, 3, 4]

def stats(base, ivs, evs, lv, nat):
    out = []
    for i in range(6):
        core = (2 * base[i] + ivs[i] + evs[i] // 4) * lv // 100
        if i == 0:
            out.append(1 if base[0] == 1 else core + lv + 10)
            continue
        m = 10
        if nat // 5 != nat % 5:
            if NAT_STAT[nat // 5] == i: m = 11
            if NAT_STAT[nat % 5] == i: m = 9
        out.append((core + 5) * m // 10)
    return out

rows = []
for t in load('trainers.json'):
    if t['name'] in ('', '-') or not t['team'] or t['class'].startswith('#'):
        continue
    team = []
    for p in t['team']:
        if not p['level'] or not p['base']:
            continue
        s = stats(p['base'], p['ivs'], p['evs'], p['level'], p['nature_id'])
        team.append('{ %s, %d, %s, %s }' % (
            lua(key(p['species'])), p['level'], ', '.join(map(str, s)),
            lua(p['nature'] if p['nature_id'] < 25 else '')))
    if team:
        rows.append('    { %s, %s,\n        %s },' % (
            lua(key(t['class'] + t['name'])), lua(ascii(t['class'] + ' ' + t['name'])),
            ',\n        '.join(team)))

hdr = '''-- Every in-game trainer's team, from the game's own data (Sword/Shield 1.3,
-- dumped with pkNX). An in-game trainer's Pokemon have fixed IVs, EVs and
-- nature, so their stats at their level are known exactly: worked out ahead
-- in dev/gen_romdata.py -- don't edit by hand.
--
--   { key, "Class Name", { species key, level, HP, Atk, Def, SpA, SpD, Spe, nature }, ... }
-- key: class and name folded like SWSH.dexKey ("pokemontrainerhop"); the same
-- trainer comes up once per battle (Hop has a team for each starter).

SWSH = SWSH or {}

SWSH.TRAINERS = {
'''
out = os.path.join(root, 'lua', 'autorun', '06_trainers.lua')
open(out, 'w', encoding='utf-8', newline='\n').write(hdr + '\n'.join(rows) + '\n}\n')
print(len(rows), 'trainers ->', out)

# -------------------------------------------------------------- wilds --
FORM = {('Basculin', 1): 'Blue-Striped', ('Gastrodon', 1): 'East Sea', ('Shellos', 1): 'East Sea',
        ('Indeedee', 1): 'female', ('Meowstic', 1): 'female', ('Sinistea', 1): 'Antique',
        ('Pumpkaboo', 1): 'Average', ('Pumpkaboo', 2): 'Large', ('Pumpkaboo', 3): 'Super Size',
        ('Meowth', 2): 'Galarian'}
def name(s):
    if s['form']:
        return '%s (%s)' % (s['species'], FORM.get((s['species'], s['form']), 'Galarian'))
    return s['species']

# Zone names carry how they're met: "Bridge Field (Surfing)". Some
# parentheses are the place itself ("Route 9 (in Circhester Bay)").
HOW = {'Surfing': 'surfing', 'Surfing - River': 'surfing', 'Surfing - Ocean': 'surfing',
       'Flying': 'flying', 'Ground': 'overworld', '2': 'overworld', '3': 'overworld',
       'Puddles': 'puddles', 'Beach': 'beach', 'Sharpedo': 'Sharpedo spots',
       'Garbage': 'overworld', 'Lunatone/Solrock': 'overworld'}
WILD_AREA = {"Rolling Fields", "Dappled Grove", "Watchtower Ruins", "East Lake Axewell",
             "West Lake Axewell", "Axew's Eye", "South Lake Miloch", "Giant's Seat",
             "North Lake Miloch", "Motostoke Riverbank", "Bridge Field", "Stony Wilderness",
             "Dusty Bowl", "Giant's Mirror", "Hammerlocke Hills", "Giant's Cap",
             "Lake of Outrage", "Dusty Bowl and Giant's Mirror"}
ARMOR = {"Fields of Honor", "Loop Lagoon", "Training Lowlands", "Challenge Beach",
         "Soothing Wetlands", "Forest of Focus", "Brawlers' Cave", "Challenge Road",
         "Courageous Cavern", "Warm-up Tunnel", "Potbottom Desert", "Workout Sea",
         "Stepping-Stone Sea", "Insular Sea", "Honeycalm Sea", "Honeycalm Island"}
TUNDRA = {"Slippery Slope", "Frostpoint Field", "Giant's Bed", "Old Cemetery", "Snowslide Slope",
          "Tunnel to the Top", "Path to the Peak", "Giant's Foot", "Roaring-Sea Caves",
          "Frigid Sea", "Three-Point Pass", "Ballimere Lake", "Lakeside Cave",
          "Giant's Bed / Giant's Foot"}
REGIONS = [('Galar', None), ('Wild Area', WILD_AREA), ('Isle of Armor', ARMOR), ('Crown Tundra', TUNDRA)]

def place(zone, kind):
    zone = re.sub(r'\s+', ' ', zone)
    how = 'overworld' if kind == 'symbol' else 'grass (!)'
    m = re.match(r'^(.*?) \(([^()]*)\)$', zone)
    if m and m[2] in HOW:
        zone, how = m[1], HOW[m[2]] if kind == 'symbol' else how
    return zone, how

order, rows = [], defaultdict(dict)     # (area, how, mon) -> version -> info
for ver in ('Sword', 'Shield'):
    w = load('wild_%s.json' % ver.lower())
    for kind in ('symbol', 'hidden'):
        for z in w[kind]:
            for t in z['tables']:
                area, how = place(z['zone'], kind)
                if t['weather'] == 'Shaking Trees': how = 'shaking trees'
                elif t['weather'] == 'Fishing': how = 'fishing'
                if area not in order: order.append(area)
                for s in t['slots']:
                    r = rows[(area, how, name(s))].setdefault(ver, {'lv': [99, 0], 'rate': [100, 0], 'wx': set()})
                    r['lv'] = [min(r['lv'][0], t['min']), max(r['lv'][1], t['max'])]
                    r['rate'] = [min(r['rate'][0], s['rate']), max(r['rate'][1], s['rate'])]
                    if how not in ('shaking trees', 'fishing'): r['wx'].add(t['weather'])

def region(a):
    for n, s in REGIONS[1:]:
        if a in s: return n
    return 'Galar'

def span(p): return str(p[0]) if p[0] == p[1] else '%d-%d' % tuple(p)

lines = ['# Wild Pokemon by area', '',
         'From the game\'s own encounter tables (Sword/Shield 1.3, dumped with pkNX).',
         'Generated by `dev/gen_romdata.py` -- don\'t edit by hand.', '',
         '- **How**: *overworld* = walking around in the open; *grass (!)* = the',
         '  rustling "!" grass; surfing, flying, fishing and shaking trees as named.',
         '- **Weather**: *any* = in every weather the area has (most areas have one).',
         '- **Rate**: the encounter slot\'s chance, over the weathers it appears in.',
         '- **Only in**: a version exclusive. Blank = in both.', '']
# Exclusives per area: in one version's list for the area and not the other's.
have = defaultdict(lambda: defaultdict(set))
seen = defaultdict(set)                 # the weathers each area has at all
for (a, h, n), v in rows.items():
    for ver, r in v.items():
        have[a][ver].add(n)
        seen[a] |= r['wx']
for reg, _ in REGIONS:
    areas = [a for a in order if region(a) == reg]
    lines += ['## ' + reg, '']
    for a in areas:
        lines += ['### ' + a, '', '| Pokemon | Lv | How | Weather | Rate | Only in |', '|---|---|---|---|---|---|']
        mine = sorted((k for k in rows if k[0] == a), key=lambda k: (k[1], -max(r['rate'][1] for r in rows[k].values()), k[2]))
        for k in mine:
            v = rows[k]
            r = v.get('Sword') or v['Shield']
            excl = '' if len(v) == 2 else next(iter(v))
            # The other version may have it elsewhere in this area (another way).
            if excl and k[2] in have[a]['Shield' if excl == 'Sword' else 'Sword']: excl += ' (this way)'
            wx = set().union(*(x['wx'] for x in v.values()))
            if len(wx) >= len(seen[a]) or not wx: wxs = 'any'
            elif len(wx) > len(seen[a]) / 2: wxs = 'not ' + ', '.join(sorted(seen[a] - wx))
            else: wxs = ', '.join(sorted(wx))
            wxs = wxs.replace('Normal Weather', 'clear')
            lines.append('| %s | %s | %s | %s | %s%% | %s |' % (k[2], span(r['lv']), k[1], wxs, span(r['rate']), excl))
        lines.append('')
os.makedirs(os.path.join(root, 'docs'), exist_ok=True)
out = os.path.join(root, 'docs', 'wild.md')
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
print(len(order), 'areas,', len(rows), 'rows ->', out)

# ------------------------------------------------------------- pokedex --
# The species in the game, national order, with their regional numbers; and
# for each, where it's met in each version (best way per area), for the
# Pokedex checklist's "where to get it" card.
WX = {'Normal Weather': 'clear', 'Overcast': 'cloudy', 'Raining': 'rain', 'Thunderstorm': 'storm',
      'Intense Sun': 'sun', 'Snowing': 'snow', 'Snowstorm': 'blizzard', 'Sandstorm': 'sand',
      'Heavy Fog': 'fog'}
where = defaultdict(lambda: defaultdict(dict))      # key -> ver -> area -> (rate, how, wx)
for (a, h, n), v in rows.items():
    k = key(n.split(' (')[0])
    for ver, r in v.items():
        wx = '' if not r['wx'] or len(r['wx']) >= len(seen[a]) else '/'.join(WX[w] for w in sorted(r['wx'], key=list(WX).index)[:2]) + ('+' if len(r['wx']) > 2 else '')
        best = where[k][ver].get(a)
        if not best or r['rate'][1] > best[0]:
            where[k][ver][a] = (r['rate'][1], h, wx)
out_rows = []
for s in load('species.json'):
    if not s['present']: continue
    k = key(s['species'])
    wv = []
    for ver, tag in (('Sword', 'sw'), ('Shield', 'sh')):
        places = sorted(where[k][ver].items(), key=lambda kv: (-kv[1][0], kv[0]))
        if places:
            wv.append('%s = { %s }' % (tag, ', '.join('{ %s, %d, %s }' % (
                lua(ascii(a)), r, lua(h + (', ' + wx if wx else ''))) for a, (r, h, wx) in places)))
    out_rows.append('    { %d, %s, %d, %d, %d%s },' % (
        s['dex'], lua(k), s['galar'], s['armor'], s['crown'],
        (', ' + ', '.join(wv)) if wv else ''))
hdr = '''-- The Pokedex checklist's data: every species in Sword/Shield (1.3, with
-- both DLCs), in national order, with its number in each regional dex (0 = not
-- in it) and where it's met in the wild in each version -- per area the best
-- way and its rate, best first. From the game's own data; generated by
-- dev/gen_romdata.py -- don't edit by hand.
--   { national, key (SWSH.DEX), galar, armor, crown,
--     sw = { { area, rate %, how }, ... }, sh = { ... } }

SWSH = SWSH or {}

SWSH.POKEDEX = {
'''
out = os.path.join(root, 'lua', 'autorun', '07_pokedex.lua')
open(out, 'w', encoding='utf-8', newline='\n').write(hdr + '\n'.join(out_rows) + '\n}\n')
print(len(out_rows), 'species ->', out)

# --------------------------------------------------------------- areas --
# What the game's area banner can name ("Rolling Fields", "Route 9"), each with
# everything met there in each version: per species its ways -- how, best
# rate, levels, weather. A zone counts under its own name and under the place
# its parentheses name ("Route 9 (in Circhester Bay)": Route 9 AND Circhester
# Bay); "Dusty Bowl and Giant's Mirror" under both.
def banners(area):
    m = re.match(r"^(?:City|Town) of (.*)$", area)
    if m: return [m[1]]
    m = re.match(r"^(.*?) \((?:in |on )(.*)\)$", area)
    if m: return [m[1], m[2]]
    m = re.match(r"^(.*?) \(.*\)$", area)
    if m: return [m[1]]
    return re.split(r" and | / ", area) if (' and ' in area or ' / ' in area) else [area]

ways = defaultdict(lambda: defaultdict(lambda: defaultdict(dict)))   # banner -> ver -> name -> how -> info
bseen, bregion = defaultdict(set), {}
for (a, h, n), v in rows.items():
    for b in banners(a):
        bseen[b] |= seen[a]
        bregion.setdefault(b, region(a))
        for ver, r in v.items():
            w = ways[b][ver][n].setdefault(h, {'lv': [99, 0], 'rate': 0, 'wx': set()})
            w['lv'] = [min(w['lv'][0], r['lv'][0]), max(w['lv'][1], r['lv'][1])]
            w['rate'] = max(w['rate'], r['rate'][1])
            w['wx'] |= r['wx']

def wxText(wx, seen):
    if not wx or len(wx) >= len(seen): return ''
    names = [WX[w] for w in sorted(wx, key=list(WX).index)]
    if len(wx) > len(seen) / 2:
        return 'not ' + '/'.join(WX[w] for w in sorted(seen - wx, key=list(WX).index))
    return '/'.join(names)

out_rows = []
for b in sorted(ways, key=lambda b: (order.index(next(a for a in order if b in banners(a))), b)):
    parts = ['region = %s' % lua(bregion[b])]
    for ver, tag in (('Sword', 'sw'), ('Shield', 'sh')):
        mons = []
        for n, hows in ways[b][ver].items():
            ws = sorted(hows.items(), key=lambda kv: -kv[1]['rate'])
            mons.append((max(w['rate'] for _, w in ws), n, ws))
        mons.sort(key=lambda m: (-m[0], m[1]))
        parts.append('%s = {\n%s }' % (tag, ',\n'.join('        { %s, %s, { %s } }' % (
            lua(key(n.split(' (')[0])), lua(ascii(n)),
            ', '.join('{ %s, %d, %d, %d, %s }' % (lua(h), w['rate'], w['lv'][0], w['lv'][1], lua(wxText(w['wx'], bseen[b])))
                      for h, w in ws)) for _, n, ws in mons)))
    out_rows.append('    [%s] = { %s },' % (lua(ascii(b)), ',\n      '.join(parts)))
hdr = '''-- What is met where, by the name the game's area banner shows ("Rolling
-- Fields", "Route 9"): per version, each species with its ways of meeting it
-- there, best rate first. From the game's own encounter tables; generated by
-- dev/gen_romdata.py -- don't edit by hand.
--   [name] = { region, sw = { { key, "Name (form)", { { how, rate %, lo, hi, weather }, ... } }, ... }, sh = ... }
-- weather: "" = any; else the ones it needs ("rain/storm") or "not fog".

SWSH = SWSH or {}

SWSH.AREAS = {
'''
out = os.path.join(root, 'lua', 'autorun', '08_areas.lua')
open(out, 'w', encoding='utf-8', newline='\n').write(hdr + '\n'.join(out_rows) + '\n}\n')
print(len(out_rows), 'banner areas ->', out)
