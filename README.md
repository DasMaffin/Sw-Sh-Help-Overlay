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
  lua/autorun/90_dev_teach.lua  DEV ONLY: glyph teaching (delete for shipping)
  dev/                       DEV ONLY: tools, samples, teaching workers
```

## What it does (so far)

When the white dialogue box is on screen it reads the two lines of text. Once
the typewriter animation has stopped, it prints them to the console:

```
[Sw-Sh-Help-Overlay] Sw-Sh-Help-Overlay: How about it, Lucy? Let’s race! / Bet I can make it to my house first, what with you
```

Characters it doesn't know yet print as `[?]`. While the dev layer is in
(`lua/autorun/90_dev_teach.lua` + `dev/`, removed for shipping), it learns
them by itself: a line with unknown letters is looked up in the game's own
text, and if only one answer fits, the letters are learned, logged
(`DEV learned new letter 'M' from "Meeeh?"`) and used from then on. You can
also teach by hand in the overlay. Learned letters land in
`data/<addon>/learned.txt`; send that file in so they get baked into the
shipped atlas for everyone.

Settings: *Print dialogue text to the console* and *Show what the reader sees*
(outlines the sampled lines and shows the live reading).

## Dev

```
pip install lupa pillow numpy
python3 dev/gen_atlas.py --check   # rebuild the atlas from dev/samples, re-read them
python3 dev/sim.py dev/samples/hop_1.webp   # run the whole addon on a screenshot
```

Box geometry is measured at 1920x1080 and scaled to the capture's size.
