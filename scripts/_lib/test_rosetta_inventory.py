"""Focused checks for ``scripts/rosetta_inventory.py``."""

from __future__ import annotations

import contextlib
import io
import subprocess
import tempfile
from pathlib import Path

import rosetta_inventory as inventory

from _lib.test_harness import RunCounts, record_result


def make_record(
    title: str,
    *,
    bucket: str = "1",
    subbucket: str = "(none)",
    porting_status: str = "not-started",
) -> inventory.InventoryRecord:
    return inventory.InventoryRecord(
        title=title,
        url=inventory.title_to_url(title),
        extract="",
        bucket=bucket,
        subbucket=subbucket,
        matched_rule="default",
        difficulty="trivial",
        rosetta_category=inventory.title_to_rosetta_category(title),
        features=("functions",),
        porting_status=porting_status,
    )


def run_classification_case() -> tuple[bool, str]:
    cases = [
        ("Factorial", "Compute n!", ("1", "(none)", "default")),
        ("Read entire file", "Read the whole text file and print it.", ("2", "2a", "keyword:file")),
        (
            "Fixed length records",
            "Write a program to read 80 column fixed length records and write out the reverse of each line.",
            ("2", "2a", "keyword:fixed length records"),
        ),
        ("JSON round-trip", "Serialize data to JSON and decode it again.", ("2", "2c", "keyword:json")),
        ("Regular expression parser", "Use a regex to match text.", ("3", "3a", "keyword:regular expression")),
        ("Averages/Mean time of day", "Map times of day to angles and compute the average time of day.", ("3", "3b", "keyword:time of day")),
        ("GUI menu demo", "Open a window with a menu.", ("4", "4a", "keyword:gui")),
        ("HTTP", "Access and print a URL's content to the console.", ("4", "4b", "keyword:http")),
        (
            "Hello world/Text",
            "Task Display the string Hello world! on a text console. Related tasks Hello world/Web server",
            ("1", "(none)", "default"),
        ),
        (
            "100 doors",
            "The first time through, visit every door and toggle it; the second time, only every 2nd door.",
            ("1", "(none)", "default"),
        ),
        (
            "Append a record to the end of a text file",
            "Many systems offer the ability to open a file for writing such that data is appended to the end of the file.",
            ("2", "2a", "keyword:file"),
        ),
        (
            "URL encoding",
            "Convert a provided string into URL encoding representation.",
            ("1", "(none)", "default"),
        ),
        (
            "Add a variable to a class instance at runtime",
            "This is useful when methods are based on a data file that is not available until runtime. This is referred to as monkeypatching.",
            ("4", "(none)", "keyword:class instance"),
        ),
        (
            "Church numerals",
            "The number N is encoded by a function that applies its first argument N times to its second argument.",
            ("3", "(none)", "keyword:church numerals"),
        ),
        (
            "Higher-order functions",
            "Pass a function as an argument to another function.",
            ("3", "(none)", "keyword:higher-order functions"),
        ),
        (
            "Sort using a custom comparator",
            "Use a sorting facility provided by the language/library, combined with your own callback comparison function.",
            ("3", "(none)", "keyword:callback comparison function"),
        ),
        (
            "Partial function application",
            "Take a function of many parameters and apply arguments to some parameters to create a new function.",
            ("3", "(none)", "keyword:partial function application"),
        ),
        (
            "Nested function",
            "The inner function can access variables from the outer function.",
            ("3", "(none)", "keyword:nested function"),
        ),
        (
            "Call a function in a shared library",
            "Show how to call a function in a shared library without linking to it at compile-time.",
            ("4", "4d", "keyword:shared library"),
        ),
        (
            "Call a foreign-language function",
            "Show how a foreign language function can be called from the language.",
            ("4", "4d", "keyword:foreign-language function"),
        ),
        (
            "Compiler/code generator",
            "The program should read input from a file and/or stdin, and write output to a file and/or stdout.",
            ("2", "2b", "keyword:compiler/code generator"),
        ),
        (
            "Hostname",
            "Task Find the name of the host on which the routine is running.",
            ("4", "4e", "keyword:hostname"),
        ),
        (
            "Hunt the Wumpus",
            "Each turn the player can either walk into an adjacent room or shoot into an adjacent room.",
            ("2", "2b", "keyword:hunt the wumpus"),
        ),
        (
            "Shell one-liner",
            "Show how to specify and execute a short program in the language from a command shell.",
            ("4", "4e", "keyword:shell one-liner"),
        ),
        (
            "Polymorphism",
            "Create two classes Point(x,y) and Circle(x,y,r) with a polymorphic function print.",
            ("4", "(none)", "keyword:polymorphism"),
        ),
        (
            "Parametric polymorphism",
            "Define a type declaration that is generic over another type, not one based upon inheritance.",
            ("1", "(none)", "default"),
        ),
        (
            "Dating agency",
            "The sailor decides which ladies to actually date.",
            ("1", "(none)", "default"),
        ),
        (
            "Active Directory/Connect",
            "Establish a connection to an Active Directory or Lightweight Directory Access Protocol server.",
            ("4", "4b", "keyword:active directory"),
        ),
        (
            "Write to Windows event log",
            "Write script status to the Windows Event Log.",
            ("4", "4e", "keyword:windows event log"),
        ),
        (
            "P-Adic square roots",
            "Convert rational a/b to its approximate p-adic square root.",
            ("3", "3e", "keyword:p-adic"),
        ),
        (
            "Roots of unity",
            "Explore working with complex numbers.",
            ("3", "3e", "keyword:roots of unity"),
        ),
        (
            "Long multiplication",
            "This is one possible approach to arbitrary-precision integer algebra.",
            ("3", "3e", "keyword:arbitrary-precision"),
        ),
        (
            "Rosetta Code/Count examples",
            "You'll need to use the Media Wiki API to count examples on each task page.",
            ("4", "4b", "keyword:media wiki api"),
        ),
        (
            "Object serialization",
            "Create a set of data types based upon inheritance and serialize them to a file.",
            ("4", "(none)", "keyword:based upon inheritance"),
        ),
        (
            "Particle fountain",
            "Implement a particle fountain with several hundred particles in motion.",
            ("4", "4c", "keyword:particle fountain"),
        ),
        (
            "Hough transform",
            "Implement the Hough transform used as part of feature extraction with digital images.",
            ("4", "4c", "keyword:digital images"),
        ),
        (
            "Spinning rod animation/Text",
            "Animate text frames in the console with a delay between each frame.",
            ("1", "(none)", "default"),
        ),
    ]
    for title, extract, expected in cases:
        bucket, subbucket, matched_rule, _features = inventory.classify_task(title, extract)
        actual = (bucket, subbucket, matched_rule)
        if actual != expected:
            return False, f"{title!r} classified as {actual!r}, expected {expected!r}"
    _bucket, _subbucket, _rule, features = inventory.classify_task(
        "Hello world/Text",
        "Task Display the string Hello world! on a text console. Related tasks Hello world/Web server",
    )
    if "concurrency" in features:
        return False, f"unexpected concurrency feature in {features!r}"
    return True, ""


