#!/usr/bin/env python3
"""Fetch, classify, and sync Rosetta Code programming tasks into Project 5."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import textwrap
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from _lib.harness_common import REPO_ROOT

ROSETTA_API_URL = "https://rosettacode.org/w/api.php"
ROSETTA_CATEGORY = "Category:Programming_Tasks"
USER_AGENT = "safe-rosetta-inventory/0.1 (+https://github.com/berkeleynerd/safe)"
CACHE_ROOT = REPO_ROOT / ".cache" / "rosetta"
CACHE_FILE = CACHE_ROOT / "programming_tasks_v1.json"
CACHE_SCHEMA_VERSION = 1
DEFAULT_OWNER = "berkeleynerd"
DEFAULT_PROJECT_NUMBER = 5
DEFAULT_PARENT_ISSUE_NUMBER = 347
EXTRACT_CHARS = 400
HTTP_THROTTLE_SECONDS = 1.0
GRAPHQL_BATCH_SIZE = 20
CATEGORY_MEMBER_BATCH_SIZE = 500
EXTRACT_BATCH_SIZE = 20
PROJECT_FIELD_FETCH_LIMIT = 100
PROJECT_ITEM_FETCH_LIMIT = 5000
BODY_URL_RE = re.compile(r"^\*\*Rosetta URL:\*\*\s+(\S+)\s*$", re.MULTILINE)
WHITESPACE_RE = re.compile(r"\s+")
RELATED_TASKS_RE = re.compile(r"\bRelated tasks?\b", re.IGNORECASE)
INLINE_URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)
COMMENT_MARKER_RE = re.compile(r"<!--\s*([A-Za-z0-9:_-]+)\s*-->")


@dataclass(frozen=True)
class Keyword:
    label: str
    regex: re.Pattern[str]
    skip_title_prefixes: tuple[str, ...] = ()
    skip_title_suffixes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Rule:
    bucket: str
    subbucket: str
    title_keywords: tuple[Keyword, ...] = ()
    body_keywords: tuple[Keyword, ...] = ()
    feature_hints: tuple[str, ...] = ()


@dataclass(frozen=True)
class RawTask:
    pageid: int
    title: str
    url: str
    extract: str


@dataclass(frozen=True)
class InventoryRecord:
    title: str
    url: str
    extract: str
    bucket: str
    subbucket: str
    matched_rule: str
    difficulty: str
    rosetta_category: str
    features: tuple[str, ...]
    porting_status: str

    @property
    def feature_text(self) -> str:
        return ", ".join(self.features)


@dataclass(frozen=True)
class ProjectField:
    name: str
    field_id: str
    kind: str
    option_ids: dict[str, str]


@dataclass(frozen=True)
class ProjectItem:
    item_id: str
    content_type: str
    title: str
    body: str
    field_values: dict[str, str]
    draft_issue_id: str | None = None
    issue_number: int | None = None

    @property
    def rosetta_url(self) -> str | None:
        if value := self.field_values.get("Rosetta URL"):
            return value
        return parse_rosetta_url_from_body(self.body)


@dataclass(frozen=True)
class IssueComment:
    comment_id: str
    body: str


@dataclass(frozen=True)
class DraftUpdate:
    item_id: str
    draft_issue_id: str
    title: str
    body: str


@dataclass(frozen=True)
class FieldUpdate:
    item_id: str
    field_name: str
    value: str | None


@dataclass(frozen=True)
class SyncPlan:
    creates: tuple[InventoryRecord, ...]
    draft_updates: tuple[DraftUpdate, ...]
    field_updates: tuple[FieldUpdate, ...]
    unchanged: int
    missing: tuple[ProjectItem, ...]


REVIEW_SAMPLE_QUOTAS: dict[tuple[str, str], int] = {
    ("1", "(none)"): 17,
    ("2", "2a"): 8,
    ("2", "2b"): 1,
    ("2", "2c"): 1,
    ("3", "(none)"): 3,
    ("3", "3a"): 1,
    ("3", "3b"): 3,
    ("3", "3c"): 2,
    ("3", "3d"): 2,
    ("3", "3e"): 2,
    ("4", "(none)"): 1,
    ("4", "4a"): 3,
    ("4", "4b"): 2,
    ("4", "4c"): 3,
    ("4", "4d"): 1,
}
# The deterministic review sample stays fixed at 50 tasks. Bucket 4e is
# intentionally excluded because platform-specific tasks are already out of
# scope through v1.0 and do not inform the current porting burn-down.

REVIEW_SAMPLE_ANCHOR_TITLES = (
    "Hello world/Text",
    "100 doors",
    "Church numerals",
    "Higher-order functions",
    "Monads/List monad",
    "Add a variable to a class instance at runtime",
    "Append a record to the end of a text file",
    "URL encoding",
    "Regular expressions",
    "Hello world/Graphical",
    "Bitmap",
)
REVIEW_SAMPLE_ANCHOR_TITLE_SET = frozenset(REVIEW_SAMPLE_ANCHOR_TITLES)

PORTED_SAMPLE_TITLE_ALIASES = {
    "samples/rosetta/arithmetic/collatz_bounded.safe": "Hailstone sequence",
    "samples/rosetta/arithmetic/factorial.safe": "Factorial",
    "samples/rosetta/arithmetic/fibonacci.safe": "Fibonacci sequence",
    "samples/rosetta/arithmetic/gcd.safe": "Greatest common divisor",
    "samples/rosetta/data_structures/bounded_stack.safe": "Stack",
    "samples/rosetta/sorting/binary_search.safe": "Binary search",
    "samples/rosetta/sorting/bubble_sort.safe": "Sorting algorithms/Bubble sort",
    "samples/rosetta/text/hello_print.safe": "Hello world/Text",
}

LOCAL_ONLY_SAMPLE_PATHS = {
    "samples/rosetta/concurrency/producer_consumer.safe",
    "samples/rosetta/data_structures/fixed_to_growable.safe",
    "samples/rosetta/data_structures/growable_sum.safe",
    "samples/rosetta/data_structures/growable_to_fixed.safe",
    "samples/rosetta/data_structures/parse_result.safe",
    "samples/rosetta/text/bounded_prefix.safe",
    "samples/rosetta/text/enum_dispatch.safe",
    "samples/rosetta/text/grade_message.safe",
    "samples/rosetta/text/lookup_pair.safe",
    "samples/rosetta/text/lookup_result.safe",
    "samples/rosetta/text/opcode_dispatch.safe",
}

TRIVIAL_HINTS = (
    "hello world",
    "factorial",
    "greatest common divisor",
    "binary search",
    "bubble sort",
    "hailstone",
    "stack",
    "sum",
    "variables",
    "loops",
)

COMPLEX_HINTS = (
    "compiler",
    "parser",
    "interpreter",
    "concurrent",
    "thread",
    "socket",
    "http",
    "regex",
    "calendar",
    "unicode",
    "cryptographic",
    "graphics",
    "gui",
    "fractal",
    "matrix",
    "serialization",
    "cross-compile",
)

FEATURE_KEYWORDS = (
    ("arrays", ("array", "list", "vector", "matrix", "sort", "search", "stack", "queue")),
    ("strings", ("string", "text", "word", "unicode", "utf-8", "utf-16", "grapheme")),
    ("arithmetic", ("number", "integer", "prime", "factorial", "fibonacci", "sum", "gcd")),
    ("loops", ("loop", "iterate", "range", "sequence", "search", "sort")),
    ("conditionals", ("case", "branch", "dispatch", "if", "switch", "match")),
    ("records", ("record", "struct", "tuple", "pair", "result", "object")),
    ("concurrency", ("thread", "producer", "consumer", "channel", "concurrent")),
    ("i/o", ("file", "stdin", "standard input", "command-line", "read", "write")),
    ("serialization", ("json", "csv", "xml", "yaml", "protobuf", "serialize")),
    ("enums", ("enumeration", "enum")),
)


def literal_keyword(
    label: str,
    literal: str,
    *,
    skip_title_prefixes: Iterable[str] = (),
    skip_title_suffixes: Iterable[str] = (),
) -> Keyword:
    escaped = re.escape(literal)
    # Some Python builds emit `"a\\ b"` here while others emit `"a b"`.
    escaped = re.sub(r"(?:\\ )| ", r"\\s+", escaped)
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 _/\-.:+]*", literal):
        pattern = rf"\b{escaped}\b"
    else:
        pattern = escaped
    return Keyword(
        label=label,
        regex=re.compile(pattern, re.IGNORECASE),
        skip_title_prefixes=tuple(prefix.lower() for prefix in skip_title_prefixes),
        skip_title_suffixes=tuple(suffix.lower() for suffix in skip_title_suffixes),
    )


def coerce_keyword(keyword: str | Keyword) -> Keyword:
    if isinstance(keyword, Keyword):
        return keyword
    return literal_keyword(keyword, keyword)


def make_rule(
    bucket: str,
    subbucket: str,
    *,
    title_keywords: Iterable[str | Keyword] = (),
    body_keywords: Iterable[str | Keyword] = (),
    feature_hints: Iterable[str] = (),
) -> Rule:
    return Rule(
        bucket=bucket,
        subbucket=subbucket,
        title_keywords=tuple(coerce_keyword(keyword) for keyword in title_keywords),
        body_keywords=tuple(coerce_keyword(keyword) for keyword in body_keywords),
        feature_hints=tuple(feature_hints),
    )


RULES = (
    make_rule(
        "4",
        "4a",
        title_keywords=("gui", "window", "windowed", "dialog", "menu", "gtk", "qt", "tk", "graphical", "mouse"),
        body_keywords=("gui object", "alert box", "plain window", "text area"),
    ),
    make_rule(
        "4",
        "4b",
        title_keywords=("http", "https", "socket", "sockets", "web server", "smtp", "ftp", "irc", "soap", "active directory"),
        body_keywords=(
            "access a url's content",
            "web server",
            "lightweight directory access protocol",
            "ldap server",
            "media wiki api",
            "mediawiki api",
        ),
    ),
    make_rule(
        "4",
        "4c",
        title_keywords=(
            "draw",
            "canvas",
            "image",
            "bitmap",
            "pixel",
            "raster",
            "vector graphics",
            "graphics",
            literal_keyword("animation", "animation", skip_title_suffixes=("/text",)),
            "particle fountain",
        ),
        body_keywords=(
            "two-dimensional graphing",
            "cartesian plane",
            "periodically changing the display",
            "digital images",
            "source image",
            "target image",
        ),
    ),
    make_rule(
        "4",
        "4d",
        title_keywords=(
            "exec",
            "spawn process",
            "system call",
            "fork",
            "ffi",
            "foreign-language function",
            "foreign language function",
            "shared library",
            "another language to call a function",
        ),
    ),
    make_rule(
        "4",
        "4e",
        title_keywords=("windows-only", "linux-only", "macos-only", "platform-specific", "windows event log", "hostname", "shell one-liner"),
        body_keywords=("host on which the routine is running",),
    ),
    make_rule(
        "4",
        "(none)",
        title_keywords=(
            "class instance",
            "classes",
            "inheritance",
            "unknown method call",
            literal_keyword("polymorphism", "polymorphism", skip_title_prefixes=("parametric polymorphism",)),
        ),
        body_keywords=(
            "monkeypatching",
            "dynamic dispatch mechanism",
            literal_keyword("inheritance hierarchy", "inheritance hierarchy", skip_title_prefixes=("parametric polymorphism",)),
            literal_keyword("based upon inheritance", "based upon inheritance", skip_title_prefixes=("parametric polymorphism",)),
        ),
    ),
    make_rule("3", "3a", title_keywords=("regex", "regular expression", "regular expressions"), feature_hints=("strings",)),
    make_rule(
        "3",
        "3b",
        title_keywords=("date", "calendar", "epoch", "time of day", "day of the week", "leap year"),
        body_keywords=("iso 8601", "time of day", "day of the week"),
    ),
    make_rule("3", "3c", title_keywords=("sha", "md5", "hmac", "aes", "rsa", "cryptographic")),
    make_rule("3", "3d", title_keywords=("unicode", "utf-8", "utf-16", "grapheme"), feature_hints=("strings",)),
    make_rule(
        "3",
        "3e",
        title_keywords=(
            "bignum",
            "arbitrary precision",
            "arbitrary-precision",
            "rational",
            "complex",
            "p-adic",
            "roots of unity",
            "gaussian primes",
        ),
        body_keywords=("complex number", "complex numbers", "arbitrary-precision"),
        feature_hints=("arithmetic",),
    ),
    make_rule(
        "3",
        "(none)",
        title_keywords=(
            "callback",
            "church numerals",
            "closures/value capture",
            "currying",
            "first class environments",
            "first-class functions",
            "function composition",
            "higher-order functions",
            "monad",
            "nested function",
            "partial function application",
            "y combinator",
        ),
        body_keywords=(
            "anonymous functions are encouraged",
            "apply a function to each element",
            "callback comparison function",
            "create new functions from preexisting functions at run-time",
            "pass a function as an argument",
            "use functions as arguments to other functions",
            "use functions as return values of other functions",
        ),
        feature_hints=("functions",),
    ),
    make_rule(
        "2",
        "2a",
        title_keywords=("file", "files", "directory", "directories", "tape", "fixed length records"),
        body_keywords=(
            "open a file",
            "open the file",
            "text file",
            "input file",
            "output file",
            "lines of a file",
            "file exists",
            "file for writing",
            "read from a file",
            "write to a file",
            "append to the end of the file",
            "read entire file",
        ),
        feature_hints=("i/o",),
    ),
    make_rule(
        "2",
        "2b",
        title_keywords=("stdin", "standard input", "command-line", "program name", "compiler/code generator", "hunt the wumpus"),
        body_keywords=("arguments from", "read input from a file and/or stdin"),
        feature_hints=("i/o",),
    ),
    make_rule(
        "2",
        "2c",
        title_keywords=("json", "csv", "xml", "yaml", "protobuf"),
        body_keywords=("serialize", "serialization"),
        feature_hints=("serialization",),
    ),
    make_rule(
        "2",
        "2d",
        title_keywords=("assert", "test framework", "round-trip"),
        body_keywords=("expected output file",),
    ),
    make_rule("2", "2e", title_keywords=("cross-compile", "target architecture"), body_keywords=("embed in",)),
    make_rule("2", "2f", title_keywords=("generate documentation", "doc comment", "api doc")),
)


def normalize_space(text: str) -> str:
    return WHITESPACE_RE.sub(" ", text).strip()


def classification_extract(extract: str) -> str:
    normalized = normalize_space(extract)
    match = RELATED_TASKS_RE.search(normalized)
    if match is None:
        trimmed = normalized
    else:
        trimmed = normalized[: match.start()].strip()
    without_urls = INLINE_URL_RE.sub("", trimmed)
    return normalize_space(without_urls)


def slugify(text: str) -> str:
    lowered = text.lower().replace("&", " and ")
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", lowered)).strip("_")


def title_to_url(title: str) -> str:
    return "https://rosettacode.org/wiki/" + quote(title.replace(" ", "_"), safe="/()")


def title_to_rosetta_category(title: str) -> str:
    if "/" not in title:
        return ""
    return title.split("/", 1)[0].replace("_", " ")


def classify_task(title: str, extract: str) -> tuple[str, str, str, tuple[str, ...]]:
    title_haystack = normalize_space(title).lower()
    body_haystack = classification_extract(extract).lower()
    for rule in RULES:
        for keyword in rule.title_keywords:
            if any(title_haystack.startswith(prefix) for prefix in keyword.skip_title_prefixes):
                continue
            if any(title_haystack.endswith(suffix) for suffix in keyword.skip_title_suffixes):
                continue
            if keyword.regex.search(title_haystack):
                features = infer_features(title, extract, seed=rule.feature_hints)
                return rule.bucket, rule.subbucket, f"keyword:{keyword.label}", features
        for keyword in rule.body_keywords:
            if any(title_haystack.startswith(prefix) for prefix in keyword.skip_title_prefixes):
                continue
            if any(title_haystack.endswith(suffix) for suffix in keyword.skip_title_suffixes):
                continue
            if keyword.regex.search(body_haystack):
                features = infer_features(title, extract, seed=rule.feature_hints)
                return rule.bucket, rule.subbucket, f"keyword:{keyword.label}", features
    return "1", "(none)", "default", infer_features(title, extract)


def infer_features(title: str, extract: str, *, seed: Iterable[str] = ()) -> tuple[str, ...]:
    haystack = normalize_space(f"{title}\n{classification_extract(extract)}").lower()
    ordered: list[str] = []
    seen = set()

    def add(feature: str) -> None:
        if feature in seen:
            return
        seen.add(feature)
        ordered.append(feature)

    for feature in seed:
        add(feature)
    for feature, keywords in FEATURE_KEYWORDS:
        if any(keyword in haystack for keyword in keywords):
            add(feature)
    if not ordered:
        add("functions")
    return tuple(ordered)


def infer_difficulty(title: str, extract: str, bucket: str) -> str:
    haystack = normalize_space(f"{title}\n{classification_extract(extract)}").lower()
    if bucket in {"3", "4"}:
        return "complex"
    if any(hint in haystack for hint in COMPLEX_HINTS):
        return "complex"
    if any(hint in haystack for hint in TRIVIAL_HINTS):
        return "trivial"
    return "moderate"


def parse_rosetta_url_from_body(body: str) -> str | None:
    match = BODY_URL_RE.search(body)
    return match.group(1) if match else None


def build_item_body(record: InventoryRecord) -> str:
    extract = record.extract or "No introductory extract available from the MediaWiki API."
    category = record.rosetta_category or "(none)"
    return textwrap.dedent(
        f"""\
        **Rosetta URL:** {record.url}
        **Bucket:** {record.bucket}
        **Sub-bucket:** {record.subbucket}
        **Porting Status:** {record.porting_status}
        **Difficulty:** {record.difficulty}
        **Matched rule:** {record.matched_rule}
        **Rosetta Category:** {category}
        **Features Used:** {record.feature_text}

        **Extract**

        {extract}
        """
    ).strip()


def desired_field_values(record: InventoryRecord) -> dict[str, str | None]:
    return {
        "Bucket": record.bucket,
        "Sub-bucket": record.subbucket,
        "Porting Status": record.porting_status,
        "Difficulty": record.difficulty,
        "Rosetta Category": record.rosetta_category or None,
        "Rosetta URL": record.url,
        "Features Used": record.feature_text,
    }


def current_iso_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def request_json(params: dict[str, str], *, throttle_seconds: float, last_request_at: list[float]) -> dict[str, Any]:
    elapsed = time.monotonic() - last_request_at[0]
    if elapsed < throttle_seconds:
        time.sleep(throttle_seconds - elapsed)
    request = Request(
        ROSETTA_API_URL + "?" + urlencode(params),
        headers={"User-Agent": USER_AGENT},
    )
    try:
        with urlopen(request, timeout=60) as response:
            raw_payload = response.read()
        payload = json.loads(raw_payload)
    except (HTTPError, URLError) as exc:
        raise RuntimeError(f"rosetta api request failed: {exc}") from exc
    except json.JSONDecodeError as exc:
        snippet = raw_payload[:200].decode("utf-8", errors="replace")
        raise RuntimeError(
            f"rosetta api request returned invalid JSON for {request.full_url}: {exc}; snippet={snippet!r}"
        ) from exc
    last_request_at[0] = time.monotonic()
    return payload


def fetch_live_task_count(*, throttle_seconds: float, last_request_at: list[float]) -> int:
    payload = request_json(
        {
            "action": "query",
            "titles": ROSETTA_CATEGORY,
            "prop": "categoryinfo",
            "format": "json",
            "formatversion": "2",
        },
        throttle_seconds=throttle_seconds,
        last_request_at=last_request_at,
    )
    try:
        return int(payload["query"]["pages"][0]["categoryinfo"]["size"])
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise RuntimeError(f"unexpected categoryinfo response from Rosetta API: {exc}") from exc


def fetch_raw_tasks(*, throttle_seconds: float) -> tuple[int, list[RawTask], str]:
    last_request_at = [0.0]
    category_size = fetch_live_task_count(throttle_seconds=throttle_seconds, last_request_at=last_request_at)
    members: list[tuple[int, str]] = []
    cmcontinue: str | None = None
    category_page_count = 0
    while True:
        params = {
            "action": "query",
            "list": "categorymembers",
            "cmtitle": ROSETTA_CATEGORY,
            "cmtype": "page",
            "cmlimit": str(CATEGORY_MEMBER_BATCH_SIZE),
            "format": "json",
            "formatversion": "2",
        }
        if cmcontinue is not None:
            params["cmcontinue"] = cmcontinue
        payload = request_json(params, throttle_seconds=throttle_seconds, last_request_at=last_request_at)
        category_page_count += 1
        for page in payload.get("query", {}).get("categorymembers", []):
            title = page["title"]
            if is_draft_title(title):
                continue
            members.append((int(page["pageid"]), title))
        print(
            f"rosetta_inventory: category page {category_page_count} "
            f"loaded ({len(members)} task titles so far)",
            flush=True,
        )
        cmcontinue = payload.get("continue", {}).get("cmcontinue")
        if cmcontinue is None:
            break

    extracts_by_pageid: dict[int, str] = {}
    pageid_batches = list(batched([pageid for pageid, _title in members], EXTRACT_BATCH_SIZE))
    for batch_index, pageid_batch in enumerate(pageid_batches, start=1):
        payload = request_json(
            {
                "action": "query",
                "pageids": "|".join(str(pageid) for pageid in pageid_batch),
                "prop": "extracts",
                "exintro": "1",
                "explaintext": "1",
                "exchars": str(EXTRACT_CHARS),
                "format": "json",
                "formatversion": "2",
            },
            throttle_seconds=throttle_seconds,
            last_request_at=last_request_at,
        )
        for page in payload.get("query", {}).get("pages", []):
            extracts_by_pageid[int(page["pageid"])] = normalize_space(page.get("extract", ""))
        if batch_index == 1 or batch_index == len(pageid_batches) or batch_index % 10 == 0:
            print(
                f"rosetta_inventory: extract batch {batch_index}/{len(pageid_batches)} loaded",
                flush=True,
            )

    tasks: list[RawTask] = []
    for pageid, title in members:
        tasks.append(
            RawTask(
                pageid=pageid,
                title=title,
                url=title_to_url(title),
                extract=extracts_by_pageid.get(pageid, ""),
            )
        )
    tasks.sort(key=lambda task: task.title.casefold())
    return category_size, tasks, current_iso_timestamp()


def is_draft_title(title: str) -> bool:
    lowered = title.casefold()
    return lowered.startswith("draft:") or lowered.startswith("draft ")


def load_cached_tasks() -> tuple[int, list[RawTask], str] | None:
    if not CACHE_FILE.exists():
        return None
    try:
        payload = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid rosetta cache {CACHE_FILE}: {exc}") from exc
    if payload.get("schema_version") != CACHE_SCHEMA_VERSION:
        return None
    tasks = [
        RawTask(
            pageid=int(item["pageid"]),
            title=item["title"],
            url=item["url"],
            extract=item.get("extract", ""),
        )
        for item in payload.get("tasks", [])
    ]
    tasks.sort(key=lambda task: task.title.casefold())
    return int(payload["category_size"]), tasks, payload["fetched_at"]


def save_cached_tasks(category_size: int, tasks: list[RawTask], fetched_at: str) -> None:
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": CACHE_SCHEMA_VERSION,
        "category": ROSETTA_CATEGORY,
        "category_size": category_size,
        "fetched_at": fetched_at,
        "tasks": [
            {
                "pageid": task.pageid,
                "title": task.title,
                "url": task.url,
                "extract": task.extract,
            }
            for task in tasks
        ],
    }
    CACHE_FILE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_or_fetch_tasks(*, refresh: bool, throttle_seconds: float) -> tuple[int, list[RawTask], str]:
    if not refresh:
        cached = load_cached_tasks()
        if cached is not None:
            return cached
    category_size, tasks, fetched_at = fetch_raw_tasks(throttle_seconds=throttle_seconds)
    save_cached_tasks(category_size, tasks, fetched_at)
    return category_size, tasks, fetched_at


def inventory_records_for_tasks(tasks: Iterable[RawTask], *, ported_urls: set[str]) -> list[InventoryRecord]:
    records: list[InventoryRecord] = []
    for task in tasks:
        bucket, subbucket, matched_rule, features = classify_task(task.title, task.extract)
        records.append(
            InventoryRecord(
                title=task.title,
                url=task.url,
                extract=task.extract,
                bucket=bucket,
                subbucket=subbucket,
                matched_rule=matched_rule,
                difficulty=infer_difficulty(task.title, task.extract, bucket),
                rosetta_category=title_to_rosetta_category(task.title),
                features=features,
                porting_status="ported" if task.url in ported_urls else "not-started",
            )
        )
    return records


def known_sample_paths() -> set[str]:
    return set(PORTED_SAMPLE_TITLE_ALIASES) | set(LOCAL_ONLY_SAMPLE_PATHS)


def resolve_ported_sample_urls(records: Iterable[InventoryRecord]) -> tuple[set[str], list[str]]:
    records_by_title = {record.title: record for record in records}
    known_paths = known_sample_paths()
    warnings: list[str] = []
    ported_urls: set[str] = set()

    sample_paths = sorted((REPO_ROOT / "samples" / "rosetta").rglob("*.safe"))
    for sample_path in sample_paths:
        rel = sample_path.relative_to(REPO_ROOT).as_posix()
        if rel not in known_paths:
            raise RuntimeError(f"rosetta sample mapping missing for {rel}")
        aliased_title = PORTED_SAMPLE_TITLE_ALIASES.get(rel)
        if aliased_title is None:
            warnings.append(f"local-only sample not imported into Project 5: {rel}")
            continue
        record = records_by_title.get(aliased_title)
        if record is None:
            raise RuntimeError(f"ported sample alias {rel} -> {aliased_title!r} did not resolve to a fetched Rosetta task")
        ported_urls.add(record.url)
    return ported_urls, warnings


def validate_sample_consistency(records: Iterable[InventoryRecord]) -> None:
    records_by_url = {record.url: record for record in records}
    missing: list[str] = []
    for sample_path, title in sorted(PORTED_SAMPLE_TITLE_ALIASES.items()):
        url = title_to_url(title)
        record = records_by_url.get(url)
        if record is None:
            missing.append(f"{sample_path} -> {title} (missing task record)")
            continue
        # This is a deliberate assertion for the current imported Rosetta sample slice tracked by #347.
        # Future non-Bucket-1 Rosetta imports should update this contract together with the inventory design.
        if record.bucket != "1" or record.subbucket != "(none)" or record.porting_status != "ported":
            missing.append(
                f"{sample_path} -> {title} (bucket={record.bucket}, sub={record.subbucket}, porting={record.porting_status})"
            )
    if missing:
        detail = "\n".join(f" - {entry}" for entry in missing)
        raise RuntimeError(
            "ported sample consistency check failed:\n"
            f"{detail}\n"
            "If a future aliased Rosetta sample is intentionally outside Bucket 1/(none), "
            "update validate_sample_consistency() to reflect that expanded contract."
        )


def build_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner", default=DEFAULT_OWNER)
    parser.add_argument("--project-number", type=int, default=DEFAULT_PROJECT_NUMBER)
    parser.add_argument("--parent-issue", type=int, default=DEFAULT_PARENT_ISSUE_NUMBER)
    parser.add_argument("--refresh", action="store_true", help="refresh the Rosetta cache from the live wiki")
    parser.add_argument("--dry-run", action="store_true", help="print the sync plan without mutating Project 5")
    parser.add_argument("--limit", type=int, default=0, help="limit the number of tasks after fetch and sort")
    parser.add_argument(
        "--throttle-seconds",
        type=float,
        default=HTTP_THROTTLE_SECONDS,
        help="minimum delay between Rosetta Code API requests",
    )
    parser.add_argument(
        "--review-sample",
        action="store_true",
        help="print the deterministic 50-task review sample markdown and exit",
    )
    return parser.parse_args(argv)


def run_capture(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def gh_json(argv: list[str]) -> dict[str, Any]:
    completed = run_capture(argv)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit code {completed.returncode}"
        raise RuntimeError(f"{' '.join(argv)} failed: {detail}")
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{' '.join(argv)} returned invalid JSON: {exc}") from exc


def gh_graphql(query: str, variables: dict[str, str | int | None] | None = None) -> dict[str, Any]:
    argv = ["gh", "api", "graphql", "-f", f"query={query}"]
    for name, value in (variables or {}).items():
        if value is None:
            continue
        flag = "-F" if isinstance(value, int) else "-f"
        argv.extend([flag, f"{name}={value}"])
    payload = gh_json(argv)
    if payload.get("errors"):
        raise RuntimeError(f"graphql request failed: {json.dumps(payload['errors'], indent=2)}")
    return payload


def text_value_raw(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        raw = value.get("raw")
        if isinstance(raw, str):
            return raw
    raise RuntimeError(f"unexpected text payload shape: {value!r}")


def project_item_field_value(item: dict[str, Any], field_name: str) -> str | None:
    target = re.sub(r"[^a-z0-9]+", "", field_name.casefold())
    for key, value in item.items():
        if re.sub(r"[^a-z0-9]+", "", key.casefold()) != target:
            continue
        if isinstance(value, str) and value:
            return value
    return None


def fetch_project_fields(project_number: int, *, owner: str) -> tuple[str, dict[str, ProjectField]]:
    payload = gh_json(["gh", "project", "view", str(project_number), "--owner", owner, "--format", "json"])
    project_id = payload["id"]
    fields_payload = gh_json(
        [
            "gh",
            "project",
            "field-list",
            str(project_number),
            "--owner",
            owner,
            "--limit",
            str(PROJECT_FIELD_FETCH_LIMIT),
            "--format",
            "json",
        ]
    )
    listed_fields = fields_payload.get("fields", [])
    total_count = fields_payload.get("totalCount")
    if isinstance(total_count, int) and total_count > len(listed_fields):
        raise RuntimeError(
            f"project {project_number} field list truncated at {len(listed_fields)} items; "
            f"increase PROJECT_FIELD_FETCH_LIMIT above {total_count}"
        )
    fields: dict[str, ProjectField] = {}
    for field in listed_fields:
        option_ids = {text_value_raw(option["name"]): option["id"] for option in field.get("options", [])}
        fields[field["name"]] = ProjectField(
            name=field["name"],
            field_id=field["id"],
            kind="single_select" if field["type"] == "ProjectV2SingleSelectField" else "text",
            option_ids=option_ids,
        )
    required = {
        "Bucket",
        "Sub-bucket",
        "Porting Status",
        "Difficulty",
        "Rosetta Category",
        "Rosetta URL",
        "Features Used",
    }
    missing = sorted(required - set(fields))
    if missing:
        raise RuntimeError(f"project {project_number} is missing required Rosetta fields: {', '.join(missing)}")
    return project_id, fields


def fetch_project_items(project_number: int, *, owner: str) -> list[ProjectItem]:
    payload = gh_json(
        [
            "gh",
            "project",
            "item-list",
            str(project_number),
            "--owner",
            owner,
            "--limit",
            str(PROJECT_ITEM_FETCH_LIMIT),
            "--format",
            "json",
        ]
    )
    listed_items = payload.get("items", [])
    total_count = payload.get("totalCount")
    if isinstance(total_count, int) and total_count > len(listed_items):
        raise RuntimeError(
            f"project {project_number} item list truncated at {len(listed_items)} items; "
            f"increase PROJECT_ITEM_FETCH_LIMIT above {total_count}"
        )
    items: list[ProjectItem] = []
    required_fields = (
        "Bucket",
        "Sub-bucket",
        "Porting Status",
        "Difficulty",
        "Rosetta Category",
        "Rosetta URL",
        "Features Used",
    )
    for item in listed_items:
        content = item["content"]
        content_type = content["type"]
        if content_type not in {"DraftIssue", "Issue"}:
            continue
        field_values: dict[str, str] = {}
        for field_name in required_fields:
            if value := project_item_field_value(item, field_name):
                field_values[field_name] = value
        items.append(
            ProjectItem(
                item_id=item["id"],
                content_type=content_type,
                draft_issue_id=content.get("id") if content_type == "DraftIssue" else None,
                issue_number=content.get("number"),
                title=content["title"],
                body=content.get("body", ""),
                field_values=field_values,
            )
        )
    return items


def plan_sync(
    records: Iterable[InventoryRecord],
    existing_items: Iterable[ProjectItem],
    *,
    parent_issue: int,
) -> SyncPlan:
    desired_by_url = {record.url: record for record in records}
    rosetta_items: dict[str, ProjectItem] = {}
    missing: list[ProjectItem] = []
    creates: list[InventoryRecord] = []
    draft_updates: list[DraftUpdate] = []
    field_updates: list[FieldUpdate] = []
    unchanged = 0

    for item in existing_items:
        if item.content_type == "Issue" and item.issue_number == parent_issue:
            continue
        url = item.rosetta_url
        if url is None:
            continue
        if url in rosetta_items:
            existing_item = rosetta_items[url]
            raise RuntimeError(
                f"duplicate Project 5 item for Rosetta URL {url} "
                f"(existing item_id={existing_item.item_id!r}, new item_id={item.item_id!r}); "
                "manually delete one duplicate item from the project and re-run; "
                "additional duplicates for this URL may still exist"
            )
        rosetta_items[url] = item

    for url, record in desired_by_url.items():
        item = rosetta_items.pop(url, None)
        if item is None:
            creates.append(record)
            continue
        if item.content_type != "DraftIssue" or item.draft_issue_id is None:
            raise RuntimeError(
                f"existing Project 5 item for {url} is not a draft issue and cannot be updated safely "
                f"(item_id={item.item_id!r}, content_type={item.content_type!r}, title={item.title!r}); "
                "remove or relocate the non-draft item from Project 5 and re-run"
            )

        desired_body = build_item_body(record)
        desired_fields = desired_field_values(record)
        mutated = False

        if item.title != record.title or item.body != desired_body:
            draft_updates.append(
                DraftUpdate(
                    item_id=item.item_id,
                    draft_issue_id=item.draft_issue_id,
                    title=record.title,
                    body=desired_body,
                )
            )
            mutated = True

        for field_name, desired_value in desired_fields.items():
            current_value = item.field_values.get(field_name)
            if current_value != desired_value:
                field_updates.append(FieldUpdate(item_id=item.item_id, field_name=field_name, value=desired_value))
                mutated = True

        if not mutated:
            unchanged += 1

    for item in sorted(rosetta_items.values(), key=lambda entry: entry.title.casefold()):
        missing.append(item)

    return SyncPlan(
        creates=tuple(sorted(creates, key=lambda record: record.title.casefold())),
        draft_updates=tuple(draft_updates),
        field_updates=tuple(field_updates),
        unchanged=unchanged,
        missing=tuple(missing),
    )


def batched(values: list[Any], size: int) -> Iterable[list[Any]]:
    for start in range(0, len(values), size):
        yield values[start : start + size]


def graphql_string(value: str) -> str:
    return json.dumps(value)


def create_project_items(
    project_id: str,
    records: list[InventoryRecord],
) -> dict[str, ProjectItem]:
    created: dict[str, ProjectItem] = {}

    batches = list(batched(records, GRAPHQL_BATCH_SIZE))
    for batch_index, batch in enumerate(batches, start=1):
        parts: list[str] = []
        aliases: list[str] = []
        for index, record in enumerate(batch):
            alias = f"create_{index}"
            aliases.append(alias)
            parts.append(
                f"""{alias}: addProjectV2DraftIssue(
  input: {{
    projectId: {graphql_string(project_id)}
    title: {graphql_string(record.title)}
    body: {graphql_string(build_item_body(record))}
  }}
) {{
  projectItem {{
    id
    content {{
      ... on DraftIssue {{
        id
        title
        body
      }}
    }}
  }}
}}"""
            )
        payload = gh_graphql("mutation {\n" + "\n".join(parts) + "\n}")
        for alias, record in zip(aliases, batch):
            project_item = payload["data"][alias]["projectItem"]
            content = project_item["content"]
            created[record.url] = ProjectItem(
                item_id=project_item["id"],
                content_type="DraftIssue",
                draft_issue_id=content["id"],
                issue_number=None,
                title=content["title"],
                body=content["body"],
                field_values={},
            )
        if batch_index == 1 or batch_index == len(batches) or batch_index % 10 == 0:
            print(
                f"rosetta_inventory: created draft batch {batch_index}/{len(batches)}",
                flush=True,
            )
    return created


def apply_draft_updates(draft_updates: list[DraftUpdate]) -> None:
    batches = list(batched(draft_updates, GRAPHQL_BATCH_SIZE))
    for batch_index, batch in enumerate(batches, start=1):
        parts: list[str] = []
        for index, update in enumerate(batch):
            alias = f"draft_{index}"
            parts.append(
                f"""{alias}: updateProjectV2DraftIssue(
  input: {{
    draftIssueId: {graphql_string(update.draft_issue_id)}
    title: {graphql_string(update.title)}
    body: {graphql_string(update.body)}
  }}
) {{
  draftIssue {{
    id
  }}
}}"""
            )
        gh_graphql("mutation {\n" + "\n".join(parts) + "\n}")
        if batch_index == 1 or batch_index == len(batches) or batch_index % 10 == 0:
            print(
                f"rosetta_inventory: updated draft batch {batch_index}/{len(batches)}",
                flush=True,
            )


def apply_field_updates(
    project_id: str,
    field_map: dict[str, ProjectField],
    field_updates: list[FieldUpdate],
) -> None:
    batches = list(batched(field_updates, GRAPHQL_BATCH_SIZE))
    for batch_index, batch in enumerate(batches, start=1):
        parts: list[str] = []
        for index, update in enumerate(batch):
            alias = f"field_{index}"
            field = field_map[update.field_name]
            if update.value is None:
                parts.append(
                    f"""{alias}: clearProjectV2ItemFieldValue(
  input: {{
    projectId: {graphql_string(project_id)}
    itemId: {graphql_string(update.item_id)}
    fieldId: {graphql_string(field.field_id)}
  }}
) {{
  projectV2Item {{
    id
  }}
}}"""
                )
                continue
            if field.kind == "single_select":
                option_id = field.option_ids.get(update.value)
                if option_id is None:
                    raise RuntimeError(f"field {field.name!r} missing option {update.value!r}")
                value_fragment = f"{{ singleSelectOptionId: {graphql_string(option_id)} }}"
            else:
                value_fragment = f"{{ text: {graphql_string(update.value)} }}"
            parts.append(
                f"""{alias}: updateProjectV2ItemFieldValue(
  input: {{
    projectId: {graphql_string(project_id)}
    itemId: {graphql_string(update.item_id)}
    fieldId: {graphql_string(field.field_id)}
    value: {value_fragment}
  }}
) {{
  projectV2Item {{
    id
  }}
}}"""
            )
        gh_graphql("mutation {\n" + "\n".join(parts) + "\n}")
        if batch_index == 1 or batch_index == len(batches) or batch_index % 20 == 0:
            print(
                f"rosetta_inventory: applied field batch {batch_index}/{len(batches)}",
                flush=True,
            )


def sync_project(
    project_id: str,
    field_map: dict[str, ProjectField],
    plan: SyncPlan,
    records_by_url: dict[str, InventoryRecord],
    *,
    dry_run: bool,
) -> tuple[int, int]:
    if dry_run:
        created_field_updates = sum(len(desired_field_values(record)) for record in plan.creates)
        return len(plan.creates), created_field_updates + len(plan.draft_updates) + len(plan.field_updates)

    created_count = 0
    mutated_count = 0

    if plan.creates:
        created_items = create_project_items(project_id, list(plan.creates))
        created_count = len(created_items)
        new_field_updates: list[FieldUpdate] = []
        for url, item in created_items.items():
            record = records_by_url[url]
            for field_name, value in desired_field_values(record).items():
                new_field_updates.append(FieldUpdate(item_id=item.item_id, field_name=field_name, value=value))
        apply_field_updates(project_id, field_map, new_field_updates)
        mutated_count += len(new_field_updates)

    if plan.draft_updates:
        apply_draft_updates(list(plan.draft_updates))
        mutated_count += len(plan.draft_updates)
    if plan.field_updates:
        apply_field_updates(project_id, field_map, list(plan.field_updates))
        mutated_count += len(plan.field_updates)

    return created_count, mutated_count


def load_issue_comments(repo: str, issue_number: int) -> list[IssueComment]:
    payload = gh_json(["gh", "issue", "view", str(issue_number), "--repo", repo, "--json", "comments"])
    comments: list[IssueComment] = []
    for comment in payload.get("comments", []):
        comments.append(IssueComment(comment_id=comment["id"], body=comment["body"]))
    return comments


def comment_marker(body: str) -> str | None:
    match = COMMENT_MARKER_RE.search(body)
    if match is None:
        return None
    return match.group(1)


def update_issue_comment(comment_id: str, body: str) -> None:
    gh_graphql(
        """
        mutation($id: ID!, $body: String!) {
          updateIssueComment(input: {id: $id, body: $body}) {
            issueComment {
              id
            }
          }
        }
        """,
        {"id": comment_id, "body": body},
    )


def post_issue_comment(repo: str, issue_number: int, body: str) -> None:
    completed = run_capture(["gh", "issue", "comment", str(issue_number), "--repo", repo, "--body", body])
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit code {completed.returncode}"
        raise RuntimeError(f"failed to comment on issue #{issue_number}: {detail}")


def ensure_issue_comment(repo: str, issue_number: int, body: str, *, dry_run: bool) -> None:
    existing = load_issue_comments(repo, issue_number)
    marker = comment_marker(body)
    if marker is None:
        raise AssertionError("ensure_issue_comment expects a marker-bearing body")
    for comment in existing:
        if comment_marker(comment.body) == marker and comment.body == body:
            return
    for comment in existing:
        if comment_marker(comment.body) != marker:
            continue
        if dry_run:
            print(f"would update issue comment {comment.comment_id} on issue #{issue_number}:\n{body}\n")
            return
        update_issue_comment(comment.comment_id, body)
        return
    if dry_run:
        print(f"would comment on issue #{issue_number}:\n{body}\n")
        return
    post_issue_comment(repo, issue_number, body)


def build_delta_comment(category_size: int, task_count: int, fetched_at: str) -> str:
    delta = category_size - task_count
    return textwrap.dedent(
        f"""\
        <!-- rosetta-inventory:category-delta -->
        `scripts/rosetta_inventory.py` fetched `{task_count}` live Programming Tasks at `{fetched_at}`.

        The Rosetta category reports `categoryinfo.size = {category_size}`, for a delta of `{delta}` because `categoryinfo.size` counts all category members, while this script fetches only `cmtype=page` results and then applies title-based draft filtering.
        """
    ).strip()


def build_missing_items_comment(items: Iterable[ProjectItem], fetched_at: str) -> str:
    missing = list(items)
    lines = [
        "<!-- rosetta-inventory:missing-items -->",
        f"`scripts/rosetta_inventory.py` found {len(missing)} Project 5 item(s) whose `Rosetta URL` no longer appears in the live `{ROSETTA_CATEGORY}` listing as of `{fetched_at}`.",
        "",
    ]
    for item in missing[:50]:
        url = item.rosetta_url or "(missing Rosetta URL field/body)"
        lines.append(f"- {item.title} — {url}")
    if len(missing) > 50:
        lines.append(f"- ... and {len(missing) - 50} more")
    return "\n".join(lines)


def bucket_summary(records: Iterable[InventoryRecord]) -> dict[tuple[str, str], int]:
    counts: dict[tuple[str, str], int] = {}
    for record in records:
        key = (record.bucket, record.subbucket)
        counts[key] = counts.get(key, 0) + 1
    return counts


def print_bucket_summary(records: list[InventoryRecord]) -> None:
    print("bucket summary:")
    for (bucket, subbucket), count in sorted(bucket_summary(records).items()):
        print(f" - {bucket}/{subbucket}: {count}")


def evenly_spaced_records(records: list[InventoryRecord], count: int) -> list[InventoryRecord]:
    if count <= 0:
        return []
    if count >= len(records):
        return list(records)

    selected: list[InventoryRecord] = []
    used_indices: set[int] = set()
    for index in range(count):
        if count == 1:
            target = len(records) // 2
        else:
            target = round(index * (len(records) - 1) / (count - 1))
        if target not in used_indices:
            used_indices.add(target)
            selected.append(records[target])
            continue

        found_index: int | None = None
        for distance in range(1, len(records)):
            lower = target - distance
            if lower >= 0 and lower not in used_indices:
                found_index = lower
                break
            upper = target + distance
            if upper < len(records) and upper not in used_indices:
                found_index = upper
                break
        if found_index is None:
            raise RuntimeError("evenly_spaced_records could not find a unique record for the requested quota")
        used_indices.add(found_index)
        selected.append(records[found_index])
    return selected


def build_review_sample(records: Iterable[InventoryRecord]) -> list[InventoryRecord]:
    records_by_bucket: dict[tuple[str, str], list[InventoryRecord]] = {}
    records_by_title: dict[str, InventoryRecord] = {}
    for record in records:
        records_by_bucket.setdefault((record.bucket, record.subbucket), []).append(record)
        records_by_title[record.title] = record

    for bucket_key in records_by_bucket:
        records_by_bucket[bucket_key].sort(key=lambda record: record.title.casefold())

    anchors_by_bucket: dict[tuple[str, str], list[InventoryRecord]] = {}
    for title in REVIEW_SAMPLE_ANCHOR_TITLES:
        record = records_by_title.get(title)
        if record is None:
            raise RuntimeError(f"review sample anchor {title!r} is missing from the inventory")
        anchors_by_bucket.setdefault((record.bucket, record.subbucket), []).append(record)

    selected: list[InventoryRecord] = []
    seen_titles: set[str] = set()
    for bucket_key, quota in REVIEW_SAMPLE_QUOTAS.items():
        bucket_records = records_by_bucket.get(bucket_key, [])
        if len(bucket_records) < quota:
            raise RuntimeError(
                f"review sample bucket {bucket_key[0]}/{bucket_key[1]} has {len(bucket_records)} record(s), quota is {quota}"
            )
        anchor_records = anchors_by_bucket.get(bucket_key, [])
        if len(anchor_records) > quota:
            raise RuntimeError(
                f"review sample bucket {bucket_key[0]}/{bucket_key[1]} has {len(anchor_records)} anchors, quota is {quota}"
            )
        remaining = [record for record in bucket_records if record.title not in {item.title for item in anchor_records}]
        chosen = list(anchor_records)
        chosen.extend(evenly_spaced_records(remaining, quota - len(anchor_records)))
        chosen.sort(key=lambda record: record.title.casefold())
        for record in chosen:
            if record.title in seen_titles:
                raise RuntimeError(f"duplicate review sample selection for {record.title!r}")
            seen_titles.add(record.title)
        selected.extend(chosen)

    if len(selected) != sum(REVIEW_SAMPLE_QUOTAS.values()):
        raise RuntimeError(f"review sample expected {sum(REVIEW_SAMPLE_QUOTAS.values())} records, got {len(selected)}")
    missing_anchors = REVIEW_SAMPLE_ANCHOR_TITLE_SET - seen_titles
    if missing_anchors:
        raise RuntimeError(f"review sample is missing anchor(s): {sorted(missing_anchors)!r}")
    return selected


def review_sample_omissions(records: Iterable[InventoryRecord]) -> dict[tuple[str, str], int]:
    counts = bucket_summary(records)
    return {
        bucket_key: count
        for bucket_key, count in sorted(counts.items())
        if count and bucket_key not in REVIEW_SAMPLE_QUOTAS
    }


def review_result_placeholder(record: InventoryRecord) -> str:
    return "confirmed" if record.title in REVIEW_SAMPLE_ANCHOR_TITLE_SET else "pending-review"


def review_rationale(record: InventoryRecord) -> str:
    if record.matched_rule == "default":
        return "no blocker rule matched; portable-per-spec default"
    label = record.matched_rule.removeprefix("keyword:")
    if record.bucket == "2":
        return f"matched `{label}`; current blocker is PR12.x infrastructure"
    if record.bucket == "3":
        return f"matched `{label}`; current blocker is missing language/library design"
    if record.bucket == "4":
        return f"matched `{label}`; current blocker is out-of-scope surface"
    return f"matched `{label}`"


def build_review_sample_markdown(records: Iterable[InventoryRecord]) -> str:
    sections: list[str] = []
    all_records = list(records)
    sample = build_review_sample(all_records)
    grouped: dict[tuple[str, str], list[InventoryRecord]] = {}
    for record in sample:
        grouped.setdefault((record.bucket, record.subbucket), []).append(record)

    sections.append("Deterministic 50-task review sample:")
    for bucket_key in sorted(REVIEW_SAMPLE_QUOTAS):
        bucket_records = grouped.get(bucket_key, [])
        sections.append("")
        sections.append(f"**{bucket_key[0]}/{bucket_key[1]}**")
        for record in bucket_records:
            sections.append(
                f"- `{record.title}` — `{record.bucket}/{record.subbucket}` — {review_rationale(record)} — result: `{review_result_placeholder(record)}`"
            )
    omitted = review_sample_omissions(all_records)
    if omitted:
        sections.append("")
        sections.append("Review sample omissions:")
        for (bucket, subbucket), count in omitted.items():
            sections.append(
                f"- `{bucket}/{subbucket}` omitted from the deterministic 50-task sample by design ({count} inventory record(s) present)."
            )
    return "\n".join(sections)


def main(argv: list[str] | None = None) -> int:
    args = build_args(argv or sys.argv[1:])
    repo = f"{args.owner}/safe"

    try:
        category_size, raw_tasks, fetched_at = load_or_fetch_tasks(
            refresh=args.refresh,
            throttle_seconds=args.throttle_seconds,
        )
    except RuntimeError as exc:
        print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
        return 1

    provisional_records = inventory_records_for_tasks(raw_tasks, ported_urls=set())
    try:
        ported_urls, sample_warnings = resolve_ported_sample_urls(provisional_records)
    except RuntimeError as exc:
        print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
        return 1

    full_records = inventory_records_for_tasks(raw_tasks, ported_urls=ported_urls)
    records = full_records[: args.limit] if args.limit else full_records
    try:
        validate_sample_consistency(full_records)
    except RuntimeError as exc:
        print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
        return 1

    if args.review_sample:
        try:
            print(build_review_sample_markdown(full_records))
        except RuntimeError as exc:
            print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
            return 1
        return 0

    try:
        project_id, field_map = fetch_project_fields(args.project_number, owner=args.owner)
        existing_items = fetch_project_items(args.project_number, owner=args.owner)
    except RuntimeError as exc:
        print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
        return 1

    plan = plan_sync(records, existing_items, parent_issue=args.parent_issue)
    if args.limit:
        plan = SyncPlan(
            creates=plan.creates,
            draft_updates=plan.draft_updates,
            field_updates=plan.field_updates,
            unchanged=plan.unchanged,
            missing=(),
        )
    records_by_url = {record.url: record for record in records}

    print(
        f"rosetta_inventory: fetched {len(raw_tasks)} tasks from {ROSETTA_CATEGORY} "
        f"(category size {category_size}, fetched_at {fetched_at})"
    )
    if args.limit:
        print(f"rosetta_inventory: limited sync set to first {len(records)} task(s)")
    print_bucket_summary(records)
    print(f"rosetta_inventory: sample aliases marked ported: {len(ported_urls)}")
    for warning in sample_warnings:
        print(f"rosetta_inventory: note: {warning}")
    print(
        "rosetta_inventory: plan "
        f"creates={len(plan.creates)} draft updates={len(plan.draft_updates)} "
        f"field updates={len(plan.field_updates)} unchanged={plan.unchanged} missing={len(plan.missing)}"
    )

    try:
        created_count, mutated_count = sync_project(
            project_id,
            field_map,
            plan,
            records_by_url,
            dry_run=args.dry_run,
        )
    except RuntimeError as exc:
        print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
        return 1

    delta = category_size - len(raw_tasks)
    if delta != 0:
        comment = build_delta_comment(category_size, len(raw_tasks), fetched_at)
        try:
            ensure_issue_comment(repo, args.parent_issue, comment, dry_run=args.dry_run)
        except RuntimeError as exc:
            print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
            return 1
    if plan.missing:
        comment = build_missing_items_comment(plan.missing, fetched_at)
        try:
            ensure_issue_comment(repo, args.parent_issue, comment, dry_run=args.dry_run)
        except RuntimeError as exc:
            print(f"rosetta_inventory: ERROR: {exc}", file=sys.stderr)
            return 1

    mode = "dry-run" if args.dry_run else "sync"
    print(
        f"rosetta_inventory: {mode} complete "
        f"(created={created_count}, updated={mutated_count}, unchanged={plan.unchanged}, missing={len(plan.missing)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
