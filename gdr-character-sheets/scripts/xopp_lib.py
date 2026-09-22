#!/usr/bin/env python3
"""Helpers to build Xournal++ files (.xopp) over a blank character-sheet PDF.

Copy this file next to your make_sheets.py and `import xopp_lib as X`.

What it gives you
-----------------
- fonts and text measuring that match what Xournal++ (Pango) will render
- text elements placed by BASELINE (the sheet's printed rules are baselines)
- wrapping that shrinks the font until the text fits its box
- marks: dots, discs, rings, checks, crosses, filled triangles, white-out rects
- an image element (for text on slanted rules, portraits, dice icons)
- Page: the geometry of a printed sheet page read from the PDF itself
  (words, symbol glyphs, rules, small vector shapes) so nothing is measured by hand
- writers: page/xopp XML, gzip, export to PDF, merge, render to PNG for checking

Units are PDF points everywhere (1 pt = 1/72 in), origin top-left, y grows down.
"""
import gzip
import base64
import io
import math
import os
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

from PIL import Image, ImageFont

# --- page sizes (points) --------------------------------------------------------
A4_PORTRAIT = (595.276, 841.89)
A4_LANDSCAPE = (841.89, 595.276)
A5_PORTRAIT = (419.528, 595.276)
A5_LANDSCAPE = (595.276, 420.945)
LETTER_PORTRAIT = (612.0, 792.0)

BLACK = "#000000ff"
RED = "#b3121bff"
GREY = "#666666ff"
WHITE = "#ffffffff"

# --- fonts ------------------------------------------------------------------------
# The user's fontconfig maps every family to Cascadia Code (a coding font). A
# clean XDG_CONFIG_HOME makes fc-match and Xournal++ resolve the real fonts.
_CLEAN_ENV = dict(os.environ)
_CLEAN_ENV["XDG_CONFIG_HOME"] = tempfile.mkdtemp(prefix="xopp-fonts-")


def clean_env():
    return dict(_CLEAN_ENV)


_STYLE_WORDS = {"bold", "italic", "oblique", "light", "medium", "semibold", "black", "condensed", "regular"}


def fc_pattern(name):
    """'Liberation Sans Bold Italic' -> 'Liberation Sans:bold:italic'. fc-match reads
    trailing style words as part of the family name and falls back to the default
    font, so the style must be given after a colon. Pango (Xournal++) understands
    both forms, so the element keeps the plain name."""
    words = name.split()
    fam, styles = [], []
    for w in words:
        (styles if w.lower() in _STYLE_WORDS and fam else fam).append(w)
    return ":".join([" ".join(fam)] + [w.lower() for w in styles])


def font_file(name):
    """The .ttf fontconfig resolves `name` to (e.g. 'Liberation Sans Bold')."""
    return subprocess.check_output(["fc-match", "-f", "%{file}", fc_pattern(name)],
                                   env=_CLEAN_ENV).decode().strip()


_font_files = {}
_fonts = {}


