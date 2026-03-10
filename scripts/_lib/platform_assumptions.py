"""Shared platform and environment assumptions for repo glue gates."""

from __future__ import annotations

SUPPORTED_FRONTEND_ENVIRONMENTS = ("linux", "macos")
UNSUPPORTED_FRONTEND_ENVIRONMENTS = ("windows",)

SUPPORTED_PLATFORM_POLICY_TEXT = "Ubuntu/Linux CI and local macOS"
UNSUPPORTED_PLATFORM_POLICY_TEXT = "Windows is explicitly unsupported"

MASKED_PYTHON_INTERPRETERS = ("python", "python3", "python3.11")
DOCUMENTED_PYTHON_FORMS = (
    "`python`",
    "`python3`",
    "`python3.11`",
    "`python3.<minor>`",
    "path-qualified Python invocations",
)

MACOS_SDK_DISCOVERY_FORMS = (
    "`xcrun --show-sdk-path`",
    "`SDKROOT`",
)

STATIC_PYTHON_INVOCATION_PATTERNS = (
    r"(?<![A-Za-z0-9_./-])python(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_./-])python3(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_./-])python3\.\d+(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_.-])(?:\.{1,2}/|[^\"'\s]+/)+python(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_.-])(?:\.{1,2}/|[^\"'\s]+/)+python3(?![A-Za-z0-9_.-])",
    r"(?<![A-Za-z0-9_.-])(?:\.{1,2}/|[^\"'\s]+/)+python3\.\d+(?![A-Za-z0-9_.-])",
)
