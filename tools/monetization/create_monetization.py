#!/usr/bin/env python3
"""
create_monetization.py — create this game's developer products and game passes on
the Roblox universe, wire the ids into ShopData.lua, and audit the live prices.

WHY THIS EXISTS
    All 11 monetization ids ship as 0. An unset id makes the shop cell render the
    disabled "SOON" state, so a first-session player opens the shop onto a wall of
    dead buttons — at the exact moment first-session retention is decided
    (docs/recipes/publish-readiness.md). Creating them by hand is 11 dashboard
    forms, each with a MANDATORY icon; over the API only `name` is required.

      POST https://apis.roblox.com/developer-products/v2/universes/{u}/developer-products
      POST https://apis.roblox.com/game-passes/v1/universes/{u}/game-passes
    multipart/form-data. (The `/cloud/`-prefixed variants some docs show are 404.)
    Note the version asymmetry — products are v2, passes are v1. It is real.

⚠ THERE IS NO DELETE ENDPOINT, AND DEV PRODUCTS HAVE NO UPDATE ENDPOINT EITHER.
    A game pass can be re-PATCHed (name, price, icon) and retired
    (`--retire KEY` -> isForSale=false). A DEVELOPER PRODUCT cannot: seven update /
    icon candidates were probed against the live API in the reference project and
    none worked, so a dev product's name, description and price are FIXED AT
    CREATION, FOREVER. Decide product-vs-pass and read the dry run before --apply.

AUTH — cookie is the proven path
    cookie (default): a `.ROBLOSECURITY` session cookie + the XSRF handshake.
        Point the tool at a file holding the cookie; it is read at runtime and
        never printed, never copied into the repo:
            python ... --cookie-file C:/path/to/ROBLOSECURITY.txt
            $env:ROBLOSECURITY_FILE = "C:/path/to/ROBLOSECURITY.txt"   # or this
        A cookie is a full account session — keep the file OUTSIDE the repo. It is
        pinned to the `.roblox.com` domain here, so the CDN icon fetch never
        receives it.
    key: an Open Cloud API key in ROBLOX_API_KEY. These are NOT `/cloud/` Open
        Cloud endpoints, so a key is very unlikely to be the credential they
        accept — --auth key is therefore refused for any WRITE. Read-only use is
        allowed so you can find out cheaply.

PRICING — regional pricing is forced OFF, on purpose
    Measured in the reference project: creating with `isRegionalPricingEnabled=true`
    makes Roblox treat `price` as a seed for its own regional ladder, and the base
    price does NOT come back equal to what you asked for (its price audit found
    mismatches on every item). The shop UI prints `ShopData.priceRobux` on the card
    while Roblox charges the live price, so any drift means the card LIES about the
    cost. Everything here therefore sends isRegionalPricingEnabled=false, and every
    create is READ BACK from the live listing before the next one is attempted.

    ⚠ For passes that read-back has a repair path (--fix-prices). For dev products
    it does not, which is why --apply creates ONE dev product first, verifies its
    live price, and refuses to continue if it came back wrong.

RESUMABLE / IDEMPOTENT
    Three independent safety nets, because a minted id is unrecoverable:
      1. id_map.json is the LEDGER and is authoritative: a key with a truthy `id`
         for this universe is adopted and never re-created. Written after EVERY
         single create, before the next call.
      2. The live universe is listed and matched by name for anything the ledger
         does not know about.
      3. An unrecognised 200 from a listing is FATAL, never "the universe is
         empty" — that mistake would duplicate the whole catalogue permanently.

USAGE
    python tools/monetization/create_monetization.py --preflight   # who/where, read-only
    python tools/monetization/create_monetization.py               # dry run
    python tools/monetization/create_monetization.py --verify      # audit ids + live prices
    python tools/monetization/create_monetization.py --apply --only gems-s
    python tools/monetization/create_monetization.py --apply --write-shopdata
    python tools/monetization/create_monetization.py --apply --fix-prices --icons
    python tools/monetization/create_monetization.py --apply --retire vip
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("this tool needs `requests`:  python -m pip install requests")

# The Windows console defaults to cp1252, which cannot encode the ⚠ this tool leans
# on to mark the irreversible steps — argparse's own --help crashed on it. Reconfigure
# rather than drop the marks: an unreadable warning is still better than none, and
# `errors="replace"` means a legacy console degrades to `?` instead of a traceback.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

API = "https://apis.roblox.com"
UNIVERSE_ID = 10593425705  # "Eat the Cake" — both PlaceConfig place ids resolve here
REPO = Path(__file__).resolve().parents[2]
SHOPDATA = REPO / "src" / "server" / "common" / "data" / "ShopData.lua"
PLACECONFIG = REPO / "src" / "shared" / "config" / "PlaceConfig.lua"
ID_MAP = Path(__file__).resolve().parent / "id_map.json"

# dev-product create is 3/s, game-pass create 5/s per the OpenAPI spec; stay well under.
THROTTLE_SECONDS = 0.7

# The dashboard-facing copy. `name` is what the buyer reads in the Roblox purchase
# prompt and on the web, so it is the full product name — NOT the ShopData key, and
# not the in-card `desc`, which is clamped to ~15-22 chars by the cell width
# (docs/features/shop.md) and reads as a fragment out of context.
#
# `priceRobux` is NOT repeated here: it is read from ShopData, the single tuning
# point (R1). Duplicating it is how the card and the checkout drift apart.
#
# ⚠ ONLY ROBUX PRODUCTS BELONG HERE. Since the boosts became GEM-priced they carry
# no `devProductId` and no `priceRobux` at all, so a leftover entry does not merely
# create a product nobody sells — `read_shopdata_prices()` runs before every branch
# of main(), including --verify and the dry run, and sys.exit()s on the first key it
# cannot find (or that has no devProductId). One stale key therefore bricks the whole
# tool, which is the only supported way to create the ids the shop is blocked on.
#
# ORDER MATTERS: the first entry is the one --apply proves the pricing hypothesis on
# (see PRICING). It must be a cheap, low-stakes product — not the Starter Pack.
PRODUCT_COPY = {
    "gems-s":      ("100 Gems",     "100 Gems, added to your balance instantly."),
    "gems-m":      ("450 Gems",     "450 Gems, added to your balance instantly."),
    "gems-l":      ("1,050 Gems",   "1,050 Gems, added to your balance instantly."),
    "gems-xl":     ("2,500 Gems",   "2,500 Gems - the best rate in the shop."),
    "starterpack": (
        "Starter Pack",
        "200 Gems, plus x2 Calories, bigger bites and x2 speed - each for 15 minutes.",
    ),
}

PASS_COPY = {
    "x2calories": ("x2 Calories", "Permanently double the calories you gain from eating."),
    "x2gems":     ("x2 Gems",     "Permanently double the gems you get from finds."),
    "autoeat":    ("Auto-Eat",    "Eat automatically - hands free."),
    "autogym":    ("Auto-Gym",    "Burn fat in the background, even while you are away."),
    "capacity2":  ("x2 Stomach",  "Twice the stomach capacity, so you eat longer per trip."),
    "vip":        ("VIP",         "Every perk above, plus 5 squishy slots instead of 3."),
}

# The boosts (x2 Calories, Extra Bite Size, x2 Speed, x2 Stomach) and the two eggs
# are NOT in PRODUCT_COPY on purpose:
#   • the boosts are bought with GEMS now — they must never get a dashboard id, or
#     the same item would be on sale twice at two unrelated prices;
#   • `lucky-egg`, `mega-egg` and `instant-burn` were removed from the catalogue
#     entirely (2026-07-31).
# `instant-burn` had already been held back behind a flag, because its grant kind
# (`burn`) is registered only by the GAME partition while the shop opens in the
# LOBBY, and RunResetSubs empties the belly on every profile load anyway. That
# flag is gone with the product.


def kind_of(key: str) -> str:
    return "product" if key in PRODUCT_COPY else "pass"


def id_field(key: str) -> str:
    return "devProductId" if key in PRODUCT_COPY else "gamePassId"


# --------------------------------------------------------------------------- auth


class Fatal(Exception):
    """Something that must stop the run rather than be retried or skipped."""


class Client:
    """Either cookie+XSRF or an Open Cloud key, behind one `.request`."""

    def __init__(self, mode: str, cookie_file: str | None):
        self.session = requests.Session()
        self.mode = mode
        self.xsrf = ""
        self.user = None
        if mode == "cookie":
            cookie, source = resolve_cookie(cookie_file)
            # Pin the cookie to roblox.com. A domain-less cookie is sent to EVERY
            # host the session touches, which here includes the rbxcdn URL the
            # icon bytes come from.
            self.session.cookies.set(".ROBLOSECURITY", cookie, domain=".roblox.com", path="/")
            print(f"auth: .ROBLOSECURITY cookie (from {source})")
            # POST to a harmless endpoint purely to be handed an XSRF token.
            try:
                handshake = self.session.post("https://auth.roblox.com/v2/logout", timeout=45)
            except requests.RequestException as exc:
                raise Fatal(f"could not reach auth.roblox.com for the XSRF handshake: {exc}")
            self.xsrf = handshake.headers.get("x-csrf-token", "")
            if not self.xsrf:
                raise Fatal(
                    f"no x-csrf-token in the handshake response (HTTP {handshake.status_code}) — "
                    "the cookie is probably expired or malformed."
                )
            try:
                me = self.session.get(
                    "https://users.roblox.com/v1/users/authenticated",
                    headers={"x-csrf-token": self.xsrf}, timeout=45,
                )
            except requests.RequestException as exc:
                raise Fatal(f"could not reach users.roblox.com: {exc}")
            if me.status_code != 200:
                raise Fatal(f"the cookie did not authenticate ({me.status_code}) — refresh it.")
            self.user = me.json()
            print(f"      signed in as {self.user.get('name')} ({self.user.get('id')})")
        else:
            key = os.environ.get("ROBLOX_API_KEY", "").strip()
            if not key:
                raise Fatal(
                    "ROBLOX_API_KEY is not set. Create one at\n"
                    "  https://create.roblox.com/dashboard/credentials\n"
                    "with scopes developer-product:read/write + game-pass:read/write, or use\n"
                    "  --auth cookie --cookie-file <path>   (the verified path)"
                )
            self.session.headers["x-api-key"] = key
            print("auth: Open Cloud API key (ROBLOX_API_KEY)")
            print("      ⚠ NOT VERIFIED — these are not /cloud/ endpoints. Reads only; "
                  "writes are refused under --auth key.")

    def _headers(self) -> dict:
        return {"x-csrf-token": self.xsrf} if self.mode == "cookie" else {}

    def request(self, method: str, url: str, files: dict | None = None,
                params: dict | None = None) -> tuple[int, object]:
        """One call, with the retries this API actually needs: XSRF rotation, 429,
        and transport/5xx. A transport error on a CREATE is the dangerous case —
        Roblox may have minted the un-deletable item and we lost the response — so
        it is retried rather than reported as a clean failure."""
        last_status, last_body = 0, ""
        for attempt in range(4):
            try:
                r = self.session.request(
                    method, url, headers=self._headers(), files=files, params=params, timeout=90
                )
            except requests.RequestException as exc:
                last_status, last_body = 0, str(exc)
                if attempt < 3:
                    time.sleep(1.5 * (attempt + 1))
                    continue
                return last_status, last_body
            # Roblox rotates the XSRF token and replays the rejection once. It
            # attaches x-csrf-token to 403s GENERALLY though, not only to token
            # failures, so a permission 403 looks identical — without the attempt
            # guard it span the loop and fell out as a bare (0, ""), which then
            # slipped straight past create_items' `status in (401, 403)` credential
            # check and reported a permission failure as "HTTP 0".
            if (r.status_code == 403 and self.mode == "cookie"
                    and r.headers.get("x-csrf-token") and attempt < 3):
                self.xsrf = r.headers["x-csrf-token"]
                last_status, last_body = r.status_code, r.text
                continue
            if r.status_code == 429 and attempt < 3:
                time.sleep(retry_after_seconds(r.headers.get("Retry-After")))
                continue
            if 500 <= r.status_code < 600 and attempt < 3:
                time.sleep(1.5 * (attempt + 1))
                last_status, last_body = r.status_code, r.text
                continue
            try:
                return r.status_code, r.json()
            except ValueError:
                return r.status_code, r.text
        return last_status, last_body

    def get_json(self, url: str, params: dict | None = None) -> tuple[int, object]:
        return self.request("GET", url, params=params)


def retry_after_seconds(value: str | None) -> float:
    """Retry-After is either delta-seconds or an HTTP date. float() on a date raises."""
    try:
        return max(0.5, min(30.0, float(value)))
    except (TypeError, ValueError):
        return 3.0


def resolve_cookie(explicit: str | None) -> tuple[str, str]:
    """Read the cookie from a file or the environment. Never returns it in a log line."""
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise Fatal(f"--cookie-file {path} does not exist")
        return path.read_text(encoding="utf-8").strip(), str(path)
    env_file = os.environ.get("ROBLOSECURITY_FILE", "").strip()
    if env_file:
        path = Path(env_file).expanduser()
        if not path.is_file():
            raise Fatal(f"ROBLOSECURITY_FILE points at {path}, which does not exist")
        return path.read_text(encoding="utf-8").strip(), "$ROBLOSECURITY_FILE"
    env_value = os.environ.get("ROBLOSECURITY", "").strip()
    if env_value:
        return env_value, "$ROBLOSECURITY"
    raise Fatal(
        "no .ROBLOSECURITY cookie available. Pass one of:\n"
        "  --cookie-file C:/path/to/ROBLOSECURITY.txt\n"
        '  $env:ROBLOSECURITY_FILE = "C:/path/to/ROBLOSECURITY.txt"\n'
        "Keep that file OUTSIDE this repo — a cookie is a full account session.\n"
        "Or use --auth key with ROBLOX_API_KEY set (reads only)."
    )


def multipart(fields: dict, image: bytes | None = None, image_part: str = "File") -> dict:
    """`requests` files= dict. A scalar becomes (None, "value"): a named form part
    with no filename and no content type, which is what these endpoints expect."""
    out = {k: (None, str(v)) for k, v in fields.items() if v is not None}
    if image is not None:
        out[image_part] = ("icon.png", image, "image/png")
    return out


# ------------------------------------------------------------------ ShopData I/O


def shopdata_text() -> str:
    # newline="" keeps the file's existing CRLF/LF endings byte-for-byte, so wiring an
    # id never shows up as a whole-file line-ending diff. (Path.read_text only learned
    # `newline` in 3.13; this has to run on the 3.11 that is installed.)
    with open(SHOPDATA, "r", encoding="utf-8", newline="") as fh:
        return fh.read()


def write_shopdata_text(src: str) -> None:
    with open(SHOPDATA, "w", encoding="utf-8", newline="") as fh:
        fh.write(src)


def table_span(src: str, table: str) -> tuple[int, int]:
    """Character span of a whole `ShopData.<table> = { ... }` literal. Entry lookups
    are scoped to this so a key can never be found in, or spliced into, the wrong
    table — the two tables use different id field names."""
    opener = re.search(r"\n" + re.escape(table) + r" = \{", src)
    if not opener:
        raise Fatal(f"ShopData.lua has no `{table} = {{` table — the tool and the data file disagree.")
    start = opener.end()
    closer = re.search(r"\n\}", src[start:])
    if not closer:
        raise Fatal(f"ShopData.lua's `{table}` table is never closed by a `}}` at column 0.")
    return start, start + closer.start()


def entry_span(src: str, key: str) -> tuple[int, int]:
    """Character span of one `["key"] = { ... }` entry, WITHIN its own table: from its
    opener to the next top-level entry or the table's end. Brace counting would also
    work, but the table's own indentation is a stronger anchor than nested braces.
    Bounding at the table end matters — without it the LAST entry of each table spans
    to EOF and a missing id line would splice a digit into unrelated code."""
    table = "ShopData.products" if key in PRODUCT_COPY else "ShopData.gamepasses"
    t_start, t_end = table_span(src, table)
    opener = re.search(r'\n\t\["' + re.escape(key) + r'"\] = \{', src[t_start:t_end])
    if not opener:
        raise Fatal(
            f"{table} has no entry for '{key}' — the catalog and the data file disagree."
        )
    start = t_start + opener.end()
    nxt = re.search(r'\n\t\["', src[start:t_end])
    end = start + (nxt.start() if nxt else t_end - start)
    return start, end


def read_shopdata_prices() -> dict[str, tuple[int, str]]:
    """key -> (priceRobux, kind). ShopData is the single tuning point for price (R1),
    so the catalog reads it instead of carrying a second copy that can drift."""
    src = shopdata_text()
    out: dict[str, tuple[int, str]] = {}
    for key in list(PRODUCT_COPY) + list(PASS_COPY):
        kind = kind_of(key)
        start, end = entry_span(src, key)
        block = src[start:end]
        # A gem-priced item must NEVER reach the Creator Dashboard: creation is
        # irreversible, so the same boost would then be on sale for gems AND for
        # Robux at a price nothing in the game reads. Catch the drift here, where
        # it costs a message, rather than after the POST.
        if re.search(r'currency = "gems"', block):
            raise Fatal(
                f"ShopData entry '{key}' is GEM-priced but is still listed in PRODUCT_COPY — "
                "remove it from the catalog (gem items get no dashboard id)."
            )
        field = id_field(key)
        if not re.search(field + r" = \d+", block):
            raise Fatal(f"ShopData entry '{key}' has no {field} — wrong table?")
        price = re.search(r"priceRobux = (\d+)", block)
        if not price:
            raise Fatal(f"ShopData entry '{key}' has no priceRobux")
        if int(price.group(1)) < 1:
            raise Fatal(f"ShopData entry '{key}' has priceRobux 0 — the API minimum is 1 Robux.")
        out[key] = (int(price.group(1)), kind)
    return out


def read_shopdata_ids() -> dict[str, int]:
    src = shopdata_text()
    out: dict[str, int] = {}
    for key in list(PRODUCT_COPY) + list(PASS_COPY):
        start, end = entry_span(src, key)
        m = re.search(id_field(key) + r" = (\d+)", src[start:end])
        if m:
            out[key] = int(m.group(1))
    return out


def write_shopdata(resolved: dict[str, int], force: bool) -> int:
    src = original = shopdata_text()
    wrote, kept, problems = 0, 0, 0
    for key, new_id in sorted(resolved.items()):
        field = id_field(key)
        start, end = entry_span(src, key)
        m = re.search(field + r" = (\d+)", src[start:end])
        if not m:
            print(f"  ! {key}: no {field} to patch — set it to {new_id} by hand")
            problems += 1
            continue
        current = int(m.group(1))
        if current == new_id:
            kept += 1
            continue
        # Never silently repoint a live, already-selling id at something else.
        if current != 0 and not force:
            print(
                f"  ! {key}: {field} is already {current}, not 0 — refusing to overwrite "
                f"with {new_id}. Re-run with --force if that is really what you want."
            )
            problems += 1
            continue
        at = start + m.start(1)
        src = src[:at] + str(new_id) + src[at + len(m.group(1)):]
        print(f"  + {key:13s} {field} = {new_id}")
        wrote += 1
    if src != original:
        write_shopdata_text(src)
        print(f"\nwrote {wrote} id(s) into {SHOPDATA.relative_to(REPO)} ({kept} already correct)")
    else:
        print(f"\nShopData.lua unchanged ({kept} id(s) already correct)")
    return problems


# ------------------------------------------------------------------- id journal


def load_map() -> dict:
    if ID_MAP.is_file():
        try:
            return json.loads(ID_MAP.read_text(encoding="utf-8"))
        except ValueError as exc:
            raise Fatal(
                f"{ID_MAP} is not valid JSON ({exc}). It is the ONLY record of "
                "permanently-minted ids — fix it by hand, do not delete it."
            )
    return {}


def save_map(m: dict) -> None:
    ID_MAP.write_text(json.dumps(m, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def ledger_id(id_map: dict, key: str, universe: int) -> int | None:
    """The ledger is authoritative. An entry stamped with a DIFFERENT universe is
    not ours — id_map.json is one file but --universe is a flag."""
    entry = id_map.get(key)
    if not isinstance(entry, dict):
        return None
    item_id = entry.get("id")
    if not isinstance(item_id, int) or item_id <= 0:
        return None
    stamped = entry.get("universe")
    if stamped is not None and int(stamped) != int(universe):
        return None
    return item_id


# ------------------------------------------------------------------ live listing


def _listing_page(c: Client, url: str, params: dict, container: str) -> tuple[list, str]:
    status, body = c.get_json(url, params=params)
    if status != 200:
        raise Fatal(f"listing {container} failed (HTTP {status}): {str(body)[:400]}")
    if not isinstance(body, dict):
        raise Fatal(f"listing {container} returned {type(body).__name__}, not an object: {str(body)[:400]}")
    # An unrecognised 200 must NEVER read as "the universe is empty": combined with
    # name-based adoption that would create a second permanent copy of everything.
    if container not in body and "nextPageToken" not in body and "nextPageCursor" not in body:
        raise Fatal(
            f"unexpected {container} listing shape, keys={sorted(body)} — refusing to proceed "
            "(treating this as an empty universe would duplicate the whole catalogue, "
            "and neither resource can be deleted)."
        )
    items = body.get(container)
    if items is None:
        items = []
    if not isinstance(items, list):
        raise Fatal(f"listing {container}: `{container}` is {type(items).__name__}, not a list")
    token = body.get("nextPageToken") or ""
    if not token and body.get("nextPageCursor"):
        # The legacy param name. Follow it, but say so — if this ever fires, the
        # pageToken form below is wrong for this endpoint.
        print(f"  ! {container}: paginating on the legacy `nextPageCursor`, not `nextPageToken`")
        token = body["nextPageCursor"]
    return items, token


def list_products(c: Client, u: int) -> list[dict]:
    out: list[dict] = []
    token = ""
    for _ in range(50):
        params = {"pageSize": 50}
        if token:
            params["pageToken"] = token
        items, token = _listing_page(
            c, f"{API}/developer-products/v2/universes/{u}/developer-products/creator",
            params, "developerProducts",
        )
        out += items
        if not token:
            return out
    raise Fatal("developer-product listing did not terminate after 50 pages")


def list_passes(c: Client, u: int) -> list[dict]:
    out: list[dict] = []
    token = ""
    for _ in range(50):
        # passView=Full is load-bearing: without it price / userBasePriceInRobux /
        # displayIconImageAssetId are simply absent from the rows.
        params = {"passView": "Full", "pageSize": 100}
        if token:
            params["pageToken"] = token
        items, token = _listing_page(
            c, f"{API}/game-passes/v1/universes/{u}/game-passes", params, "gamePasses",
        )
        out += items
        if not token:
            return out
    raise Fatal("game-pass listing did not terminate after 50 pages")


def live_price(entry: dict, kind: str) -> int | None:
    """The field that carries the ACTUAL Robux price differs per resource:
    products -> priceInformation.defaultPriceInRobux, passes -> userBasePriceInRobux.
    `price` on a pass is not it (and is null when the pass is off sale)."""
    if kind == "product":
        info = entry.get("priceInformation") or {}
        for field in ("defaultPriceInRobux", "priceInRobux"):
            if info.get(field) is not None:
                return int(info[field])
        return int(entry["priceInRobux"]) if entry.get("priceInRobux") is not None else None
    for field in ("userBasePriceInRobux", "price", "priceInRobux"):
        if entry.get(field) is not None:
            return int(entry[field])
    return None


def pick_id(entry: dict, kind: str) -> int | None:
    keys = ("productId", "developerProductId", "id") if kind == "product" else ("gamePassId", "id", "targetId")
    for k in keys:
        for variant in (k, k[0].upper() + k[1:]):
            value = entry.get(variant)
            if value is None or isinstance(value, bool):
                continue
            try:
                as_int = int(value)
            except (TypeError, ValueError):
                continue
            if as_int > 0:
                return as_int
    return None


def entry_name(entry: dict) -> str:
    for field in ("name", "Name"):
        value = entry.get(field)
        if isinstance(value, str):
            return value.strip()
    return ""


def index_by_name(entries: list[dict]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for e in entries:
        name = entry_name(e)
        if not name:
            continue
        # First writer wins: if two live items share a name, adopting the older one
        # is at least deterministic. Report it — one of them is a stray.
        if name in out:
            print(f"  ! two live items are both named {name!r} — adopting the first")
            continue
        out[name] = e
    return out


# ------------------------------------------------------------------------ icons


def game_icon(c: Client, place_id: int) -> bytes | None:
    """The experience icon, reused as every pass's icon. Optional over the API but
    the dashboard makes it mandatory, and a blank thumbnail in the purchase prompt
    looks broken."""
    status, body = c.get_json(
        "https://thumbnails.roblox.com/v1/places/gameicons",
        params={"placeIds": place_id, "size": "512x512", "format": "Png", "isCircular": "false"},
    )
    row = None
    if status == 200 and isinstance(body, dict):
        data = body.get("data")
        if isinstance(data, list) and data and isinstance(data[0], dict):
            row = data[0]
    if not row:
        print(f"  ! could not resolve the game icon for place {place_id} (HTTP {status}) — skipping icons")
        return None
    if row.get("state") not in (None, "Completed"):
        print(f"  ! the game icon for place {place_id} is in state {row.get('state')!r}, not Completed — skipping icons")
        return None
    url = row.get("imageUrl")
    if not url:
        print(f"  ! the thumbnail response carried no imageUrl — skipping icons")
        return None
    # A separate session: the CDN has no business receiving the cookie, and this
    # host is outside the .roblox.com pin anyway.
    try:
        img = requests.get(url, timeout=90).content
    except requests.RequestException as exc:
        print(f"  ! downloading the icon failed ({exc}) — skipping icons")
        return None
    if not img.startswith(b"\x89PNG\r\n\x1a\n"):
        print(f"  ! what came back from the icon URL is not a PNG ({len(img)} bytes) — skipping icons")
        return None
    print(f"  icon: {len(img)} bytes from place {place_id}")
    return img


def patch_pass(c: Client, u: int, item_id: int, fields: dict, img: bytes | None = None) -> tuple[int, object]:
    """The one endpoint that updates a game pass: price, sale flag and icon all ride
    the same multipart PATCH, and a partial PATCH is accepted. Dev products have no
    equivalent — see the module header."""
    return c.request(
        "PATCH", f"{API}/game-passes/v1/universes/{u}/game-passes/{item_id}",
        multipart(fields, image=img, image_part="File"),
    )


# ------------------------------------------------------------------- preflight


def resolve_place_universe(c: Client, place_id: int) -> int | None:
    status, body = c.get_json(f"{API}/universes/v1/places/{place_id}/universe")
    if status == 200 and isinstance(body, dict):
        try:
            return int(body.get("universeId"))
        except (TypeError, ValueError):
            return None
    print(f"  ! place {place_id}: HTTP {status} {str(body)[:160]}")
    return None


def read_place_config() -> dict[str, int]:
    out: dict[str, int] = {}
    if not PLACECONFIG.is_file():
        return out
    src = PLACECONFIG.read_text(encoding="utf-8")
    for name in ("lobbyPlaceId", "gamePlaceId"):
        m = re.search(r"PlaceConfig\." + name + r" = (\d+)", src)
        if m:
            out[name] = int(m.group(1))
    return out


def preflight(c: Client, u: int) -> bool:
    """Read-only: prove the credential, and prove the universe is the one both
    PlaceConfig places belong to. Monetization ids, DataStores and the teleport
    handoff are all universe-scoped, so a wrong universe here is not recoverable."""
    print("\n=== PREFLIGHT (read-only) ===")
    ok = True
    places = read_place_config()
    if not places:
        print(f"  ! could not read place ids out of {PLACECONFIG.relative_to(REPO)}")
        ok = False
    for name, place_id in sorted(places.items()):
        resolved = resolve_place_universe(c, place_id)
        if resolved == u:
            print(f"  ok {name:13s} {place_id} -> universe {resolved}")
        else:
            print(f"  ! {name:13s} {place_id} -> universe {resolved}, EXPECTED {u}")
            ok = False
    status, body = c.get_json("https://games.roblox.com/v1/games", params={"universeIds": u})
    if status == 200 and isinstance(body, dict) and body.get("data"):
        g = body["data"][0]
        creator = g.get("creator") or {}
        print(f"  ok universe {u}: {g.get('name')!r}  rootPlace={g.get('rootPlaceId')}  "
              f"creator={creator.get('name')!r} ({creator.get('type')})")
    else:
        print(f"  ! could not read universe {u} metadata (HTTP {status}): {str(body)[:200]}")
        ok = False
    return ok


# ------------------------------------------------------------------------- main


def build_catalog(prices: dict[str, tuple[int, str]], only: set[str] | None) -> list[tuple]:
    catalog: list[tuple[str, str, str, str, int]] = []
    for key, (name, desc) in PRODUCT_COPY.items():
        catalog.append(("product", key, name, desc, prices[key][0]))
    for key, (name, desc) in PASS_COPY.items():
        catalog.append(("pass", key, name, desc, prices[key][0]))
    if only is not None:
        unknown = only - {k for _, k, *_ in catalog}
        if unknown:
            raise Fatal(f"--only names key(s) that are not in the catalog: {', '.join(sorted(unknown))}")
        catalog = [row for row in catalog if row[1] in only]
    return catalog


def resolve_existing(c: Client, u: int, catalog: list[tuple], id_map: dict, prices: dict
                     ) -> tuple[dict[str, int], list[tuple], dict, dict]:
    """Ledger first, live listing second. Returns (resolved, todo, products, passes)."""
    products = index_by_name(list_products(c, u))
    passes = index_by_name(list_passes(c, u))
    print(f"  live now: {len(products)} developer product(s), {len(passes)} game pass(es)")

    resolved: dict[str, int] = {}
    todo: list[tuple] = []
    live_by_id = {("product", pick_id(e, "product")): e for e in products.values()}
    live_by_id.update({("pass", pick_id(e, "pass")): e for e in passes.values()})

    for kind, key, name, desc, price in catalog:
        from_ledger = ledger_id(id_map, key, u)
        found = (products if kind == "product" else passes).get(name)
        existing = from_ledger or (pick_id(found, kind) if found else None)
        if not existing:
            todo.append((kind, key, name, desc, price))
            continue
        resolved[key] = existing
        # Look the adopted id up BY ID only. Falling back to the name-matched row
        # here described a DIFFERENT item: a stale ledger id would then borrow the
        # live namesake's price, the "not in the live listing" flag would never
        # print, and --write-shopdata would wire a dead id while exiting 0.
        entry = live_by_id.get((kind, existing)) or {}
        actual = live_price(entry, kind) if entry else None
        source = "ledger" if from_ledger else "name"
        flag = ""
        if not entry:
            flag = "   <-- NOT IN THE LIVE LISTING"
        elif actual != price:
            flag = f"   <-- LIVE PRICE {actual}, ShopData says {price}"
        print(f"  = {kind:7s} {key:13s} exists -> {existing} ({source})  {price:>5} R${flag}")
        # Never let an adoption in one universe overwrite an id minted in another.
        # This write happens on a plain DRY RUN, and the journal is the only record
        # of an id that can never be deleted — a mistyped --universe used to
        # silently destroy it. Reads are already universe-guarded (ledger_id).
        prior = id_map.get(key)
        prior_universe = prior.get("universe") if isinstance(prior, dict) else None
        if isinstance(prior, dict) and prior.get("id") and prior_universe not in (None, u):
            print(f"  ! {key}: the ledger holds id {prior.get('id')} for universe "
                  f"{prior_universe}; NOT overwriting it with {existing} from universe {u}")
            continue
        id_map[key] = {**(prior or {}), "kind": kind, "name": name,
                       "price": price, "id": existing, "universe": u, "adopted": True}
    return resolved, todo, products, passes


def read_back(c: Client, u: int, kind: str, item_id: int) -> dict | None:
    """Re-list and find the item we just created. The id ShopData receives MUST be
    the id the live listing reports, because that is the id ProcessReceipt sees."""
    entries = list_products(c, u) if kind == "product" else list_passes(c, u)
    for e in entries:
        if pick_id(e, kind) == item_id:
            return e
    return None


def create_items(c: Client, u: int, todo: list[tuple], resolved: dict[str, int],
                 id_map: dict, limit: int) -> tuple[int, int]:
    """Create, journal, read back. Returns (created, failed)."""
    created, failed, consecutive_failures = 0, 0, 0
    price_proven = {"product": False, "pass": False}
    for kind, key, name, desc, price in todo:
        if limit and created >= limit:
            print(f"  (--limit {limit} reached; re-run to continue)")
            break
        url = (f"{API}/developer-products/v2/universes/{u}/developer-products" if kind == "product"
               else f"{API}/game-passes/v1/universes/{u}/game-passes")
        status, body = c.request("POST", url, multipart({
            "name": name,
            "description": desc,
            "price": price,
            "isForSale": "true",
            # See PRICING in the header: true makes `price` a seed, not the price.
            "isRegionalPricingEnabled": "false",
        }))
        new_id = pick_id(body, kind) if isinstance(body, dict) else None
        if not new_id:
            failed += 1
            consecutive_failures += 1
            print(f"  ! {key}: create FAILED (HTTP {status}) {str(body)[:300]}")
            id_map.setdefault("_failures", {})[key] = {"http": status, "resp": str(body)[:500],
                                                       "name": name, "universe": u}
            save_map(id_map)
            if status in (401, 403):
                raise Fatal(
                    f"HTTP {status} on create — the credential is not accepted for this "
                    f"universe. Stopping before the rest is attempted."
                )
            if isinstance(body, dict) and (body.get("errorCode") or body.get("code") or body.get("errors")):
                print(f"  the API named an error: {json.dumps(body)[:300]}")
            if consecutive_failures >= 2:
                raise Fatal("two creates failed in a row — stopping rather than hammering the API.")
            time.sleep(THROTTLE_SECONDS)
            continue

        consecutive_failures = 0
        # Journal BEFORE anything else can fail: an id we minted but forgot is an
        # orphan product that can never be deleted and never be found by key.
        id_map[key] = {"kind": kind, "name": name, "price": price, "id": new_id,
                       "http": status, "universe": u}
        if isinstance(id_map.get("_failures"), dict):
            id_map["_failures"].pop(key, None)
        save_map(id_map)
        resolved[key] = new_id
        created += 1
        print(f"  + {kind:7s} {key:13s} -> {new_id}   ({name} / {price} R$)")
        time.sleep(THROTTLE_SECONDS)

        # Read the price back from the live listing before minting anything else.
        # For a dev product this is the ONLY moment the pricing hypothesis can be
        # falsified cheaply — there is no update endpoint to repair it with.
        if not price_proven[kind]:
            entry = read_back(c, u, kind, new_id)
            if entry is None:
                raise Fatal(
                    f"{key} was created as {new_id} but does not appear in the live listing. "
                    "Stopping — the id journal has it; investigate before creating more."
                )
            actual = live_price(entry, kind)
            id_map[key]["livePrice"] = actual
            save_map(id_map)
            if actual == price:
                print(f"    read-back ok: live price {actual} R$ == ShopData {price} R$")
                price_proven[kind] = True
            elif kind == "pass":
                print(f"    ! read-back: live price {actual} R$ != ShopData {price} R$ — "
                      "repairable, run --apply --fix-prices afterwards")
                price_proven[kind] = True
            else:
                raise Fatal(
                    f"{key} came back at {actual} R$, not {price} R$. "
                    "isRegionalPricingEnabled=false did NOT pin the price, and a developer "
                    "product has no update endpoint — the other 4 must NOT be created this "
                    "way. Create the dev products by hand in the Creator Dashboard "
                    "(docs/recipes/publish-readiness.md) and re-run with --write-shopdata."
                )
    return created, failed


def fix_prices(c: Client, u: int, catalog: list[tuple], resolved: dict[str, int],
               prices: dict) -> int:
    """PATCH every PASS whose live price differs from ShopData back to the exact
    Robux amount with regional pricing off, and verify the read-back. Dev products
    are skipped — they have no update endpoint at all.

    ⚠ The PATCH deliberately does NOT carry `isForSale`. It used to send `"true"`
    to every resolved pass, which silently UN-RETIRED anything `--retire` had taken
    off sale — and `--apply --fix-prices --icons` is the routine command, so a pass
    retired weeks earlier came back on sale with nothing in the output saying so.
    Retirement is the only undo this API has; a price fix must not reverse it."""
    print("\nFIX PRICES (passes only — dev products cannot be updated)")
    bad = 0
    kinds = {key: kind for kind, key, *_ in catalog}
    live = {pick_id(e, "pass"): e for e in list_passes(c, u)}
    targets = []
    for key, item_id in sorted(resolved.items()):
        if kinds.get(key) != "pass":
            continue
        entry = live.get(item_id)
        if entry is None:
            bad += 1
            print(f"  ! {key:13s} ({item_id}) is not in the live listing — skipped")
            continue
        if entry.get("isForSale") is False:
            print(f"  {key:13s} is RETIRED (isForSale=false) — left alone")
            continue
        actual = live_price(entry, "pass")
        if actual == prices[key][0]:
            print(f"  {key:13s} already {actual} R$ — no PATCH needed")
            continue
        targets.append((key, item_id, actual))
    if not targets:
        print("  every live pass price already matches ShopData")
        return bad
    for key, item_id, actual in targets:
        price = prices[key][0]
        status, body = patch_pass(
            c, u, item_id, {"price": price, "isRegionalPricingEnabled": "false"},
        )
        if status not in (200, 204):
            bad += 1
            print(f"  ! {key:13s} PATCH -> HTTP {status} {str(body)[:200]}")
        else:
            print(f"  {key:13s} PATCH {actual} -> {price} R$ -> HTTP {status}")
        time.sleep(0.5)
    after = {pick_id(e, "pass"): e for e in list_passes(c, u)}
    print("  verify:")
    for key, item_id, _ in targets:
        entry = after.get(item_id) or {}
        actual = live_price(entry, "pass")
        if actual != prices[key][0]:
            bad += 1
            print(f"    ! {key:13s} userBasePriceInRobux={actual}, expected {prices[key][0]}")
        else:
            print(f"    ok {key:13s} {actual} R$")
    return bad


def retire(c: Client, u: int, keys: list[str], resolved: dict[str, int], id_map: dict) -> int:
    """The ONLY way to undo a mistake: take a pass off sale. Passes only."""
    print("\nRETIRE (isForSale=false)")
    bad = 0
    for key in keys:
        if kind_of(key) != "pass":
            print(f"  ! {key}: dev products have NO update endpoint — a mis-created one "
                  "cannot be retired, only left unreferenced by ShopData.")
            bad += 1
            continue
        item_id = resolved.get(key) or ledger_id(id_map, key, u)
        if not item_id:
            print(f"  ! {key}: no live id known — nothing to retire")
            bad += 1
            continue
        status, body = patch_pass(c, u, item_id, {"isForSale": "false"})
        ok = status in (200, 204)
        if not ok:
            bad += 1
        entry = id_map.get(key)
        if isinstance(entry, dict):
            entry["deactivated"] = ok
            save_map(id_map)
        print(f"  {key:13s} ({item_id}) -> HTTP {status}{'' if ok else ' ' + str(body)[:160]}")
        time.sleep(0.4)
    return bad


def verify(catalog: list[tuple], resolved: dict[str, int], prices: dict,
           products: dict, passes: dict) -> int:
    """Audit: does what is live match ShopData — id AND price — and is ShopData wired?"""
    wired = read_shopdata_ids()
    by_id = {("product", pick_id(e, "product")): e for e in products.values()}
    by_id.update({("pass", pick_id(e, "pass")): e for e in passes.values()})
    bad = 0
    print("\n=== VERIFY ===")
    print("  (price source: products -> priceInformation.defaultPriceInRobux, "
          "passes -> userBasePriceInRobux)")
    for kind, key, name, desc, price in catalog:
        live = resolved.get(key)
        in_file = wired.get(key, 0)
        problems = []
        if live is None:
            problems.append("does NOT exist live")
        if in_file == 0:
            problems.append("ShopData id is 0")
        elif live is not None and in_file != live:
            problems.append(f"ShopData has {in_file}, live is {live}")
        actual = None
        if live is not None:
            entry = by_id.get((kind, live))
            if entry is None:
                problems.append("not in the live listing")
            else:
                actual = live_price(entry, kind)
                if actual != price:
                    problems.append(f"LIVE PRICE {actual} R$, ShopData says {price} R$")
                if kind == "pass" and entry.get("isForSale") is False:
                    problems.append("isForSale=false (retired)")
        if problems:
            bad += 1
            print(f"  ! {kind:7s} {key:13s} {'; '.join(problems)}")
        else:
            print(f"  ok {kind:7s} {key:13s} {live}  {actual} R$")
    print(f"\n{len(catalog) - bad}/{len(catalog)} fully wired and correctly priced; {bad} problem(s)")
    return bad


def root_place(c: Client, u: int) -> int:
    status, body = c.get_json("https://games.roblox.com/v1/games", params={"universeIds": u})
    if status == 200 and isinstance(body, dict) and body.get("data"):
        try:
            return int(body["data"][0].get("rootPlaceId") or 0)
        except (TypeError, ValueError):
            return 0
    print(f"  ! could not resolve the root place of universe {u} (HTTP {status})")
    return 0


def run(args) -> int:
    prices = read_shopdata_prices()
    only = set(args.only.split(",")) if args.only else None
    catalog = build_catalog(prices, only)

    writes_requested = bool(args.apply or args.retire)
    if writes_requested and args.auth == "key":
        raise Fatal(
            "--auth key cannot perform writes: these are not /cloud/ Open Cloud endpoints "
            "and an API key is not the credential they accept. Use --auth cookie."
        )

    c = Client(args.auth, args.cookie_file)
    u = args.universe

    if args.preflight:
        return 0 if preflight(c, u) else 1

    print(f"universe {u}   catalog: {len(catalog)} item(s) "
          f"({sum(1 for k, *_ in catalog if k == 'product')} products, "
          f"{sum(1 for k, *_ in catalog if k == 'pass')} passes)")
    print("  (the four boosts are gem-priced and deliberately have no dashboard id)")

    id_map = load_map()
    resolved, todo, products, passes = resolve_existing(c, u, catalog, id_map, prices)

    if args.verify:
        # --verify writes nothing at all, not even the journal.
        return 1 if verify(catalog, resolved, prices, products, passes) else 0

    save_map(id_map)
    failed = 0

    # --retire is a MODE, not a modifier: it returns instead of falling through.
    # It used to run and then continue into the create path, so `--apply --retire
    # vip` against a universe that had nothing yet printed "nothing to retire" and
    # then permanently minted the whole catalogue — including the very pass the
    # user was trying to take off sale.
    if args.retire:
        if not args.apply:
            print("\nRETIRE skipped — it takes a LIVE pass off sale and needs --apply.")
            for key in args.retire.split(","):
                item_id = resolved.get(key) or ledger_id(id_map, key, u)
                print(f"  would PATCH {key} ({item_id or 'no id known'}) isForSale=false")
            return 1
        failed += retire(c, u, args.retire.split(","), resolved, id_map)
        save_map(id_map)
        return 1 if failed else 0

    if todo:
        print(f"\nTO CREATE ({len(todo)}{f', limited to {args.limit} this run' if args.limit else ''}):")
        for kind, key, name, desc, price in todo:
            print(f"  + {kind:7s} {key:13s} {price:>5} R$  {name}")
    else:
        print("\nnothing to create.")

    if todo and not args.apply:
        print("\nDRY RUN — nothing was created. Re-run with --apply to create the items above.")
        print("⚠ Creation is PERMANENT: there is no delete endpoint, and a DEVELOPER PRODUCT")
        print("  has no update endpoint either — its name, description and price are final.")
    elif todo:
        print("\nCREATING")
        created, create_failures = create_items(c, u, todo, resolved, id_map, args.limit)
        failed += create_failures
        print(f"\ncreated {created} item(s); journal: {ID_MAP.relative_to(REPO)}")

    save_map(id_map)

    img = None
    if args.icons:
        if not args.apply:
            print("\nICONS skipped — --icons performs writes and needs --apply.")
        else:
            place = args.place or root_place(c, u)
            print("\nICONS (game passes only — dev products have no working icon endpoint;")
            print("       set those in the Creator Dashboard by hand)")
            img = game_icon(c, place) if place else None

    # The icon PATCH and the price PATCH are now INDEPENDENT. They used to be one
    # call, which is how `isForSale=true` ended up riding along on a routine
    # `--apply --fix-prices --icons` and un-retiring passes. Each carries only the
    # fields it is named after.
    if img is not None:
        print("\nICON PATCH (icon only — price and sale state untouched)")
        kinds = {key: kind for kind, key, *_ in catalog}
        for key, item_id in sorted(resolved.items()):
            if kinds.get(key) != "pass":
                continue
            status, body = patch_pass(c, u, item_id, {}, img=img)
            if status not in (200, 204):
                failed += 1
                print(f"  ! {key:13s} -> HTTP {status} {str(body)[:200]}")
            else:
                print(f"  {key:13s} -> HTTP {status}")
            time.sleep(0.5)

    if args.fix_prices:
        if not args.apply:
            print("\nFIX PRICES skipped — it performs writes and needs --apply.")
        else:
            failed += fix_prices(c, u, catalog, resolved, prices)

    print("\nRESOLVED IDS")
    for kind, key, *_ in catalog:
        print(f"  {kind:7s} {key:13s} {resolved.get(key, '-')}")

    if args.write_shopdata and resolved:
        print("\nWIRING ShopData.lua")
        failed += write_shopdata(resolved, args.force)

    remaining = [k for k, v in read_shopdata_ids().items() if v == 0]
    if remaining:
        print(f"\nSTILL 0 in ShopData ({len(remaining)}): {', '.join(sorted(remaining))}")
    else:
        print("\nevery id in ShopData is non-zero.")

    if failed:
        print(f"\n{failed} problem(s) — see the lines marked `!` above.")
        return 1
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="actually perform writes (IRREVERSIBLE: there is no delete endpoint)")
    ap.add_argument("--write-shopdata", action="store_true", help="write the resolved ids into ShopData.lua")
    ap.add_argument("--icons", action="store_true",
                    help="PATCH the experience icon onto every game pass (needs --apply)")
    ap.add_argument("--fix-prices", action="store_true",
                    help="re-PATCH every pass to its exact ShopData price, regional pricing off (needs --apply)")
    ap.add_argument("--retire", metavar="KEY[,KEY]",
                    help="take the named game pass(es) off sale — the only undo that exists (needs --apply)")
    ap.add_argument("--verify", action="store_true",
                    help="audit only: live id AND live price vs ShopData. Writes nothing.")
    ap.add_argument("--preflight", action="store_true",
                    help="read-only: prove the credential and that both PlaceConfig places live in --universe")
    ap.add_argument("--only", metavar="KEY[,KEY]", help="restrict the catalog to these keys")
    ap.add_argument("--limit", type=int, default=0, help="create at most N items this run (0 = no limit)")
    ap.add_argument("--force", action="store_true", help="allow overwriting a non-zero id in ShopData.lua")
    ap.add_argument("--auth", choices=("cookie", "key"), default="cookie", help="default: cookie (the verified path)")
    ap.add_argument("--cookie-file", help="path to a file containing the .ROBLOSECURITY cookie")
    ap.add_argument("--universe", type=int, default=UNIVERSE_ID)
    ap.add_argument("--place", type=int, default=0, help="place id to take the icon from (default: the universe root)")
    args = ap.parse_args()

    try:
        sys.exit(run(args))
    except Fatal as exc:
        sys.exit(f"\nFATAL: {exc}")


if __name__ == "__main__":
    main()
