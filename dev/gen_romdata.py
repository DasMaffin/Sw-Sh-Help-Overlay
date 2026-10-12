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
SPOTS = {'Garbage', 'Lunatone/Solrock'}
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
        # A special spot keeps its name: the panel shows it as where in the place.
        zone, how = m[1] if m[2] not in SPOTS else zone, HOW[m[2]] if kind == 'symbol' else how
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
# Bay); "Dusty Bowl and Giant's Mirror" under both. Any other parentheses
# name a separate part of the place ("Route 2 (High Level)"), kept with each
# way so the panel can say so.
PARTS = {'High Level': 'High-level area', 'Low Level': 'Low-level area', 'Near Station': 'Near the station',
         'Garbage': 'Garbage area', 'Lunatone/Solrock': 'Lunatone/Solrock spot'}
def part(area):
    m = re.match(r"^.*? \((?!in |on )(.*)\)$", area)
    return PARTS.get(m[1], m[1]) if m else ''

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
            w = ways[b][ver][n].setdefault((h, part(a)), {'lv': [99, 0], 'rate': 0, 'wx': set()})
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
# Like pkmn_stats' FRLG floors: a way (grass, fishing...) is one row, but a
# place's separate parts ("Route 2 (High Level)") keep their own odds and
# levels in `per` -- never one number for both: Zigzagoon is 2% on Route 2
# and 50% in its high-level part. p is the best part, pLo the worst.
def wayLua(b, h, parts):
    parts = sorted(parts, key=lambda pw: (pw[0] != '', -pw[1]['rate']))   # the place itself first
    rates = [w['rate'] for _, w in parts]
    lo, hi = min(w['lv'][0] for _, w in parts), max(w['lv'][1] for _, w in parts)
    wx = set().union(*(w['wx'] for _, w in parts))
    out = '{ %s, %d, %d, %d, %s, %d' % (lua(h), max(rates), lo, hi, lua(wxText(wx, bseen[b])), min(rates))
    if any(pt for pt, _ in parts):
        out += ', { %s }' % ', '.join('{ %s, %d, %d, %d, %s }' % (
            lua(pt or b), w['rate'], w['lv'][0], w['lv'][1], lua(wxText(w['wx'], bseen[b]))) for pt, w in parts)
    return out + ' }'

for b in sorted(ways, key=lambda b: (order.index(next(a for a in order if b in banners(a))), b)):
    parts = ['region = %s' % lua(bregion[b])]
    for ver, tag in (('Sword', 'sw'), ('Shield', 'sh')):
        mons = []
        for n, hows in ways[b][ver].items():
            byHow = defaultdict(list)
            for (h, pt), w in hows.items(): byHow[h].append((pt, w))
            # Order: met in the place itself first, then best rate there.
            ws = sorted(byHow.items(), key=lambda kv: (
                -max([w['rate'] for pt, w in kv[1] if not pt] or [-1]), -max(w['rate'] for _, w in kv[1])))
            only = all(pt for _, ps in ws for pt, _ in ps)       # only in a separate part: listed last
            best = max([w['rate'] for _, ps in ws for pt, w in ps if not pt] or [w['rate'] for _, ps in ws for _, w in ps])
            mons.append((only, best, n, ws))
        mons.sort(key=lambda m: (m[0], -m[1], m[2]))
        parts.append('%s = {\n%s }' % (tag, ',\n'.join('        { %s, %s, { %s } }' % (
            lua(key(n.split(' (')[0])), lua(ascii(n)),
            ', '.join(wayLua(b, h, ps) for h, ps in ws)) for _, _, n, ws in mons)))
    out_rows.append('    [%s] = { %s },' % (lua(ascii(b)), ',\n      '.join(parts)))
hdr = '''-- What is met where, by the name the game's area banner shows ("Rolling
-- Fields", "Route 9"): per version, each species with its ways of meeting it
-- there, the place's own first. From the game's own encounter tables;
-- generated by dev/gen_romdata.py -- don't edit by hand.
--   [name] = { region, sw = { { key, "Name (form)", { way, ... } }, ... }, sh = ... }
--   way = { how, p, lo, hi, weather, pLo[, per] }
-- p / pLo: best / worst rate over the place's parts (equal without parts).
-- weather: "" = any; else the ones it needs ("rain/storm") or "not fog".
-- per: only when the place has separate parts, like pkmn_stats' floors --
--   { { part, rate, lo, hi, weather }, ... }, part = the place's own name
--   for the place itself, else "High-level area", "Near the station"...

SWSH = SWSH or {}

SWSH.AREAS = {
'''
out = os.path.join(root, 'lua', 'autorun', '08_areas.lua')
open(out, 'w', encoding='utf-8', newline='\n').write(hdr + '\n'.join(out_rows) + '\n}\n')
print(len(out_rows), 'banner areas ->', out)

