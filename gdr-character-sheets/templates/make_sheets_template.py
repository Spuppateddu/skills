#!/usr/bin/env python3
"""Build the player sheets for the "<ONE-SHOT>" one-shot (<GAME>).

For each character an Xournal++ file (.xopp) is written with the blank
"<SHEET>.pdf" as background and the data placed over the printed fields, then
exported to PDF. Open the .xopp in Xournal++ to move or edit anything.
Everything is merged into schede/<oneshot>-schede-tutte.pdf.

To re-export a .xopp you edited by hand with the same fonts:
    python3 make_sheets.py --export schede/1_name.xopp

Run:  python3 make_sheets.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xopp_lib as X  # copied next to this file from the gdr-character-sheets skill

HERE = os.path.dirname(os.path.abspath(__file__))
BG_PDF = os.path.join(HERE, "..", "<SHEET>.pdf")          # the blank sheet
OUT_DIR = os.path.join(HERE, "schede")
PAGE = X.A4_LANDSCAPE                                       # check with sheet_geometry.py
FONT, BOLD = "Liberation Sans", "Liberation Sans Bold"      # or Georgia / Georgia Bold

# --- the characters (from <data file>) ----------------------------------------------
PLAYERS = [
    dict(
        file="1_name_alias",
        nome="Name", alias="Alias",
        # ... every field of the sheet, in the sheet's own words
    ),
]


# --- one sheet ----------------------------------------------------------------------
def sheet_layer(p):
    """Everything drawn over page 1 of the blank sheet for character p."""
    pg = X.Page(BG_PDF, 1)                 # printed words, symbols, rules of the page
    els = []
    # text on a printed rule: baseline = rule y - 2, label sits under the rule
    els += X.fit_line(36, 70.3, p["nome"], 205, (11, 10, 9), BOLD)
    # a ring around a printed option
    # els.append(X.ring_around(pg.find("akoros", xr=(36, 215), yr=(125, 160))))
    # dots for a rating: the 4 symbol glyphs on the line of the action name
    # x0, x1, base, size = pg.find("schermire", xr=(700, 800))
    # for s in pg.symbols_near(base, font="Wingdings-Regular", glyph=("122",), xr=(680, 760))[:p["schermire"]]:
    #     cx, cy = X.sym_center(s); els.append(X.dot(cx, cy, 0.56 * s["size"]))
    # a tick in the box just before an item name
    # hit = pg.find("una lama o due", xr=(680, 830)); box = pg.symbols_near(hit[2], xr=(hit[0] - 26, hit[0]))[0]
    # els.append(X.check(*X.sym_center(box)))
    # notes on the printed rules, two lines per rule, bold headers
    # rules = X.rules_baselines(324.89, 20.207, 13, per_rule=2)
    # els += X.notes_block(p["note"], 36, 342, rules, name=FONT, bold=BOLD)
    return els


def build(p):
    pages = [X.page_pdf(1, sheet_layer(p), BG_PDF, True, PAGE)]
    return X.xopp_xml(pages)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--export":
        sys.exit(0 if X.export_pdf(sys.argv[2]) else 1)
    if not os.path.exists(BG_PDF):
        sys.exit(f"blank sheet not found: {BG_PDF}")
    os.makedirs(OUT_DIR, exist_ok=True)
    pdfs = []
    for p in PLAYERS:
        path = os.path.join(OUT_DIR, p["file"] + ".xopp")
        X.write_xopp(path, build(p))
        pdfs.append(X.export_pdf(path))
    if all(pdfs):
        X.merge_pdfs(pdfs, os.path.join(OUT_DIR, "schede-tutte.pdf"))


if __name__ == "__main__":
    main()
