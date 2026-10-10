# Sw-Sh-Help-Overlay

An MCCP addon for Pokémon Sword & Shield. Clone this repo straight into the
app's `addons/` folder; the repo root is the addon folder:

```
addons/Sw-Sh-Help-Overlay/
  mod.txt
  lua/autorun/05_atlas.lua   glyph fingerprints (generated, see dev/)
  lua/autorun/10_mod.lua     registration, settings, box geometry
  lua/autorun/30_reader.lua  sampling (OnFrame), logging (Think), debug overlay
  workers/reader.lua         the OCR, on its own thread
  lua/autorun/90_dev_teach.lua  DEV ONLY: glyph teaching + teach panel (delete for shipping)
  dev/                       DEV ONLY: tools, samples, teaching workers
```

## What it does (so far)

When the white dialogue box is on screen it reads the two lines of text, and
the speaker's name from the dark plate above it when there is one. Once
the typewriter animation has stopped, it prints them to the console, once per
box (the same text prints again only after the box has closed):

```
[mod] Sw-Sh-Help-Overlay: How about it, Lucy? Let’s race! / Bet I can make it to my house first, what with you
```

Characters it doesn't know yet print as `[?]` (a real `?` is the game's own
question mark).

## Log messages

On an MCCP build with log levels and colours (engine `development`, Oct 2026)
the mod logs under its own levels, so Options → Developer can show just them:

- **Dialogue**: finished boxes. Text in white, unreadable glyphs `[?]` in red,
  the glyph count in blue.
- **Teaching** (DEV only): learned letters in green with the letter in yellow;
  "could not learn" in orange.
- **Important**: problems (unsupported frame format, no teaching data).

Older builds get the same lines without colour or levels.

| Message | Meaning |
|---|---|
| `<line 1> / <line 2>` | A finished box. |
| `Hop: <line 1> / <line 2>` | A finished box with a speaker's name plate (name in orange). |
| `... [glyphs 42/109 en]` | Appended to the first finished box after letters were learned: characters the reader knows / distinct characters in that language's game text. Touching pairs (`w.`) don't count. |
| `DEV learned new letter 'M' from "Meeeh?" (read as "[?]eeeh?")` | Self-teaching found the letter. A pair like `'w.'` means two characters whose ink touches. `; "Lucy" taken as a name` means that word matched a name placeholder in the game text. |
| `DEV learned new letter 'H' (name plate) from "Hop" ...` | A letter of the name plate's own (white-on-dark, heavier) style. |
| `DEV learned new letter 'l' (typed in; was read as "I")` | Learned from the manual teach panel (`line 1\|line 2\|name`). |
| `DEV could not learn from "...": <reason>` | `not in the game text`, `ambiguous` (several answers fit), `too many unknowns` (more than 3), `too little known text`. It waits for another box. |
| `DEV Learned N glyphs.` / `DEV learned glyphs cleared` | Teach panel results. |
| `DEV self-teaching is off -- no dev/teach/teach_<lang>.lua` | No game text for the chosen language. |
| `frame format ... is not supported yet (NV12 only)` | Capture isn't NV12; nothing is read. |

## Self-teaching (DEV ONLY)

While the dev layer is in (`lua/autorun/90_dev_teach.lua` + `dev/`, removed
for shipping), unknown letters are learned by themselves: a line with `[?]`
is looked up in the game's own text (CPokemon/swsh-text), and if only one
answer fits, the letters are learned, logged and used from then on. Settings
*DEV: learn unknown letters from the game's text* and *DEV: game language*
(restart to apply). You can also teach by hand in the overlay (Shift+Tab).

Learned letters land in
`ModdableCaptureCardProvider\data\Sw-Sh-Help-Overlay\learned.txt`. To get
them baked into the shipped atlas for everyone, copy that file to
`dev/learned/<name>.txt` and push (or send it in); after the baked update,
press *Forget learned* and delete your `dev/learned` copy.

Settings: *Print dialogue text to the console* and *Show what the reader sees*
(outlines the sampled lines and shows the live reading).

## Dev

```
pip install lupa pillow numpy
python3 dev/gen_atlas.py --check   # rebuild the atlas from dev/samples, re-read them
python3 dev/sim.py dev/samples/hop_1.webp   # run the whole addon on a screenshot
```

Box geometry is measured at 1920x1080 and scaled to the capture's size.