# ------------------------------------------------------------- specials --
# Gifts, in-game trades and fixed ("static") Pokemon, per banner name, like
# pkmn_stats' FRLG specials. The game keeps their places in its scripts, so:
#   gifts + statics: PKHeX's Encounters8.cs (species, level, location id,
#     weather), with its SwSh location names -- both fetched into ROMs/pkhex/
#     (see README), read here, not committed;
#   trades: levels and wants from the game (specials.json), places by hand.
# Story battles (ScriptedNoMarks) are left out, but not the legendaries.
pk = os.path.join(root, 'ROMs', 'pkhex')
SPECIES = {s['dex']: s['species'] for s in load('species.json')}
FORM2 = {('Raichu', 1): 'Alolan', ('Sandshrew', 1): 'Alolan', ('Vulpix', 1): 'Alolan', ('Meowth', 1): 'Alolan',
         ('Exeggutor', 1): 'Alolan', ('Marowak', 1): 'Alolan', ('Diglett', 1): 'Alolan', ('Meowth', 2): 'Galarian',
         ('Keldeo', 1): 'Resolute', ('Indeedee', 1): 'Female', ('Lycanroc', 1): 'Midnight', ('Darmanitan', 2): 'Galarian',
         ('Rotom', 1): 'Heat', ('Rotom', 2): 'Wash', ('Rotom', 3): 'Frost', ('Rotom', 4): 'Fan', ('Rotom', 5): 'Mow'}
def spName(dex, form):
    sp = SPECIES.get(dex, '#%d' % dex)
    return '%s (%s)' % (sp, FORM2[(sp, form)]) if (sp, form) in FORM2 else name({'species': sp, 'form': form})
WEATHER = {'Normal': 'clear', 'Overcast': 'cloudy', 'Raining': 'rain', 'Thunderstorm': 'storm',
           'Intense_Sun': 'sun', 'Snowing': 'snow', 'Snowstorm': 'blizzard', 'Sandstorm': 'sand',
           'Heavy_Fog': 'fog', 'Stormy': 'rain/storm', 'Icy': 'snow/blizzard'}
BASE_WX = ['clear', 'cloudy', 'rain', 'storm', 'sun', 'snow', 'blizzard', 'sand', 'fog']
def weatherText(w):
    if not w or w.startswith('All'): return ''
    if w == 'No_Sun_Sand': return 'not sun/sand'
    got = {b for p in w.split('|') for b in WEATHER.get(p.strip(), p.strip()).split('/')}
    if len(got) > len(BASE_WX) / 2:          # most of them: say which not
        return 'not ' + '/'.join(b for b in BASE_WX if b not in got) if len(got) < len(BASE_WX) else ''
    return '/'.join(b for b in BASE_WX if b in got)
# A place inside another: listed under both banners.
INSIDE = {'Battle Tower': ['Wyndon'], 'Master Dojo': ['Fields of Honor'], 'Wild Area Station': ['Rolling Fields']}
# One sentence each on how you get it (the game's scripts aren't read: by hand).
DIG = 'The Diglett hunter in the Fields of Honor gives it once you have found %d of the Alolan Diglett.'
GIFT_HOW = {'Grookey': 'Leon lets you choose one of the three at the very start of the game.',
            'Scorbunny': 'Leon lets you choose one of the three at the very start of the game.',
            'Sobble': 'Leon lets you choose one of the three at the very start of the game.',
            'Charmander': "Leon gives it at his house in Postwick once you're Champion.",
            'Type: Null': 'Given at the Battle Tower in Wyndon after the post-game story.',
            'Toxel': 'The Pokemon Nursery worker on Route 5 gives you a Toxel Egg.',
            'Pikachu': "A man in the Wild Area Station gives it if the Switch has a Let's Go Pikachu save.",
            'Eevee': "A man in the Wild Area Station gives it if the Switch has a Let's Go Eevee save.",
            'Dracozolt': 'Cara Liss on Route 6 restores it from a Fossilized Bird and a Fossilized Drake.',
            'Arctozolt': 'Cara Liss on Route 6 restores it from a Fossilized Bird and a Fossilized Dino.',
            'Dracovish': 'Cara Liss on Route 6 restores it from a Fossilized Fish and a Fossilized Drake.',
            'Arctovish': 'Cara Liss on Route 6 restores it from a Fossilized Fish and a Fossilized Dino.',
            'Bulbasaur': "Mustard lets you choose it or Squirtle after the dojo's first trial.",
            'Squirtle': "Mustard lets you choose it or Bulbasaur after the dojo's first trial.",
            'Kubfu': "Mustard gives it to you during the Isle of Armor story, after the dojo's trials.",
            'Porygon': 'Given at the Master Dojo after you beat Mustard at the end of the Isle of Armor story.',
            'Meowth (Alolan)': DIG % 5, 'Slowpoke': DIG % 10, 'Vulpix (Alolan)': DIG % 20,
            'Sandshrew (Alolan)': DIG % 30, 'Raichu (Alolan)': DIG % 40, 'Marowak (Alolan)': DIG % 50,
            'Exeggutor (Alolan)': DIG % 75, 'Diglett (Alolan)': DIG % 150,
            'Rowlet': DIG % 100 + ' Only if your starter was Grookey.',
            'Litten': DIG % 100 + ' Only if your starter was Scorbunny.',
            'Popplio': DIG % 100 + ' Only if your starter was Sobble.',
            'Glastrier': 'Crown Tundra story: grow the Iceroot Carrot to call it to the shrine. You get it or Spectrier, not both.',
            'Spectrier': 'Crown Tundra story: grow the Shaderoot Carrot to call it to the shrine. You get it or Glastrier, not both.',
            'Cosmog': 'An old woman in a Freezington house gives it after the Crown Tundra story.',
            'Poipole': 'Given in the Max Lair once you have caught Ultra Beasts on Dynamax Adventures, after the Crown Tundra story.'}