def _pil_font(name, size):
    if name not in _font_files:
        _font_files[name] = font_file(name)
    key = (name, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(_font_files[name], int(size * 20))
    return _fonts[key]


def text_width(s, size, name="Liberation Sans"):
    """Width in points. Pango sets a hair wider than PIL, hence the 2 %."""
    return _pil_font(name, size).getlength(s) / 20.0 * 1.02


def ascent(size, name="Liberation Sans"):
    """Distance from the top of the text box to the baseline, in points."""
    a, d = _pil_font(name, size).getmetrics()
    return a / 20.0


def line_height(size, name="Liberation Sans"):
    a, d = _pil_font(name, size).getmetrics()
    return (a + d) / 20.0 * 1.02


# --- wrapping ---------------------------------------------------------------------
def wrap(text, size, width, name="Liberation Sans", first_width=None):
    """Greedy word wrap; the first line may have its own width (after a bold header)."""
    lines, cur = [], ""
    limit = first_width if first_width is not None else width
    for word in text.split():
        cand = (cur + " " + word).strip()
        if text_width(cand, size, name) <= limit or not cur:
            cur = cand
        else:
            lines.append(cur)
            cur = word
            limit = width
    if cur:
        lines.append(cur)
    return lines


def wrap_widths(text, size, widths, name="Liberation Sans", first_indent=0.0):
    """Wrap where line k may use widths[k] (to go around printed text).
    Returns None when the lines run out."""
    lines, cur, k = [], "", 0
    for word in text.split():
        if k >= len(widths):
            return None
        limit = widths[k] - (first_indent if k == 0 else 0)
        cand = (cur + " " + word).strip()
        if text_width(cand, size, name) <= limit or not cur:
            cur = cand
        else:
            lines.append(cur)
            cur = word
            k += 1
    if cur:
        if k >= len(widths):
            return None
        lines.append(cur)
    return lines


# --- elements ---------------------------------------------------------------------
def text_top(x, top, s, size, name="Liberation Sans", color=BLACK):
    """Raw text element: (x, top) is the top-left of the text box. Multi-line with \\n."""
    return (f'<text font="{name}" size="{size}" x="{x:.2f}" y="{top:.2f}" '
            f'color="{color}">{escape(s)}</text>')


def text(x, baseline, s, size, name="Liberation Sans", color=BLACK):
    """Text whose baseline sits on `baseline` (write ON a printed rule: rule_y - 2)."""
    return text_top(x, baseline - ascent(size, name), s, size, name, color)


def centred(cx, cy, s, size, name="Liberation Sans Bold", color=BLACK):
    """Text visually centred on (cx, cy): digits/capitals are about 0.7 em tall."""
    w = text_width(s, size, name)
    return text(cx - w / 2, cy + size * 0.35, s, size, name, color)


def fit_line(x, baseline, s, width, sizes, name="Liberation Sans", color=BLACK):
    """One line, shrinking the font through `sizes` until it fits `width`."""
    for size in sizes:
        if text_width(s, size, name) <= width:
            return [text(x, baseline, s, size, name, color)]
    raise SystemExit(f"text too long for a single line ({width:.0f}pt): {s[:50]}...")


def paragraphs(paras, x, first_baseline, last_baseline, width,
               sizes=(7, 6.5, 6, 5.5), name="Liberation Sans", color=BLACK):
    """Wrapped paragraphs in a box, one element per line, shrinking until they fit."""
    for size in sizes:
        step = size * 1.18
        gap = size * 0.15
        els, b = [], first_baseline
        for para in paras:
            for line in wrap(para, size, width, name):
                els.append(text(x, b, line, size, name, color))
                b += step
            b += gap
        if b - step - gap <= last_baseline + 0.01:
            return els
    raise SystemExit(f"text too long for its box: {paras[0][:40]}...")


def rules_baselines(first_rule, step, count, per_rule=1, lift=2.0):
    """Baselines just above each printed rule; per_rule=2 adds one midway
    (a notes area with 20pt rules holds twice the text at 6-7pt)."""
    out = []
    for k in range(count):
        rule = first_rule + k * step
        for j in range(per_rule):
            out.append(rule - lift - j * step / per_rule)
    return sorted(out)


def notes_block(sections, x0, width, baselines, sizes=(7.0, 6.7, 6.4, 6.1, 5.8, 5.5, 5.2, 5.0),
                name="Liberation Sans", bold="Liberation Sans Bold", widths=None, color=BLACK):
    """[(bold header, body)] sections on the given baselines; the body continues on
    the header's line. The largest size that fits is used. `widths` may give a
    usable width per baseline, to flow around printed text."""
    widths = widths or [width] * len(baselines)
    for size in sizes:
        els, i, ok = [], 0, True
        for header, body in sections:
            hw = text_width(header, size, bold) + 5 if header else 0
            lines = wrap_widths(body, size, widths[i:], name, first_indent=hw)
            if lines is None:
                ok = False
                break
            if header:
                els.append(text(x0, baselines[i], header, size, bold, color))
            els.append(text(x0 + hw, baselines[i], lines[0], size, name, color))
            for ln in lines[1:]:
                i += 1
                els.append(text(x0, baselines[i], ln, size, name, color))
            i += 1
        if ok:
            return els
    raise SystemExit("notes do not fit even at the smallest size")


def stroke(pts, w=1.0, color=BLACK, cap="round", fill=None):
    """A pen stroke through `pts`. fill=255 fills the closed polygon (opaque)."""
    body = " ".join(f"{x:.2f} {y:.2f}" for x, y in pts)
    f = f' fill="{fill}"' if fill is not None else ""
    return f'<stroke tool="pen" color="{color}" width="{w}"{f} capStyle="{cap}">{body}</stroke>'


def dot(cx, cy, d, color=BLACK):
    """A filled circle of diameter d: a very short stroke with round caps."""
    return stroke([(cx - 0.05, cy), (cx + 0.05, cy)], w=d, color=color)


def _circle_pts(cx, cy, rx, ry, n=48):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n))
            for i in range(n + 1)]


