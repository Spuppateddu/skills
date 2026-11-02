---
name: music-tagger
description: Clean up a folder of songs (mp3, m4a) — find every song on MusicBrainz, write full tags (title, artist, album artist, album, year, track number, genre, MusicBrainz ids) and embed the album cover, rename the files to "Artist - Title", and move duplicates away. Works in two steps — a scan that changes nothing and writes a report the user reviews and edits, then apply — with an undo. Does what MusicBrainz Picard does, but from the command line. Use when the user is in or points at a music folder and says e.g. "tag my music", "fix the metadata of these songs", "add the album covers", "remove duplicate songs", "rename the mp3 files", "sistema i metadati delle canzoni", "run picard on this folder".
---

# music-tagger

Tag, add covers to, rename and de-duplicate a folder of songs. Same data as
MusicBrainz Picard (MusicBrainz for the tags, the Cover Art Archive for the
covers, AcoustID for fingerprints), but scripted, and **nothing changes before
the user has seen and accepted a report**.

Script: `scripts/music_tagger.py` (below, `MT` = `python3 <skill dir>/scripts/music_tagger.py`).

## Ground rules

- **Never `apply` before the user has accepted the report** in this conversation.
  A new scan, or an edit the user did not ask for, means asking again.
- Nothing is ever deleted: duplicates go to `<folder>/_duplicates/`. Tell the user
  they can delete that folder themselves once they've listened.
- Every `apply` can be reversed with `undo`.
- The folder is the user's music, so never run anything that modifies files
  besides `apply` / `undo`.

## Setup — automatic, on first use

Nothing to install by hand, nothing system-wide, no sudo:

- `fpcalc` (Chromaprint): taken from `PATH`, or the official static build is
  downloaded once into `~/.cache/music-tagger/bin/`.
- `mutagen` (Python tag library): used if installed, else a venv is made once in
  `~/.cache/music-tagger/venv/`.
- Every web answer and cover is cached in `~/.cache/music-tagger/`, so a second
  scan of the same folder takes minutes, not an hour.

**Optional — AcoustID key.** Without it, songs are found from their existing
MusicBrainz id, their tags, or their file name. With it, songs with a useless
name (`Track 01.mp3`, `ANTHEM.mp3`) are also found by the sound itself. The
user gets a free key at <https://acoustid.org/new-application>, then:
`mkdir -p ~/.config/music-tagger && echo KEY > ~/.config/music-tagger/acoustid.key`
(or `export ACOUSTID_API_KEY=KEY`). Mention this once if the report shows many
"not found" songs and no key is set.

## Flow

1. **Scan** (changes nothing):
   ```bash
   MT scan "<folder>"            # add --limit 30 for a quick try
   ```
   MusicBrainz allows 1 request per second, so a first scan takes about
   **2 seconds per song** (≈ 1 hour for 1500 songs). Run it in the background
   and wait. It writes `<folder>/.music-tagger/plan.json` and `report.md`,
   and prints a summary.

2. **Show the report.** Give the user the printed summary, then the parts that
   need a human, in this order, read from `report.md`:
   - 🗑️ duplicate groups (which one is kept, which one moves away, and why — bitrate),
   - ⚠️ matches to check, with the reason,
   - ❓ not found and 🎛️ speed-up/cover versions (they only get a cleaner name),
   - a handful of ✅ rows as a sample. Link `report.md` for the full list.

   Then ask: **accept, or change something?**

3. **Edit** what the user asks for. Songs are referred to by their `#` number:
   ```bash
   MT edit "<folder>" 12 action=skip                 # leave it alone
   MT edit "<folder>" 3,7,10-15 action=rename        # clean the name only, no tags
   MT edit "<folder>" 40 action=tag                  # tag a duplicate instead of moving it
   MT edit "<folder>" 41 action=remove               # treat as a duplicate
   MT edit "<folder>" 9 title="Vai" album="Vai!"     # fix a tag by hand
   MT edit "<folder>" 9 name="ALFA - Vai.mp3"        # force a file name
   ```
   Actions: `tag` (tags + cover + rename), `rename` (name only), `skip`,
   `remove` (move to `_duplicates/`). Tag fields: title, artist, albumartist,
   album, date, tracknumber, totaltracks, discnumber, genre.
   Each edit prints the new summary; show what changed and ask again.

