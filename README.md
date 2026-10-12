# Sw-Sh-Help-Overlay

An MCCP addon for Pokémon Sword & Shield that reads the game's battle text,
prints it to the console, and while a battle menu is up shows both Pokémon's
stats for their level beside their HP panels. Clone this repo straight into MCCP's `addons/` folder; the
repo root is the addon folder.

It needs the native mod **`ocr`** (`bin/ocr.dll`): the OCR module built from
[DasMaffin/RapidOcrOnnx, branch `mccp`](https://github.com/DasMaffin/RapidOcrOnnx/tree/mccp).
Without it the addon logs that the module is missing and does nothing.

```
addons/Sw-Sh-Help-Overlay/
  mod.txt                    version; depends on ocr
  lua/autorun/10_mod.lua     registration, settings, logging, where the text is
  lua/autorun/05_dex.lua     Gen 8 base stats, #1-898 (generated from Showdown's data)
  lua/autorun/30_reader.lua  which box is up -> ocr.read -> ocr.poll -> console
  lua/autorun/40_battle.lua  who is fighting, at what level; the two stats panels
  dev/                       sample screenshots and a simulator (not used by MCCP)
```

## How it reads

Asynchronously, so the video never waits for OCR:

1. **OnFrame** (every frame) checks a few pixels to see what's on screen —
   the battle message box; with *Read text outside battles too* also the white
   dialogue box (and the speaker's name plate above it), the dark system
   message box, or neither (then it tries the cutscene subtitle lines)
   — and passes that box's lines to `ocr.read(frame, regions)`. The module
   copies them and returns at once; if it is still busy, the frame is skipped.
2. **Think** collects finished results with `ocr.poll()`. A box is printed once
   its text is the same twice running (the typewriter animation is done), and
   again only after it has changed or gone away. A box closed before it was
   read twice (mashing A) is printed from its last reading when it goes.

Each region is one line of text, read in the module's `line` mode
(recognition only): faster and more accurate than letting it find the text.

## Battle stats

Who is fighting comes from the battle text — "Go! Scorbunny!" (also "You're
in charge, …!", "Go for it, …!") is yours, "… sent out Wooloo!" and "You
encountered a wild …!" the opponent's — and from the HP panels themselves,
which are read while a battle menu is up: each name, each "Lv.", and your
HP ("8/23"). A panel reading counts once it has been read the same twice.

Two panels in the look of pkmn_stats' YOURS / ENEMY panels then show each
Pokémon's types and its stats at its level: YOURS above your HP panel, ENEMY
under theirs. A stat whose exact value isn't known is a range (Gen 8's
formula over what isn't known); the bar is solid to the low end and faint to
the high end, on one scale for both panels.

| | IVs | EVs | Nature |
|---|---|---|---|
| Yours | 0–31 | 0–252 | ×0.9–×1.1 — HP is exact: the panel's max HP |
| Enemy | 0–31 | 0 (in-game trainers and wild Pokémon have none) | ×0.9–×1.1 |
| A trainer's | fixed | fixed | fixed — exact stats, nature shown |

A trainer's Pokémon are exact: every in-game trainer's team is in
`lua/autorun/06_trainers.lua`, from the game's own data. The trainer comes
from "Pokémon Trainer Hop sent out …!" or "You are challenged by …!", and the
species and level off their HP panel pick the Pokémon from the team.

Before a level is read the rows are base stats ("base stats" in the title
bar). A name that isn't a species — a nickname — shows as "not in the
Pokédex". A species with a Galarian form shows that form.

## Route information

On entering an area the game shows its name bottom right ("Rolling Fields",
"Wild Area" under it, on a magenta band). That banner is read, and a list
top left — like pkmn_stats' FRLG route panel — shows what's met there in the
version you're playing:

- each species, coloured by its best way of meeting it (green on land, blue
  on water; a wave for surfing, a rod for fishing, a tree for shaking trees)
  with its rate, and the ball (click: caught);
- a place's separate parts are never merged into one number, like FRLG's
  floors: Zigzagoon on Route 2 is 2% there and 50% in its high-level area, so
  the row says "2-50%". One met **only** in such a part is listed last with it
  named ("Gossifleur *High-level area*");
- **hovering** a row: every way it's met here — how, rate, levels, the
  weather it needs, and each part of the place with its own odds — and where
  else it's met;
- **clicking** a row opens its Bulbapedia page.

Towns say "No wild Pokemon here". The area is remembered across restarts;
the list steps aside during battles. Setting *Show route information*: on,
off, or overlay only. Data: `lua/autorun/08_areas.lua`, from the game's own
encounter tables (a zone's surfing and flying tables are under the name the
banner shows; its separate parts — high-level area, near the station, ... —
keep their own odds).

## Pokédex checklist

Turn on *Pokedex checklist* in the settings: a panel down the right of the
window, like pkmn_stats' FRLG one, listing every species in Sword/Shield (664,
both DLCs) with a ball to tick.

- **National / Galar / Armor / Tundra** picks the dex — each regional one in
  its own order and numbers. The count (`12/400`) is within that dex.
- **Showing:** cycles everything / still missing / caught.
- **The ball** toggles caught. It also ticks itself:
  - from the battle text, in the game's own words: "Gotcha! … was caught!",
    "…’s data was added to the Pokédex.", "You caught …!" (and "… has been
    sent to a Box!" with *Read text outside battles too* on);
  - from the Poké Ball the game puts right of a wild Pokémon's HP bar when you
    already have its species — read with the HP panels while a battle menu is
    up, and only with that panel's name read the same twice.

  Nothing ever unticks one but a click.
- **Hovering a row** says where it's found in the wild in the version you're
  playing, best rate first — or that only the other version has it, or that no
  wild table does (evolve, raid, trade or gift).
- **Clicking a row** opens its Bulbapedia page. The wheel scrolls; the panel
  can be dragged, and the pin keeps it up with the overlay closed.

## Console output

| Line | When |
|---|---|
| `Hop: <line 1> / <line 2>` | The dialogue box, with the name plate when there is one. |
| `<line 1> / <line 2>` | The dialogue box without a name plate. |
| `[system] <line 1> / <line 2>` | The dark system message box. |
| `[battle] <line 1> / <line 2>` | The battle message box (dark band across the whole bottom). |
| `[cutscene] <line 1> / <line 2>` | A cutscene subtitle (white text over the scene). |
| `[you] Scorbunny` | Your Pokémon, from the battle text or your HP panel. |
| `[foe] Wooloo` | The opponent's, from the battle text or their HP panel. |
| `[you] Scorbunny Lv.6` | A level read off an HP panel (`[foe]` for theirs). |
| `[trainer] Pokemon Trainer Hop` | The trainer you're fighting, from the battle text. |
| `[foe] Grookey Lv.5 of Pokemon Trainer Hop: exact stats, Hardy` | Their Pokémon was found in their team. |
| `[area] Rolling Fields (Wild Area)` | The area banner was read (`(no wild Pokemon)` for a town). |
| `[dex] Wooloo caught (caught)` | A Pokédex checklist mark changed: `(caught)` from the text, `(ball by the HP bar)`, `(clicked)` by hand. |
| `the OCR module isn't available ...` | `bin/ocr.dll` is missing or failed to load. |
| `OCR failed: ...` | The module reported an error for a job. |
| `frame format ... is not supported` | The capture isn't NV12. |

On MCCP builds with log levels the lines are logged under the level
**Dialogue**, so Options → Developer can show just them.

The English model only knows ASCII, so `'` is printed as `’` and `--` as `—`
(the game uses those); `é` comes out as `e`. It can't read `₽` either: that is
put back in the money messages ("You got ₽400 for winning!").

Settings: *Print what is read to the console*; *Read text outside battles too*
(off: battle text only); *Show both Pokemon's stats in battle*; *Pokedex checklist*; *Show route information* (on / off / overlay only); and *Show
what the reader sees* (outlines the lines being read and shows the latest
reading).

## Dev

```
pip install lupa pillow numpy rapidocr_onnxruntime
python3 dev/sim.py                       # every screenshot in dev/samples
python3 dev/sim.py dev/samples/hop_1.webp
python3 dev/sim.py --png out --say "Go! Scorbunny!" dev/samples/battle_moves.webp
python3 dev/sim.py --png out --dex --hover 1600,300 dev/samples/battle_moves.webp
python3 dev/sim.py --png out --hover 100,175 dev/samples/area_rolling_fields.webp
python3 dev/sim.py --png out --area "Route 2" --hover 60,368 dev/samples/hop_1.webp
```

[docs/wild.md](docs/wild.md) lists the wild Pokémon of every area — how
they're met, levels, weather, rates — with Sword and Shield exclusives marked.

Trainer teams, the checklist's and route list's data (`07_pokedex.lua`,
`08_areas.lua`) and the wild list are dumped from your own game files with
pkNX (`dev/pknx-export`, needs a clone of kwsch/pkNX and Oodle's
`oo2core_8_win64.dll` beside the exe), then generated:

```
dotnet run -c Release --project dev/pknx-export -- ROMs/out ROMs/export
python3 dev/gen_romdata.py ROMs/export
```

`ROMs/` (game files) is never committed.

`dev/sim.py` runs the addon under a mocked engine, with a stand-in for the
`ocr` module (same API, Python RapidOCR underneath — its readings are close to
the DLL's, not identical). Box positions are measured at 1920x1080 and scaled
to the capture's size.
