#!/usr/bin/env python3
"""music-tagger — tag a folder of songs from MusicBrainz, in two steps.

  scan   <folder>              look everything up, change nothing; writes
                               <folder>/.music-tagger/plan.json + report.md
  edit   <plan> <id> k=v ...   change one entry of the plan (action, name, tags)
  report <plan>                rebuild report.md after edits
  apply  <plan> [--dry-run]    write tags + cover, rename, move duplicates
  undo   <plan> [--run DIR]    reverse the last (or the given) apply

Song identity comes from, in order: the MusicBrainz recording id already in the
tags, a MusicBrainz text search (tags, then file name), then an AcoustID
fingerprint lookup when a key is configured. Covers come from the Cover Art
Archive. Duplicates are found by recording id and by audio fingerprint.
"""
import argparse
import difflib
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

CACHE = Path(os.environ.get("MUSIC_TAGGER_CACHE", Path.home() / ".cache" / "music-tagger"))
UA = "music-tagger-skill/1.0 ( https://github.com/Spuppateddu/skills )"
MB = "https://musicbrainz.org/ws/2/"
CAA = "https://coverartarchive.org/"
FPCALC_VERSION = "1.6.1"
AUDIO_EXT = {".mp3", ".m4a"}
WORKDIR = ".music-tagger"
DUP_DIR = "_duplicates"

# A song re-uploaded with a changed speed/pitch is not the original recording:
# never tag it as the original, only clean its name.
VARIANT_RE = re.compile(
    r"\b(speed\s*up|sped\s*up|spedup|nightcore|slowed|reverb|8d(\s*audio)?|daycore|"
    r"bass\s*boost(ed)?|tik\s*tok\s*version|cover\s+(by|di)|(drum|piano|guitar|violin|metal|rock|female|male)\s+cover|karaoke)\b|[\(\[]\s*cover\s*[\)\]]", re.I)
# Words in a MusicBrainz title that mark another version of the song.
VERSION_RE = re.compile(r"\b(remix|rmx|live|edit|version|acoustic|instrumental|mix|remaster(ed)?|demo|"
                        r"unplugged|extended|radio)\b", re.I)
# Version words in a FILE name: the match (and a duplicate) must say the same.
FILE_VERSION_RE = re.compile(r"\b(remix|rmx|live|acoustic|instrumental|unplugged|cover|extended|"
                             r"(?:english|japanese|korean|spanish|italian|french)(?=\s+ver))", re.I)
# Words YouTube rips add to a name. A bracket containing any of them is dropped.
NOISE_RE = re.compile(
    r"official|music\s*video|video\s*clip|videoclip|lyric|testo|audio|video\s*ufficiale|"
    r"visuali[sz]er|\bhd\b|\bhq\b|\b4k\b|explicit|\bclean\b|\bprod\b|free\s*download|out\s*now|"
    r"\bmv\b|\bm/v\b|full\s*song|radio\s*edit\s*video", re.I)
TRAIL_NOISE_RE = re.compile(
    r"(\s*[-–|]?\s*(official\s*(music\s*)?(video|audio)|lyrics?(\s*video)?|music\s*video|"
    r"audio(\s*ufficiale)?|video\s*ufficiale|testo|hd|hq|\(\d+\)|copy|copia))+\s*$", re.I)
STOP = {"ft", "feat", "featuring", "x", "vs", "e", "and", "the", "with", "prod", "official",
        "video", "lyrics", "lyric", "audio", "music", "testo", "a", "di", "il", "la"}
SEC_BAD = {"Compilation", "Live", "Remix", "DJ-mix", "Mixtape/Street", "Demo", "Interview",
           "Spokenword", "Audiobook"}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ── dependencies: installed on first use, nothing system-wide ───────────────

def ensure_mutagen():
    try:
        import mutagen  # noqa: F401
        return
    except ImportError:
        pass
    venv = CACHE / "venv"
    py = venv / "bin" / "python"
    if Path(sys.executable).resolve() == py.resolve():
        sys.exit("mutagen is missing even inside the skill venv")
    if not py.exists():
        log(f"mutagen not found — installing it into {venv}")
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        subprocess.run([str(py), "-m", "pip", "install", "-q", "mutagen"], check=True)
    os.execv(str(py), [str(py), *sys.argv])


def ensure_fpcalc():
    found = shutil.which("fpcalc")
    if found:
        return found
    local = CACHE / "bin" / "fpcalc"
    if local.exists():
        return str(local)
    system = platform.system().lower()
    arch = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "arm64", "arm64": "arm64"}.get(
        platform.machine().lower())
    if system == "darwin":
        name = f"chromaprint-fpcalc-{FPCALC_VERSION}-macos-universal"
    elif system == "linux" and arch:
        name = f"chromaprint-fpcalc-{FPCALC_VERSION}-linux-{arch}"
    else:
        sys.exit("No fpcalc for this platform: install chromaprint (fpcalc) yourself")
    url = f"https://github.com/acoustid/chromaprint/releases/download/v{FPCALC_VERSION}/{name}.tar.gz"
    log(f"fpcalc not found — downloading {url}")
    local.parent.mkdir(parents=True, exist_ok=True)
    tgz = local.parent / f"{name}.tar.gz"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r, open(tgz, "wb") as f:
        shutil.copyfileobj(r, f)
    with tarfile.open(tgz) as t:
        member = next(m for m in t.getmembers() if m.isfile() and m.name.endswith("/fpcalc"))
        with t.extractfile(member) as src, open(local, "wb") as dst:
            shutil.copyfileobj(src, dst)
    local.chmod(0o755)
    tgz.unlink()
    return str(local)