def run_body_roundtrip_case() -> tuple[bool, str]:
    record = inventory.InventoryRecord(
        title="Sorting algorithms/Bubble sort",
        url=inventory.title_to_url("Sorting algorithms/Bubble sort"),
        extract="Sort a list using bubble sort.",
        bucket="1",
        subbucket="(none)",
        matched_rule="default",
        difficulty="trivial",
        rosetta_category="Sorting algorithms",
        features=("arrays", "loops"),
        porting_status="ported",
    )
    body = inventory.build_item_body(record)
    parsed_url = inventory.parse_rosetta_url_from_body(body)
    if parsed_url != record.url:
        return False, f"round-trip body URL mismatch: {parsed_url!r}"
    desired = inventory.desired_field_values(record)
    if desired["Bucket"] != "1" or desired["Porting Status"] != "ported":
        return False, f"unexpected desired field values {desired!r}"
    return True, ""


def run_sample_mapping_case() -> tuple[bool, str]:
    records = [
        inventory.InventoryRecord(
            title=title,
            url=inventory.title_to_url(title),
            extract="",
            bucket="1",
            subbucket="(none)",
            matched_rule="default",
            difficulty="trivial",
            rosetta_category=inventory.title_to_rosetta_category(title),
            features=("functions",),
            porting_status="not-started",
        )
        for title in sorted(set(inventory.PORTED_SAMPLE_TITLE_ALIASES.values()))
    ]
    try:
        ported_urls, warnings = inventory.resolve_ported_sample_urls(records)
    except RuntimeError as exc:
        return False, str(exc)
    expected_count = len(inventory.PORTED_SAMPLE_TITLE_ALIASES)
    if len(ported_urls) != expected_count:
        return False, f"expected {expected_count} ported sample URLs, got {len(ported_urls)}"
    if len(warnings) != len(inventory.LOCAL_ONLY_SAMPLE_PATHS):
        return False, f"expected {len(inventory.LOCAL_ONLY_SAMPLE_PATHS)} local-only warnings, got {len(warnings)}"
    return True, ""


