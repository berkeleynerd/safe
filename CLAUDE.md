# CLAUDE.md

## Repository Shape

Safe is maintained here as a minimal development workflow:

- `compiler_impl/` contains the reference compiler workspace
- `tests/` contains the fixture corpus
- `samples/rosetta/` contains sample programs
- `companion/` contains the SPARK companion and emission templates
- `spec/` and `docs/` contain the language and design documentation
- `scripts/run_tests.py`, `scripts/run_samples.py`, and `scripts/run_proofs.py`
  are the active repo workflows

The old milestone pipeline, execution reports, and `run_pr*.py` scripts are
intentionally gone.

## Development Commands

```bash
# Build the compiler
(cd compiler_impl && alr build)

# Run tests
python3 scripts/run_tests.py

# Run proofs (requires GNATprove)
python3 scripts/run_proofs.py

# Check samples
python3 scripts/run_samples.py

# Run the embedded concurrency evidence lane
python3 scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency

# Check emitted Ada stability for refactoring work
python3 scripts/snapshot_emitted_ada.py --check
```

## Platform Policy

- Supported: local Linux and Ubuntu-based CI
- Unsupported: macOS and Windows

## CI Structure

- `.github/workflows/ci.yml` runs on PR events, merge-queue candidates, manual
  `workflow_dispatch`, and pushes to `main`.
- PR events are intentionally fast:
  - `Prove` runs `python3 scripts/run_proofs.py --mode=check`
  - `Test` and `Embedded` report deferred fast-lane status and do not run the
    full sweep on PR pushes
- Full repo CI runs on merge-queue candidates, manual `workflow_dispatch`, and
  pushes to `main`.
- The merge queue is the only full pre-merge repo gate. `Test`, `Prove`, and
  `Embedded` must all pass there before code lands; a failure kicks the queued
  PR back out without merging.
- After merge, `main` reruns the same full `Test`, `Prove`, and `Embedded`
  lanes.
- If a post-merge `main` CI lane fails, CI opens one deduplicated alarm issue
  per failing job so recurring regressions stay visible.
- Claude review, security, and deep-audit PR workflows are separate from
  `ci.yml` and continue to run on PR events.
- The contributor pre-commit hook is the primary author-side gate. It should
  run the full local verification path before a branch is pushed.
- Skipping the pre-commit hook with `--no-verify` does not avoid validation; it
  only delays failure feedback from local push time to merge-queue time.
- Merge queue protection on `main` is load-bearing. Direct merges to `main`
  should remain blocked by branch protection.

## Guidance

- The repo-local wrapper CLI in `scripts/safe_cli.py` supports:
  - `safe build [--clean] [--clean-proofs] [--no-prove] [--level 1|2 (default: 1)] [--target-bits 32|64] <file.safe>`
  - `safe run [--no-prove] [--level 1|2 (default: 1)] [--target-bits 32|64] <file.safe>`
  - `safe prove [--verbose] [--level 1|2 (default: 2)] [--target-bits 32|64] [file.safe]`
  - `safe deploy [--target stm32f4] --board stm32f4-discovery [--simulate] <file.safe>`
- `safe build`, `safe run`, and `safe prove` share the per-project
  incremental cache under `.safe-build/`.
- Shared emitted Ada support lives in `compiler_impl/stdlib/ada`, with
  `compiler_impl/stdlib/safe_stdlib.gpr` retained for manual integration.
- The current proof inventory and checkpoint ownership live in
  `scripts/_lib/proof_inventory.py`.
- The embedded/Jorvik evidence lane is the repo-local
  `scripts/run_embedded_smoke.py --target stm32f4 --suite concurrency` flow.
- Ada Language Server is recommended for Ada editor integration, but is not
  part of CI or the required repo workflow.
- `docs/roadmap.md` is the current roadmap file.
- Keep `compiler/translation_rules.md` and `compiler/ast_schema.json` aligned
  with compiler-facing documentation changes.
- Treat `tests/`, `samples/rosetta/`, and `docs/` as the visible contract around
  the compiler.
- `scripts/safe_cli.py` and `scripts/safe_lsp.py` remain supported repo-local
  tooling and should continue to work.
- The current proof boundary is documented in
  `docs/emitted_output_verification_matrix.md`.
- For refactoring PRs that should preserve emitted Ada shape, run
  `python3 scripts/snapshot_emitted_ada.py --check`. If emitted Ada changes
  intentionally, regenerate `tests/emitted_ada_snapshot.json` with
  `python3 scripts/snapshot_emitted_ada.py`.

## Review Process

The repository has three Claude review workflows:

- Claude Code Review is automatic on PR open/push and is diff-scoped. It should
  focus on issues introduced by the PR.
- Claude Security Review is automatic on PR open/push and is limited to concrete
  security and proof-integrity concerns.
- Claude Deep Audit is on-demand and audits whole files around a change. It is
  for latent surrounding-code issues, not normal PR review.

When a PR should trigger the guarded Claude review/security workflows, the PR
head branch must live in `Pretty-Good-Apps/safe`. Fork PRs do not satisfy the
same-repo guard and should not be used as the primary review path.

The review and security workflows intentionally do not check out PR code into
their privileged jobs. If a checkout is needed to satisfy workflow tooling, it
must be a trusted checkout of `main`, not the PR merge ref or PR head. They
inspect PR state through GitHub metadata and `gh pr diff` / `gh pr view`
instead, so PR content is handled as untrusted data rather than executed
workspace state.

The `@claude` interactive workflow is comment-only. It can inspect PR metadata
and reply on the PR, but it is not allowed to check out or execute PR code. If
an `@claude` request needs code changes or command execution, handle it through
a local agent run or a normal PR update instead of the comment workflow.

The interactive workflow keeps the triggering `@claude ...` comment as the user
request. Static guardrails belong in the Claude CLI system prompt layer, not in
the action `prompt:` field.

The workflow `--allowedTools` entries intentionally narrow access to specific
`gh pr ...` subcommands, but those wildcards do not sanitize shell arguments by
themselves. Behavioral prompt/system-prompt guardrails remain load-bearing.

The trusted inline-comment MCP capability used by the security workflow comes
from the pinned `anthropics/claude-code-action` bundle and should be re-audited
whenever that action SHA changes.

Preferred publishing flow:

```bash
git push upstream HEAD:refs/heads/<branch-name>
```

Then open the PR from `Pretty-Good-Apps:<branch-name>` to `main`. If development
started on a fork branch, mirror the branch to `upstream` before opening the
review PR.

Invoke Claude Deep Audit on a PR by adding the `deep-audit` label:

```bash
gh pr edit <N> --add-label deep-audit
```

If the label does not exist yet, a repo admin should create it once:

```bash
gh label create deep-audit --color B60205 \
  --description "Trigger Claude Deep Audit workflow on this PR"
```

Invoke it manually against an open PR:

```bash
gh workflow run claude-audit.yml -f pr_number=<N>
```

Invoke it manually against explicit paths on main:

```bash
gh workflow run claude-audit.yml --ref main \
  -f paths=compiler_impl/src/safe_frontend-mir_analyze.adb
```

Deep Audit looks for fail-closed violations, walker exhaustiveness gaps,
`Wide_Integer` overflow and narrowing risks, dead or duplicated emit/decode
logic, and contract drift. It intentionally does not duplicate the automatic
diff review or security review.
