"""Shared platform and environment assumptions for repo glue gates."""

from __future__ import annotations

SUPPORTED_FRONTEND_ENVIRONMENTS = ("linux",)
UNSUPPORTED_FRONTEND_ENVIRONMENTS = ("macos", "windows")

SUPPORTED_PLATFORM_POLICY_TEXT = "Ubuntu/Linux CI and local Linux"
UNSUPPORTED_PLATFORM_POLICY_TEXT = "macOS and Windows are explicitly unsupported"
PATH_LOOKUP_POLICY_TEXT = "PATH-based command discovery"
TEMPDIR_POLICY_TEXT = "deterministic TemporaryDirectory prefixes"
SHELL_POLICY_TEXT = "shell-free"

MASKED_PYTHON_INTERPRETERS = ("python", "python3", "python3.11")
DOCUMENTED_PYTHON_FORMS = (
    "`python`",
    "`python3`",
    "`python3.11`",
    "`python3.<minor>`",
    "path-qualified Python invocations",
)

STATIC_PYTHON_INVOCATION_PATTERNS = (
    r"(?<![A-Za-z0-9_./-])python(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_./-])python3(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_./-])python3\.\d+(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_.-])(?:\.{1,2}/|[^\"'\s]+/)+python(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_.-])(?:\.{1,2}/|[^\"'\s]+/)+python3(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_.-])(?:\.{1,2}/|[^\"'\s]+/)+python3\.\d+(?![A-Za-z0-9_.-])",
)