def run_sample_mapping_error_case() -> tuple[bool, str]:
    original_resolve_ported_sample_urls = inventory.resolve_ported_sample_urls

    def fake_resolve_ported_sample_urls(_records: list[inventory.InventoryRecord]) -> tuple[set[str], list[str]]:
        raise RuntimeError("sample mapping exploded")

    inventory.resolve_ported_sample_urls = fake_resolve_ported_sample_urls
    try:
        ok, detail = run_sample_mapping_case()
    finally:
        inventory.resolve_ported_sample_urls = original_resolve_ported_sample_urls

    if ok:
        return False, "sample mapping case unexpectedly succeeded after a resolve_ported_sample_urls failure"
    if detail != "sample mapping exploded":
        return False, f"unexpected sample mapping error detail {detail!r}"
    return True, ""


def run_title_helpers_case() -> tuple[bool, str]:
    url = inventory.title_to_url("Hello world/Text")
    if url != "https://rosettacode.org/wiki/Hello_world/Text":
        return False, f"unexpected title URL {url!r}"
    category = inventory.title_to_rosetta_category("Sorting algorithms/Bubble sort")
    if category != "Sorting algorithms":
        return False, f"unexpected title-derived category {category!r}"
    trimmed = inventory.classification_extract(
        "Task Display the string Hello world! on a text console. Related tasks Hello world/Web server"
    )
    if "Web server" in trimmed or not trimmed.endswith("text console."):
        return False, f"unexpected trimmed extract {trimmed!r}"
    trimmed = inventory.classification_extract(
        "Read JSON from https://example.com/spec.json and display it."
    )
    if trimmed != "Read JSON from and display it.":
        return False, f"inline URL was not stripped from extract {trimmed!r}"
    return True, ""


def run_sample_consistency_case() -> tuple[bool, str]:
    baseline_records = [make_record(title, porting_status="ported") for title in sorted(set(inventory.PORTED_SAMPLE_TITLE_ALIASES.values()))]
    try:
        inventory.validate_sample_consistency(baseline_records)
    except RuntimeError as exc:
        return False, str(exc)

    # The current aliased Rosetta imports are intentionally the Bucket 1/(none) sample set tracked by #347.
    records = list(baseline_records)
    records[0] = make_record(records[0].title, bucket="2", subbucket="2a", porting_status="ported")
    try:
        inventory.validate_sample_consistency(records)
    except RuntimeError:
        pass
    else:
        return False, "ported sample consistency accepted a non-bucket-1 aliased sample"

    records = list(baseline_records)
    records[0] = make_record(records[0].title, porting_status="not-started")
    try:
        inventory.validate_sample_consistency(records)
    except RuntimeError:
        return True, ""
    return False, "ported sample consistency accepted a non-ported aliased sample"


def run_gh_graphql_case() -> tuple[bool, str]:
    original_run_capture = inventory.run_capture
    captured: dict[str, list[str]] = {}

    def fake_run_capture(argv: list[str]) -> subprocess.CompletedProcess[str]:
        captured["argv"] = list(argv)
        return subprocess.CompletedProcess(argv, 0, stdout="{}", stderr="")

    inventory.run_capture = fake_run_capture
    try:
        inventory.gh_graphql(
            "query($id: ID!, $count: Int!) { node(id: $id) { id } }",
            {"id": "PVTI_test", "count": 7, "ignored": None},
        )
    finally:
        inventory.run_capture = original_run_capture

    argv = captured.get("argv")
    if argv is None:
        return False, "gh_graphql did not invoke run_capture"
    if "-f" not in argv or "id=PVTI_test" not in argv:
        return False, f"gh_graphql did not pass string variables with -f: {argv!r}"
    if "-F" not in argv or "count=7" not in argv:
        return False, f"gh_graphql did not pass int variables with -F: {argv!r}"
    if any(part.startswith("ignored=") for part in argv):
        return False, f"gh_graphql should skip None-valued variables: {argv!r}"
    return True, ""


def run_plan_sync_parent_issue_case() -> tuple[bool, str]:
    desired_records = [make_record("Factorial")]
    parent_issue_item = inventory.ProjectItem(
        item_id="PVTI_parent",
        content_type="Issue",
        title="Rosetta inventory tracking",
        body="**Rosetta URL:** https://rosettacode.org/wiki/Tracking_only\n",
        field_values={},
        issue_number=999,
    )

    plan = inventory.plan_sync(desired_records, [parent_issue_item], parent_issue=999)
    if plan.missing:
        return False, f"parent issue override should be ignored, found missing items: {plan.missing!r}"

    plan = inventory.plan_sync(desired_records, [parent_issue_item], parent_issue=347)
    if len(plan.missing) != 1 or plan.missing[0].issue_number != 999:
        return False, f"non-parent issue should remain in missing set, got {plan.missing!r}"
    return True, ""