# Legendaries waiting in one place (keyed by species).
BIRD = 'After the Crown Tundra story, Peony sends you to Dyna Tree Hill; then it roams here. Chase it down to battle.'
SWORDS = "After the Crown Tundra story, follow its footprints; it waits here for you."
REGI = "After the Crown Tundra story, solve the Giant's Bed temple's puzzle, then this ruin's puzzle to wake it."
LEGEND_HOW = {'Articuno': BIRD, 'Zapdos': BIRD, 'Moltres': BIRD, 'Cobalion': SWORDS, 'Terrakion': SWORDS, 'Virizion': SWORDS,
              'Keldeo': 'Appears here once you have caught Cobalion, Terrakion and Virizion.',
              'Regirock': REGI, 'Regice': REGI, 'Registeel': REGI,
              'Regieleki': "Solve the puzzle here and choose it or Regidrago; you only get one.",
              'Regidrago': "Solve the puzzle here and choose it or Regieleki; you only get one.",
              'Regigigas': "Bring Regirock, Regice, Registeel, Regieleki and Regidrago to the temple.",
              'Calyrex': 'Crown Tundra story: battle it at the shrine once its steed is back.'}
LEGEND = {144, 145, 146, 377, 378, 379, 486, 638, 639, 640, 647, 894, 895, 896, 897, 898}
specials = defaultdict(list)          # banner -> [(key, name, tag, how, lv, ver)]
def addSpecial(places, n, tag, how, lv, ver):
    for p in places:
        for b in [p] + INSIDE.get(p, []):
            row = (key(n.split(' (')[0]), ascii(n), tag, how, lv, ver)
            if row not in specials[b]: specials[b].append(row)

if os.path.exists(os.path.join(pk, 'Encounters8.cs')):
    locs = open(os.path.join(pk, 'text_swsh_00000_en.txt'), encoding='utf-8-sig').read().splitlines()
    lst, gift = None, False
    for line in open(os.path.join(pk, 'Encounters8.cs'), encoding='utf-8'):
        m = re.search(r'readonly \S+ (\w+) =', line)
        if m:
            lst = m[1] if m[1].startswith('Static') else None
            gift = lst == 'StaticSWSH'
            continue
        if '#region Static Part 1' in line: gift = False
        if not lst or not re.match(r'\s*new\(', line): continue
        f = lambda k: (re.search(r'\b%s\s*=\s*([^,}]+)' % k, line) or [None, None])[1]
        dex, lv, loc = int(f('Species')), int(f('Level')), int(f('Location'))
        if loc < 0 or (f('ScriptedNoMarks') and dex not in LEGEND and not gift): continue
        cross = re.search(r'Crossover = new\(([^)]*)\)', line)
        places = [locs[loc]] + ([locs[int(c)] for c in cross[1].split(',')] if cross else [])
        n = spName(dex, int(f('Form') or 0))
        ver = {'StaticSW': 'Sword', 'StaticSH': 'Shield'}.get(lst, '')
        wm = re.search(r'Weather = ([\w| ]+)', line)
        wx = weatherText(wm[1].strip() if wm else '')
        if gift:
            addSpecial(places, n, 'Gift', GIFT_HOW.get(n, 'Gift'), lv, ver)
        else:
            sp = n.split(' (')[0]
            how = LEGEND_HOW.get(sp) or ('A strong one stands in the open here; walk into it to battle'
                                         + (' (only in %s weather).' % wx if wx else '.'))
            if dex in LEGEND and sp in LEGEND_HOW: how = 'Legendary. ' + how
            addSpecial(places, n, 'Static', how, lv, ver)