def acoustid_key():
    key = os.environ.get("ACOUSTID_API_KEY")
    if key:
        return key.strip()
    f = Path.home() / ".config" / "music-tagger" / "acoustid.key"
    return f.read_text().strip() if f.exists() else None


# ── HTTP with an on-disk cache and the MusicBrainz 1 request/second limit ────

_rate_lock = threading.Lock()
_last_call = {}
_MISSING = b"\x00missing"


def http_get(url, rate=None, binary=False):
    key = hashlib.sha1(url.encode()).hexdigest()
    path = CACHE / "http" / key[:2] / key
    if path.exists():
        data = path.read_bytes()
    else:
        data = None
        host = urllib.parse.urlparse(url).netloc
        for attempt in range(6):
            if rate:
                with _rate_lock:
                    wait = _last_call.get(host, 0) + rate - time.monotonic()
                    if wait > 0:
                        time.sleep(wait)
                    _last_call[host] = time.monotonic()
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=30) as r:
                    data = r.read()
                break
            except urllib.error.HTTPError as e:
                if e.code in (400, 404):
                    data = _MISSING
                    break
                if e.code in (429, 500, 502, 503, 504):
                    time.sleep(2 ** attempt)
                    continue
                raise
            except (urllib.error.URLError, TimeoutError, ConnectionError):
                time.sleep(2 ** attempt)
        if data is None:
            raise RuntimeError(f"giving up on {url}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if data == _MISSING:
        return None
    return data if binary else json.loads(data)


def mb(path, **params):
    params["fmt"] = "json"
    return http_get(MB + path + "?" + urllib.parse.urlencode(params), rate=1.1)


def mb_recording(rid):
    return mb(f"recording/{rid}", inc="releases+media+release-groups+artist-credits+genres")


def cover_art(release_id, group_id):
    for kind, mbid in (("release", release_id), ("release-group", group_id)):
        if not mbid:
            continue
        try:
            data = http_get(f"{CAA}{kind}/{mbid}/front-500", binary=True)
        except Exception as e:  # a cover the archive can't serve now: no cover, not a failed scan
            log(f"  cover not downloaded for {kind} {mbid}: {e}")
            continue
        if data:
            path = CACHE / "covers" / f"{mbid}.img"
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            return str(path)
    return None


# ── text helpers ─────────────────────────────────────────────────────────────

def norm(s):
    s = unicodedata.normalize("NFKD", (s or "").lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("&", " and ").replace("’", "").replace("'", "")
    return re.sub(r"[\W_]+", " ", s).strip()


def tokens(s):
    return norm(s).split()


def tok_eq(a, b):
    if a == b:
        return True
    if len(a) >= 4 and len(b) >= 4:
        return a.startswith(b) or b.startswith(a) or difflib.SequenceMatcher(None, a, b).ratio() >= 0.8
    return False


def cover_ratio(need, have):
    """Share of the tokens in `need` that appear (fuzzily) in `have`."""
    if not need:
        return 0.0
    return sum(1 for t in need if any(tok_eq(t, h) for h in have)) / len(need)


def clean_stem(stem):
    s = stem if " " in stem else stem.replace("_", " ")  # "my_song_name"; keep a "_" we wrote
    s = re.sub(r"[\(\[\{]([^\)\]\}]*)[\)\]\}]",
               lambda m: "" if NOISE_RE.search(m.group(1)) else m.group(0), s)
    s = re.sub(r"\(\s*\)|\[\s*\]", "", s)
    for _ in range(3):
        s = TRAIL_NOISE_RE.sub("", s)
    s = re.sub(r"^\s*(0\d{1,3}\s*[-.]|\d{1,2}\.)\s+", "", s)  # "0002 - " / "07. ", not the band "883 - "
    s = re.sub(r"\s+", " ", s).strip(" -–|.")
    return s or stem.strip()


def safe_name(s, limit=200):
    """File-name standard: Picard/beets character rules, NFC, at most `limit` UTF-8 bytes."""
    s = unicodedata.normalize("NFC", s)
    s = s.translate(str.maketrans({"\u2010": "-", "\u2011": "-", "\u2013": "-", "\u2014": "-",
                                   "\u2018": "'", "\u2019": "'", "\u201c": "'", "\u201d": "'"}))
    s = re.sub(r'[/\\:*?"<>|\x00-\x1f]', "_", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"^[.-]", "_", s)
    while len(s.encode()) > limit:
        s = s[:-1]
    return s.rstrip(" .") or "untitled"


def credit_phrase(credit):
    return "".join(c.get("name", "") + c.get("joinphrase", "") for c in credit or []).strip()


def credit_names(credit):
    out = []
    for c in credit or []:
        out.append(c.get("name", ""))
        if c.get("artist", {}).get("name"):
            out.append(c["artist"]["name"])
    return [n for n in out if n]


def date_num(d):
    if not d:
        return 99999999
    p = (d + "-0-0").split("-")
    try:
        return int(p[0]) * 10000 + int(p[1] or 0) * 100 + int(p[2] or 0)
    except ValueError:
        return 99999999


# ── reading files ────────────────────────────────────────────────────────────

def read_file(path):
    import mutagen
    from mutagen.id3 import ID3
    info = {"title": "", "artist": "", "album": "", "date": "", "recording_id": "",
            "release_id": "", "has_cover": False, "length": 0, "bitrate": 0, "readable": True}
    try:
        m = mutagen.File(path, easy=True)
    except Exception:
        m = None
    if m is None:
        info["readable"] = False
        return info
    info["length"] = round(getattr(m.info, "length", 0) or 0, 1)
    info["bitrate"] = int((getattr(m.info, "bitrate", 0) or 0) / 1000)
    t = m.tags or {}

    def first(k):
        v = t.get(k)
        return str(v[0]).strip() if v else ""
    info.update(title=first("title"), artist=first("artist"), album=first("album"),
                date=first("date"), genre=first("genre"), recording_id=first("musicbrainz_trackid"),
                release_id=first("musicbrainz_albumid"))
    if path.suffix.lower() == ".mp3":
        try:
            info["has_cover"] = bool(ID3(path).getall("APIC"))
        except Exception:
            pass
    else:
        raw = mutagen.File(path)
        info["has_cover"] = bool(raw is not None and raw.tags and raw.tags.get("covr"))
    return info


def fingerprint(fpcalc, path, raw=True):
    cmd = [fpcalc, "-json", "-length", "120"] + (["-raw"] if raw else []) + [str(path)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return json.loads(out.stdout)
    except Exception:
        return None


# ── identifying a song ───────────────────────────────────────────────────────

def release_rank(rel, prefer_id=None, prefer_album=None, artist_ids=()):
    rg = rel.get("release-group") or {}
    s = 0
    if artist_ids and {c.get("artist", {}).get("id") for c in rel.get("artist-credit") or []} & set(artist_ids):
        s += 3
    if prefer_id and rel.get("id") == prefer_id:
        s += 3
    if prefer_album and norm(rel.get("title")) == norm(prefer_album):
        s += 2
    if rel.get("status") == "Official":
        s += 10
    s += {"Album": 6, "Single": 5, "EP": 4}.get(rg.get("primary-type"), 0)
    sec = set(rg.get("secondary-types") or [])
    s -= 8 * len(sec & SEC_BAD) + 2 * ("Soundtrack" in sec)
    return (s, -date_num(rel.get("date")))


def eval_candidate(r, qtok, length):
    """Score one search result against the words we know. None = not this song."""
    title = r.get("title", "")
    main = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip() or title
    tt = tokens(main)
    t_ratio = cover_ratio(tt, qtok)
    if not tt or t_ratio < 0.75:
        return None
    artists = credit_names(r.get("artist-credit"))
    a_ok = [n for n in artists if tokens(n) and cover_ratio(tokens(n), qtok) == 1.0]
    if not a_ok:
        return None
    meaningful = [t for t in qtok if t not in STOP]
    explained = tokens(title) + [t for n in artists for t in tokens(n)]
    coverage = cover_ratio(meaningful, explained) if meaningful else 0
    if coverage <= 0.5:
        return None
    rlen = r.get("length")
    diff = abs(length - rlen / 1000) if rlen and length else None
    if diff is not None and diff > 45:
        return None
    said = tokens(title + " " + r.get("disambiguation", ""))
    if any(not any(tok_eq(v, h) for h in said) for v in file_versions(" ".join(qtok))):
        return None
    live = bool(re.search(r"\blive\b", (r.get("disambiguation", "") + " " + title).lower())) \
        and "live" not in qtok
    rels = r.get("releases") or []
    best_rel = max((release_rank(x)[0] for x in rels), default=-20)
    score = (r.get("score", 0) / 100 + 2 * t_ratio + 2 * coverage
             - (diff / 15 if diff is not None else 1) - 3 * live + best_rel / 10)
    need = 1.0 if file_versions(" ".join(qtok)) else 0.6  # a remix must be the right remixer
    sure = diff is not None and diff <= 7 and t_ratio == 1 and coverage >= need and not live
    why = []
    if diff is None:
        why.append("MusicBrainz has no length to compare")
    elif diff > 7:
        why.append(f"length differs by {diff:.0f}s")
    if t_ratio < 1:
        why.append("title only partly matches")
    if coverage < 0.6:
        why.append("file name has words the match doesn't explain")
    if live:
        why.append("match is a live version")
    other = other_version(title, qtok)
    if other:
        sure = False
        why.append(f"match is a '{other}' version, the file name doesn't say so")
    return score, sure, why


def file_versions(text):
    return {m.group(1).lower() for m in FILE_VERSION_RE.finditer(text or "")}


def other_version(title, have):
    """A version word (remix, live, ...) in the MusicBrainz title but not in the file."""
    for m in VERSION_RE.finditer(title or ""):
        if not any(tok_eq(norm(m.group(1)), h) for h in have):
            return m.group(1).lower()
    return None


def search(qtitle, qartist, qtok, length):
    if not qtitle:
        return None
    q = f"recording:({' '.join(qtitle[:12])}) AND artist:({' '.join(qartist[:12])})"
    res = mb("recording", query=q, limit=15) or {}
    best = None
    for r in res.get("recordings", []):
        ev = eval_candidate(r, qtok, length)
        if ev and (best is None or ev[0] > best[1][0]):
            best = (r, ev)
    return best


def pick(rec, prefer_id=None, prefer_album=None):
    """Choose the release and build the tags we will write."""
    rels = rec.get("releases") or []
    if not rels:
        return None
    own = [c["artist"]["id"] for c in rec.get("artist-credit") or [] if c.get("artist")]
    rel = max(rels, key=lambda x: release_rank(x, prefer_id, prefer_album, own))
    medium = (rel.get("media") or [{}])[0]
    track = next((t for t in medium.get("tracks") or medium.get("track") or []), {})
    rg = rel.get("release-group") or {}
    genres = sorted(rec.get("genres") or rel.get("genres") or rg.get("genres") or [],
                    key=lambda g: -g.get("count", 0))
    number = track.get("number", "")
    if not str(number).isdigit():
        number = track.get("position", "")
    return {
        "title": track.get("title") or rec.get("title", ""),
        "artist": credit_phrase(rec.get("artist-credit") or track.get("artist-credit")),
        "albumartist": credit_phrase(rel.get("artist-credit")) or credit_phrase(rec.get("artist-credit")),
        "album": rel.get("title", ""),
        "date": rel.get("date") or rg.get("first-release-date", ""),
        "tracknumber": str(number or ""),
        "totaltracks": str(medium.get("track-count") or ""),
        "discnumber": str(medium.get("position") or ""),
        "genre": genres[0]["name"].title() if genres else "",
        "mb_recording_id": rec.get("id", ""),
        "mb_track_id": track.get("id", ""),
        "mb_release_id": rel.get("id", ""),
        "mb_release_group_id": rg.get("id", ""),
        "mb_artist_ids": [c["artist"]["id"] for c in rec.get("artist-credit") or [] if c.get("artist")],
        "mb_albumartist_ids": [c["artist"]["id"] for c in rel.get("artist-credit") or [] if c.get("artist")],
        "length": round((rec.get("length") or 0) / 1000),
    }


def identify(f, akey, fpcalc, folder):
    """Fill f['status'], f['new'], f['reason']."""
    cur = f["current"]
    name_stem = Path(f["file"]).stem
    clean = clean_stem(name_stem)
    ftok = tokens(clean)
    if VARIANT_RE.search(name_stem) or VARIANT_RE.search(cur["title"]):
        f.update(status="variant", reason="speed/pitch-changed version — not tagged as the original")
        return
    if not cur["readable"]:
        f.update(status="not_found", reason="file could not be read")
        return

    rec, sure, why, how = None, True, [], ""
    if cur["recording_id"]:
        rec = mb_recording(cur["recording_id"])
        how = "MusicBrainz id already in the tags"
        if rec and len(ftok) >= 2 and cover_ratio(tokens(rec.get("title")), ftok + tokens(cur["title"])) == 0:
            sure, why = False, ["tags and file name disagree"]
        other = rec and other_version(rec.get("title"), ftok)
        if other:
            sure, why = False, why + [f"tagged as a '{other}' version, the file name doesn't say so"]
        meaningful = [t for t in ftok if t not in STOP]
        explained = tokens((rec or {}).get("title")) + [t for n in credit_names((rec or {}).get("artist-credit"))
                                                         for t in tokens(n)]
        if rec and len(meaningful) >= 2 and cover_ratio(meaningful, explained) <= 0.5:
            sure, why = False, why + ["file name has an artist the tags don't credit"]
        said = tokens((rec or {}).get("title", "") + " " + (rec or {}).get("disambiguation", ""))
        missing = [v for v in file_versions(name_stem) if not any(tok_eq(v, h) for h in said)]
        if rec and missing:
            sure, why = False, why + [f"file name says '{missing[0]}', the tagged song doesn't"]

    prefer_id, prefer_album = cur["release_id"], cur["album"]
    if rec and not sure:
        # The old tags look wrong (often a bad Picard match): the file name decides.
        hit = search(ftok, ftok, ftok, cur["length"])
        if hit and hit[1][1]:
            r, (_, sure, why) = hit
            rec, prefer_id, prefer_album = mb_recording(r["id"]), None, None
            how = "old MusicBrainz tag looked wrong — text search on the file name"

    if not rec:
        qtok = sorted(set(ftok) | set(tokens(cur["title"])) | set(tokens(cur["artist"])))
        hit = None
        if cur["title"] and cur["artist"]:
            hit = search(tokens(cur["title"]), tokens(cur["artist"]), qtok, cur["length"])
            how = "text search on the tags"
        if not hit:
            hit = search(ftok, ftok, qtok, cur["length"])
            how = "text search on the file name"
        if hit:
            r, (_, sure, why) = hit
            rec = mb_recording(r["id"])

    if not rec and akey:
        fp = fingerprint(fpcalc, folder / f["file"], raw=False)
        if fp and fp.get("fingerprint"):
            res = http_get("https://api.acoustid.org/v2/lookup?" + urllib.parse.urlencode(
                {"client": akey, "meta": "recordingids", "duration": int(fp["duration"]),
                 "fingerprint": fp["fingerprint"]}), rate=0.4) or {}
            for r in sorted(res.get("results", []), key=lambda x: -x.get("score", 0)):
                if r.get("score", 0) >= 0.8 and r.get("recordings"):
                    rec = mb_recording(r["recordings"][0]["id"])
                    how, sure, why = "audio fingerprint (AcoustID)", True, []
                    break

    new = pick(rec, prefer_id, prefer_album) if rec else None
    if not new:
        f.update(status="not_found", reason="no confident match on MusicBrainz")
        return
    f.update(status="matched" if sure else "check", new=new,
             reason="; ".join([how] + why))


# ── duplicates ───────────────────────────────────────────────────────────────

def fp_similarity(a, b, max_shift=40):
    """Share of equal bits between two raw chromaprints, best shift within about ±5 s."""
    a = a[10:130]
    best = 0.0
    for shift in range(-max_shift, max_shift + 1):
        if 10 + shift < 0:
            continue
        y = b[10 + shift:130 + shift]
        n = min(len(a), len(y))
        if n < 60:
            continue
        diff = sum(((a[i] ^ y[i]) & 0xFFFFFFFF).bit_count() for i in range(n))
        best = max(best, 1 - diff / (32 * n))
    return best


def find_duplicates(files):
    parent = list(range(len(files)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def join(i, j):
        parent[root(i)] = root(j)

    # Same audio = duplicate; a MusicBrainz id alone is not enough (old tags can be wrong).
    # First a cheap filter: copies of one song share hundreds of fingerprint values
    # (top 20 bits), different songs a few dozen at most.
    index = {}
    for i, f in enumerate(files):
        for v in {x >> 12 for x in (f.get("fp") or [])[10:]}:
            index.setdefault(v, []).append(i)
    shared = {}
    for ids in index.values():
        if len(ids) > 50:  # a value common to many songs (silence) proves nothing
            continue
        for x in range(len(ids)):
            for y in range(x + 1, len(ids)):
                shared[(ids[x], ids[y])] = shared.get((ids[x], ids[y]), 0) + 1
    for (i, j), n in shared.items():
        if n < 50 or root(i) == root(j) or "variant" in (files[i]["status"], files[j]["status"]):
            continue
        if abs(files[i]["current"]["length"] - files[j]["current"]["length"]) > 20:
            continue  # extended mix, radio edit
        if file_versions(files[i]["file"]) != file_versions(files[j]["file"]):
            continue  # "English Version" vs "Japanese Version", original vs remix
        if fp_similarity(files[i]["fp"], files[j]["fp"]) >= 0.9:
            join(i, j)
    groups = {}
    for i in range(len(files)):
        groups.setdefault(root(i), []).append(i)
    return [g for g in groups.values() if len(g) > 1]


def keep_rank(f):
    c, n = f["current"], f.get("new") or {}
    return (c["bitrate"], f["status"] in ("matched", "check"), c["has_cover"],
            -abs(c["length"] - n.get("length", c["length"])), -len(f["file"]))


# ── names ────────────────────────────────────────────────────────────────────

def target_stem(f):
    n = f.get("new")
    if f["action"] == "tag" and n and n.get("artist") and n.get("title"):
        return safe_name(f"{n['artist']} - {n['title']}")
    return safe_name(clean_stem(Path(f["file"]).stem))


def assign_names(plan):
    """New file names, unique ignoring case (phones and USB sticks ignore case)."""
    taken = set()
    for f in plan["files"]:
        if f["action"] == "remove":
            f["new_name"] = None
            continue
        if f.get("name_locked"):
            taken.add(f["new_name"].casefold())
            continue
        ext = Path(f["file"]).suffix.lower()
        stem = target_stem(f)
        name = stem + ext
        if name.casefold() in taken and f.get("new", {}).get("album"):
            name = safe_name(f"{stem} ({f['new']['album']})") + ext
        k = 2
        while name.casefold() in taken:
            name = f"{stem} ({k}){ext}"
            k += 1
        taken.add(name.casefold())
        f["new_name"] = name


# ── scan ─────────────────────────────────────────────────────────────────────

def cmd_scan(args):
    folder = Path(args.folder).expanduser().resolve()
    fpcalc = ensure_fpcalc()
    akey = acoustid_key()
    paths = sorted(p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in AUDIO_EXT)
    others = sorted(p.name for p in folder.iterdir()
                    if p.is_file() and p.suffix.lower() not in AUDIO_EXT and not p.name.startswith("."))
    if args.limit:
        paths = paths[:args.limit]
    log(f"{len(paths)} songs in {folder}" + ("" if akey else " (no AcoustID key: fingerprint lookup off)"))

    def load(p):
        st = p.stat()
        fp = fingerprint(fpcalc, p)
        return {"file": p.name, "size": st.st_size, "mtime": st.st_mtime, "current": read_file(p),
                "fp": (fp or {}).get("fingerprint")}

    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        files = list(ex.map(load, paths))
    log("read tags + fingerprints; looking songs up on MusicBrainz (about 1-2 s per song)…")
    start = time.monotonic()
    for k, f in enumerate(files, 1):
        try:
            identify(f, akey, fpcalc, folder)
        except Exception as e:  # one bad lookup must not lose the whole scan
            f.update(status="not_found", reason=f"lookup error: {e}")
        if k % 25 == 0 or k == len(files):
            eta = (time.monotonic() - start) / k * (len(files) - k)
            log(f"  {k}/{len(files)}  (about {eta / 60:.0f} min left)")

    log("downloading covers…")
    with_new = [f for f in files if f.get("new")]
    with ThreadPoolExecutor(max_workers=8) as ex:
        found = ex.map(lambda f: cover_art(f["new"]["mb_release_id"], f["new"]["mb_release_group_id"]), with_new)
        for f, c in zip(with_new, found):
            f["new"]["cover"] = c
    for i, f in enumerate(files, 1):
        f["id"] = i
        f["action"] = {"matched": "tag", "check": "tag"}.get(f["status"], "rename")
        f["dup_group"] = None
    for gid, group in enumerate(find_duplicates(files), 1):
        keep = max(group, key=lambda i: keep_rank(files[i]))
        for i in group:
            files[i]["dup_group"] = gid
            if i != keep:
                files[i]["action"] = "remove"
    for f in files:
        f.pop("fp", None)
        f["tags_same"] = tags_same(f)

    plan = {"folder": str(folder), "scanned": datetime.now().isoformat(timespec="seconds"),
            "acoustid": bool(akey), "other_files": others, "files": files}
    assign_names(plan)
    work = folder / WORKDIR
    work.mkdir(exist_ok=True)
    plan_path = work / "plan.json"
    save_plan(plan, plan_path)
    print(write_report(plan, plan_path))


def tags_same(f):
    """The file already holds what we would write: apply leaves it untouched (no MEGA re-upload)."""
    c, n = f["current"], f.get("new")
    if not n:
        return False
    keys = (("title", "title"), ("artist", "artist"), ("album", "album"), ("date", "date"),
            ("genre", "genre"), ("recording_id", "mb_recording_id"), ("release_id", "mb_release_id"))
    return all((c.get(a) or "") == (n.get(b) or "") for a, b in keys) and (c["has_cover"] or not n.get("cover"))


def save_plan(plan, path):
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(json.dumps(plan, indent=1, ensure_ascii=False))
    tmp.replace(path)


def load_plan(path):
    path = Path(path).expanduser()
    if path.is_dir():
        path = path / WORKDIR / "plan.json" if (path / WORKDIR).is_dir() else path / "plan.json"
    return json.loads(path.read_text()), path


# ── report ───────────────────────────────────────────────────────────────────

def md(s):
    return str(s or "").replace("|", "\\|")


def write_report(plan, plan_path):
    files = plan["files"]
    by = lambda st: [f for f in files if f["status"] == st]  # noqa: E731
    tag = [f for f in files if f["action"] == "tag" and not f.get("tags_same")]
    remove = [f for f in files if f["action"] == "remove"]
    renames = [f for f in files if f["action"] != "remove" and f["new_name"] != f["file"]]
    covers = [f for f in tag if f["new"].get("cover") and not f["current"]["has_cover"]]
    summary = [
        f"Folder: {plan['folder']}  ·  scanned {plan['scanned']}  ·  {len(files)} songs",
        "",
        f"- ✅ identified, sure: {len(by('matched'))}",
        f"- ⚠️ identified, please check: {len(by('check'))}",
        f"- ❓ not found (name cleanup only): {len(by('not_found'))}",
        f"- 🎛️ speed-up / nightcore versions (name cleanup only): {len(by('variant'))}",
        f"- 🗑️ duplicates to move to {DUP_DIR}/: {len(remove)}",
        f"- 🏷️ songs whose tags will be written: {len(tag)}  (🖼️ {len(covers)} get a cover they lack)",
        f"- ✏️ files renamed: {len(renames)}",
        f"- ⏭️ skipped by you: {sum(1 for f in files if f['action'] == 'skip')}",
    ]
    if not plan.get("acoustid"):
        summary.append("- ℹ️ no AcoustID key: songs with bad names were not tried by fingerprint")
    if plan.get("other_files"):
        summary.append(f"- ℹ️ ignored, not mp3/m4a: {', '.join(plan['other_files'][:10])}")
    out = ["# Music tagger report", ""] + summary + [""]

    def arrow(f):
        return f"→ {md(f['new_name'])}" if f["new_name"] and f["new_name"] != f["file"] else "(same name)"

    groups = {}
    for f in files:
        if f["dup_group"]:
            groups.setdefault(f["dup_group"], []).append(f)
    if groups:
        out += ["## 🗑️ Duplicates", ""]
        for gid, g in sorted(groups.items()):
            out.append(f"**Group {gid}**")
            for f in sorted(g, key=lambda f: f["action"] == "remove"):
                verb = "move away" if f["action"] == "remove" else "KEEP"
                out.append(f"- {verb} · #{f['id']} {md(f['file'])} — {f['current']['bitrate']} kbps, "
                           f"{f['current']['length']:.0f}s")
            out.append("")

    by_rec = {}
    for f in files:
        rid = (f.get("new") or {}).get("mb_recording_id")
        if rid and f["action"] != "remove":
            by_rec.setdefault(rid, []).append(f)
    maybe = [g for g in by_rec.values() if len(g) > 1]
    if maybe:
        out += ["## 🔁 Same song on MusicBrainz, different audio — kept, check by ear", "",
                "Often a different version (remix, intro, language) or a wrong old tag. "
                "To drop one: `edit <folder> <#> action=remove`.", ""]
        for g in maybe:
            out.append("- " + "  ·  ".join(f"#{f['id']} {md(f['file'])} ({f['current']['bitrate']} kbps, "
                                           f"{f['current']['length']:.0f}s)" for f in g))
        out.append("")

    def table(title, rows, cols):
        nonlocal out
        if not rows:
            return
        out += [f"## {title}", "", "| " + " | ".join(c[0] for c in cols) + " |",
                "|" + "---|" * len(cols)]
        out += ["| " + " | ".join(md(c[1](f)) for c in cols) + " |" for f in rows]
        out.append("")

    live = lambda st: [f for f in files if f["status"] == st and f["action"] != "remove"]  # noqa: E731
    n = lambda f: f.get("new") or {}  # noqa: E731
    table("⚠️ Please check these matches", live("check"), [
        ("#", lambda f: f["id"]), ("file", lambda f: f["file"]),
        ("match", lambda f: f"{n(f).get('artist')} - {n(f).get('title')}"),
        ("album (year)", lambda f: f"{n(f).get('album')} ({n(f).get('date', '')[:4]})"),
        ("why", lambda f: f["reason"]), ("action", lambda f: f["action"])])
    table("❓ Not found — only the name is cleaned", live("not_found"), [
        ("#", lambda f: f["id"]), ("file", lambda f: f["file"]), ("new name", arrow),
        ("why", lambda f: f["reason"])])
    table("🎛️ Speed-up / nightcore versions — only the name is cleaned", live("variant"), [
        ("#", lambda f: f["id"]), ("file", lambda f: f["file"]), ("new name", arrow)])
    table("✅ Identified", live("matched"), [
        ("#", lambda f: f["id"]), ("file", lambda f: f["file"]), ("new name", arrow),
        ("album", lambda f: n(f).get("album")), ("year", lambda f: n(f).get("date", "")[:4]),
        ("genre", lambda f: n(f).get("genre")), ("cover", lambda f: "🖼️" if n(f).get("cover") else "—"),
        ("action", lambda f: f["action"])])

    report_path = Path(plan_path).with_name("report.md")
    report_path.write_text("\n".join(out))
    return "\n".join(summary + ["", f"Report: {report_path}", f"Plan:   {plan_path}"])


def cmd_report(args):
    plan, path = load_plan(args.plan)
    assign_names(plan)  # names follow the current naming rules, edits are kept
    save_plan(plan, path)
    print(write_report(plan, path))


# ── edit ─────────────────────────────────────────────────────────────────────

TAG_FIELDS = ("title", "artist", "albumartist", "album", "date", "tracknumber", "totaltracks",
              "discnumber", "genre")


def cmd_edit(args):
    plan, path = load_plan(args.plan)
    ids = set()
    for part in args.ids.split(","):
        a, _, b = part.partition("-")
        ids.update(range(int(a), int(b or a) + 1))
    for f in plan["files"]:
        if f["id"] not in ids:
            continue
        for kv in args.changes:
            k, _, v = kv.partition("=")
            if k == "action":
                if v not in ("tag", "rename", "skip", "remove"):
                    sys.exit("action must be tag, rename, skip or remove")
                if v == "tag" and not f.get("new"):
                    sys.exit(f"#{f['id']} has no match to tag with")
                f["action"] = v
            elif k == "name":
                f["new_name"] = safe_name(v)
                f["name_locked"] = True
            elif k in TAG_FIELDS:
                f.setdefault("new", {})[k] = v
                f["tags_same"] = False
            else:
                sys.exit(f"unknown field {k}: use action, name or one of {', '.join(TAG_FIELDS)}")
        log(f"#{f['id']} {f['file']}: action={f['action']}")
    assign_names(plan)
    save_plan(plan, path)
    print(write_report(plan, path))


# ── apply / undo ─────────────────────────────────────────────────────────────

def write_tags(path, new, backup):
    """Write tags + cover. Saves the old tag first so undo can put it back."""
    data = Path(new["cover"]).read_bytes() if new.get("cover") else None
    mime = "image/png" if data and data[:4] == b"\x89PNG" else "image/jpeg"
    track = new.get("tracknumber", "")
    if track and new.get("totaltracks"):
        track += "/" + new["totaltracks"]
    if path.suffix.lower() == ".mp3":
        from mutagen.id3 import (ID3, APIC, TALB, TCON, TDRC, TIT2, TPE1, TPE2, TPOS, TRCK, TXXX,
                                 UFID, ID3NoHeaderError)
        try:
            tags = ID3(path)
            backup.write_bytes(b"")
            tags.save(backup, v1=0, v2_version=3)
        except ID3NoHeaderError:
            tags = ID3()
        for fid in ("TIT2", "TPE1", "TPE2", "TALB", "TDRC", "TYER", "TDAT", "TRCK", "TPOS", "TCON", "APIC"):
            tags.delall(fid)
        tags.delall("UFID:http://musicbrainz.org")
        for k in [k for k in tags.keys() if k.startswith("TXXX:MusicBrainz")]:
            del tags[k]
        for frame, key in ((TIT2, "title"), (TPE1, "artist"), (TPE2, "albumartist"), (TALB, "album"),
                           (TDRC, "date"), (TCON, "genre"), (TPOS, "discnumber")):
            if new.get(key):
                tags.add(frame(encoding=3, text=new[key]))
        if track:
            tags.add(TRCK(encoding=3, text=track))
        if new.get("mb_recording_id"):
            tags.add(UFID(owner="http://musicbrainz.org", data=new["mb_recording_id"].encode()))
        for desc, key in (("MusicBrainz Album Id", "mb_release_id"),
                          ("MusicBrainz Release Group Id", "mb_release_group_id"),
                          ("MusicBrainz Release Track Id", "mb_track_id"),
                          ("MusicBrainz Artist Id", "mb_artist_ids"),
                          ("MusicBrainz Album Artist Id", "mb_albumartist_ids")):
            v = new.get(key)
            if v:
                tags.add(TXXX(encoding=3, desc=desc, text=v if isinstance(v, list) else [v]))
        if data:
            tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=data))
        tags.save(path, v2_version=3)
    else:
        from mutagen.mp4 import MP4, MP4Cover
        shutil.copy2(path, backup)
        m = MP4(path)
        if m.tags is None:
            m.add_tags()
        for atom, key in (("\xa9nam", "title"), ("\xa9ART", "artist"), ("aART", "albumartist"),
                          ("\xa9alb", "album"), ("\xa9day", "date"), ("\xa9gen", "genre")):
            if new.get(key):
                m.tags[atom] = [new[key]]
        if new.get("tracknumber", "").isdigit():
            m.tags["trkn"] = [(int(new["tracknumber"]), int(new.get("totaltracks") or 0))]
        if new.get("discnumber", "").isdigit():
            m.tags["disk"] = [(int(new["discnumber"]), 0)]
        for name, key in (("MusicBrainz Track Id", "mb_recording_id"), ("MusicBrainz Album Id", "mb_release_id"),
                          ("MusicBrainz Release Group Id", "mb_release_group_id")):
            if new.get(key):
                m.tags[f"----:com.apple.iTunes:{name}"] = [new[key].encode()]
        if data:
            fmt = MP4Cover.FORMAT_PNG if mime == "image/png" else MP4Cover.FORMAT_JPEG
            m.tags["covr"] = [MP4Cover(data, imageformat=fmt)]
        m.save()


def restore_tags(path, backup):
    if path.suffix.lower() == ".mp3":
        from mutagen.id3 import ID3, ID3NoHeaderError
        try:
            ID3(path).delete(path, delete_v1=False, delete_v2=True)
        except ID3NoHeaderError:
            pass
        if backup.exists() and backup.stat().st_size:
            ID3(backup).save(path, v1=0, v2_version=3)
    else:
        shutil.copy2(backup, path)


def cmd_apply(args):
    plan, path = load_plan(args.plan)
    folder = Path(plan["folder"])
    run = path.parent / ("undo-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    journal = None
    if not args.dry_run:
        run.mkdir()
        journal = open(run / "journal.jsonl", "a")

    def note(**entry):
        if journal:
            journal.write(json.dumps(entry, ensure_ascii=False) + "\n")
            journal.flush()

    done = {"removed": 0, "tagged": 0, "renamed": 0, "changed": 0, "failed": 0}
    todo = []
    for f in plan["files"]:
        p = folder / f["file"]
        if f["action"] == "skip":
            continue
        if not p.exists() or p.stat().st_size != f["size"] or abs(p.stat().st_mtime - f["mtime"]) > 1:
            log(f"#{f['id']} changed or gone since the scan — left alone: {f['file']}")
            done["changed"] += 1
            continue
        todo.append(f)

    for f in [f for f in todo if f["action"] == "remove"]:
        src = folder / f["file"]
        dst = folder / DUP_DIR / f["file"]
        k = 2
        while dst.exists():
            dst = dst.with_name(f"{Path(f['file']).stem} ({k}){src.suffix}")
            k += 1
        log(f"move   #{f['id']} {f['file']} → {DUP_DIR}/{dst.name}")
        if not args.dry_run:
            dst.parent.mkdir(exist_ok=True)
            src.rename(dst)
            note(op="move", src=str(src), dst=str(dst))
        done["removed"] += 1

    for f in [f for f in todo if f["action"] == "tag" and not f.get("tags_same")]:
        log(f"tag    #{f['id']} {f['file']}")
        if args.dry_run:
            done["tagged"] += 1
            continue
        backup = run / f"{f['id']}.bak"
        try:
            write_tags(folder / f["file"], f["new"], backup)
            note(op="tags", file=str(folder / f["file"]), backup=str(backup))
            done["tagged"] += 1
        except Exception as e:
            log(f"  failed: {e}")
            done["failed"] += 1

    # Two passes, so A→B and B→A swaps can't overwrite each other.
    moves = [f for f in todo if f["action"] != "remove" and f["new_name"] and f["new_name"] != f["file"]]
    temp = {}
    for f in moves:
        src = folder / f["file"]
        tmp = folder / f".mt-{f['id']}{src.suffix}"
        if not args.dry_run:
            src.rename(tmp)
            note(op="rename", src=str(src), dst=str(tmp))
        temp[f["id"]] = tmp
    for f in moves:
        dst = folder / f["new_name"]
        log(f"rename #{f['id']} {f['file']} → {f['new_name']}")
        if args.dry_run:
            done["renamed"] += 1
            continue
        if dst.exists():
            dst = folder / f["file"]  # target appeared since the scan: keep the old name
            log(f"  {f['new_name']} already exists — kept the old name")
        else:
            done["renamed"] += 1
        temp[f["id"]].rename(dst)
        note(op="rename", src=str(temp[f["id"]]), dst=str(dst))

    if journal:
        journal.close()
    print(json.dumps(done))
    print("dry run — nothing changed" if args.dry_run else f"undo with: undo {path}  (journal: {run})")


def cmd_undo(args):
    plan, path = load_plan(args.plan)
    runs = sorted(path.parent.glob("undo-*"))
    run = Path(args.run) if args.run else (runs[-1] if runs else None)
    if not run or not (run / "journal.jsonl").exists():
        sys.exit("nothing to undo")
    entries = [json.loads(line) for line in (run / "journal.jsonl").read_text().splitlines() if line]
    for e in reversed(entries):
        if e["op"] in ("rename", "move"):
            Path(e["dst"]).rename(e["src"])
        elif e["op"] == "tags":
            restore_tags(Path(e["file"]), Path(e["backup"]))
    run.rename(run.with_name(run.name.replace("undo-", "undone-")))
    dup = Path(plan["folder"]) / DUP_DIR
    if dup.is_dir() and not any(dup.iterdir()):
        dup.rmdir()
    print(f"undone {len(entries)} steps from {run.name}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("folder")
    s.add_argument("--limit", type=int, help="only the first N songs (for a test)")
    s.set_defaults(fn=cmd_scan)
    s = sub.add_parser("report")
    s.add_argument("plan")
    s.set_defaults(fn=cmd_report)
    s = sub.add_parser("edit")
    s.add_argument("plan")
    s.add_argument("ids", help="12 or 3,7,9 or 10-15")
    s.add_argument("changes", nargs="+", help="action=skip|tag|rename|remove, name=..., title=...")
    s.set_defaults(fn=cmd_edit)
    s = sub.add_parser("apply")
    s.add_argument("plan")
    s.add_argument("--dry-run", action="store_true")
    s.set_defaults(fn=cmd_apply)
    s = sub.add_parser("undo")
    s.add_argument("plan")
    s.add_argument("--run", help="undo this run folder instead of the last one")
    s.set_defaults(fn=cmd_undo)
    args = ap.parse_args()
    ensure_mutagen()
    args.fn(args)


if __name__ == "__main__":
    main()