def run_fetch_project_fields_case() -> tuple[bool, str]:
    original_gh_json = inventory.gh_json
    captured: dict[str, list[str]] = {}

    def fake_gh_json(argv: list[str]) -> dict[str, object]:
        if argv[:4] == ["gh", "project", "view", "5"]:
            return {"id": "PVT_kwDOA"}
        if argv[:4] == ["gh", "project", "field-list", "5"]:
            captured["argv"] = list(argv)
            names = (
                "Bucket",
                "Sub-bucket",
                "Porting Status",
                "Difficulty",
                "Rosetta Category",
                "Rosetta URL",
                "Features Used",
            )
            return {
                "fields": [
                    {
                        "name": name,
                        "id": f"field-{index}",
                        "type": "ProjectV2SingleSelectField" if index < 4 else "ProjectV2Field",
                        "options": [{"name": {"raw": "1"}, "id": "option-1"}] if name == "Bucket" else [],
                    }
                    for index, name in enumerate(names, start=1)
                ]
            }
        raise AssertionError(f"unexpected gh_json argv: {argv!r}")

    inventory.gh_json = fake_gh_json
    try:
        project_id, fields = inventory.fetch_project_fields(5, owner="berkeleynerd")
    finally:
        inventory.gh_json = original_gh_json

    if project_id != "PVT_kwDOA":
        return False, f"unexpected project id {project_id!r}"
    if captured.get("argv", [])[:4] != ["gh", "project", "field-list", "5"]:
        return False, f"fetch_project_fields did not use gh project field-list: {captured.get('argv')!r}"
    if "--limit" not in captured.get("argv", []) or str(inventory.PROJECT_FIELD_FETCH_LIMIT) not in captured.get("argv", []):
        return False, f"fetch_project_fields did not request the configured field limit: {captured.get('argv')!r}"
    if sorted(fields) != [
        "Bucket",
        "Difficulty",
        "Features Used",
        "Porting Status",
        "Rosetta Category",
        "Rosetta URL",
        "Sub-bucket",
    ]:
        return False, f"unexpected field map keys {sorted(fields)!r}"
    return True, ""


def run_fetch_project_items_case() -> tuple[bool, str]:
    original_gh_json = inventory.gh_json
    captured: dict[str, list[str]] = {}

    def fake_gh_json(argv: list[str]) -> dict[str, object]:
        captured["argv"] = list(argv)
        return {
            "items": [
                {
                    "id": "PVTI_test",
                    "bucket": "1",
                    "subBucket": "(none)",
                    "portingStatus": "ported",
                    "rosettaUrl": "https://rosettacode.org/wiki/Factorial",
                    "featuresUsed": "functions, loops",
                    "content": {"id": "DI_test", "type": "DraftIssue", "title": "Factorial", "body": "body"},
                }
            ]
        }

    inventory.gh_json = fake_gh_json
    try:
        items = inventory.fetch_project_items(5, owner="berkeleynerd")
    finally:
        inventory.gh_json = original_gh_json

    if captured.get("argv", [])[:4] != ["gh", "project", "item-list", "5"]:
        return False, f"fetch_project_items did not use gh project item-list: {captured.get('argv')!r}"
    if "--limit" not in captured.get("argv", []) or str(inventory.PROJECT_ITEM_FETCH_LIMIT) not in captured.get("argv", []):
        return False, f"fetch_project_items did not request the configured item limit: {captured.get('argv')!r}"
    if len(items) != 1:
        return False, f"expected one parsed project item, got {items!r}"
    item = items[0]
    if item.field_values != {
        "Bucket": "1",
        "Sub-bucket": "(none)",
        "Porting Status": "ported",
        "Rosetta URL": "https://rosettacode.org/wiki/Factorial",
        "Features Used": "functions, loops",
    }:
        return False, f"unexpected parsed field values {item.field_values!r}"
    return True, ""


def run_fetch_live_task_count_case() -> tuple[bool, str]:
    original_request_json = inventory.request_json

    def fake_request_json(
        params: dict[str, str],
        *,
        throttle_seconds: float,
        last_request_at: list[float],
    ) -> dict[str, object]:
        return {"query": {"pages": [{}]}}

    inventory.request_json = fake_request_json
    try:
        try:
            inventory.fetch_live_task_count(throttle_seconds=0.0, last_request_at=[0.0])
        except RuntimeError as exc:
            if "unexpected categoryinfo response" not in str(exc):
                return False, f"unexpected error text from fetch_live_task_count: {exc}"
            return True, ""
        return False, "fetch_live_task_count accepted a malformed categoryinfo payload"
    finally:
        inventory.request_json = original_request_json