else:
    print('no ROMs/pkhex/Encounters8.cs: gifts and statics left out')

# Trades: index in the game's table -> the trader's place. Regina's
# regional-form trades (0-11) move around the Isle of Armor: left out.
TRADE_AT = {12: 'Turffield', 13: 'Motostoke', 14: 'Hulbury', 15: 'Hammerlocke', 16: 'Stow-on-Side',
            17: 'Stow-on-Side', 18: 'Ballonlea', 19: 'Circhester', 20: 'Circhester', 21: 'Spikemuth', 22: 'Wyndon'}
TRADE_VER = {16: 'Sword', 17: 'Shield', 19: 'Sword', 20: 'Shield'}
TRADE_WHERE = {12: 'in the Gym lobby', 13: 'in the Pokemon Center', 14: 'by the market', 15: 'outside the Vault',
               16: 'on a rooftop', 17: 'on a rooftop', 18: 'in the Gym entrance hall', 21: 'behind a stall at the end of town',
               22: 'in a house'}
for t in load('specials.json')['trades']:
    if t['i'] not in TRADE_AT: continue
    want = spName(next(d for d, s in SPECIES.items() if s == t['wants']), t['wants_form'])
    where = TRADE_WHERE.get(t['i'])
    addSpecial([TRADE_AT[t['i']]], spName(t['dex'], t['form']), 'Trade',
               'Someone %s will trade it for your %s.' % (where or 'here', ascii(want)), t['level'], TRADE_VER.get(t['i'], ''))

out_rows = []
for b in sorted(specials):
    out_rows.append('    [%s] = {\n%s },' % (lua(ascii(b)), ',\n'.join('        { %s, %s, %s, %s, %d, %s }' % (
        lua(k), lua(n), lua(tag), lua(how), lv, lua(ver)) for k, n, tag, how, lv, ver in specials[b])))
hdr = '''-- Gifts, in-game trades and fixed ("static") Pokemon by the name the game's
-- area banner shows -- the route panel lists them under the wild ones, as
-- pkmn_stats' FRLG specials. Generated by dev/gen_romdata.py (PKHeX's
-- Encounters8 places for gifts and statics, trades' places by hand) -- don't
-- edit by hand.
--   [name] = { { key, "Name (form)", tag, how, level, version ("" = both) }, ... }

SWSH = SWSH or {}

SWSH.SPECIALS = {
'''
out = os.path.join(root, 'lua', 'autorun', '09_specials.lua')
open(out, 'w', encoding='utf-8', newline='\n').write(hdr + '\n'.join(out_rows) + '\n}\n')
print(len(out_rows), 'places with specials ->', out)

