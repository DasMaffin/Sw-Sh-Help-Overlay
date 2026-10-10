# Notes for future sessions

- **Branch: work and push on `main` only** (user's instruction).
- **No engine work from this repo.** ModdableCaptureCardProvider is read-only
  reference here; if something needs an engine change, say so and stop.
  Its docs: `docs/wiki/*.html` (native modules: `native.html`, header
  `include/mccp_module.h`) -- check the `development` branch, it's ahead.
- The repo root IS the addon folder: users clone it into MCCP's `addons/`.
- **OCR is the native module `ocr`** (`require("ocr")`, `bin/ocr.dll`), built
  from DasMaffin/RapidOcrOnnx branch `mccp` (a fork of RapidAI/RapidOcrOnnx,
  NOT RapidAI/RapidOCR). Its API: `ocr.read(frame, regions[, {lang=}])` ->
  id or `nil,"busy"` (copies the pixels, returns at once);
  `ocr.poll()` -> nil or `{id, ms, regions={{key, lines={{text, score,
  x0,y0,x1,y1}}}}}` or `{id, error}`; `ocr.languages()`, `ocr.version()`.
  Regions: `{x,y,w,h, mode="line"|"auto", key=}`. Line mode = one known
  text line, recognition only (~20-40 ms); auto = detection too (~0.5 s for
  1080p). Default language `en` is ASCII only.
- The user REMOVED the old pixel-matching reader, the glyph atlas and all
  self-teaching on purpose. Don't bring them back.
- The reader is asynchronous: OnFrame decides which box is up (cheap pixel
  probes) and calls `ocr.read`; Think calls `ocr.poll` and prints. By default
  only battle text is read (setting `read_all` adds dialogue/sys/subtitles).
  Battle text feeds `40_battle.lua` (who's fighting) -> base-stat panel above
  the player's HP panel while `SWSH.BATTLE.panel` (battle menu) is white.
- `lua/autorun/05_dex.lua` is generated from Showdown's pokedex.json (today's stats +
  Showdown's gen8 mod = Sword/Shield numbers; keys = lowercase alnum names,
  Galarian forms preferred); regenerate with
  `dev/gen_dex.py`, don't hand-edit.
- Geometry is measured at 1920x1080 in `lua/autorun/10_mod.lua` (`SWSH.BOX`,
  `NAME`, `BATTLE`, `SYS`, `SUB`; battle is checked before sys, whose probes
  it also matches) and scaled to the frame.
- Log through `SWSH.log(level, ...)`: level `SWSH.LV.dialogue` / `important`,
  colours from `SWSH.C`; falls back to one plain string on engines without
  LOG_LEVEL. Keep README.md's "Console output" table in sync.
- Test with `python3 dev/sim.py` (mock engine + stand-in ocr module).
  Screenshots + their text: `dev/samples/` and `truth.txt`.