def run_request_json_decode_case() -> tuple[bool, str]:
    original_urlopen = inventory.urlopen

    class FakeResponse:
        def __enter__(self) -> "FakeResponse":
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            return None

        def read(self) -> bytes:
            return b"<html>not json</html>"

    def fake_urlopen(request, timeout: int = 60) -> FakeResponse:
        return FakeResponse()

    inventory.urlopen = fake_urlopen
    try:
        try:
            inventory.request_json({"action": "query"}, throttle_seconds=0.0, last_request_at=[0.0])
        except RuntimeError as exc:
            if "returned invalid JSON" not in str(exc):
                return False, f"unexpected request_json decode error text: {exc}"
            return True, ""
        return False, "request_json accepted an invalid JSON payload"
    finally:
        inventory.urlopen = original_urlopen


def run_load_cached_tasks_invalid_json_case() -> tuple[bool, str]:
    original_cache_root = inventory.CACHE_ROOT
    original_cache_file = inventory.CACHE_FILE
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_root = Path(tmpdir)
            cache_file = cache_root / "programming_tasks_v1.json"
            inventory.CACHE_ROOT = cache_root
            inventory.CACHE_FILE = cache_file
            cache_file.write_text("{not valid json", encoding="utf-8")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                cached = inventory.load_cached_tasks()
    finally:
        inventory.CACHE_ROOT = original_cache_root
        inventory.CACHE_FILE = original_cache_file

    if cached is not None:
        return False, f"load_cached_tasks should ignore invalid cache payloads, got {cached!r}"
    warning = stderr.getvalue()
    if "ignoring invalid rosetta cache" not in warning:
        return False, f"load_cached_tasks did not emit the invalid-cache warning: {warning!r}"
    return True, ""


def run_save_cached_tasks_atomic_case() -> tuple[bool, str]:
    original_cache_root = inventory.CACHE_ROOT
    original_cache_file = inventory.CACHE_FILE
    original_replace = inventory.Path.replace
    replace_calls: list[tuple[str, str]] = []

    def recording_replace(self: Path, target: Path) -> Path:
        replace_calls.append((self.name, Path(target).name))
        return original_replace(self, target)

    inventory.Path.replace = recording_replace
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_root = Path(tmpdir)
            cache_file = cache_root / "programming_tasks_v1.json"
            inventory.CACHE_ROOT = cache_root
            inventory.CACHE_FILE = cache_file
            inventory.save_cached_tasks(
                1,
                [
                    inventory.RawTask(
                        pageid=1,
                        title="Factorial",
                        url=inventory.title_to_url("Factorial"),
                        extract="Compute n!",
                    )
                ],
                "2026-04-22T00:00:00Z",
            )
            leftovers = sorted(path.name for path in cache_root.glob("programming_tasks_v1.json.tmp-*"))
            payload = inventory.json.loads(cache_file.read_text(encoding="utf-8"))
    finally:
        inventory.Path.replace = original_replace
        inventory.CACHE_ROOT = original_cache_root
        inventory.CACHE_FILE = original_cache_file

    if not replace_calls:
        return False, "save_cached_tasks did not replace the cache file from a temp path"
    temp_name, target_name = replace_calls[0]
    if not temp_name.startswith("programming_tasks_v1.json.tmp-") or target_name != "programming_tasks_v1.json":
        return False, f"save_cached_tasks used an unexpected replace path: {replace_calls!r}"
    if leftovers:
        return False, f"save_cached_tasks left temp files behind: {leftovers!r}"
    if payload.get("category_size") != 1 or payload.get("fetched_at") != "2026-04-22T00:00:00Z":
        return False, f"save_cached_tasks wrote unexpected payload metadata: {payload!r}"
    if payload.get("tasks", [{}])[0].get("title") != "Factorial":
        return False, f"save_cached_tasks wrote unexpected task payload: {payload!r}"
    return True, ""


def run_literal_keyword_case() -> tuple[bool, str]:
    keyword = inventory.literal_keyword("fixed length records", "fixed length records")
    if not keyword.regex.search("fixed   length\trecords"):
        return False, "literal_keyword did not treat whitespace in multi-word literals flexibly"
    return True, ""


def run_text_value_raw_case() -> tuple[bool, str]:
    if inventory.text_value_raw("plain") != "plain":
        return False, "text_value_raw did not accept plain strings"
    if inventory.text_value_raw({"raw": "rich"}) != "rich":
        return False, "text_value_raw did not extract rich-text payloads"
    try:
        inventory.text_value_raw({"html": "missing raw"})
    except RuntimeError:
        return True, ""
    return False, "text_value_raw accepted an invalid payload shape"


