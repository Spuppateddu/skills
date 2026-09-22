#!/usr/bin/env bash
# Check that everything the skill needs is installed.
ok=0
for t in xournalpp mutool pdftotext pdfinfo fc-match python3; do
  if command -v "$t" >/dev/null 2>&1; then echo "ok    $t"; else echo "MISSING $t"; ok=1; fi
done
if command -v qpdf >/dev/null 2>&1 || command -v pdfunite >/dev/null 2>&1; then echo "ok    qpdf or pdfunite"; else echo "MISSING qpdf (or pdfunite)"; ok=1; fi
python3 -c "import PIL; print('ok    Pillow', PIL.__version__)" 2>/dev/null || { echo "MISSING python3 Pillow (pip install pillow)"; ok=1; }
echo "fonts (clean fontconfig):"
for f in "Liberation Sans" "Liberation Sans Bold" "Georgia" "Georgia Bold" "DejaVu Sans"; do
  pat=$(python3 -c "import sys; sys.path.insert(0, \"$(dirname "$0")\"); import xopp_lib; print(xopp_lib.fc_pattern(sys.argv[1]))" "$f")
  printf "  %-22s -> %s\n" "$f" "$(XDG_CONFIG_HOME=$(mktemp -d) fc-match -f '%{family} %{style}: %{file}' "$pat")"
done
echo "Debian/Ubuntu: apt install xournalpp mupdf-tools poppler-utils qpdf fonts-liberation python3-pil"
exit $ok
