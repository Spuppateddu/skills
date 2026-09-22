# The .xopp file, in short

A `.xopp` is a **gzip-compressed XML** file. `xopp_lib.py` writes it for you; this
page is for when you need to know what is inside (to debug, or to hand-tune).

```xml
<?xml version="1.0" standalone="no"?>
<xournal creator="make_sheets.py" fileversion="4">
<title>Xournal++ document - see https://xournalpp.github.io/</title>
<page width="841.89" height="595.276">
<background type="pdf" domain="absolute" filename="/abs/path/blank-sheet.pdf" pageno="15"/>
<layer>
<text font="Liberation Sans" size="9" x="36.00" y="61.86" color="#000000ff">Holtz Skelkallan</text>
<stroke tool="pen" color="#000000ff" width="5.3" capStyle="round">696.75 226.00 696.85 226.00</stroke>
<stroke tool="pen" color="#b3121bff" width="0.6" fill="255" capStyle="round">x y x y x y x y</stroke>
<image left="40" top="270" right="180" bottom="284">BASE64-PNG</image>
</layer>
</page>
<page width="841.89" height="595.276">
<background type="pdf" pageno="7"/>
<layer></layer>
</page>
</xournal>
```

## Units and origin
- Everything is in **PDF points** (1 pt = 1/72 in), origin **top-left**, y grows down.
  This is also what `mutool trace` and `pdftotext -bbox` report, so measurements
  transfer 1:1. A4 landscape = 841.89 x 595.276, A4 portrait = 595.276 x 841.89,
  A5 landscape = 595.276 x 420.945.
- From a PNG rendered at `dpi`: `pt = px * 72 / dpi`.

## Background
- `type="pdf"` with `domain="absolute" filename="..."` on the **first** page of the
  file only; later pages just give `pageno`. `pageno` is 1-based in the PDF.
- The file keeps a reference to the PDF, not a copy: if the blank sheet moves, the
  .xopp opens empty. Keep the blank PDF next to the one-shot folder.
- `type="solid" color="#ffffffff" style="plain"` for a blank page (handout cards).

## Text
- `x`, `y` are the **top-left of the text box**, not the baseline. The baseline is
  `y + ascent(font, size)`; `xopp_lib.text()` does the conversion so you can think
  in baselines (a printed rule is a baseline: write at `rule_y - 2`).
- `font` is a fontconfig family with style words: `Liberation Sans`,
  `Liberation Sans Bold`, `Georgia Italic`. `size` in points.
- Multi-line text: put `\n` in the content. Pango line height is about 1.15 em for
  Liberation Sans and Georgia. One element per line gives you control of the
  pitch (needed to sit lines on printed rules); one element per paragraph is
  easier to edit by hand in Xournal++. Use per-line when there are rules.
- No rotation, no rich text: a bold word inside a sentence is a second element
  placed at `x + width(previous)`. Slanted or curved text is an image (below).
- Xournal++ measures text with Pango; PIL's `getlength` is about 2 % narrower.
  `xopp_lib.text_width` already adds that 2 %.

## Strokes
- `tool="pen"`, `color="#rrggbbaa"`, `width` in points, points as `x y x y ...`.
- `capStyle="round"` (default) or `"butt"`. A **short stroke with round caps** is a
  perfect filled dot of diameter `width` (`xopp_lib.dot`).
- `fill="255"` fills the closed polygon (1..255 = opacity). Use it for discs,
  triangles and **white rectangles that hide a printed default** value you have
  to replace (`xopp_lib.rect`). Strokes cannot be hollow-with-outline in one
  element: draw the fill, then the outline if you want one.

## Images
- `<image left top right bottom>` with the PNG base64 inside. Keep them small (a
  6 pt line of text at 8 px/pt is fine); they stay movable in Xournal++.
- Use for: text on slanted rules (render with PIL, rotate), portraits, dice icons.

## Export
```
XDG_CONFIG_HOME=$(mktemp -d) xournalpp --create-pdf=out.pdf file.xopp
```
The empty config directory matters on this machine: the user's fontconfig maps
every family to Cascadia Code, so without it the sheet exports in a monospace
font. `xopp_lib.export_pdf` does this. The export is headless (no window opens)
and takes ~1 s per file.

## Layers
One `<layer>` is enough. Xournal++ users can add layers by hand; the script
always writes into a single one so a rebuild replaces everything it wrote.
