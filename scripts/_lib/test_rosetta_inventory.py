"""Focused checks for ``scripts/rosetta_inventory.py``."""

from __future__ import annotations

import subprocess

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
            "Define a type declaration that is generic over another type.",
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
    if inventory.slugify("Greatest common divisor") != "greatest_common_divisor":
        return False, "slugify did not normalize spacing"
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
    inventory.validate_sample_consistency(baseline_records)

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


def run_gh_paginated_arrays_case() -> tuple[bool, str]:
    original_run_capture = inventory.run_capture

    def fake_run_capture(argv: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(argv, 0, stdout="[] not-json", stderr="")

    inventory.run_capture = fake_run_capture
    try:
        try:
            inventory.gh_paginated_arrays(["gh", "api", "/example"])
        except RuntimeError as exc:
            if "returned invalid JSON" not in str(exc):
                return False, f"unexpected JSON decode error text: {exc}"
            return True, ""
        return False, "gh_paginated_arrays accepted malformed JSON"
    finally:
        inventory.run_capture = original_run_capture


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
    original_gh_paginated_arrays = inventory.gh_paginated_arrays
    captured: dict[str, list[str]] = {}

    def fake_gh_json(argv: list[str]) -> dict[str, object]:
        return {"id": "PVT_kwDOA"}

    def fake_gh_paginated_arrays(argv: list[str]) -> list[dict[str, object]]:
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
        return [
            {
                "name": name,
                "node_id": f"field-{index}",
                "id": str(100 + index),
                "data_type": "single_select" if index < 4 else "text",
                "options": [{"name": {"raw": "1"}, "id": "option-1"}] if name == "Bucket" else [],
            }
            for index, name in enumerate(names, start=1)
        ]

    inventory.gh_json = fake_gh_json
    inventory.gh_paginated_arrays = fake_gh_paginated_arrays
    try:
        project_id, fields = inventory.fetch_project_fields(5, owner="berkeleynerd")
    finally:
        inventory.gh_json = original_gh_json
        inventory.gh_paginated_arrays = original_gh_paginated_arrays

    if project_id != "PVT_kwDOA":
        return False, f"unexpected project id {project_id!r}"
    if "--paginate" not in captured.get("argv", []):
        return False, f"fetch_project_fields did not request pagination: {captured.get('argv')!r}"
    if f"X-GitHub-Api-Version: {inventory.GITHUB_API_VERSION}" not in captured.get("argv", []):
        return False, f"fetch_project_fields did not use the stable API version: {captured.get('argv')!r}"
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
    original_gh_paginated_arrays = inventory.gh_paginated_arrays
    captured: dict[str, list[str]] = {}

    field_map = {
        "Bucket": inventory.ProjectField("Bucket", "field-bucket", 101, "single_select", {"1": "option-1"}),
        "Porting Status": inventory.ProjectField("Porting Status", "field-porting", 102, "single_select", {"ported": "option-2"}),
        "Rosetta URL": inventory.ProjectField("Rosetta URL", "field-url", 103, "text", {}),
        "Features Used": inventory.ProjectField("Features Used", "field-features", 104, "text", {}),
    }

    def fake_gh_paginated_arrays(argv: list[str]) -> list[dict[str, object]]:
        captured["argv"] = list(argv)
        return [
            {
                "node_id": "PVTI_test",
                "content_type": "DraftIssue",
                "content": {"node_id": "DI_test", "title": "Factorial", "body": "body"},
                "fields": [
                    {"name": "Bucket", "data_type": "single_select", "value": {"name": {"raw": "1"}}},
                    {"name": "Porting Status", "data_type": "single_select", "value": {"name": "ported"}},
                    {"name": "Rosetta URL", "data_type": "text", "value": {"raw": "https://rosettacode.org/wiki/Factorial"}},
                    {"name": "Features Used", "data_type": "text", "value": "functions, loops"},
                ],
            }
        ]

    inventory.gh_paginated_arrays = fake_gh_paginated_arrays
    try:
        items = inventory.fetch_project_items(5, owner="berkeleynerd", field_map=field_map)
    finally:
        inventory.gh_paginated_arrays = original_gh_paginated_arrays

    if "--paginate" not in captured.get("argv", []):
        return False, f"fetch_project_items did not request pagination: {captured.get('argv')!r}"
    if f"X-GitHub-Api-Version: {inventory.GITHUB_API_VERSION}" not in captured.get("argv", []):
        return False, f"fetch_project_items did not use the stable API version: {captured.get('argv')!r}"
    if len(items) != 1:
        return False, f"expected one parsed project item, got {items!r}"
    item = items[0]
    if item.field_values != {
        "Bucket": "1",
        "Porting Status": "ported",
        "Rosetta URL": "https://rosettacode.org/wiki/Factorial",
        "Features Used": "functions, loops",
    }:
        return False, f"unexpected parsed field values {item.field_values!r}"
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


def run_issue_comment_marker_case() -> tuple[bool, str]:
    original_load_issue_comments = inventory.load_issue_comments
    original_run_capture = inventory.run_capture
    called = {"value": False}

    def fake_load_issue_comments(repo: str, issue_number: int) -> list[str]:
        return [inventory.build_delta_comment(category_size=10, task_count=9, fetched_at="2026-04-21T00:00:00Z")]

    def fake_run_capture(argv: list[str]) -> subprocess.CompletedProcess[str]:
        called["value"] = True
        return subprocess.CompletedProcess(argv, 0, stdout="", stderr="")

    inventory.load_issue_comments = fake_load_issue_comments
    inventory.run_capture = fake_run_capture
    try:
        inventory.ensure_issue_comment(
            "berkeleynerd/safe",
            347,
            inventory.build_delta_comment(category_size=10, task_count=9, fetched_at="2026-04-22T00:00:00Z"),
            dry_run=False,
        )
    finally:
        inventory.load_issue_comments = original_load_issue_comments
        inventory.run_capture = original_run_capture

    if called["value"]:
        return False, "ensure_issue_comment posted a duplicate marker-matched comment"
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

    sample = inventory.build_review_sample(records)
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

    markdown = inventory.build_review_sample_markdown(records)
    if "**1/(none)**" not in markdown or "**3/(none)**" not in markdown or "**4/(none)**" not in markdown:
        return False, "review sample markdown is missing expected bucket sections"
    if "result: `confirmed`" not in markdown:
        return False, "review sample markdown is missing expected sections or anchor confirmation markers"
    if "Review sample omissions:" not in markdown or "`4/4e` omitted from the deterministic 50-task sample by design" not in markdown:
        return False, "review sample markdown is missing the expected omitted-bucket note"
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
        ("sample consistency", run_sample_consistency_case),
        ("gh pagination errors", run_gh_paginated_arrays_case),
        ("plan sync parent issue", run_plan_sync_parent_issue_case),
        ("fetch project fields", run_fetch_project_fields_case),
        ("fetch project items", run_fetch_project_items_case),
        ("text value raw", run_text_value_raw_case),
        ("issue comment marker", run_issue_comment_marker_case),
        ("review placeholder", run_review_placeholder_case),
        ("review sample", run_review_sample_case),
    ]
    for label, case in cases:
        passed += record_result(failures, f"rosetta inventory: {label}", case())
    return passed, 0, failures