def disc(cx, cy, r, color=RED):
    """A filled disc as a polygon (use it to mark a chosen option in a printed circle)."""
    return stroke(_circle_pts(cx, cy, r, r, 24), w=0.6, color=color, fill=255)


def ring(cx, cy, r, w=1.0, color=BLACK):
    return stroke(_circle_pts(cx, cy, r, r), w=w, color=color)


def ellipse(x0, y0, x1, y1, w=1.0, color=BLACK):
    return stroke(_circle_pts((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2), w=w, color=color)


def ring_around(hit, pad_x=2.5, pad_y=1.5, w=1.0, color=BLACK):
    """An ellipse around a printed word found with Page.find(): hit = (x0, x1, baseline, size)."""
    x0, x1, base, size = hit
    return ellipse(x0 - pad_x, base - 0.75 * size - pad_y, x1 + pad_x, base + 0.2 * size + pad_y, w, color)


def check(cx, cy, s=3.2, w=1.3, color=BLACK):
    """A tick mark centred on (cx, cy); s ~ half the box size."""
    return stroke([(cx - s * 0.9, cy - s * 0.05), (cx - s * 0.25, cy + s * 0.75), (cx + s, cy - s * 0.9)],
                  w=w, color=color)


def cross(cx, cy, r=4.5, w=1.8, color=RED):
    return [stroke([(cx - r, cy - r), (cx + r, cy + r)], w=w, color=color),
            stroke([(cx - r, cy + r), (cx + r, cy - r)], w=w, color=color)]


def polygon(pts, color=BLACK, w=0.6, fill=255):
    pts = list(pts) + [pts[0]]
    return stroke(pts, w=w, color=color, fill=fill)


def triangle(cx, cy, h, direction="up", color=BLACK, margin=0.9):
    """A filled triangle of half-size h pointing up/down/left/right, kept `margin`
    inside the printed outline."""
    m = margin
    if direction == "up":
        pts = [(cx, cy - h + m), (cx - h + m, cy + h - m), (cx + h - m, cy + h - m)]
    elif direction == "down":
        pts = [(cx, cy + h - m), (cx - h + m, cy - h + m), (cx + h - m, cy - h + m)]
    elif direction == "right":
        pts = [(cx + h - m, cy), (cx - h + m, cy - h + m), (cx - h + m, cy + h - m)]
    else:
        pts = [(cx - h + m, cy), (cx + h - m, cy - h + m), (cx + h - m, cy + h - m)]
    return polygon(pts, color)


def rect(x0, y0, x1, y1, color=WHITE, w=0.3, fill=255):
    """A filled rectangle. In white it hides a printed default value you must replace."""
    return stroke([(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)], w=w, color=color, fill=fill)


def image(img, left, top, width_pt):
    """A PIL image (or PNG bytes) as an <image> element, `width_pt` points wide."""
    if isinstance(img, (bytes, bytearray)):
        data = bytes(img)
        w, h = Image.open(io.BytesIO(data)).size
    else:
        buf = io.BytesIO()
        img.save(buf, "PNG")
        data = buf.getvalue()
        w, h = img.size
    height_pt = width_pt * h / w
    b64 = base64.b64encode(data).decode("ascii")
    return (f'<image left="{left:.2f}" top="{top:.2f}" right="{left + width_pt:.2f}" '
            f'bottom="{top + height_pt:.2f}">{b64}</image>')


def text_image(runs, size, angle_deg=0.0, scale=8, color=(0, 0, 0, 255)):
    """One line of text rendered with PIL, optionally rotated, for places where a
    text element cannot go (slanted rules, curved boxes). `runs` = [(text, font name)].
    Returns (PIL image, points_per_pixel, (baseline_x, baseline_y) of the left end
    of the baseline inside the image, in points)."""
    fonts = {n: ImageFont.truetype(font_file(n), int(size * scale)) for _, n in runs}
    asc = max(f.getmetrics()[0] for f in fonts.values())
    desc = max(f.getmetrics()[1] for f in fonts.values())
    width = sum(fonts[n].getlength(t) for t, n in runs)
    pad = 4 * scale
    W, H = int(width) + 2 * pad, asc + desc + 2 * pad
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    x = pad
    for t, n in runs:
        draw.text((x, pad), t, font=fonts[n], fill=color)
        x += fonts[n].getlength(t)
    ang = math.radians(angle_deg)
    rot = img.rotate(-angle_deg, resample=Image.BICUBIC, expand=True)
    dx, dy = pad - W / 2, pad + asc - H / 2
    px = rot.width / 2 + dx * math.cos(ang) - dy * math.sin(ang)
    py = rot.height / 2 + dx * math.sin(ang) + dy * math.cos(ang)
    return rot, 1.0 / scale, (px / scale, py / scale)


# --- reading the printed sheet ------------------------------------------------------
def _norm(s):
    return s.lower().replace("’", "'").replace("‘", "'").replace(" ", " ")


SYMBOL_FONT_HINTS = ("wingding", "dingbat", "symbol", "webdings", "zapf")


class Page:
    """Everything printed on one page of a PDF, with positions (from `mutool trace`).

    - lines: [(baseline, text, spans)] of the printed words, top to bottom
    - symbols: glyphs from symbol fonts (Wingdings, ZapfDingbats...): the dots,
      boxes and triangles many sheets are made of
    - shapes: vector paths (rules, boxes, circles) with bounding boxes
    """

    def __init__(self, pdf, pageno, cache_dir=None):
        self.pdf, self.pageno = os.path.abspath(pdf), pageno
        cache_dir = cache_dir or tempfile.gettempdir()
        tag = os.path.basename(pdf).replace(" ", "_")
        path = os.path.join(cache_dir, f"trace-{tag}-p{pageno}.xml")
        if not os.path.exists(path) or os.path.getmtime(path) < os.path.getmtime(pdf):
            with open(path, "w") as fh:
                subprocess.run(["mutool", "trace", self.pdf, str(pageno)], stdout=fh, check=True)
        root = ET.fromstring(open(path).read())
        page = root.find("page")
        mb = [float(v) for v in page.get("mediabox").split()]
        self.width, self.height = mb[2] - mb[0], mb[3] - mb[1]
        self.symbols, self.shapes = [], []
        chars = []
        for ft in root.iter("fill_text"):
            a, b, c, d, e, f = (float(v) for v in ft.get("transform").split())
            color = ft.get("color")
            for sp in ft:
                if sp.tag != "span":
                    continue
                font = sp.get("font", "").split("+")[-1]
                size = float(sp.get("trm").split()[0])
                symbolic = any(h in font.lower() for h in SYMBOL_FONT_HINTS)
                for g in sp:
                    x, y = float(g.get("x")), float(g.get("y"))
                    X, Y = a * x + c * y + e, b * x + d * y + f
                    adv = float(g.get("adv")) * size
                    if (g.get("unicode") or "").isspace():
                        continue  # spacing glyphs, in symbol fonts too
                    if symbolic:
                        self.symbols.append(dict(font=font, glyph=g.get("glyph"), x=X, y=Y,
                                                 size=size, adv=adv, color=color))
                    else:
                        chars.append((X, Y, size, adv, g.get("unicode") or ""))
        for el in root.iter():
            if el.tag not in ("fill_path", "stroke_path"):
                continue
            a, b, c, d, e, f = (float(v) for v in el.get("transform").split())
            pts = []
            for ch in el:
                if ch.tag in ("moveto", "lineto"):
                    x, y = float(ch.get("x")), float(ch.get("y"))
                    pts.append((a * x + c * y + e, b * x + d * y + f))
                elif ch.tag == "curveto":
                    for k in ("1", "2", "3"):
                        x, y = float(ch.get("x" + k)), float(ch.get("y" + k))
                        pts.append((a * x + c * y + e, b * x + d * y + f))
            if not pts:
                continue
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            self.shapes.append(dict(kind=el.tag, color=el.get("color"), lw=el.get("linewidth"),
                                    curved=any(ch.tag == "curveto" for ch in el), n=len(pts),
                                    x0=min(xs), y0=min(ys), x1=max(xs), y1=max(ys)))
        grouped = {}
        for ch in chars:
            grouped.setdefault(round(ch[1] * 2) / 2, []).append(ch)
        self.lines = []
        for base, cs in sorted(grouped.items()):
            cs.sort()
            txt, spans, prev_end = "", [], None
            for x, y, size, adv, u in cs:
                if prev_end is not None and x - prev_end > 0.25 * size and not txt.endswith(" "):
                    txt += " "
                    spans.append(None)
                u = _norm(u)
                txt += u
                spans.extend([(x, x + adv, size)] * len(u))
                prev_end = x + adv
            self.lines.append((base, txt, spans))

    @property
    def has_text(self):
        return bool(self.lines)

    def find_all(self, needle, xr=None, yr=None):
        """Every occurrence of `needle` (case-insensitive) -> [(x0, x1, baseline, size)].
        Ligatures 'fi'/'fl' are stored as 'if'/'lf' by some fonts; retried swapped."""
        needle = _norm(needle)
        out = self._find_all(needle, xr, yr)
        if not out and ("fi" in needle or "fl" in needle):
            out = self._find_all(needle.replace("fi", "if").replace("fl", "lf"), xr, yr)
        return out

    def _find_all(self, needle, xr, yr):
        out = []
        for base, txt, spans in self.lines:
            if yr and not (yr[0] <= base <= yr[1]):
                continue
            start = 0
            while True:
                i = txt.find(needle, start)
                if i < 0:
                    break
                start = i + 1
                sp = [s for s in spans[i:i + len(needle)] if s]
                if not sp:
                    continue
                x0, x1 = min(s[0] for s in sp), max(s[1] for s in sp)
                if xr and not (xr[0] <= x0 <= xr[1]):
                    continue
                out.append((x0, x1, base, sp[0][2]))
        return out

    def find(self, needle, xr=None, yr=None):
        hits = self.find_all(needle, xr, yr)
        if not hits:
            raise SystemExit(f"text not found on page {self.pageno}: {needle!r} (x={xr}, y={yr})")
        return hits[0]

    def symbols_near(self, baseline, font=None, glyph=None, xr=None, tol=5.0):
        """Symbol glyphs on a printed line, left to right."""
        out = [s for s in self.symbols
               if abs(s["y"] - baseline) <= tol
               and (font is None or s["font"].lower().startswith(font.lower()))
               and (glyph is None or s["glyph"] in glyph)
               and (xr is None or xr[0] <= s["x"] <= xr[1])]
        return sorted(out, key=lambda s: s["x"])

    def rules(self, min_len=40, xr=None, yr=None):
        """Horizontal printed lines -> [(y, x0, x1)] top to bottom."""
        out = []
        for s in self.shapes:
            if s["kind"] != "stroke_path" or abs(s["y1"] - s["y0"]) > 0.5 or s["x1"] - s["x0"] < min_len:
                continue
            if xr and not (xr[0] <= s["x0"] <= xr[1]):
                continue
            if yr and not (yr[0] <= s["y0"] <= yr[1]):
                continue
            out.append((s["y0"], s["x0"], s["x1"]))
        return sorted(out)

    def small_shapes(self, max_size=20, xr=None, yr=None):
        """Small vector paths (boxes, circles, ticks) -> dicts with centre cx, cy."""
        out = []
        for s in self.shapes:
            w, h = s["x1"] - s["x0"], s["y1"] - s["y0"]
            if w > max_size or h > max_size or (w < 1 and h < 1):
                continue
            cx, cy = (s["x0"] + s["x1"]) / 2, (s["y0"] + s["y1"]) / 2
            if xr and not (xr[0] <= cx <= xr[1]):
                continue
            if yr and not (yr[0] <= cy <= yr[1]):
                continue
            out.append(dict(s, cx=cx, cy=cy, w=w, h=h))
        return sorted(out, key=lambda s: (round(s["cy"]), s["cx"]))

    def shapes_near(self, baseline, xr=None, tol=6.0, max_size=20):
        """Small vector shapes whose centre sits on a printed line (boxes drawn as paths)."""
        return [s for s in self.small_shapes(max_size, xr) if abs(s["cy"] - (baseline - 3)) <= tol]


def sym_center(s):
    """Centre of a symbol glyph (dot, box, triangle): the ink sits above the baseline."""
    return s["x"] + s["adv"] / 2, s["y"] - 0.35 * s["size"]


# --- writing ------------------------------------------------------------------------
def page_pdf(pageno, els, bg_pdf, first, size):
    """A page whose background is page `pageno` of `bg_pdf`. Only the first page of
    a file names the PDF (absolute path); later pages reuse it."""
    w, h = size
    bg = (f'<background type="pdf" domain="absolute" filename="{escape(os.path.abspath(bg_pdf))}" pageno="{pageno}"/>'
          if first else f'<background type="pdf" pageno="{pageno}"/>')
    return f'<page width="{w}" height="{h}">\n{bg}\n<layer>\n' + "\n".join(els) + '\n</layer>\n</page>'


def page_blank(els, size, color="#ffffffff"):
    w, h = size
    return (f'<page width="{w}" height="{h}">\n<background type="solid" color="{color}" style="plain"/>\n'
            '<layer>\n' + "\n".join(els) + '\n</layer>\n</page>')


def xopp_xml(pages, creator="make_sheets.py"):
    return ('<?xml version="1.0" standalone="no"?>\n'
            f'<xournal creator="{creator}" fileversion="4">\n'
            '<title>Xournal++ document - see https://xournalpp.github.io/</title>\n'
            + "\n".join(pages) + "\n</xournal>\n")


def write_xopp(path, xml):
    with gzip.open(path, "wb") as fh:
        fh.write(xml.encode("utf-8"))


def export_pdf(xopp_path, pdf_path=None):
    """xournalpp --create-pdf with the clean font environment. Returns the PDF path or None."""
    pdf_path = pdf_path or os.path.splitext(xopp_path)[0] + ".pdf"
    r = subprocess.run(["xournalpp", f"--create-pdf={pdf_path}", xopp_path],
                       capture_output=True, text=True, env=_CLEAN_ENV)
    ok = r.returncode == 0 and os.path.exists(pdf_path)
    print(("ok   " if ok else "FAIL ") + (pdf_path if ok else f"{xopp_path}  {r.stderr.strip()[-400:]}"))
    return pdf_path if ok else None


def merge_pdfs(pdfs, out):
    if shutil.which("qpdf"):
        subprocess.run(["qpdf", "--empty", "--pages", *pdfs, "--", out], check=True)
    else:
        subprocess.run(["pdfunite", *pdfs, out], check=True)
    print("ok   " + out)
    return out


def render_png(pdf, out_prefix, dpi=110, pages=None):
    """Render pages to <out_prefix>_<n>.png so you can LOOK at the result."""
    args = ["mutool", "draw", "-r", str(dpi), "-o", f"{out_prefix}_%d.png", pdf]
    if pages:
        args.append(pages)
    subprocess.run(args, check=True, capture_output=True)
