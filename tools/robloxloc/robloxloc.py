#!/usr/bin/env python3
"""
robloxloc — a project-agnostic workbench for Roblox cloud localization.

One CSV = the whole game's text (Source + every language). Edit cells in the CSV,
push only what changed; pull refreshes the CSV with the cloud state (including
machine translations). Manual pushes lock as manual — auto-translation never
overwrites them.

Commands
  pull    harvest strings from the project + download the cloud table -> rewrite the CSV
  status  show what would be pushed (diff CSV vs the last synced baseline)
  push    upload new sources + CHANGED translation cells (chunked, retried)
          --prune also deletes rows marked orphan=yes (in cloud but no longer in project)
  setup   one-time per project: add languages, enable auto-translation,
          enable "Use Translated Content"

Usage
  python tools/robloxloc/robloxloc.py [--config localization/localization.config.json] <command>

Config (JSON, lives next to the CSV; paths in harvest.* are relative to the
project root = the config file's parent directory's parent):
{
  "universeId": 123,
  "cookieFile": "C:/path/ROBLOSECURITY.txt",
  "csv": "translations.csv",
  "baseline": ".baseline.json",
  "sourceLanguage": "en",
  "languages": ["es","pt","fr", ...],
  "harvest": {
    "keyedModules": ["src/client/data/LocaleData.lua"],
    "catalogues": [ {"file": "src/server/data/DiceData.lua", "fields": ["name","desc"]} ],
    "staticEntries": "localization/static_entries.json"
  }
}

Reuse in another project: copy tools/robloxloc/ + create localization/ with a
config for that game (its universeId + its harvest rules). Nothing else is shared.
"""

import argparse
import collections
import csv
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

# ⚠ Windows consoles default to cp1252, which cannot encode the ⚠ / — this file
# prints — and a UnicodeEncodeError in a `print` KILLS the run AFTER the CSV has
# already been written, which reads exactly like a failed pull. Seen 2026-08-07:
# `pull` wrote all 314 rows and then crashed on its own warning line. Force the
# streams to UTF-8 instead of stripping the characters.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
import urllib.parse
from pathlib import Path

SEP = chr(1)  # baseline identity separator between key and source

CHUNK = 25  # the PATCH rejects big batches ("Maximum entries exceeded") and 504s — small + retries wins
TOKEN_RE = re.compile(r"\{[^{}]+\}")

# LocaleData key charset. Deliberately WIDER than kebab-case: keys are often built
# by concatenating an id that is camelCase in the config (`"hex-name-" .. statId`
# -> "hex-name-biteRadius"). A kebab-only class silently SKIPS those rows, and a
# skipped row is an untranslated string nobody notices until production.
KEY_RE = re.compile(r'\["([A-Za-z0-9_\-]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"')


# ── web API ──────────────────────────────────────────────────────────────────

class Api:
    def __init__(self, cookie: str):
        self.cookie = cookie
        self.csrf = ""

    def call(self, method, url, body=None, csrf_retry=True, attempts=4):
        data = None if body is None else json.dumps(body).encode("utf-8")
        last_err = None
        for attempt in range(attempts):
            req = urllib.request.Request(url, data=data, method=method)
            req.add_header("Cookie", ".ROBLOSECURITY=" + self.cookie)
            req.add_header("Content-Type", "application/json")
            req.add_header("User-Agent", "Mozilla/5.0 (robloxloc)")
            if self.csrf:
                req.add_header("X-CSRF-TOKEN", self.csrf)
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    text = r.read().decode("utf-8")
                    return json.loads(text) if text.strip() else {}
            except urllib.error.HTTPError as e:
                token = e.headers.get("x-csrf-token")
                if e.code == 403 and token and csrf_retry:
                    self.csrf = token
                    return self.call(method, url, body, csrf_retry=False, attempts=attempts)
                last_err = f"{method} {url} -> {e.code}: {e.read().decode('utf-8', 'replace')[:300]}"
                if e.code not in (429, 500, 502, 503, 504):
                    raise RuntimeError(last_err)
            except (urllib.error.URLError, TimeoutError) as e:
                last_err = f"{method} {url} -> {e}"
            wait = 5 * (attempt + 1)
            print(f"  retry in {wait}s ({last_err})")
            time.sleep(wait)
        raise RuntimeError(last_err)