4. **Apply**, once the user accepts:
   ```bash
   MT apply "<folder>" --dry-run   # optional: lists every step
   MT apply "<folder>"
   ```
   Files that changed since the scan are left alone and counted as `changed`.
   Songs whose tags already match are not rewritten, so re-running the skill on
   a synced folder (MEGA, Dropbox…) only re-uploads the files that really change.
   If many changed, scan again rather than apply an old plan.

5. **Undo** if the user doesn't like the result:
   ```bash
   MT undo "<folder>"              # the last apply; --run <dir> for an older one
   ```

## What it decides on its own

- **Which song.** In order: the MusicBrainz recording id already in the tags
  (an earlier Picard run), a MusicBrainz search on the tags, a search on the
  cleaned file name, then AcoustID if a key is set. Old ids are often wrong
  (a bad Picard match): when the file name disagrees with them — other title,
  an artist not credited, a version word like "remix" missing — the file name
  is searched again and a sure hit replaces the old id; otherwise ⚠️.
  A version word in the file name (remix, acoustic, live, cover, English…)
  must be in the match too. A search hit counts only if
  the title and an artist are both in the name, and the length is within 45 s.
  Within 7 s and with no unexplained words it is ✅; otherwise ⚠️ with the reason.
- **Which album.** Official release, the artist's own album, then single or EP,
  then the earliest. Compilations, live, remix and DJ-mix albums lose, and so do
  soundtracks, a little. An album already in the tags only breaks ties: earlier
  Picard runs often picked "Hits 2019"-style compilations.
- **Speed-up, nightcore, slowed, 8D, karaoke, "cover by …"** are not the
  original recording: they are never tagged as the original, only renamed.
- **Duplicates** are decided by the **sound only**: ≥ 90% equal fingerprint
  bits within a ±5 s shift (copies score ~0.96, remixes/covers ≤ 0.70), lengths
  within 20 s, the same version words in both names ("English Version" vs
  "Japanese Version" share the music, not the vocals), never a speed-up
  version. The highest bitrate is kept. Songs with the same MusicBrainz id but
  different audio are only listed (🔁) — old ids can be wrong.
- **Names** follow one standard (the flat-folder form of Picard's and beets'
  naming; both sort albums into `Artist/Album/NN Title` folders, a flat
  playlist folder uses `Artist - Title`):
  - `Artist - Title.ext`, with the artist and title exactly as MusicBrainz
    writes them: featured artists in the artist part (`A feat. B - Title`),
    MusicBrainz capitalization, version info kept (`(… remix)`, `(live)`).
  - `/ \ : * ? " < > |` and control characters become `_` (Picard/beets
    rule), so files copy to phones, USB sticks and Windows. Typographic dashes
    and quotes become `-` and `'`. A leading `.` or `-` becomes `_`.
  - Non-Latin letters are kept, in Unicode NFC form. At most 200 UTF-8 bytes,
    because Linux allows 255 bytes per name and one CJK letter takes 3.
  - Extension in lower case. A clash gets ` (Album)`, then ` (2)`. Names that
    differ only by case also clash, because phones and USB sticks ignore case.
  - Songs not found keep their name, minus YouTube noise like
    `(Official Video)`, `Lyrics`, `(1)`, or a leading `0002 - `.
  - `report` re-applies these rules to an existing plan (hand-set names stay).
- **Tags** are written as ID3v2.3 for mp3 (what every car stereo and phone
  reads), with the cover as a 500 px JPEG. Other tags already in the file are kept.

## Files

- `<folder>/.music-tagger/plan.json` — the plan; `report.md` — the report.
- `<folder>/.music-tagger/undo-<time>/` — journal + old tags, one per apply.
- `<folder>/_duplicates/` — moved duplicates.

Only `.mp3` and `.m4a` files directly inside the folder are handled; other
files are listed in the report and left alone.
