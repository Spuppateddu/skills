---
name: pdf-doc
description: Write a document as a styled, self-contained HTML file and render it to PDF — reports, proposals, offers, manuals, specs, briefs. Every document shares one layout (cover page, auto-generated table of contents, consistent tables/callouts/code), so a whole set of PDFs looks like it came from the same house. The brand colour (one or two), the optional logo, the language and the verbal style (formal, plain/non-technical, technical, commercial) are asked at the start and baked into the file. The HTML stays editable: change the text or the colours, re-run the converter, get an updated PDF — the table of contents rebuilds itself. Installs nothing; renders with the Chrome/Chromium already on the machine (WeasyPrint or wkhtmltopdf as fallbacks). Use when the user says e.g. "make a PDF report", "write a proposal as a PDF", "genera un PDF", "create a branded document", "turn this into a nice PDF", "regenerate the PDF from the HTML".
---

# pdf-doc

Produce a document in two files that stay in sync:

- `<name>.html` — the source. Self-contained: the stylesheet is inlined and the
  logo is base64-embedded, so it is one portable file the user can open, read,
  and edit in any editor.
- `<name>.pdf` — the render.

The loop is: **generate once → edit the HTML freely → re-run the converter.**
Never regenerate a document from scratch to apply an edit; that throws away the
user's changes. After the first generation, the HTML is the source of truth.

## Scripts

All paths are relative to this skill folder. Run them with `bash`.

| Script | Purpose |
|---|---|
| `scripts/new_doc.sh` | Build the HTML: cover, TOC scaffold, brand tokens, inlined stylesheet, embedded logo. Run **once** per document. |
| `scripts/html2pdf.sh` | Rebuild the TOC, then render to PDF. Run every time. |
| `scripts/refresh_toc.sh` | Rebuild only the TOC. Called automatically by the two above; rarely needed on its own. |

## Step 1 — ask before writing

Ask for anything the user has not already given. Use one `AskUserQuestion` with
several questions rather than a series of messages. What you need:

1. **Colour** — one or two hex colours. One colour is enough; the second is used
   for accents (the cover rule, pull quotes, alternate callouts, sub-section
   numbers). Offer a few concrete options plus a custom hex, e.g.
   deep blue `#1F4E79`, graphite `#2E3338`, forest `#1E5945`, burgundy `#7A2E39`.
   Any hex works — pale colours are darkened automatically for heading text, and
   the cover's text flips to dark when the brand colour is light.
2. **Logo** — a path to a png/jpg/svg/webp/gif, or none. If the logo artwork is
   dark and the cover band is dark, pass `--logo-invert` to knock it out white.
3. **Language** — the language of the document. Everything visible is written in
   it, including the cover labels and the TOC heading.
4. **Verbal style** — see the table below.
5. **Cover metadata** — client, author, date, version, reference… whatever fits.
   Labels in the document's language.

Do not ask about layout, fonts, margins or page furniture. Those are fixed on
purpose — that fixity is what makes every PDF from this skill match.

### Verbal styles

| Style | How to write |
|---|---|
| `formal` | Impersonal and precise. No contractions, no exclamations, complete sentences. In Italian/Spanish/German use the impersonal or the formal address consistently. Suits contracts, offers, official reports. |
| `plain` (non-technical) | Short sentences, active voice, address the reader directly. Every technical term either avoided or explained in the same sentence. No jargon left bare. Suits clients and stakeholders who do not share your domain. |
| `technical` | Exact terminology, real names, versions, commands, parameters. Code and tables where they carry information better than prose. No marketing adjectives. Suits engineers. |
| `commercial` | Lead with the outcome for the reader, then the substance. Concrete and quantified; no hype, no superlatives. Suits proposals and offers. |

Hold the chosen style for the whole document, including headings and captions.

## Step 2 — write the content