# ----------------------------------------------------------- evolutions --
# The game's own evolution table (evolutions.json), each method in a short
# sentence for the evolutions panel.
def a(item): return ('an ' if item[:1] in tuple('AEIOU') else 'a ') + item
def evoText(e):
    m, arg, lv = e['method'], ascii(e['arg']) if e['arg'] else None, e['level']
    to = SPECIES[e['to']]
    return {
        'LevelUp': 'Level %d' % lv,
        'LevelUpFriendship': 'Level up with high friendship',
        'LevelUpFriendshipMorning': 'Level up with high friendship during the day',
        'LevelUpFriendshipNight': 'Level up with high friendship at night',
        'Trade': 'Trade it',
        'TradeHeldItem': 'Trade it holding %s' % a(arg or ''),
        'TradeShelmetKarrablast': 'Trade it for a %s' % ('Shelmet' if to == 'Escavalier' else 'Karrablast'),
        'UseItem': 'Use %s' % a(arg or ''),
        'UseItemMale': 'Use %s on a male' % a(arg or ''),
        'UseItemFemale': 'Use %s on a female' % a(arg or ''),
        'LevelUpATK': 'Level %d with Attack higher than Defense' % lv,
        'LevelUpDEF': 'Level %d with Defense higher than Attack' % lv,
        'LevelUpAeqD': 'Level %d with Attack equal to Defense' % lv,
        'LevelUpNinjask': 'Level %d' % lv,
        'LevelUpHeldItemDay': 'Level up holding %s during the day' % a(arg or ''),
        'LevelUpHeldItemNight': 'Level up holding %s at night' % a(arg or ''),
        'LevelUpKnowMove': 'Level up knowing %s' % arg,
        'LevelUpWithTeammate': 'Level up with %s in the party' % a(arg or ''),
        'LevelUpMale': 'Level %d (male)' % lv,
        'LevelUpFemale': 'Level %d (female)' % lv,
        'LevelUpFormFemale1': 'Level %d (female)' % lv,
        'LevelUpAffection50MoveType': 'Level up with high friendship knowing a Fairy move',
        'LevelUpMoveType': 'Level %d with a Dark-type Pokemon in the party' % lv,
        'LevelUpWeather': 'Level %d while it rains (or fog) outside' % lv,
        'LevelUpMorning': 'Level %d during the day' % lv,
        'LevelUpNight': 'Level %d at night' % lv,
        'LevelUpDusk': 'Level %d in the evening (7-8 pm)' % lv,
        'LevelUpVersion': 'Level %d' % lv,
        'LevelUpInverted': 'Level %d holding the Switch upside down' % lv,
        'CriticalHitsInBattle': 'Land 3 critical hits in one battle',
        'HitPointsLostInBattle': 'Lose 49+ HP without fainting, then pass under the Dusty Bowl rock arch',
        'Spin': 'Spin around while it holds a Sweet',
        'LevelUpNatureAmped': 'Level %d (its nature decides the form)' % lv,
        'LevelUpNatureLowKey': 'Level %d (its nature decides the form)' % lv,
        'TowerOfDarkness': 'Clear the Tower of Darkness (Isle of Armor)',
        'TowerOfWaters': 'Clear the Tower of Waters (Isle of Armor)',
    }.get(m)
EVO_VER = {791: 'Sword', 792: 'Shield'}
# Forms that aren't regional ones, by their own names.
EVO_FORM = {('Lycanroc', 2): 'Dusk', ('Lycanroc', 1): 'Midnight', ('Rockruff', 1): 'Own Tempo', ('Toxtricity', 0): 'Amped',
            ('Toxtricity', 1): 'Low Key', ('Polteageist', 1): 'Antique', ('Urshifu', 0): 'Single Strike',
            ('Urshifu', 1): 'Rapid Strike'}
def evoName(dex, form):
    sp = SPECIES[dex]
    if sp == 'Alcremie': return sp                # its creams: one species to own
    if (sp, form) in EVO_FORM: return sp + (' (%s)' % EVO_FORM[(sp, form)] if EVO_FORM[(sp, form)] else '')
    return spName(dex, form)    # Cosmoem: Solgaleo / Lunala
evo_rows, seen = [], set()
if os.path.exists(os.path.join(src, 'evolutions.json')):
    for e in load('evolutions.json'):
        t = evoText(e)
        if not t: continue             # Feebas by beauty: not in this game
        fn, tn = ascii(evoName(e['from'], e['from_form'])), ascii(evoName(e['to'], e['to_form']))
        # The same form carries over (Alolan Vulpix -> Alolan Ninetales, East
        # Sea Shellos -> East Sea Gastrodon).
        if '(' in fn and e['to_form'] == e['from_form'] and (SPECIES[e['to']], e['to_form']) not in EVO_FORM:
            tn = ascii(SPECIES[e['to']]) + fn[fn.index(' ('):]
        row = (key(SPECIES[e['from']]), fn, key(SPECIES[e['to']]), tn, t, EVO_VER.get(e['to'], ''))
        if row in seen: continue
        seen.add(row)
        evo_rows.append(row)
        if e['method'] == 'LevelUpNinjask':     # Shedinja: the game's side effect, not in the table
            evo_rows.append((row[0], row[1], 'shedinja', 'Shedinja',
                             'Level %d with a free party slot and a spare Poke Ball' % e['level'], ''))
    hdr = '''-- Every evolution in the game, from its own evolution table: what into
-- what and how, in a short sentence (the evolutions panel, 47_evos.lua).
-- Generated by dev/gen_romdata.py -- don't edit by hand.
--   { from key, "From (form)", to key, "To (form)", how, version ("" = both) }

SWSH = SWSH or {}

SWSH.EVOS = {
'''
    out = os.path.join(root, 'lua', 'autorun', '09_evolutions.lua')
    open(out, 'w', encoding='utf-8', newline='\n').write(hdr + ',\n'.join('    { %s }' % ', '.join(lua(v) for v in r) for r in evo_rows) + '\n}\n')
    print(len(evo_rows), 'evolutions ->', out)
else:
    print('no evolutions.json: run pknx-export again')
