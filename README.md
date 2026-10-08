# Sw-Sh-Help-Overlay

An MCCP addon for Pokémon Sword & Shield. Clone this repo straight into the
app's `addons/` folder; the repo root is the addon folder:

```
addons/Sw-Sh-Help-Overlay/
  mod.txt
  lua/autorun/05_atlas.lua   glyph fingerprints (generated, see dev/)
  lua/autorun/10_mod.lua     registration, settings, box geometry, learned glyphs
  lua/autorun/30_reader.lua  sampling (OnFrame), logging (Think), teach panel, debug overlay
  workers/reader.lua         the OCR, on its own thread
  dev/                       offline tools and sample screenshots (not used by the engine)
```

## What it does (so far)

When the white dialogue box is on screen it reads the two lines of text. Once
the typewriter animation has stopped, it prints them to the console:

```
[Sw-Sh-Help-Overlay] Sw-Sh-Help-Overlay: How about it, Lucy? Let’s race! / Bet I can make it to my house first, what with you
```

Characters it has never seen print as `?`. To teach them, open the overlay
(Shift+Tab) while a box is showing, type exactly what the box says into
*SwSh reader: teach glyphs* (put `|` between the two lines), and press
**Learn**. Learned glyphs are saved in `data/<addon>/learned.txt` and used
right away. You can teach any language this way.

Settings: *Print dialogue text to the console* and *Show what the reader sees*
(outlines the sampled lines and shows the live reading).

## Dev

```
pip install lupa pillow numpy
python3 dev/gen_atlas.py --check   # rebuild the atlas from dev/samples, re-read them
python3 dev/sim.py dev/samples/hop_1.webp   # run the whole addon on a screenshot
```

Box geometry is measured at 1920x1080 and scaled to the capture's size.