def run_delta_comment_case() -> tuple[bool, str]:
    comment = inventory.build_delta_comment(100, 97, "2026-04-22T00:00:00Z")
    if "cmtype=page" not in comment or "title-based draft filtering" not in comment:
        return False, f"delta comment is missing the fetch/filter explanation: {comment!r}"
    return True, ""


def run_issue_comment_marker_case() -> tuple[bool, str]:
    original_load_issue_comments = inventory.load_issue_comments
    original_post_issue_comment = inventory.post_issue_comment
    original_update_issue_comment = inventory.update_issue_comment
    posted = {"value": False}
    updated: list[tuple[str, str]] = []

    def fake_load_issue_comments(repo: str, issue_number: int) -> list[inventory.IssueComment]:
        return [
            inventory.IssueComment(
                comment_id="IC_existing",
                body=inventory.build_delta_comment(category_size=10, task_count=9, fetched_at="2026-04-21T00:00:00Z"),
            )
        ]

    def fake_post_issue_comment(repo: str, issue_number: int, body: str) -> None:
        posted["value"] = True

    def fake_update_issue_comment(comment_id: str, body: str) -> None:
        updated.append((comment_id, body))

    inventory.load_issue_comments = fake_load_issue_comments
    inventory.post_issue_comment = fake_post_issue_comment
    inventory.update_issue_comment = fake_update_issue_comment
    try:
        inventory.ensure_issue_comment(
            "berkeleynerd/safe",
            347,
            inventory.build_delta_comment(category_size=10, task_count=9, fetched_at="2026-04-22T00:00:00Z"),
            dry_run=False,
        )
    finally:
        inventory.load_issue_comments = original_load_issue_comments
        inventory.post_issue_comment = original_post_issue_comment
        inventory.update_issue_comment = original_update_issue_comment

    if posted["value"]:
        return False, "ensure_issue_comment posted a new comment instead of updating the marker-matched comment"
    if updated != [
        (
            "IC_existing",
            inventory.build_delta_comment(category_size=10, task_count=9, fetched_at="2026-04-22T00:00:00Z"),
        )
    ]:
        return False, f"ensure_issue_comment did not update the marker-matched comment in place: {updated!r}"
    return True, ""


def run_missing_items_comment_case() -> tuple[bool, str]:
    items = [
        inventory.ProjectItem(
            item_id=f"PVTI_{index:03d}",
            content_type="DraftIssue",
            title=f"Missing {index:03d}",
            body=f"**Rosetta URL:** https://rosettacode.org/wiki/Missing_{index:03d}\n",
            field_values={"Rosetta URL": f"https://rosettacode.org/wiki/Missing_{index:03d}"},
            draft_issue_id=f"DI_{index:03d}",
        )
        for index in range(51)
    ]
    comment = inventory.build_missing_items_comment(items, "2026-04-22T00:00:00Z")
    if "found 51 project item(s)" not in comment:
        return False, f"missing-items comment omitted the total count: {comment!r}"
    if "- Missing 049 — https://rosettacode.org/wiki/Missing_049" not in comment:
        return False, "missing-items comment did not include the 50th listed item"
    if "- Missing 050 — https://rosettacode.org/wiki/Missing_050" in comment:
        return False, "missing-items comment should cap the explicit list at 50 entries"
    if "- ... and 1 more" not in comment:
        return False, "missing-items comment did not emit the truncation summary"
    return True, ""


def run_plan_sync_duplicate_case() -> tuple[bool, str]:
    duplicate_url = inventory.title_to_url("Factorial")
    items = [
        inventory.ProjectItem(
            item_id="PVTI_first",
            content_type="DraftIssue",
            title="Factorial",
            body=f"**Rosetta URL:** {duplicate_url}\n",
            field_values={"Rosetta URL": duplicate_url},
            draft_issue_id="DI_first",
        ),
        inventory.ProjectItem(
            item_id="PVTI_second",
            content_type="DraftIssue",
            title="Factorial copy",
            body=f"**Rosetta URL:** {duplicate_url}\n",
            field_values={"Rosetta URL": duplicate_url},
            draft_issue_id="DI_second",
        ),
    ]
    try:
        inventory.plan_sync([make_record("Factorial")], items, parent_issue=347)
    except RuntimeError as exc:
        detail = str(exc)
        if "existing item_id='PVTI_first'" not in detail or "new item_id='PVTI_second'" not in detail:
            return False, f"duplicate-item error omitted the conflicting item ids: {detail!r}"
        if "additional duplicates for this URL may still exist" not in detail:
            return False, f"duplicate-item error omitted the additional-duplicates note: {detail!r}"
        return True, ""
    return False, "plan_sync accepted duplicate project items for the same Rosetta URL"


