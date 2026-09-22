#!/usr/bin/env python3
"""Show what is printed where on a page of a blank character-sheet PDF.

    python3 sheet_geometry.py SHEET.pdf --page 15
    python3 sheet_geometry.py SHEET.pdf --page 15 --overlay /tmp/ov.png   # to LOOK at it
    python3 sheet_geometry.py SHEET.pdf --page 15 --find "schermire"        # where is a word
    python3 sheet_geometry.py SHEET.pdf --page 15 --json /tmp/p15.json      # everything

It reads the page with `mutool trace` (see xopp_lib.Page) and prints:
  - page size and whether the page has a text layer at all
  - the printed lines of text with their baseline and x range
  - the symbol glyphs (Wingdings, ZapfDingbats...) grouped by font/glyph/size/colour:
    these are usually the dots, checkboxes and triangles of the sheet
  - the horizontal rules (the lines you write on)
  - small vector shapes (boxes, circles drawn as paths) grouped by size
The overlay draws every symbol and small shape on a render of the page, with its
group id, so you can tell which group is the action dots, which the checkboxes...

A page with no text layer (a scanned sheet) prints a warning: render it with
`mutool draw -r 144` and measure the boxes on the PNG instead (px * 72 / dpi = pt).
"""
import argparse
import json
import os
import subprocess
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xopp_lib import Page, sym_center  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--page", type=int, default=1)
    ap.add_argument("--overlay", help="write a PNG with symbols and shapes marked")
    ap.add_argument("--dpi", type=int, default=144)
    ap.add_argument("--find", action="append", default=[], help="print where this text is")
    ap.add_argument("--json", help="dump lines, symbols, rules and small shapes")
    ap.add_argument("--all-lines", action="store_true", help="print every printed line")
    a = ap.parse_args()

    pg = Page(a.pdf, a.page)
    print(f"page {a.page}: {pg.width:.2f} x {pg.height:.2f} pt")
    if not pg.has_text:
        print("WARNING: no text layer on this page (scanned or outlined). Render it and measure by hand:")
        print(f"  mutool draw -r {a.dpi} -o page.png '{a.pdf}' {a.page}   # pt = px * 72 / {a.dpi}")

    for needle in a.find:
        hits = pg.find_all(needle)
        if not hits:
            print(f"find {needle!r}: NOT FOUND")
        for x0, x1, base, size in hits:
            print(f"find {needle!r}: x={x0:.1f}-{x1:.1f} baseline={base:.1f} size={size}")

    print(f"\n{len(pg.lines)} printed lines" + ("" if a.all_lines else " (first 40; --all-lines for all)"))
    for base, txt, spans in (pg.lines if a.all_lines else pg.lines[:40]):
        xs = [s[0] for s in spans if s]
        print(f"  y={base:6.1f} x={min(xs):6.1f}  {txt[:100]}")

    groups = defaultdict(list)
    for s in pg.symbols:
        groups[(s["font"], s["glyph"], s["size"], s["color"])].append(s)
    print(f"\n{len(pg.symbols)} symbol glyphs in {len(groups)} groups (id: font glyph size colour -> count, first centres)")
    ids = {}
    for i, (k, v) in enumerate(sorted(groups.items(), key=lambda kv: -len(kv[1]))):
        ids[k] = i
        v.sort(key=lambda s: (round(s["y"]), s["x"]))
        cs = ", ".join("(%.0f,%.0f)" % sym_center(s) for s in v[:4])
        print(f"  g{i}: {k[0]} glyph={k[1]} size={k[2]} colour='{k[3]}' -> {len(v)}  {cs}")

    rules = pg.rules()
    print(f"\n{len(rules)} horizontal rules (y: x0-x1)")
    for y, x0, x1 in rules[:60]:
        print(f"  y={y:6.2f}  x={x0:6.1f}-{x1:6.1f}")

    small = pg.small_shapes()
    sizes = Counter((s["kind"], round(s["w"]), round(s["h"]), s["curved"]) for s in small)
    print(f"\n{len(small)} small vector shapes (kind w h curved -> count)")
    for k, n in sizes.most_common(15):
        ex = [s for s in small if (s["kind"], round(s["w"]), round(s["h"]), s["curved"]) == k][:3]
        cs = ", ".join(f"({s['cx']:.0f},{s['cy']:.0f})" for s in ex)
        print(f"  {k[0]} {k[1]}x{k[2]} curved={int(k[3])} -> {n}  {cs}")

    if a.json:
        json.dump(dict(width=pg.width, height=pg.height,
                       lines=[dict(baseline=b, text=t, x0=min(s[0] for s in sp if s) if any(sp) else None)
                              for b, t, sp in pg.lines],
                       symbols=pg.symbols, rules=rules, small_shapes=small),
                  open(a.json, "w"), indent=1, ensure_ascii=False)
        print("json ->", a.json)

    if a.overlay:
        from PIL import Image, ImageDraw
        tmp = a.overlay + ".render.png"
        subprocess.run(["mutool", "draw", "-r", str(a.dpi), "-o", tmp, a.pdf, str(a.page)],
                       check=True, capture_output=True)
        im = Image.open(tmp).convert("RGB")
        os.remove(tmp)
        d = ImageDraw.Draw(im)
        k = a.dpi / 72.0
        palette = ["red", "blue", "green", "magenta", "orange", "purple", "brown", "cyan", "olive", "navy"]
        for key, v in groups.items():
            col = palette[ids[key] % len(palette)]
            for j, s in enumerate(v):
                x0, x1 = s["x"] * k, (s["x"] + s["adv"]) * k
                y1, y0 = s["y"] * k, (s["y"] - 0.7 * s["size"]) * k
                d.rectangle([x0, y0, x1, y1], outline=col, width=2)
                if j < 3:  # label only the first glyphs of a group, or the page drowns in ids
                    d.text((x0, y0 - 10), f"g{ids[key]}", fill=col)
        for s in small:
            d.rectangle([s["x0"] * k, s["y0"] * k, s["x1"] * k, s["y1"] * k], outline="gray", width=1)
        for y, x0, x1 in rules:
            d.line([x0 * k, y * k, x1 * k, y * k], fill="deepskyblue", width=1)
        im.save(a.overlay)
        print("overlay ->", a.overlay, "(symbol groups in colour with their g-id, small shapes grey, rules blue)")


if __name__ == "__main__":
    main()