# ── config / context ─────────────────────────────────────────────────────────

class Ctx:
    def __init__(self, config_path: Path):
        self.config_dir = config_path.parent
        self.root = self.config_dir.parent
        cfg = json.loads(config_path.read_text(encoding="utf-8-sig"))
        self.universe = cfg["universeId"]
        self.cookie_file = Path(cfg["cookieFile"])
        self.csv_path = self.config_dir / cfg.get("csv", "translations.csv")
        self.baseline_path = self.config_dir / cfg.get("baseline", ".baseline.json")
        self.languages = cfg["languages"]
        self.source_language = cfg.get("sourceLanguage", "en")
        self.harvest_cfg = cfg.get("harvest", {})
        self.gi = "https://gameinternationalization.roblox.com/v1"
        self.lt = "https://localizationtables.roblox.com/v1"
        self._api = None
        self._table_id = None

    @property
    def api(self):
        if not self._api:
            # $ROBLOSECURITY_FILE wins over the config path: the config is
            # COMMITTED and its path is whoever ran `setup` first. Same
            # convention tools/monetization uses. A cookie is a full account
            # session — the file belongs outside the repo either way.
            env = os.environ.get("ROBLOSECURITY_FILE")
            path = Path(env) if env else self.cookie_file
            if not path.exists():
                sys.exit(
                    f"FATAL: cookie file not found: {path}\n"
                    "  Point $ROBLOSECURITY_FILE at it, or fix `cookieFile` in the config.\n"
                    "  Keep it OUTSIDE the repo — it is a full account session."
                )
            self._api = Api(path.read_text(encoding="utf-8-sig").strip())
        return self._api

    @property
    def table_id(self):
        if not self._table_id:
            info = self.api.call("POST", f"{self.lt}/autolocalization/games/{self.universe}/autolocalizationtable", body={})
            self._table_id = info["autoLocalizationTableId"]
        return self._table_id


# ── harvest: collect the project's live strings ──────────────────────────────

def report(what, where, seen, added):
    """Print what was ACTUALLY added, not what was read. A count that reports the
    input size hides silent drops — which is the whole failure class this
    harvester keeps producing (kebab-only keys, source collisions, numeric rows)."""
    note = "" if added == seen else f"  [{seen - added} dropped: duplicate source or nothing translatable]"
    print(f"harvest: {added} {what} from {where}{note}")


