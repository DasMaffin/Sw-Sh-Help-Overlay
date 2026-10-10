# Sw-Sh-Help-Overlay

An MCCP addon for Pokémon Sword & Shield that reads the game's text and prints
it to the console. Clone this repo straight into MCCP's `addons/` folder; the
repo root is the addon folder.

It needs the native mod **`ocr`** (`bin/ocr.dll`): the OCR module built from
[DasMaffin/RapidOcrOnnx, branch `mccp`](https://github.com/DasMaffin/RapidOcrOnnx/tree/mccp).
Without it the addon logs that the module is missing and does nothing.

```
addons/Sw-Sh-Help-Overlay/
  mod.txt                    version; depends on ocr
  lua/autorun/10_mod.lua     registration, settings, logging, where the text is
  lua/autorun/30_reader.lua  which box is up -> ocr.read -> ocr.poll -> console
  dev/                       sample screenshots and a simulator (not used by MCCP)
```

## How it reads

Asynchronously, so the video never waits for OCR:

1. **OnFrame** (every 6th frame) checks a few pixels to see what's on screen —
   the white dialogue box (and the speaker's name plate above it), the dark
   system message box, or neither (then it tries the cutscene subtitle lines)
   — and passes that box's lines to `ocr.read(frame, regions)`. The module
   copies them and returns at once; if it is still busy, the frame is skipped.
2. **Think** collects finished results with `ocr.poll()`. A box is printed once
   its text is the same twice running (the typewriter animation is done), and
   again only after it has changed or gone away.

Each region is one line of text, read in the module's `line` mode
(recognition only): faster and more accurate than letting it find the text.

## Console output

| Line | When |
|---|---|
| `Hop: <line 1> / <line 2>` | The dialogue box, with the name plate when there is one. |
| `<line 1> / <line 2>` | The dialogue box without a name plate. |
| `[system] <line 1> / <line 2>` | The dark system message box. |
| `[battle] <line 1> / <line 2>` | The battle message box (dark band across the whole bottom). |
| `[cutscene] <line 1> / <line 2>` | A cutscene subtitle (white text over the scene). |
| `the OCR module isn't available ...` | `bin/ocr.dll` is missing or failed to load. |
| `OCR failed: ...` | The module reported an error for a job. |
| `frame format ... is not supported` | The capture isn't NV12. |

On MCCP builds with log levels the lines are logged under the level
**Dialogue**, so Options → Developer can show just them.

The English model only knows ASCII, so `'` is printed as `’` and `--` as `—`
(the game uses those); `é` comes out as `e`.

Settings: *Print what is read to the console*, and *Show what the reader sees*
(outlines the lines being read and shows the latest reading).

## Dev

```
pip install lupa pillow numpy rapidocr_onnxruntime
python3 dev/sim.py                       # every screenshot in dev/samples
python3 dev/sim.py dev/samples/hop_1.webp
```

`dev/sim.py` runs the addon under a mocked engine, with a stand-in for the
`ocr` module (same API, Python RapidOCR underneath — its readings are close to
the DLL's, not identical). Box positions are measured at 1920x1080 and scaled
to the capture's size.
