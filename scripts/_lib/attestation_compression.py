"""Helpers for PR11.6.1 attestation-chain compression."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

from .harness_common import REPO_ROOT, require


ARCHIVE_ROOT = REPO_ROOT / "execution" / "archive"
RECEIPTS_ROOT = REPO_ROOT / "execution" / "compaction-receipts"
RECEIPT_PATH = RECEIPTS_ROOT / "pr1161-attestation-chain-compression.json"
ARCHIVE_SCHEMA_VERSION = 1
RECEIPT_SCHEMA_VERSION = 1
LIVE_SUBSUMER = "pr101_comprehensive_audit"


@dataclass(frozen=True)
class RetiredNodeSpec:
    node_id: str
    report_name: str
    transitive_chain: tuple[str, ...] = ()

    def original_report_path_at(self, repo_root: Path) -> Path:
        return repo_root / "execution" / "reports" / self.report_name

    @property
    def original_report_path(self) -> Path:
        return self.original_report_path_at(REPO_ROOT)

    @property
    def original_report_rel(self) -> str:
        return f"execution/reports/{self.report_name}"

    def archive_dir_at(self, repo_root: Path) -> Path:
        return repo_root / "execution" / "archive" / self.node_id

    @property
    def archive_dir(self) -> Path:
        return self.archive_dir_at(REPO_ROOT)

    def archive_report_path_at(self, repo_root: Path) -> Path:
        return self.archive_dir_at(repo_root) / "report.json"

    @property
    def archive_report_path(self) -> Path:
        return self.archive_report_path_at(REPO_ROOT)

    def archive_provenance_path_at(self, repo_root: Path) -> Path:
        return self.archive_dir_at(repo_root) / "provenance.json"

    @property
    def archive_provenance_path(self) -> Path:
        return self.archive_provenance_path_at(REPO_ROOT)

    @property
    def archive_report_rel(self) -> str:
        return f"execution/archive/{self.node_id}/report.json"

    @property
    def archive_provenance_rel(self) -> str:
        return f"execution/archive/{self.node_id}/provenance.json"


RETIRED_NODE_SPECS: tuple[RetiredNodeSpec, ...] = (
    RetiredNodeSpec(
        node_id="pr081_local_concurrency_frontend",
        report_name="pr081-local-concurrency-frontend-report.json",
        transitive_chain=("pr08_frontend_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr082_local_concurrency_analysis",
        report_name="pr082-local-concurrency-analysis-report.json",
        transitive_chain=("pr08_frontend_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr083_interface_contracts",
        report_name="pr083-interface-contracts-report.json",
        transitive_chain=("pr08_frontend_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr083a_public_constants",
        report_name="pr083a-public-constants-report.json",
        transitive_chain=("pr08_frontend_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr084_transitive_concurrency",
        report_name="pr084-transitive-concurrency-integration-report.json",
        transitive_chain=("pr08_frontend_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr08_frontend_baseline",
        report_name="pr08-frontend-baseline-report.json",
    ),
    RetiredNodeSpec(
        node_id="pr09a_emitter_surface",
        report_name="pr09a-emitter-surface-report.json",
        transitive_chain=("pr09_ada_emission_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr09a_emitter_mvp",
        report_name="pr09a-emitter-mvp-report.json",
        transitive_chain=("pr09_ada_emission_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr09b_sequential_semantics",
        report_name="pr09b-sequential-semantics-report.json",
        transitive_chain=("pr09_ada_emission_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr09b_concurrency_output",
        report_name="pr09b-concurrency-output-report.json",
        transitive_chain=("pr09_ada_emission_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr09b_snapshot_refresh",
        report_name="pr09b-snapshot-refresh-report.json",
        transitive_chain=("pr09_ada_emission_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr09_ada_emission_baseline",
        report_name="pr09-ada-emission-baseline-report.json",
    ),
    RetiredNodeSpec(
        node_id="pr10_contract_baseline",
        report_name="pr10-contract-baseline-report.json",
        transitive_chain=("pr10_emitted_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr10_emitted_flow",
        report_name="pr10-emitted-flow-report.json",
        transitive_chain=("pr10_emitted_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr10_emitted_prove",
        report_name="pr10-emitted-prove-report.json",
        transitive_chain=("pr10_emitted_baseline", LIVE_SUBSUMER),
    ),
    RetiredNodeSpec(
        node_id="pr10_emitted_baseline",
        report_name="pr10-emitted-baseline-report.json",
    ),
    RetiredNodeSpec(
        node_id="emitted_hardening_regressions",
        report_name="emitted-hardening-regressions-report.json",
    ),
    RetiredNodeSpec(
        node_id="pr101a_companion_proof_verification",
        report_name="pr101a-companion-proof-verification-report.json",
    ),
    RetiredNodeSpec(
        node_id="pr101b_template_proof_verification",
        report_name="pr101b-template-proof-verification-report.json",
    ),
)

RETIRED_NODE_IDS = tuple(spec.node_id for spec in RETIRED_NODE_SPECS)
RETIRED_NODES_BY_ID = {spec.node_id: spec for spec in RETIRED_NODE_SPECS}
RETIRED_ORIGINAL_REPORT_PATHS = {
    spec.node_id: spec.original_report_path for spec in RETIRED_NODE_SPECS
}
RETIRED_ARCHIVE_REPORT_PATHS = {
    spec.node_id: spec.archive_report_path for spec in RETIRED_NODE_SPECS
}
RETIRED_ARCHIVE_REPORT_RELS = {
    spec.node_id: spec.archive_report_rel for spec in RETIRED_NODE_SPECS
}


def retired_node_spec(node_id: str) -> RetiredNodeSpec:
    try:
        return RETIRED_NODES_BY_ID[node_id]
    except KeyError as exc:
        raise KeyError(f"unknown retired node: {node_id}") from exc


def validate_retired_node_ids(node_ids: list[str] | tuple[str, ...]) -> None:
    require(tuple(node_ids) == RETIRED_NODE_IDS, "retired node set must match the canonical 19-node compression set")


def repo_relative(path: Path, *, repo_root: Path = REPO_ROOT) -> str:
    return str(path.relative_to(repo_root))


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def leaf_hash(*, path: str, file_bytes: bytes) -> str:
    return sha256_hex(b"leaf\0" + path.encode("utf-8") + b"\0" + file_bytes)


def internal_hash(left_hex: str, right_hex: str) -> str:
    return sha256_hex(b"node\0" + bytes.fromhex(left_hex) + bytes.fromhex(right_hex))


def build_merkle_layers(leaf_hashes: list[str]) -> list[list[str]]:
    require(leaf_hashes, "merkle tree requires at least one leaf")
    layers = [leaf_hashes]
    current = leaf_hashes
    while len(current) > 1:
        next_layer: list[str] = []
        for index in range(0, len(current), 2):
            left = current[index]
            right = current[index + 1] if index + 1 < len(current) else current[index]
            next_layer.append(internal_hash(left, right))
        layers.append(next_layer)
        current = next_layer
    return layers


def merkle_root(entries: list[tuple[str, bytes]]) -> str:
    require(entries, "merkle root requires at least one entry")
    sorted_entries = sorted(entries, key=lambda item: item[0])
    leaves = [leaf_hash(path=path, file_bytes=file_bytes) for path, file_bytes in sorted_entries]
    return build_merkle_layers(leaves)[-1][0]


def inclusion_proof(entries: list[tuple[str, bytes]], *, path: str) -> list[dict[str, str]]:
    sorted_entries = sorted(entries, key=lambda item: item[0])
    leaf_paths = [entry_path for entry_path, _bytes in sorted_entries]
    require(path in leaf_paths, f"{path}: missing from Merkle entry set")
    leaves = [leaf_hash(path=entry_path, file_bytes=file_bytes) for entry_path, file_bytes in sorted_entries]
    layers = build_merkle_layers(leaves)
    index = leaf_paths.index(path)
    proof: list[dict[str, str]] = []
    for layer in layers[:-1]:
        if index % 2 == 0:
            sibling_index = index + 1 if index + 1 < len(layer) else index
            proof.append({"side": "right", "hash": layer[sibling_index]})
        else:
            sibling_index = index - 1
            proof.append({"side": "left", "hash": layer[sibling_index]})
        index //= 2
    return proof


def verify_inclusion_proof(
    *,
    path: str,
    file_bytes: bytes,
    proof: list[dict[str, str]],
    root_hex: str,
) -> bool:
    current = leaf_hash(path=path, file_bytes=file_bytes)
    for step in proof:
        side = step["side"]
        sibling = step["hash"]
        if side == "left":
            current = internal_hash(sibling, current)
        elif side == "right":
            current = internal_hash(current, sibling)
        else:
            raise ValueError(f"unknown Merkle proof side: {side}")
    return current == root_hex


def retired_merkle_entries(*, repo_root: Path = REPO_ROOT) -> list[tuple[str, bytes]]:
    entries: list[tuple[str, bytes]] = []
    for spec in RETIRED_NODE_SPECS:
        entries.append((spec.original_report_rel, spec.original_report_path_at(repo_root).read_bytes()))
    return entries


def active_report_entries(*, repo_root: Path = REPO_ROOT) -> list[tuple[str, bytes]]:
    reports_root = repo_root / "execution" / "reports"
    entries: list[tuple[str, bytes]] = []
    for path in sorted(reports_root.rglob("*.json")):
        entries.append((repo_relative(path, repo_root=repo_root), path.read_bytes()))
    require(entries, "active report set must not be empty")
    return entries