def harvest(ctx: Ctx):
    """-> ordered list of {key, source, example}; keyed entries first."""
    # Keyless rows dedupe against OTHER KEYLESS rows only — deliberately NOT
    # against keyed sources. A cloud identity is (key, context, source), so a
    # keyless "Gym" and the keyed `cat-gym`/"Gym" are two legal rows. Deduping
    # them would make the checkpoint ProximityPrompt and the lobby pad signs
    # depend on the engine source-matching rows that carry a Key — behaviour
    # nobody here has verified, and unverified assumptions are exactly why
    # translation was dead in this project to begin with. The cost is a handful
    # of extra rows; the benefit is that world text is covered either way, and
    # keeps its own `example` (machine translation renders a bare "Easy" as an
    # adverb without one).
    out, seen_sources, seen_keys = [], set(), set()

    def add(key, source, example=""):
        if not source:
            return
        if key:
            if key in seen_keys:
                sys.exit(f"FATAL: duplicate key {key}")
            seen_keys.add(key)
        else:
            # A KEYLESS row translates by exact SOURCE matching, which is global:
            # once "200" is a source, EVERY label in the game that happens to
            # render "200" becomes eligible for substitution (Arabic can swap in
            # Arabic-Indic digits). A source with no letters has nothing to
            # translate anyway, so it is all risk and no benefit. Keyed rows are
            # exempt — they match by key, and "{n}"-style templates are legal there.
            if not any(ch.isalpha() for ch in source):
                print(f"  skip (no translatable words, keyless): {source!r}")
                return
            if source in seen_sources:
                return
            seen_sources.add(source)
        out.append({"key": key, "context": "", "source": source, "example": example})

    for rel in ctx.harvest_cfg.get("keyedModules", []):
        text = (ctx.root / rel).read_text(encoding="utf-8")
        # ANCHORED at column 0 (re.M) so it can only match a real assignment
        # statement. Unanchored, it also matches the `LocaleData.strings = { ... }`
        # that module headers write when documenting the required shape — the
        # capture then starts inside the COMMENT and harvests its example row
        # (a bogus `["key"] = "value"` entry pushed to the cloud table).
        m = re.search(r"^[\w.]*\bstrings\s*=\s*\{(.*?)\n\}", text, re.S | re.M)
        if not m:
            sys.exit(f"FATAL: no `.strings = {{...}}` table in {rel}")
        found = KEY_RE.findall(m.group(1))
        if not found:
            sys.exit(f"FATAL: `.strings` table in {rel} parsed to ZERO keys")
        before = len(out)
        for key, raw in found:
            add(key, raw.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\"))
        report("keyed strings", rel, len(found), len(out) - before)

    static = ctx.harvest_cfg.get("staticEntries")
    if static:
        data = json.loads((ctx.root / static).read_text(encoding="utf-8-sig"))
        before = len(out)
        for e in data["entries"]:
            add("", e["source"], e.get("example", ""))
        report("static entries", static, len(data["entries"]), len(out) - before)

    for cat in ctx.harvest_cfg.get("catalogues", []):
        text = (ctx.root / cat["file"]).read_text(encoding="utf-8")
        pat = r'\b(?:' + "|".join(cat["fields"]) + r')\s*=\s*"((?:[^"\\]|\\.)*)"'
        found = re.findall(pat, text)
        if not found:
            print(f"WARN: no strings harvested from {cat['file']}")
        before = len(out)
        for raw in found:
            add("", raw.replace('\\"', '"').replace("\\\\", "\\"))
        report("catalogue strings", cat["file"], len(found), len(out) - before)

    # NOTE (measured 2026-08-07, universe 10593425705): `DuplicatedKeySourceContext`
    # is a PER-REQUEST validation, not a table constraint. The table happily holds
    # two rows sharing (source, context) — `upgrade-eat-speed` and `stat-eat-speed`
    # are both ("Eat Speed", "") and both live there — they simply have to arrive
    # in DIFFERENT PATCHes. So nothing is disambiguated here; `context` stays ""
    # for every row and `chunk_unique_sources()` keeps colliding rows apart.
    # (An earlier attempt assigned `context = key` to such rows. It is worse: a
    # KEY may exist only once in the table, so re-identifying a row already up
    # there costs a delete + insert, and a synthetic context breaks the source
    # matching that keyless rows depend on.)
    dupes = {s for s, n in collections.Counter(h["source"] for h in out).items() if n > 1}
    if dupes:
        print(f"harvest: {len(dupes)} English source(s) are shared by more than one row "
              "-> they will be split across separate PATCH chunks")
    return out


# ── cloud table io ───────────────────────────────────────────────────────────

def fetch_cloud(ctx: Ctx):
    """-> dict (key, source) -> {example, translations{locale: text}}"""
    entries, cursor = {}, ""
    while True:
        url = f"{ctx.lt}/localization-table/tables/{ctx.table_id}/entries?gameId={ctx.universe}"
        if cursor:
            url += "&cursor=" + urllib.parse.quote(cursor)
        page = ctx.api.call("GET", url)
        for e in page.get("data", []):
            ident = e["identifier"]
            translations = {}
            for t in e.get("translations", []):
                loc = t.get("locale", "")
                # collapse locale codes to the language level (ru-ru -> ru); DROP
                # locales not in the config (e.g. Roblox's internal zh_cjv) — they
                # can't live in the CSV and would read as phantom "cleared cells"
                lang = loc.split("-")[0] if loc.split("-")[0] in ctx.languages else loc
                if lang in ctx.languages and t.get("translationText"):
                    translations[lang] = t["translationText"]
            entries[(ident.get("key", "") or "", ident.get("context", "") or "", ident["source"])] = {
                "example": (e.get("metadata") or {}).get("example", "") or "",
                "translations": translations,
            }
        cursor = page.get("nextPageCursor")
        if not cursor:
            break
    return entries


# ── csv io (the human-facing table) ──────────────────────────────────────────

def esc(s):
    return (s or "").replace("\\", "\\\\").replace("\n", "\\n")


def unesc(s):
    # Single left-to-right pass. Replacing "\\n" before "\\\\" is NOT the inverse
    # of esc: a literal backslash followed by 'n' (an escaped "\\\\n") would have
    # its newline-escape matched first, turning C:\new into C:\<LF>ew.
    out, i = [], 0
    s = s or ""
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "n":
                out.append("\n")
                i += 2
                continue
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
        out.append(s[i])
        i += 1
    return "".join(out)


def write_csv(ctx: Ctx, rows):
    header = ["key", "context", "example", "source"] + ctx.languages + ["orphan"]
    with open(ctx.csv_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        for r in rows:
            w.writerow([r["key"], r.get("context", ""), esc(r["example"]), esc(r["source"])]
                       + [esc(r["translations"].get(lang, "")) for lang in ctx.languages]
                       + [r.get("orphan", "")])


def read_csv(ctx: Ctx):
    rows = []
    with open(ctx.csv_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for rec in reader:
            source = unesc(rec.get("source", ""))
            if not source:
                continue
            rows.append({
                "key": (rec.get("key") or "").strip(),
                "context": (rec.get("context") or "").strip(),
                "example": unesc(rec.get("example", "")),
                "source": source,
                "translations": {lang: unesc(rec.get(lang, "")) for lang in ctx.languages if (rec.get(lang) or "").strip()},
                "orphan": (rec.get("orphan") or "").strip(),
            })
    return rows


def chunk_unique_sources(entries):
    """Split `entries` into PATCH-sized chunks in which no two entries share a
    (source, context) pair.

    Roblox rejects a PATCH containing such a pair with `DuplicatedKeySourceContext`
    — and rejects the WHOLE chunk, while reporting only the duplicate count. Two
    keys holding the same English ("Shop" is both menu-shop and title-shop) are
    normal in any game, so without this the upload loses 25 rows per collision and
    looks like a random partial failure."""
    chunks = []  # list of (entries, seen_pairs)
    for e in entries:
        ident = e.get("identifier") or {}
        pair = (ident.get("source", ""), ident.get("context", "") or "")
        for rows, seen in chunks:
            if len(rows) < CHUNK and pair not in seen:
                rows.append(e)
                seen.add(pair)
                break
        else:
            chunks.append(([e], {pair}))
    return [rows for rows, _ in chunks]


def ident_of(r):
    """The cloud's row identity: (key, context, source). Roblox uniqueness is on
    (source, context) — see the note in harvest()."""
    return (r.get("key", ""), r.get("context", "") or "", r["source"])


def load_baseline(ctx: Ctx):
    if ctx.baseline_path.exists():
        # utf-8-SIG like every other read here: a BOM is what you get if anyone
        # ever rewrites this file with PowerShell's Out-File, and a hard crash on
        # a tool-managed cache file is a bad trade.
        return json.loads(ctx.baseline_path.read_text(encoding="utf-8-sig"))["entries"]
    return {}


def save_baseline(ctx: Ctx, rows):
    entries = {}
    for r in rows:
        if r.get("orphan") == "yes":
            continue
        entries[SEP.join(ident_of(r))] = {
            "example": r["example"], "translations": r["translations"],
        }
    ctx.baseline_path.write_text(json.dumps({"entries": entries}, ensure_ascii=False, indent=1), encoding="utf-8")


# ── commands ─────────────────────────────────────────────────────────────────

def cmd_pull(ctx: Ctx):
    harvested = harvest(ctx)
    cloud = fetch_cloud(ctx)
    rows, live = [], set()
    for h in harvested:
        ident = ident_of(h)
        live.add(ident)
        c = cloud.get(ident, {})
        rows.append({
            "key": h["key"],
            "context": h.get("context", ""),
            "example": c.get("example") or h["example"],
            "source": h["source"],
            "translations": c.get("translations", {}),
            "orphan": "",
        })
    for ident, c in sorted(cloud.items()):
        if ident not in live:
            rows.append({"key": ident[0], "context": ident[1], "example": c["example"], "source": ident[2],
                         "translations": c["translations"], "orphan": "yes"})
    write_csv(ctx, rows)
    # The baseline means "the cloud already has this". A harvested row that is
    # ABSENT from the cloud has never been uploaded, so it must NOT enter the
    # baseline — otherwise the next `status` reports "nothing to push" and the
    # row is invisible forever. This is how a partial/interrupted push heals
    # itself: pull, then push, and only the missing rows go up.
    save_baseline(ctx, [r for r in rows if ident_of(r) in cloud])
    orphans = sum(1 for r in rows if r["orphan"] == "yes")
    never = sum(1 for r in rows if r["orphan"] != "yes" and ident_of(r) not in cloud)
    print(f"pulled {len(rows)} rows -> {ctx.csv_path} ({len(harvested)} live, {orphans} orphan)")
    if orphans:
        print("  orphan rows = in the cloud but no longer in the project; `push --prune` deletes them")
    if never:
        print(f"  ⚠ {never} row(s) are NOT in the cloud table yet — run `push` to upload them "
              "(a previous push was partial or never ran)")

    # {token} validation has to happen HERE. The check in diff() only sees rows
    # staged for push, and pull writes the baseline from the same rows it writes
    # the CSV from — so a machine translation that mangled "{n}" into "{ n }" or
    # dropped it produces no diff, ever, and is never checked by anything.
    # FormatByKey then throws on the missing param and silently serves English.
    bad = 0
    for r in rows:
        want = set(TOKEN_RE.findall(r["source"]))
        for lang, text in sorted(r["translations"].items()):
            if set(TOKEN_RE.findall(text)) != want:
                bad += 1
                if bad <= 20:
                    print(f"  TOKEN MISMATCH [{lang}] {r['source']!r} -> {text!r}")
    if bad:
        print(f"  {bad} translation(s) have {{token}} mismatches — fix the cell in the CSV and `push` "
              "(a pushed fix LOCKS and auto-translate will not undo it)")


def diff(ctx: Ctx):
    """-> (upserts, warnings, prunable) from CSV vs baseline."""
    baseline = load_baseline(ctx)
    upserts, warnings, prunable = [], [], []
    for r in read_csv(ctx):
        if r.get("orphan") == "yes":
            prunable.append(r)
            continue
        base = baseline.get(SEP.join(ident_of(r)))
        changed = {}
        if base is None:
            changed = dict(r["translations"])  # brand-new row: push whatever is filled
        else:
            for lang, text in r["translations"].items():
                if text != base["translations"].get(lang, ""):
                    changed[lang] = text
            for lang, old in base["translations"].items():
                if old and lang not in r["translations"]:
                    warnings.append(f"cleared cell ignored (unlock in portal instead): [{lang}] {r['source']!r}")
        src_tokens = set(TOKEN_RE.findall(r["source"]))
        for lang, text in changed.items():
            if set(TOKEN_RE.findall(text)) != src_tokens:
                warnings.append(f"{{token}} mismatch [{lang}] {r['source']!r} -> {text!r}")
        if base is None or changed or (base is not None and r["example"] != base.get("example", "")):
            upserts.append({
                "identifier": {"key": r["key"], "context": r.get("context", ""), "source": r["source"]},
                "metadata": {"example": r["example"]},
                "translations": [{"locale": lang, "translationText": text} for lang, text in changed.items()],
                "delete": False,
                "_new": base is None,
                "_langs": sorted(changed),
            })
    return upserts, warnings, prunable


def cmd_status(ctx: Ctx):
    upserts, warnings, prunable = diff(ctx)
    for w in warnings:
        print("WARN:", w)
    for u in upserts:
        tag = "NEW " if u["_new"] else "EDIT"
        print(f"{tag} [{','.join(u['_langs']) or 'source-only'}] {u['identifier']['source']!r}")
    print(f"{len(upserts)} to push, {len(prunable)} orphan (push --prune to delete), {len(warnings)} warnings")


def cmd_push(ctx: Ctx, prune=False):
    upserts, warnings, prunable = diff(ctx)
    for w in warnings:
        print("WARN:", w)
    batch = [{k: v for k, v in u.items() if not k.startswith("_")} for u in upserts]
    if prune:
        batch += [{"identifier": {"key": r["key"], "context": r.get("context", ""), "source": r["source"]},
                   "translations": [], "delete": True} for r in prunable]
        print(f"pruning {len(prunable)} orphan entries")
    if not batch:
        print("nothing to push")
        return

    # A KEY may exist only ONCE in the table. Re-identifying a row that is
    # already up there — the usual reason being a new `context` to escape a
    # (source, context) collision — is therefore a DELETE followed by an INSERT,
    # never a plain upsert: the insert alone fails with
    # `KeyAlreadyExistInTableWithoutExactMatch` (measured 2026-08-07, 14 rows).
    # This is not the same thing as `--prune`, so it happens unconditionally:
    # the old identity is not a row the user chose to keep, it is a stale
    # version of a row being pushed right now.
    stale = []
    cloud_before = fetch_cloud(ctx)
    by_key = collections.defaultdict(list)
    for ident in cloud_before:
        if ident[0]:
            by_key[ident[0]].append(ident)
    for u in upserts:
        key = u["identifier"]["key"]
        if not key:
            continue
        target = (key, u["identifier"]["context"], u["identifier"]["source"])
        for existing in by_key.get(key, []):
            if existing != target:
                stale.append(existing)
    deletes = [{"identifier": {"key": k, "context": c, "source": s},
                "translations": [], "delete": True} for (k, c, s) in stale]
    if deletes:
        print(f"{len(deletes)} row(s) changed identity — deleting the old versions first "
              "(a key can only exist once in the table)")
    # Only rows the cloud actually HOLDS may enter the baseline (verified by a
    # re-read below). The baseline means "the cloud already has this"; a row
    # recorded as synced that never landed is never retried — the next `status`
    # says "nothing to push" forever and the edit is silently lost. A re-push is
    # idempotent, so when in doubt we leave a row OUT and send it again.
    aborted = 0

    def send(entries, label):
        """Chunked PATCH. Returns the number of rows in chunks that did not land."""
        nonlocal aborted
        # NOT a flat slice: chunks are built so no two entries in one PATCH share
        # a (source, context) — see chunk_unique_sources().
        parts = chunk_unique_sources(entries)
        lost, total = 0, len(parts)
        for i, chunk in enumerate(parts):
            # One bad chunk must not kill the run. `Api.call` raises after its
            # retries are spent (a 504 under load, a 4xx on one malformed row),
            # and letting that propagate throws away every LATER chunk plus the
            # record of which earlier ones landed — that is exactly how this
            # table ended up with 200 of 300 rows and no way to tell. Skip and
            # keep going; those rows stay out of the baseline and go up next push.
            try:
                resp = ctx.api.call("PATCH", f"{ctx.lt}/localization-table/tables/{ctx.table_id}?gameId={ctx.universe}",
                                    body={"entries": chunk})
            except RuntimeError as err:
                aborted += len(chunk)
                lost += len(chunk)
                print(f"  {label} {i + 1}/{total}: ABORTED ({err})")
                print("    these rows stay unsynced and will be retried by the next `push`")
                continue
            bad = resp.get("failedEntriesAndTranslations") or []
            print(f"  {label} {i + 1}/{total}: {len(chunk)} sent, {len(bad)} failed")
            for b in bad[:10]:
                print("    FAILED:", b)
            if bad:
                # MEASURED, not assumed: a PATCH reporting "1 failed" out of 25
                # landed ZERO of its 25 rows (universe 10593425705, 2026-08-07 —
                # 6 reported failures across 4 chunks, 0 of 100 rows in the table
                # afterwards). The write is ATOMIC per chunk and the per-entry
                # counts are misleading. Treat the whole chunk as unsynced.
                lost += len(chunk)
                print("    -> the PATCH is atomic: NONE of this chunk landed. It will be re-sent by the next push.")
        return lost

    # ORDER MATTERS: every delete must complete before the insert that reuses its
    # key, and a delete+insert of the same key inside ONE atomic chunk is not a
    # safe bet. Two separate passes.
    if deletes:
        send(deletes, "delete chunk")
    send(batch, "chunk")

    # Never trust the write's own success report — re-read the table and let it
    # be the judge. This is the only way to be right regardless of how the API
    # chooses to describe a partial failure.
    print("verifying against the cloud table...")
    cloud_after = fetch_cloud(ctx)
    rows, unsynced = [], 0
    for r in read_csv(ctx):
        # Orphans are not live project rows: they are cloud leftovers, and the
        # stale identities deleted above are exactly that. Counting them as
        # "missing" would report a false alarm on a fully successful push.
        if r.get("orphan") == "yes":
            continue
        if ident_of(r) in cloud_after:
            rows.append(r)
        else:
            unsynced += 1
    save_baseline(ctx, rows)

    print(f"cloud now holds {len(cloud_after)} rows; {unsynced} project row(s) still missing.")
    print("Manual translations are now LOCKED (auto-translate won't touch them).")
    if unsynced:
        print(f"WARNING: {unsynced} row(s) did NOT land and are deliberately left out of the baseline — "
              "re-run `push` to retry exactly those; nothing is lost.")
    print("note: changes reach running clients in a few minutes (cloud cache)")
    if unsynced or aborted:
        sys.exit(1)


def cmd_setup(ctx: Ctx):
    body = [{"languageCodeType": "Language", "languageCode": c, "delete": False} for c in ctx.languages]
    ctx.api.call("PATCH", f"{ctx.gi}/supported-languages/games/{ctx.universe}", body=body)
    for _ in range(2):  # toggles can silently no-op right after adding a language
        status = ctx.api.call("GET", f"{ctx.gi}/supported-languages/games/{ctx.universe}/automatic-translation-status")
        enabled = {d["languageCode"] for d in status.get("data", []) if d.get("isAutomaticTranslationEnabled")}
        missing = [c for c in ctx.languages if c not in enabled]
        if not missing:
            break
        for c in missing:
            try:
                ctx.api.call("PATCH", f"{ctx.gi}/supported-languages/games/{ctx.universe}/languages/{c}/automatic-translation-status", body=True)
            except RuntimeError as err:
                print(f"  WARN autotranslate {c}: {err}")
    ctx.api.call("PATCH", f"{ctx.lt}/autolocalization/games/{ctx.universe}/settings",
                 body={"shouldUseLocalizationTable": True})
    quota = ctx.api.call("GET", f"{ctx.gi}/automatic-translation/games/{ctx.universe}/quota")
    print("languages + auto-translation configured; Use Translated Content ON")
    print("quota:", json.dumps(quota))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default="localization/localization.config.json")
    ap.add_argument("command", choices=["pull", "push", "status", "setup"])
    ap.add_argument("--prune", action="store_true", help="push: also delete orphan rows from the cloud")
    args = ap.parse_args()
    ctx = Ctx(Path(args.config).resolve())
    if args.command == "pull":
        cmd_pull(ctx)
    elif args.command == "status":
        cmd_status(ctx)
    elif args.command == "push":
        cmd_push(ctx, prune=args.prune)
    elif args.command == "setup":
        cmd_setup(ctx)


if __name__ == "__main__":
    main()