Write the body as an HTML fragment in a temporary file (put it in your scratch
directory, not next to the user's document). Only content — no `<html>`,
`<head>`, `<body>`, no `<style>`, no cover, no TOC. Those come from the
generator.

Structure it with `<h2>` for sections and `<h3>` for sub-sections: the table of
contents is built from exactly those, so the heading structure *is* the outline.

Write real content from what the user actually gave you. If the document needs
facts you do not have, ask for them or leave a clearly marked placeholder — never
invent figures, dates, names or prices.

### Components

Use these and nothing else; they are what the stylesheet covers.

```html
<h2>Section</h2>                 <h3>Sub-section</h3>     <h4>Minor heading</h4>
<p class="lead">Opening paragraph, slightly larger.</p>
<p>Body text with <strong>emphasis</strong> and <code>inline_code()</code>.</p>
<ul><li>…</li></ul>              <ol><li>…</li></ol>

<div class="callout">
  <p class="callout__title">Heads up</p>
  <p>Boxed aside in the primary colour.</p>
</div>
<div class="callout accent">…</div>   <!-- second colour -->
<div class="callout plain">…</div>    <!-- neutral grey -->

<blockquote>Quotation.<cite>— Attribution</cite></blockquote>

<table>
  <caption>Optional caption</caption>
  <thead><tr><th>Item</th><th class="num">Amount</th></tr></thead>
  <tbody><tr><td>Licence</td><td class="num">1 200</td></tr></tbody>
  <tfoot><tr><td>Total</td><td class="num">1 200</td></tr></tfoot>
</table>

<pre><code>command --flag</code></pre>

<dl class="defs"><dt>Term</dt><dd>Definition.</dd></dl>
<figure><img src="data:image/png;base64,…" alt=""><figcaption>Caption</figcaption></figure>
<div class="cols">…</div>             <!-- two columns -->
<div class="signatures"><div>Client</div><div>Supplier</div></div>
<p class="small">Fine print.</p>
<div class="page-break"></div>        <!-- force a new page -->
```

`class="num"` right-aligns a numeric column. A table that must span pages needs
`<table class="long">`; by default tables are kept whole on one page.

**Never** reference anything external — no CDN, no web font, no remote image, no
`<script>`. The file must render identically with no network. Images go in as
`data:` URIs.

## Step 3 — generate

```bash
bash scripts/new_doc.sh \
  --title    "Piattaforma di Analisi Dati" \
  --subtitle "Proposta tecnica per il rinnovo dell'infrastruttura" \
  --eyebrow  "Proposta commerciale" \
  --color "#1F4E79" --color2 "#E8833A" \
  --logo /path/to/logo.png \
  --lang it --numbered \
  --meta "Cliente|Acme S.p.A." --meta "Autore|Alessandro" --meta "Data|4 agosto 2026" \
  --content /tmp/…/body.html \
  -o "$HOME/Documents/proposta-acme.html"
```

| Option | Notes |
|---|---|
| `--title` | Required. |
| `--subtitle`, `--eyebrow` | Cover only. The eyebrow is the small uppercase line above the title (document type, e.g. "Technical report"). |
| `--color`, `--color2` | `#rrggbb` or `#rgb`. Omit `--color2` for a single-colour document — accents then reuse the primary. |
| `--logo`, `--logo-invert` | Embedded into the file; the original is not referenced afterwards. |
| `--lang` | BCP-47 code (`it`, `en`, `fr`…). Sets `<html lang>` and the default TOC heading. |
| `--toc-title` | Override the TOC heading (defaults per language: Indice, Contents, Sommaire, Inhalt, Índice, Inhoud). |
| `--no-toc` | Drop the TOC page — right for anything under ~4 sections. |
| `--numbered` | Number the sections (1., 1.1). Good for formal and technical documents. |
| `--compact-header` | Masthead instead of a cover page: the band shrinks to a banner at the top of page 1 and the TOC follows underneath it, saving a page. Rejects `--no-toc` and `--meta` (see below). |
| `--meta "Label\|Value"` | Repeatable; each becomes a cover metadata row, in order. |
| `--content FILE` | The fragment from step 2. |
| `-o FILE` | Output path. Defaults to a slug of the title in the current directory. |

Ask the user where the document should go if it is not obvious. Do not scatter
files into the repository you happen to be working in.

### `--compact-header`

The default cover owns a whole page: logo and title on the coloured band, then
the metadata rows at the foot. `--compact-header` keeps the band — full-bleed on
the top and side edges, logo and title inside it — but shrinks it to a masthead
and lets the table of contents start on the same page. Right for short internal
documents, handovers and specs, where a full cover page reads as ceremony.

It comes with two hard edges, both enforced by the generator rather than left to
surprise you at render time:

- **It needs the TOC.** The first page keeps the zero margin that lets the band
  bleed, and the TOC underneath is what re-creates that margin for the rest of
  the page. `--compact-header --no-toc` is refused.
- **It has no metadata block.** A masthead has no room for it, so `--meta` is
  refused rather than silently dropped — losing the client or the date off a
  document is worse than an error. Fold anything essential into the subtitle or
  the body.

## Step 4 — render, and re-render

```bash
bash scripts/html2pdf.sh path/to/document.html            # → document.pdf
bash scripts/html2pdf.sh path/to/document.html out.pdf    # explicit output
```

It picks Chrome/Chromium if present, else WeasyPrint, else wkhtmltopdf
(`--engine NAME` forces one). It prints the output path and the page count.

This is also the *only* step needed after an edit. Adding, removing or renaming a
heading in the HTML updates the table of contents on the next run — the TOC is
regenerated from the headings every time, and headings get stable `id`s
automatically.

To restyle a finished document, edit the `:root` block in its
`<style id="doc-tokens">` — for instance change `--brand` and `--brand-ink` — and
re-render. To change one document's look without touching the shared layout, put
rules in its `<style id="doc-overrides">` block at the end of the file.

Page numbers are off by default; each generated file carries the CSS for them,
commented out, just above `</style>` in `doc-style`. Uncomment those five lines to
print `3 / 12` at the foot of every page but the cover.

## Verify before reporting done

Render the PDF and actually look at it, rather than trusting that it worked:

```bash
pdftoppm -png -r 68 document.pdf /tmp/…/pg    # then Read the page images
```

Check the cover (logo legible against the band, no clipped title), the TOC (every
section present, no duplicates), and that no table, callout or code block is
split awkwardly. Report the page count and both file paths.

## Notes and limits

- **Fonts.** The stylesheet resolves its faces through `@font-face`/`local()`,
  which deliberately bypasses any system-wide font alias — otherwise a machine
  configured to default everything to, say, a monospace font would render the
  whole document in it. Nothing is downloaded. If a logo is an SVG containing
  live `<text>`, it still depends on the machine's fonts; prefer a PNG or an SVG
  with outlined paths.
- **What Chrome cannot do.** No page numbers in the TOC (`target-counter` is
  unsupported), and no running headers built from section titles (`string-set` is
  unsupported). `counter(page)` in `@page` margin boxes *does* work, which is why
  the optional footer above is available. WeasyPrint supports the other two if a
  document genuinely needs them.
- **Headings must sit on one line** in the HTML (`<h2 id="x">Title</h2>`), or the
  TOC builder skips them.
- **The stylesheet is shared.** `assets/doc.css` is inlined into every document at
  generation time. Editing it changes documents generated afterwards, not ones
  already produced. Do not add per-document rules to it.