def run_build_args_case() -> tuple[bool, str]:
    args = inventory.build_args(["--limit", "3"])
    if args.limit != 3:
        return False, f"build_args did not preserve a positive --limit: {args.limit!r}"
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            inventory.build_args(["--limit", "-1"])
    except SystemExit:
        return True, ""
    return False, "build_args accepted a negative --limit"


def run_sync_project_count_case() -> tuple[bool, str]:
    record = make_record("Factorial")
    plan = inventory.SyncPlan(
        creates=(record,),
        draft_updates=(),
        field_updates=(),
        unchanged=0,
        missing=(),
    )
    expected_field_updates = len(inventory.desired_field_values(record))

    dry_created, dry_mutated = inventory.sync_project(
        "project-id",
        {},
        plan,
        {record.url: record},
        dry_run=True,
    )
    if (dry_created, dry_mutated) != (1, expected_field_updates):
        return False, f"dry-run sync counts were {(dry_created, dry_mutated)!r}, expected {(1, expected_field_updates)!r}"

    original_create_project_items = inventory.create_project_items
    original_apply_field_updates = inventory.apply_field_updates
    field_update_batches: list[list[inventory.FieldUpdate]] = []

    def fake_create_project_items(project_id: str, records: list[inventory.InventoryRecord]) -> dict[str, inventory.ProjectItem]:
        created_record = records[0]
        return {
            created_record.url: inventory.ProjectItem(
                item_id="PVTI_created",
                content_type="DraftIssue",
                title=created_record.title,
                body=inventory.build_item_body(created_record),
                field_values={},
                draft_issue_id="DI_created",
            )
        }

    def fake_apply_field_updates(
        project_id: str,
        field_map: dict[str, inventory.ProjectField],
        field_updates: list[inventory.FieldUpdate],
    ) -> None:
        field_update_batches.append(list(field_updates))

    inventory.create_project_items = fake_create_project_items
    inventory.apply_field_updates = fake_apply_field_updates
    try:
        created, mutated = inventory.sync_project(
            "project-id",
            {},
            plan,
            {record.url: record},
            dry_run=False,
        )
    finally:
        inventory.create_project_items = original_create_project_items
        inventory.apply_field_updates = original_apply_field_updates

    if created != 1 or mutated != expected_field_updates:
        return False, f"sync counts were {(created, mutated)!r}, expected {(1, expected_field_updates)!r}"
    if len(field_update_batches) != 1 or len(field_update_batches[0]) != expected_field_updates:
        return False, f"created item field updates were not applied as expected: {field_update_batches!r}"
    return True, ""


def run_review_placeholder_case() -> tuple[bool, str]:
    confirmed = inventory.review_result_placeholder(make_record("Hello world/Text"))
    if confirmed != "confirmed":
        return False, f"expected anchor title to be confirmed, got {confirmed!r}"
    pending = inventory.review_result_placeholder(make_record("Factorial"))
    if pending != "pending-review":
        return False, f"expected non-anchor title to be pending-review, got {pending!r}"
    return True, ""


