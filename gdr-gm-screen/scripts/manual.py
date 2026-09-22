#!/usr/bin/env python3
"""manual.py — read a rulebook PDF without opening the whole thing.

    manual.py extract <manual.pdf> <out-dir>       text + outline into out-dir/
    manual.py toc     <out-dir>                    chapters with their PDF pages
    manual.py grep    <out-dir> <regex> [-C N] [-i]  matches, prefixed with the PDF page
    manual.py page    <out-dir> <N>[-M] [-o FILE]  print those PDF pages (or write them to FILE)

`extract` writes:
  full-layout.txt  the text of every page (pdftotext -layout), pages split by
                   form feed, so tables and columns keep their shape;
  outline.md       the PDF bookmarks with their PDF page numbers (pdftohtml),
                   when the file has any — this is the fastest map of the book;
  README.md        what these files are and how to search them.

A page is 3-6 K characters: print at most 2-3 per call, or use `-o FILE` and
Read the file in chunks, so the output never overflows the tool limit.

Page numbers are always PDF pages (what a viewer shows), not the numbers
printed on the book's pages. Quote them as "pdf p.N".
Needs poppler-utils (pdftotext, pdftohtml, pdfinfo).
"""
import html
import os
import re
import subprocess
import sys
import tempfile


def die(msg):
    sys.exit("manual.py: " + msg)


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, errors="replace").stdout


def extract(pdf, out):
    if not os.path.isfile(pdf):
        die("no such file: " + pdf)
    os.makedirs(out, exist_ok=True)
    layout = os.path.join(out, "full-layout.txt")
    subprocess.run(["pdftotext", "-layout", pdf, layout], check=True)
    pages = open(layout, encoding="utf-8", errors="replace").read().split("\f")
    if pages and not pages[-1].strip():
        pages.pop()
    # outline via pdftohtml -xml (bookmarks carry the PDF page number)
    items = []
    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, "o")
        subprocess.run(["pdftohtml", "-xml", "-i", "-q", "-l", "1", pdf, base],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        xml = base + ".xml"
        if os.path.isfile(xml):
            x = open(xml, encoding="utf-8", errors="replace").read()
            depth = 0
            for tok in re.finditer(r"<outline>|</outline>|<item page=\"(\d+)\">(.*?)</item>", x, re.S):
                if tok.group(0) == "<outline>":
                    depth += 1
                elif tok.group(0) == "</outline>":
                    depth -= 1
                else:
                    title = html.unescape(re.sub(r"<[^>]+>", "", tok.group(2))).strip()
                    items.append((max(depth - 1, 0), int(tok.group(1)), title))
    with open(os.path.join(out, "outline.md"), "w", encoding="utf-8") as f:
        f.write("# Outline (PDF bookmarks) — page numbers are PDF pages\n\n")
        if items:
            for d, p, t in items:
                f.write("%s- %s (pdf p.%d)\n" % ("  " * d, t, p))
        else:
            f.write("(no bookmarks in this PDF — find the table of contents with:\n"
                    "  manual.py grep <out-dir> 'sommario|indice|contents' -i)\n")
    info = run(["pdfinfo", pdf]) if shutil_which("pdfinfo") else ""
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as f:
        f.write("# %s — text extracted for the GM screen\n\n" % os.path.basename(pdf))
        f.write("Source: `%s` (%d PDF pages).\n\n" % (os.path.basename(pdf), len(pages)))
        f.write("- `full-layout.txt` — every page, split by form feed, columns and tables kept.\n")
        f.write("- `outline.md` — the PDF bookmarks with PDF page numbers (%s).\n" %
                ("%d entries" % len(items) if items else "none in this file"))
        f.write("\nSearch with `manual.py grep <this-dir> '<regex>' -C 3`, read pages with "
                "`manual.py page <this-dir> 40-42`. Page numbers are PDF pages.\n")
        if info:
            f.write("\n```\n%s```\n" % info)
    print("%s: %d pages, %d outline entries -> %s" % (os.path.basename(pdf), len(pages), len(items), out))


def shutil_which(name):
    from shutil import which
    return which(name)


def load_pages(out):
    layout = os.path.join(out, "full-layout.txt")
    if not os.path.isfile(layout):
        die("no full-layout.txt in %s — run: manual.py extract <manual.pdf> %s" % (out, out))
    pages = open(layout, encoding="utf-8", errors="replace").read().split("\f")
    if pages and not pages[-1].strip():
        pages.pop()
    return pages


def toc(out):
    path = os.path.join(out, "outline.md")
    if not os.path.isfile(path):
        die("no outline.md in " + out)
    sys.stdout.write(open(path, encoding="utf-8").read())


def grep(out, pattern, ctx, flags):
    pages = load_pages(out)
    rx = re.compile(pattern, flags)
    hits = 0
    for pno, page in enumerate(pages, 1):
        lines = page.splitlines()
        marks = [i for i, l in enumerate(lines) if rx.search(l)]
        if not marks:
            continue
        shown = set()
        for i in marks:
            for j in range(max(0, i - ctx), min(len(lines), i + ctx + 1)):
                shown.add(j)
        last = None
        for j in sorted(shown):
            if last is not None and j != last + 1:
                print("      ...")
            tag = ">>" if j in marks else "  "
            print("p.%-4d %s %s" % (pno, tag, lines[j].rstrip()))
            last = j
        print()
        hits += len(marks)
    print("%d matching lines" % hits)


def page(out, spec, dest=None):
    pages = load_pages(out)
    m = re.fullmatch(r"(\d+)(?:-(\d+))?", spec)
    if not m:
        die("page spec must be N or N-M")
    a, b = int(m.group(1)), int(m.group(2) or m.group(1))
    chunks = []
    for n in range(a, b + 1):
        if 1 <= n <= len(pages):
            chunks.append("=" * 30 + " pdf p.%d " % n + "=" * 30 + "\n" + pages[n - 1].rstrip())
    text = "\n".join(chunks) + "\n"
    if dest:
        open(dest, "w", encoding="utf-8").write(text)
        print("wrote pdf p.%d-%d (%d chars) to %s — Read it in chunks" % (a, b, len(text), dest))
    else:
        sys.stdout.write(text)


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip()); return
    cmd = argv[1]
    if cmd == "extract" and len(argv) == 4:
        extract(argv[2], argv[3])
    elif cmd == "toc" and len(argv) == 3:
        toc(argv[2])
    elif cmd == "grep" and len(argv) >= 4:
        ctx, flags, rest = 2, 0, []
        args = argv[4:]
        i = 0
        while i < len(args):
            if args[i] == "-C":
                ctx = int(args[i + 1]); i += 2
            elif args[i] == "-i":
                flags |= re.I; i += 1
            else:
                die("unknown option: " + args[i])
        grep(argv[2], argv[3], ctx, flags)
    elif cmd == "page" and len(argv) in (4, 6):
        dest = None
        if len(argv) == 6:
            if argv[4] != "-o":
                die("unknown option: " + argv[4])
            dest = argv[5]
        page(argv[2], argv[3], dest)
    else:
        die("bad arguments\n\n" + __doc__.strip())


if __name__ == "__main__":
    main(sys.argv)