def run_review_sample_case() -> tuple[bool, str]:
    anchor_buckets = {
        "Hello world/Text": ("1", "(none)"),
        "100 doors": ("1", "(none)"),
        "Church numerals": ("3", "(none)"),
        "Higher-order functions": ("3", "(none)"),
        "Monads/List monad": ("3", "(none)"),
        "Add a variable to a class instance at runtime": ("4", "(none)"),
        "Append a record to the end of a text file": ("2", "2a"),
        "URL encoding": ("1", "(none)"),
        "Regular expressions": ("3", "3a"),
        "Hello world/Graphical": ("4", "4a"),
        "Bitmap": ("4", "4c"),
    }
    anchors_by_bucket: dict[tuple[str, str], list[str]] = {}
    for title, bucket_key in anchor_buckets.items():
        anchors_by_bucket.setdefault(bucket_key, []).append(title)
    records: list[inventory.InventoryRecord] = []
    for (bucket, subbucket), quota in inventory.REVIEW_SAMPLE_QUOTAS.items():
        total = quota + 3
        bucket_anchors = sorted(anchors_by_bucket.get((bucket, subbucket), []))
        for index in range(total):
            title = f"Sample {bucket}-{subbucket}-{index:02d}"
            if index < len(bucket_anchors):
                title = bucket_anchors[index]
            records.append(
                inventory.InventoryRecord(
                    title=title,
                    url=inventory.title_to_url(title),
                    extract="",
                    bucket=bucket,
                    subbucket=subbucket,
                    matched_rule="default",
                    difficulty="moderate",
                    rosetta_category=inventory.title_to_rosetta_category(title),
                    features=("functions",),
                    porting_status="not-started",
                )
            )
    for index in range(3):
        title = f"Sample 4-4e-{index:02d}"
        records.append(
            inventory.InventoryRecord(
                title=title,
                url=inventory.title_to_url(title),
                extract="",
                bucket="4",
                subbucket="4e",
                matched_rule="default",
                difficulty="moderate",
                rosetta_category=inventory.title_to_rosetta_category(title),
                features=("functions",),
                porting_status="not-started",
            )
        )

    try:
        sample = inventory.build_review_sample(records)
    except RuntimeError as exc:
        return False, f"review sample generation failed unexpectedly: {exc}"
    if len(sample) != sum(inventory.REVIEW_SAMPLE_QUOTAS.values()):
        return False, (
            "review sample count diverged from REVIEW_SAMPLE_QUOTAS: "
            f"{len(sample)} != {sum(inventory.REVIEW_SAMPLE_QUOTAS.values())}"
        )

    counts = inventory.bucket_summary(sample)
    for bucket_key, expected in inventory.REVIEW_SAMPLE_QUOTAS.items():
        if counts.get(bucket_key) != expected:
            return False, f"review sample quota mismatch for {bucket_key!r}: {counts.get(bucket_key)!r} != {expected!r}"

    sample_titles = {record.title for record in sample}
    for anchor_title in inventory.REVIEW_SAMPLE_ANCHOR_TITLES:
        if anchor_title not in sample_titles:
            return False, f"review sample missing anchor {anchor_title!r}"

    try:
        markdown = inventory.build_review_sample_markdown(records)
    except RuntimeError as exc:
        return False, f"review sample markdown generation failed unexpectedly: {exc}"
    if "**1/(none)**" not in markdown or "**3/(none)**" not in markdown or "**4/(none)**" not in markdown:
        return False, "review sample markdown is missing expected bucket sections"
    if "result: `confirmed`" not in markdown:
        return False, "review sample markdown is missing expected sections or anchor confirmation markers"
    if "Review sample omissions:" not in markdown or "`4/4e` omitted from the deterministic 50-task sample by design" not in markdown:
        return False, "review sample markdown is missing the expected omitted-bucket note"

    bitmap_index = next(index for index, record in enumerate(records) if record.title == "Bitmap")
    records[bitmap_index] = inventory.InventoryRecord(
        title="Bitmap",
        url=inventory.title_to_url("Bitmap"),
        extract="",
        bucket="4",
        subbucket="4e",
        matched_rule="default",
        difficulty="moderate",
        rosetta_category=inventory.title_to_rosetta_category("Bitmap"),
        features=("functions",),
        porting_status="not-started",
    )
    try:
        inventory.build_review_sample(records)
    except RuntimeError as exc:
        if "missing anchor(s)" not in str(exc):
            return False, f"review sample anchor guard raised the wrong error: {exc}"
    else:
        return False, "review sample accepted an anchor reclassified into an unquoted bucket"
    return True, ""


def run_rosetta_inventory_checks() -> RunCounts:
    passed = 0
    failures = []
    cases = [
        ("classification", run_classification_case),
        ("body round-trip", run_body_roundtrip_case),
        ("sample mapping", run_sample_mapping_case),
        ("sample mapping errors", run_sample_mapping_error_case),
        ("title helpers", run_title_helpers_case),
        ("build args", run_build_args_case),
        ("sample consistency", run_sample_consistency_case),
        ("gh graphql flags", run_gh_graphql_case),
        ("plan sync parent issue", run_plan_sync_parent_issue_case),
        ("fetch project fields", run_fetch_project_fields_case),
        ("fetch project items", run_fetch_project_items_case),
        ("fetch live task count", run_fetch_live_task_count_case),
        ("request json decode", run_request_json_decode_case),
        ("invalid cache load", run_load_cached_tasks_invalid_json_case),
        ("atomic cache save", run_save_cached_tasks_atomic_case),
        ("literal keyword", run_literal_keyword_case),
        ("text value raw", run_text_value_raw_case),
        ("delta comment", run_delta_comment_case),
        ("issue comment marker", run_issue_comment_marker_case),
        ("missing items comment", run_missing_items_comment_case),
        ("plan sync duplicates", run_plan_sync_duplicate_case),
        ("sync project counts", run_sync_project_count_case),
        ("review placeholder", run_review_placeholder_case),
        ("review sample", run_review_sample_case),
    ]
    for label, case in cases:
        passed += record_result(failures, f"rosetta inventory: {label}", case())
    return passed, 0, failures
