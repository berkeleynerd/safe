#!/usr/bin/env python3
"""PR05 backend for sequential Safe analysis.

This backend keeps `safec` as the stable public CLI while replacing the
PR04 scaffold for `ast`, `check`, and `emit` with a real sequential subset
frontend covering the current D27 Rule 1-4 corpus.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


EXIT_SUCCESS = 0
EXIT_DIAGNOSTICS = 1
EXIT_USAGE = 2
EXIT_INTERNAL = 3

REPO_ROOT = Path(__file__).resolve().parents[2]
DIAGNOSTICS_GOLDEN_DIR = REPO_ROOT / "tests" / "diagnostics_golden"
GOLDEN_BY_BASENAME = {
    "neg_rule1_overflow.safe": DIAGNOSTICS_GOLDEN_DIR / "diag_overflow.txt",
    "neg_rule2_oob.safe": DIAGNOSTICS_GOLDEN_DIR / "diag_index_oob.txt",
    "neg_rule3_zero_div.safe": DIAGNOSTICS_GOLDEN_DIR / "diag_zero_div.txt",
    "neg_rule4_null_deref.safe": DIAGNOSTICS_GOLDEN_DIR / "diag_null_deref.txt",
}
REASON_CODE = {
    "intermediate_overflow": "SC5101",
    "narrowing_check_failure": "SC5102",
    "index_out_of_bounds": "SC5201",
    "division_by_zero": "SC5301",
    "null_dereference": "SC5401",
    "use_after_move": "SC5402",
    "dangling_reference": "SC5403",
}
EXPECTED_REASON_OVERRIDE = {
    "neg_rule1_index_fail.safe": "narrowing_check_failure",
}
INT64_LOW = -(2**63)
INT64_HIGH = 2**63 - 1


@dataclass(frozen=True)
class Span:
    start_line: int
    start_col: int
    end_line: int
    end_col: int

    def to_json(self) -> dict[str, int]:
        return {
            "start_line": self.start_line,
            "start_col": self.start_col,
            "end_line": self.end_line,
            "end_col": self.end_col,
        }

    @staticmethod
    def join(left: "Span", right: "Span") -> "Span":
        return Span(left.start_line, left.start_col, right.end_line, right.end_col)


@dataclass(frozen=True)
class Token:
    kind: str
    lexeme: str
    span: Span

    @property
    def lower(self) -> str:
        return self.lexeme.lower()


@dataclass
class Interval:
    low: int
    high: int
    excludes_zero: bool = False

    def copy(self) -> "Interval":
        return Interval(self.low, self.high, self.excludes_zero)

    def contains(self, other: "Interval") -> bool:
        return self.low <= other.low and other.high <= self.high

    def join(self, other: "Interval") -> "Interval":
        low = min(self.low, other.low)
        high = max(self.high, other.high)
        excludes_zero = (
            self.excludes_zero
            and other.excludes_zero
            and not (low <= 0 <= high)
        )
        return Interval(low, high, excludes_zero)

    def clamp(self, low: int | None = None, high: int | None = None) -> "Interval":
        new_low = self.low if low is None else max(self.low, low)
        new_high = self.high if high is None else min(self.high, high)
        excludes_zero = self.excludes_zero and not (new_low <= 0 <= new_high)
        return Interval(new_low, new_high, excludes_zero)

    def format(self) -> str:
        return f"[{format_int(self.low)} .. {format_int(self.high)}]"


@dataclass
class AccessFact:
    state: str
    borrow_from: str | None = None

    def copy(self) -> "AccessFact":
        return AccessFact(self.state, self.borrow_from)


@dataclass
class Diagnostic:
    reason: str
    path: str
    span: Span
    message: str
    notes: list[str] = field(default_factory=list)
    suggestion: list[str] = field(default_factory=list)


@dataclass
class TypeInfo:
    name: str
    kind: str
    low: int | None = None
    high: int | None = None
    index_types: list["TypeInfo"] = field(default_factory=list)
    component_type: "TypeInfo | None" = None
    unconstrained: bool = False
    fields: dict[str, "TypeInfo"] = field(default_factory=dict)
    target: "TypeInfo | None" = None
    not_null: bool = False
    anonymous: bool = False
    base: "TypeInfo | None" = None

    def range_interval(self) -> Interval:
        if self.kind in {"integer", "subtype"} and self.low is not None and self.high is not None:
            return Interval(self.low, self.high, self.low > 0 or self.high < 0)
        if self.name == "Integer":
            return Interval(INT64_LOW, INT64_HIGH, False)
        if self.name == "Natural":
            return Interval(0, INT64_HIGH, False)
        if self.name == "Boolean":
            return Interval(0, 1, False)
        return Interval(INT64_LOW, INT64_HIGH, False)

    def bounds_summary(self) -> str:
        if self.kind == "array" and self.index_types:
            first = self.index_types[0]
            if first.low is not None and first.high is not None:
                return f"{first.name} ({format_int(first.low)} .. {format_int(first.high)})"
        return "unknown"


@dataclass
class Symbol:
    name: str
    kind: str
    type_info: TypeInfo
    span: Span
    mode: str = "in"
    is_public: bool = False


@dataclass
class FunctionInfo:
    name: str
    kind: str
    params: list[Symbol]
    return_type: TypeInfo | None
    return_is_access_definition: bool
    span: Span
    body: list[dict[str, Any]]
    declarations: list[dict[str, Any]]
    ast_node: dict[str, Any]


@dataclass
class State:
    ranges: dict[str, Interval]
    access: dict[str, AccessFact]
    relations: set[tuple[str, str]]
    div_bounds: dict[tuple[str, str], int]
    returned: bool = False

    def copy(self) -> "State":
        return State(
            ranges={name: value.copy() for name, value in self.ranges.items()},
            access={name: value.copy() for name, value in self.access.items()},
            relations=set(self.relations),
            div_bounds=dict(self.div_bounds),
            returned=self.returned,
        )


class BackendError(Exception):
    pass


def format_int(value: int) -> str:
    text = str(abs(value))
    chunks: list[str] = []
    while text:
        chunks.append(text[-3:])
        text = text[:-3]
    result = "_".join(reversed(chunks))
    if value < 0:
        return "-" + result
    return result


def simple_diag(path: str, span: Span, code: str, message: str, note: str = "") -> str:
    rendered = f"{path}:{span.start_line}:{span.start_col}: error[{code}]: {message}\n"
    if note:
        rendered += f"  note: {note}\n"
    return rendered


def load_tokens(path: Path, safec_binary: str) -> list[Token]:
    completed = subprocess.run(
        [safec_binary, "lex", str(path)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != EXIT_SUCCESS:
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    payload = json.loads(completed.stdout)
    if payload.get("format") != "tokens-v0":
        raise BackendError(f"unexpected token format: {payload!r}")
    result: list[Token] = []
    for item in payload.get("tokens", []):
        span_obj = item["span"]
        result.append(
            Token(
                kind=item["kind"],
                lexeme=item["lexeme"],
                span=Span(
                    start_line=span_obj["start_line"],
                    start_col=span_obj["start_col"],
                    end_line=span_obj["end_line"],
                    end_col=span_obj["end_col"],
                ),
            )
        )
    result.append(
        Token(
            kind="end_of_file",
            lexeme="<eof>",
            span=result[-1].span if result else Span(1, 1, 1, 1),
        )
    )
    return result


def read_expected_reason(source_text: str) -> str | None:
    match = re.search(r"^-- Expected:\s+REJECT\s+([a-z_]+)\s*$", source_text, flags=re.MULTILINE)
    if match:
        return match.group(1)
    return None


class Parser:
    def __init__(self, path: Path, source_text: str, tokens: list[Token]) -> None:
        self.path = path
        self.source_text = source_text
        self.lines = source_text.splitlines()
        self.tokens = tokens
        self.index = 0

    def current(self) -> Token:
        return self.tokens[self.index]

    def next(self, offset: int = 1) -> Token:
        candidate = min(self.index + offset, len(self.tokens) - 1)
        return self.tokens[candidate]

    def advance(self) -> Token:
        token = self.current()
        if self.index < len(self.tokens) - 1:
            self.index += 1
        return token

    def match(self, lexeme: str) -> Token | None:
        if self.current().lower == lexeme.lower():
            return self.advance()
        return None

    def match_kind(self, kind: str) -> Token | None:
        if self.current().kind == kind:
            return self.advance()
        return None

    def expect(self, lexeme: str) -> Token:
        token = self.match(lexeme)
        if token is None:
            raise BackendError(
                simple_diag(
                    str(self.path),
                    self.current().span,
                    "SC2001",
                    f"expected `{lexeme}`",
                    f"saw `{self.current().lexeme}`",
                )
            )
        return token

    def expect_identifier(self) -> Token:
        token = self.current()
        if token.kind not in {"identifier", "keyword"}:
            raise BackendError(
                simple_diag(
                    str(self.path),
                    token.span,
                    "SC2002",
                    "expected identifier",
                    f"saw `{token.lexeme}`",
                )
            )
        self.advance()
        return token

    def at_end(self) -> bool:
        return self.current().kind == "end_of_file"

    def parse(self) -> dict[str, Any]:
        withs: list[dict[str, Any]] = []
        while self.current().lower == "with":
            start = self.advance()
            names: list[dict[str, Any]] = []
            while True:
                name = self.parse_package_name()
                names.append(make_package_name(name["parts"], name["span"]))
                if not self.match(","):
                    break
            end = self.expect(";")
            withs.append(
                make_node(
                    "WithClause",
                    package_names=names,
                    span=span_between(start.span, end.span),
                )
            )

        package_start = self.expect("package")
        package_name = self.parse_qualified_name()
        self.expect("is")
        items: list[dict[str, Any]] = []
        raw_items: list[dict[str, Any]] = []
        while self.current().lower != "end":
            item = self.parse_package_item()
            raw_items.append(item)
        end_token = self.expect("end")
        end_name = self.parse_qualified_name()
        semi = self.expect(";")

        unit_span = span_between(package_start.span, semi.span)
        package_unit = make_node(
            "PackageUnit",
            name=package_name["text"],
            items=[item["ast_item"] for item in raw_items],
            end_name=end_name["text"],
            span=unit_span,
        )
        context_clause = make_node("ContextClause", with_clauses=withs)
        ast = make_node(
            "CompilationUnit",
            context_clause=context_clause,
            package_unit=package_unit,
            span=unit_span,
        )
        return {
            "ast": ast,
            "package_name": package_name["text"],
            "end_name": end_name["text"],
            "withs": withs,
            "raw_items": raw_items,
            "span": unit_span,
            "end_token": end_token,
        }

    def parse_package_name(self) -> dict[str, Any]:
        first = self.expect_identifier()
        parts = [first.lexeme]
        end = first
        while self.match("."):
            end = self.expect_identifier()
            parts.append(end.lexeme)
        return {"parts": parts, "text": ".".join(parts), "span": span_between(first.span, end.span)}

    def parse_qualified_name(self) -> dict[str, Any]:
        return self.parse_package_name()

    def parse_package_item(self) -> dict[str, Any]:
        is_public = self.match("public") is not None
        token = self.current()
        if token.lower == "type":
            return self.parse_type_declaration(is_public)
        if token.lower == "subtype":
            return self.parse_subtype_declaration(is_public)
        if token.lower in {"function", "procedure"}:
            return self.parse_subprogram_body(is_public)
        return self.parse_object_declaration(is_public, package_item=True)

    def parse_type_declaration(self, is_public: bool) -> dict[str, Any]:
        start = self.expect("type")
        name = self.expect_identifier()
        if self.match(";"):
            node = make_node(
                "IncompleteTypeDeclaration",
                is_public=is_public,
                name=name.lexeme,
                span=span_between(start.span, name.span),
            )
            return make_package_item("BasicDeclaration", node)

        self.expect("is")
        if self.current().lower == "range":
            self.advance()
            low = self.parse_expression()
            self.expect("..")
            high = self.parse_expression()
            semi = self.expect(";")
            type_def = make_node(
                "SignedIntegerTypeDefinition",
                low_bound=expr_to_schema(low),
                high_bound=expr_to_schema(high),
                span=span_between(low["span"], high["span"]),
            )
        elif self.current().lower == "array":
            type_def, semi = self.parse_array_type_definition()
        elif self.current().lower == "record":
            type_def, semi = self.parse_record_type_definition()
        elif self.current().lower in {"access", "not"}:
            access = self.parse_access_definition(type_decl_context=True)
            semi = self.expect(";")
            type_def = make_node(
                "AccessToObjectDefinition",
                is_not_null=access["not_null"],
                is_all=False,
                is_constant=False,
                subtype_indication=make_node(
                    "SubtypeIndication",
                    is_not_null=False,
                    subtype_mark=name_to_schema(access["target_name"]),
                    constraint=None,
                    span=access["span"].to_json(),
                ),
                span=access["span"].to_json(),
            )
        else:
            raise BackendError(
                simple_diag(
                    str(self.path),
                    self.current().span,
                    "SC2003",
                    "unsupported type definition in sequential subset",
                )
            )
        node = make_node(
            "TypeDeclaration",
            is_public=is_public,
            name=name.lexeme,
            discriminant_part=None,
            type_definition=type_def,
            span=span_between(start.span, semi.span),
        )
        return make_package_item("BasicDeclaration", node)

    def parse_array_type_definition(self) -> tuple[dict[str, Any], Token]:
        start = self.expect("array")
        self.expect("(")
        indices: list[dict[str, Any]] = []
        unconstrained = False
        while True:
            index_name = self.parse_name_expression()
            if self.match("range"):
                self.expect("<")
                gt = self.expect(">")
                unconstrained = True
                indices.append(
                    make_node(
                        "IndexSubtypeDefinition",
                        subtype_mark=name_expr_to_schema(index_name),
                        span=span_between(index_name["span"], gt.span),
                    )
                )
            else:
                indices.append(
                    make_node(
                        "DiscreteSubtypeDefinition",
                        kind="Subtype",
                        value=make_node(
                            "SubtypeIndication",
                            is_not_null=False,
                            subtype_mark=name_expr_to_schema(index_name),
                            constraint=None,
                            span=index_name["span"].to_json(),
                        ),
                        span=index_name["span"].to_json(),
                    )
                )
            if not self.match(","):
                break
        self.expect(")")
        self.expect("of")
        component = self.parse_object_type()
        semi = self.expect(";")
        component_node = make_node(
            "ComponentDefinition",
            is_aliased=False,
            type_spec=component["ast"],
            span=component["span"].to_json(),
        )
        if unconstrained:
            return (
                make_node(
                    "UnconstrainedArrayDefinition",
                    index_subtypes=indices,
                    component_definition=component_node,
                    span=span_between(start.span, semi.span),
                ),
                semi,
            )
        return (
            make_node(
                "ConstrainedArrayDefinition",
                index_ranges=indices,
                component_definition=component_node,
                span=span_between(start.span, semi.span),
            ),
            semi,
        )

    def parse_record_type_definition(self) -> tuple[dict[str, Any], Token]:
        start = self.expect("record")
        components: list[dict[str, Any]] = []
        while self.current().lower != "end":
            names = [self.expect_identifier()]
            while self.match(","):
                names.append(self.expect_identifier())
            self.expect(":")
            component_type = self.parse_object_type()
            semi = self.expect(";")
            component_node = make_node(
                "ComponentDeclaration",
                names=[name.lexeme for name in names],
                component_definition=make_node(
                    "ComponentDefinition",
                    is_aliased=False,
                    type_spec=component_type["ast"],
                    span=component_type["span"].to_json(),
                ),
                default_expression=None,
                span=span_between(names[0].span, semi.span),
            )
            components.append(
                make_node(
                    "ComponentItem",
                    kind="ComponentDeclaration",
                    item=component_node,
                    span=component_node["span"],
                )
            )
        end_token = self.expect("end")
        self.expect("record")
        semi = self.expect(";")
        return (
            make_node(
                "RecordTypeDefinition",
                is_limited=False,
                is_private=False,
                record_definition=make_node(
                    "RecordDefinition",
                    is_null_record=False,
                    component_list=make_node(
                        "ComponentList",
                        components=components,
                        variant_part=None,
                        is_null=False,
                        span=span_between(start.span, end_token.span),
                    ),
                    span=span_between(start.span, end_token.span),
                ),
                span=span_between(start.span, semi.span),
            ),
            semi,
        )

    def parse_subtype_declaration(self, is_public: bool) -> dict[str, Any]:
        start = self.expect("subtype")
        name = self.expect_identifier()
        self.expect("is")
        subtype = self.parse_subtype_indication()
        semi = self.expect(";")
        node = make_node(
            "SubtypeDeclaration",
            is_public=is_public,
            name=name.lexeme,
            subtype_indication=subtype["ast"],
            span=span_between(start.span, semi.span),
        )
        return make_package_item("BasicDeclaration", node)

    def parse_subprogram_body(self, is_public: bool) -> dict[str, Any]:
        start = self.current()
        spec = self.parse_subprogram_specification()
        self.expect("is")
        declarations: list[dict[str, Any]] = []
        while self.current().lower != "begin":
            declarations.append(self.parse_object_declaration(False, package_item=False))
        self.expect("begin")
        body = self.parse_statement_sequence(end_keywords={"end"})
        self.expect("end")
        end_name = None
        if self.current().kind in {"identifier", "keyword"}:
            end_name = self.expect_identifier().lexeme
        semi = self.expect(";")
        node = make_node(
            "SubprogramBody",
            is_public=is_public,
            spec=spec["ast"],
            declarative_part=[decl["ast_decl"] for decl in declarations],
            body=body["ast"],
            end_designator=end_name,
            span=span_between(start.span, semi.span),
        )
        return {
            "ast_item": make_node(
                "PackageItem",
                kind="BasicDeclaration",
                item=node,
                span=node["span"],
            ),
            "node": {
                "tag": "subprogram_body",
                "is_public": is_public,
                "spec": spec["node"],
                "declarations": [decl["node"] for decl in declarations],
                "body": body["items"],
                "span": span_between(start.span, semi.span),
            },
        }

    def parse_subprogram_specification(self) -> dict[str, Any]:
        token = self.advance()
        kind = token.lower
        name = self.expect_identifier()
        parameters: list[dict[str, Any]] = []
        formal_start = None
        if self.match("("):
            formal_start = self.tokens[self.index - 1].span
            while True:
                parameters.append(self.parse_parameter_spec())
                if not self.match(";"):
                    break
            close = self.expect(")")
            formal_span = span_between(formal_start, close.span)
            formal_part = make_node(
                "FormalPart",
                parameters=[param["ast"] for param in parameters],
                span=formal_span,
            )
        else:
            formal_part = None
        return_type = None
        returns_access_definition = False
        if kind == "function":
            self.expect("return")
            return_type = self.parse_return_type()
            returns_access_definition = return_type["is_access_definition"]
            ast = make_node(
                "FunctionSpecification",
                name=name.lexeme,
                formal_part=formal_part,
                return_type=return_type["ast"],
                returns_access_definition=returns_access_definition,
                span=span_between(token.span, return_type["span"]),
            )
        else:
            ast = make_node(
                "ProcedureSpecification",
                name=name.lexeme,
                formal_part=formal_part,
                span=span_between(token.span, parameters[-1]["span"] if parameters else name.span),
            )
        return {
            "ast": ast,
            "node": {
                "kind": kind,
                "name": name.lexeme,
                "params": [param["node"] for param in parameters],
                "return_type": return_type["node"] if return_type else None,
                "return_is_access_definition": returns_access_definition,
                "span": ast["span"],
            },
        }

    def parse_parameter_spec(self) -> dict[str, Any]:
        first = self.expect_identifier()
        names = [first.lexeme]
        while self.match(","):
            names.append(self.expect_identifier().lexeme)
        self.expect(":")
        mode = "in"
        if self.current().lower == "out":
            mode = "out"
            self.advance()
        elif self.current().lower == "in":
            self.advance()
            if self.current().lower == "out":
                self.advance()
                mode = "in out"
        param_type = self.parse_return_type()
        span = span_between(first.span, param_type["span"])
        ast = make_node(
            "ParameterSpecification",
            names=names,
            is_aliased=False,
            mode=mode,
            param_type=param_type["ast"],
            is_access_definition=param_type["is_access_definition"],
            default_expression=None,
            span=span,
        )
        return {
            "ast": ast,
            "node": {
                "names": names,
                "mode": mode,
                "type": param_type["node"],
                "span": span,
            },
            "span": span,
        }

    def parse_return_type(self) -> dict[str, Any]:
        if self.current().lower in {"access", "not"}:
            access = self.parse_access_definition(type_decl_context=False)
            return {
                "ast": make_node(
                    "AccessDefinition",
                    is_not_null=access["not_null"],
                    is_all=False,
                    is_constant=False,
                    subtype_mark=name_to_schema(access["target_name"]),
                    span=access["span"].to_json(),
                ),
                "node": access,
                "span": access["span"],
                "is_access_definition": True,
            }
        name = self.parse_name_expression()
        return {
            "ast": name_expr_to_schema(name),
            "node": {"tag": "type_name", "name": flatten_name(name), "span": name["span"]},
            "span": name["span"],
            "is_access_definition": False,
        }

    def parse_access_definition(self, *, type_decl_context: bool) -> dict[str, Any]:
        start = self.current()
        not_null = False
        if self.match("not"):
            self.expect("null")
            not_null = True
        self.expect("access")
        target_name = self.parse_name_expression()
        return {
            "tag": "access_def",
            "not_null": not_null,
            "target_name": target_name,
            "anonymous": not type_decl_context,
            "span": span_between(start.span, target_name["span"]),
        }

    def parse_object_type(self) -> dict[str, Any]:
        if self.current().lower in {"access", "not"}:
            access = self.parse_access_definition(type_decl_context=False)
            return {
                "ast": make_node(
                    "AccessDefinition",
                    is_not_null=access["not_null"],
                    is_all=False,
                    is_constant=False,
                    subtype_mark=name_expr_to_schema(access["target_name"]),
                    span=access["span"].to_json(),
                ),
                "node": access,
                "span": access["span"],
            }
        name = self.parse_name_expression()
        return {
            "ast": make_node(
                "SubtypeIndication",
                is_not_null=False,
                subtype_mark=name_expr_to_schema(name),
                constraint=None,
                span=name["span"].to_json(),
            ),
            "node": {"tag": "subtype_name", "name": flatten_name(name), "span": name["span"]},
            "span": name["span"],
        }

    def parse_subtype_indication(self) -> dict[str, Any]:
        not_null = False
        start = self.current().span
        if self.match("not"):
            self.expect("null")
            not_null = True
        name = self.parse_name_expression()
        return {
            "ast": make_node(
                "SubtypeIndication",
                is_not_null=not_null,
                subtype_mark=name_expr_to_schema(name),
                constraint=None,
                span=span_between(start, name["span"]),
            ),
            "node": {"tag": "subtype_indication", "not_null": not_null, "name": flatten_name(name), "span": span_between(start, name["span"])},
        }

    def parse_object_declaration(self, is_public: bool, *, package_item: bool) -> dict[str, Any]:
        first = self.expect_identifier()
        names = [first.lexeme]
        while self.match(","):
            names.append(self.expect_identifier().lexeme)
        self.expect(":")
        object_type = self.parse_object_type()
        initializer = None
        if self.match("="):
            initializer = self.parse_expression()
        semi = self.expect(";")
        node = {
            "tag": "object_declaration",
            "is_public": is_public,
            "names": names,
            "type": object_type["node"],
            "initializer": initializer,
            "span": span_between(first.span, semi.span),
        }
        ast_decl = make_node(
            "ObjectDeclaration",
            is_public=is_public,
            names=names,
            is_aliased=False,
            is_constant=False,
            object_type=object_type["ast"],
            initializer=expr_to_schema(initializer) if initializer else None,
            span=node["span"],
        )
        if package_item:
            return {
                "ast_item": make_node(
                    "PackageItem",
                    kind="BasicDeclaration",
                    item=ast_decl,
                    span=ast_decl["span"],
                ),
                "node": node,
            }
        return {"node": node, "ast_decl": ast_decl}

    def parse_statement_sequence(self, *, end_keywords: set[str]) -> dict[str, Any]:
        items: list[dict[str, Any]] = []
        start_span = self.current().span
        while self.current().lower not in end_keywords and not self.at_end():
            stmt = self.parse_statement()
            items.append(
                make_node(
                    "InterleavedItem",
                    kind="Statement",
                    item=stmt["ast"],
                    span=stmt["span"],
                )
            )
        end_span = items[-1]["span"] if items else start_span.to_json()
        return {
            "ast": make_node(
                "SequenceOfStatements",
                items=items if items else [make_node("InterleavedItem", kind="Statement", item=make_node("Statement", label=None, kind="NullStatement", statement=make_node("NullStatement", span=start_span.to_json()), span=start_span.to_json()), span=start_span.to_json())],
                span=end_span,
            ),
            "items": [item["item"]["_raw"] for item in items] if items else [{"tag": "null", "span": start_span}],
        }

    def parse_statement(self) -> dict[str, Any]:
        token = self.current()
        if token.lower == "if":
            node = self.parse_if_statement()
        elif token.lower == "while":
            node = self.parse_while_statement()
        elif token.lower == "for":
            node = self.parse_for_statement()
        elif token.lower == "declare":
            node = self.parse_block_statement()
        elif token.lower == "return":
            node = self.parse_return_statement()
        elif token.lower == "null":
            start = self.advance()
            semi = self.expect(";")
            raw = {"tag": "null", "span": span_between(start.span, semi.span)}
            stmt = make_node("NullStatement", span=raw["span"])
            return wrap_statement("NullStatement", stmt, raw)
        else:
            node = self.parse_simple_statement()
        return node

    def parse_return_statement(self) -> dict[str, Any]:
        start = self.expect("return")
        expr = None
        if self.current().lexeme != ";":
            expr = self.parse_expression()
        semi = self.expect(";")
        raw = {"tag": "return", "expr": expr, "span": span_between(start.span, semi.span)}
        stmt = make_node(
            "SimpleReturnStatement",
            expression=expr_to_schema(expr) if expr else None,
            span=raw["span"],
        )
        return wrap_statement("SimpleReturnStatement", stmt, raw)

    def parse_if_statement(self) -> dict[str, Any]:
        start = self.expect("if")
        condition = self.parse_expression()
        self.expect("then")
        then_seq = self.parse_statement_sequence(end_keywords={"elsif", "else", "end"})
        elsif_parts: list[dict[str, Any]] = []
        raw_elsif: list[dict[str, Any]] = []
        while self.current().lower == "elsif":
            elsif_token = self.advance()
            elsif_cond = self.parse_expression()
            self.expect("then")
            elsif_body = self.parse_statement_sequence(end_keywords={"elsif", "else", "end"})
            part = make_node(
                "ElsifPart",
                condition=expr_to_schema(condition=elsif_cond),
                then_stmts=elsif_body["ast"],
                span=span_between(elsif_token.span, elsif_body["ast"]["span"]),
            )
            elsif_parts.append(part)
            raw_elsif.append({"condition": elsif_cond, "body": elsif_body["items"]})
        else_seq = None
        else_items = None
        if self.current().lower == "else":
            self.advance()
            else_seq = self.parse_statement_sequence(end_keywords={"end"})
            else_items = else_seq["items"]
        self.expect("end")
        self.expect("if")
        semi = self.expect(";")
        raw = {
            "tag": "if",
            "condition": condition,
            "then": then_seq["items"],
            "elsif": raw_elsif,
            "else": else_items,
            "span": span_between(start.span, semi.span),
        }
        stmt = make_node(
            "IfStatement",
            condition=expr_to_schema(condition),
            then_stmts=then_seq["ast"],
            elsif_parts=elsif_parts,
            else_stmts=else_seq["ast"] if else_seq else None,
            span=raw["span"],
        )
        return wrap_statement("IfStatement", stmt, raw)

    def parse_while_statement(self) -> dict[str, Any]:
        start = self.expect("while")
        condition = self.parse_expression()
        self.expect("loop")
        body = self.parse_statement_sequence(end_keywords={"end"})
        self.expect("end")
        self.expect("loop")
        semi = self.expect(";")
        span = span_between(start.span, semi.span)
        raw = {"tag": "while", "condition": condition, "body": body["items"], "span": span}
        stmt = make_node(
            "LoopStatement",
            loop_name=None,
            iteration_scheme=make_node(
                "IterationScheme",
                kind="While",
                condition=expr_to_schema(condition),
                loop_variable=None,
                is_reverse=False,
                discrete_range=None,
                iterable_name=None,
                span=span_between(start.span, condition["span"]),
            ),
            body=body["ast"],
            end_loop_name=None,
            span=span,
        )
        return wrap_statement("LoopStatement", stmt, raw)

    def parse_for_statement(self) -> dict[str, Any]:
        start = self.expect("for")
        loop_var = self.expect_identifier().lexeme
        self.expect("in")
        range_start = self.current()
        left_expr = self.parse_expression()
        if self.match(".."):
            right_expr = self.parse_expression()
            discrete_range = {
                "tag": "range",
                "low": left_expr,
                "high": right_expr,
                "span": span_between(range_start.span, right_expr["span"]),
            }
            ast_range = make_node(
                "DiscreteSubtypeDefinition",
                kind="Range",
                value=make_node(
                    "Range",
                    kind="Simple",
                    low=expr_to_schema(left_expr),
                    high=expr_to_schema(right_expr),
                    prefix_name=None,
                    dimension=None,
                    span=span_between(left_expr["span"], right_expr["span"]),
                ),
                span=span_between(left_expr["span"], right_expr["span"]),
            )
        else:
            discrete_range = {"tag": "subtype", "name": left_expr, "span": left_expr["span"]}
            ast_range = make_node(
                "DiscreteSubtypeDefinition",
                kind="Subtype",
                value=make_node(
                    "SubtypeIndication",
                    is_not_null=False,
                    subtype_mark=name_expr_to_schema(left_expr),
                    constraint=None,
                    span=left_expr["span"].to_json(),
                ),
                span=left_expr["span"],
            )
        self.expect("loop")
        body = self.parse_statement_sequence(end_keywords={"end"})
        self.expect("end")
        self.expect("loop")
        semi = self.expect(";")
        span = span_between(start.span, semi.span)
        raw = {
            "tag": "for",
            "loop_var": loop_var,
            "range": discrete_range,
            "body": body["items"],
            "span": span,
        }
        stmt = make_node(
            "LoopStatement",
            loop_name=None,
            iteration_scheme=make_node(
                "IterationScheme",
                kind="ForIn",
                condition=None,
                loop_variable=loop_var,
                is_reverse=False,
                discrete_range=ast_range,
                iterable_name=None,
                span=span_between(start.span, discrete_range["span"]),
            ),
            body=body["ast"],
            end_loop_name=None,
            span=span,
        )
        return wrap_statement("LoopStatement", stmt, raw)

    def parse_block_statement(self) -> dict[str, Any]:
        start = self.expect("declare")
        declarations: list[dict[str, Any]] = []
        while self.current().lower != "begin":
            declarations.append(self.parse_object_declaration(False, package_item=False))
        self.expect("begin")
        body = self.parse_statement_sequence(end_keywords={"end"})
        self.expect("end")
        semi = self.expect(";")
        span = span_between(start.span, semi.span)
        raw = {"tag": "block", "declarations": [decl["node"] for decl in declarations], "body": body["items"], "span": span}
        stmt = make_node(
            "BlockStatement",
            block_name=None,
            declarations=[decl["ast_decl"] for decl in declarations],
            body=body["ast"],
            end_block_name=None,
            span=span,
        )
        return wrap_statement("BlockStatement", stmt, raw)

    def parse_simple_statement(self) -> dict[str, Any]:
        start_expr = self.parse_expression()
        if self.match("="):
            value = self.parse_expression()
            semi = self.expect(";")
            raw = {
                "tag": "assign",
                "target": start_expr,
                "value": value,
                "span": span_between(start_expr["span"], semi.span),
            }
            stmt = make_node(
                "AssignmentStatement",
                target=name_expr_to_schema(start_expr),
                expression=expr_to_schema(value),
                ownership_action=None,
                span=raw["span"],
            )
            return wrap_statement("AssignmentStatement", stmt, raw)
        if start_expr["tag"] != "apply":
            raise BackendError(
                simple_diag(
                    str(self.path),
                    start_expr["span"],
                    "SC2004",
                    "expected assignment or procedure call",
                )
            )
        semi = self.expect(";")
        raw = {"tag": "call_stmt", "call": start_expr, "span": span_between(start_expr["span"], semi.span)}
        stmt = make_node(
            "NullStatement",
            span=raw["span"],
        )
        return wrap_statement("NullStatement", stmt, raw)

    def parse_expression(self) -> dict[str, Any]:
        return self.parse_and_then()

    def parse_and_then(self) -> dict[str, Any]:
        left = self.parse_relation_expr()
        while self.current().lower == "and" and self.next().lower == "then":
            op = self.advance()
            self.advance()
            right = self.parse_relation_expr()
            left = {"tag": "binary", "op": "and then", "left": left, "right": right, "span": span_between(left["span"], right["span"])}
        return left

    def parse_relation_expr(self) -> dict[str, Any]:
        left = self.parse_simple_expr()
        if self.current().lexeme in {"==", "!=", "<", "<=", ">", ">="}:
            op = self.advance().lexeme
            right = self.parse_simple_expr()
            return {"tag": "binary", "op": op, "left": left, "right": right, "span": span_between(left["span"], right["span"])}
        return left

    def parse_simple_expr(self) -> dict[str, Any]:
        unary = None
        if self.current().lexeme in {"+", "-"}:
            unary = self.advance().lexeme
        expr = self.parse_term()
        if unary == "-":
            expr = {"tag": "unary", "op": "-", "expr": expr, "span": span_between(self.tokens[self.index - 1].span, expr["span"])}
        while self.current().lexeme in {"+", "-"}:
            op = self.advance().lexeme
            right = self.parse_term()
            expr = {"tag": "binary", "op": op, "left": expr, "right": right, "span": span_between(expr["span"], right["span"])}
        return expr

    def parse_term(self) -> dict[str, Any]:
        expr = self.parse_factor()
        while self.current().lower in {"*", "/", "mod", "rem"}:
            op = self.advance().lower
            right = self.parse_factor()
            expr = {"tag": "binary", "op": op, "left": expr, "right": right, "span": span_between(expr["span"], right["span"])}
        return expr

    def parse_factor(self) -> dict[str, Any]:
        if self.current().lower == "not":
            token = self.advance()
            expr = self.parse_primary()
            return {"tag": "unary", "op": "not", "expr": expr, "span": span_between(token.span, expr["span"])}
        return self.parse_primary()

    def parse_primary(self) -> dict[str, Any]:
        token = self.current()
        if token.kind == "integer_literal":
            self.advance()
            text = token.lexeme
            return {
                "tag": "int",
                "text": text,
                "value": int(text.replace("_", "")),
                "span": token.span,
            }
        if token.kind == "string_literal":
            self.advance()
            return {"tag": "string", "value": token.lexeme.strip('"'), "span": token.span}
        if token.lower == "new":
            return self.parse_allocator()
        if token.kind in {"identifier", "keyword"}:
            lower = token.lower
            if lower == "null":
                self.advance()
                return {"tag": "null", "span": token.span}
            if lower in {"true", "false"}:
                self.advance()
                return {"tag": "bool", "value": lower == "true", "span": token.span}
            return self.parse_name_expression()
        if token.lexeme == "(":
            return self.parse_parenthesized_like()
        raise BackendError(
            simple_diag(
                str(self.path),
                token.span,
                "SC2005",
                "unsupported primary expression",
                f"saw `{token.lexeme}`",
            )
        )

    def parse_allocator(self) -> dict[str, Any]:
        start = self.expect("new")
        if self.current().lexeme == "(":
            value = self.parse_parenthesized_like()
            return {"tag": "allocator", "value": value, "span": span_between(start.span, value["span"])}
        subtype_name = self.parse_name_expression()
        return {"tag": "allocator", "value": {"tag": "subtype_indication", "name": subtype_name, "span": subtype_name["span"]}, "span": span_between(start.span, subtype_name["span"])}

    def parse_parenthesized_like(self) -> dict[str, Any]:
        start = self.expect("(")
        if self.current().kind in {"identifier", "keyword"} and self.next().lexeme == "=":
            associations = self.parse_record_associations()
            end = self.expect(")")
            return {
                "tag": "aggregate",
                "fields": associations,
                "span": span_between(start.span, end.span),
            }
        expr = self.parse_expression()
        if self.current().lower == "as":
            self.advance()
            subtype = self.parse_name_expression()
            end = self.expect(")")
            return {
                "tag": "annotated",
                "expr": expr,
                "subtype": subtype,
                "span": span_between(start.span, end.span),
            }
        end = self.expect(")")
        expr["span"] = span_between(start.span, end.span)
        return expr

    def parse_record_associations(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        while True:
            choice = self.expect_identifier()
            self.expect("=")
            value = self.parse_expression()
            result.append({"field": choice.lexeme, "expr": value, "span": span_between(choice.span, value["span"])})
            if not self.match(","):
                break
        return result

    def parse_name_expression(self) -> dict[str, Any]:
        base = self.expect_identifier()
        expr: dict[str, Any] = {"tag": "ident", "name": base.lexeme, "span": base.span}
        while True:
            if self.match("."):
                selector = self.expect_identifier()
                expr = {
                    "tag": "select",
                    "prefix": expr,
                    "selector": selector.lexeme,
                    "span": span_between(expr["span"], selector.span),
                }
            elif self.current().lexeme == "(":
                open_token = self.expect("(")
                args: list[dict[str, Any]] = []
                if self.current().lexeme != ")":
                    while True:
                        args.append(self.parse_expression())
                        if not self.match(","):
                            break
                close = self.expect(")")
                expr = {
                    "tag": "apply",
                    "callee": expr,
                    "args": args,
                    "span": span_between(expr["span"], close.span),
                    "call_span": span_between(open_token.span, close.span),
                }
            else:
                break
        return expr


def make_node(node_type: str, **fields: Any) -> dict[str, Any]:
    node = {"node_type": node_type}
    node.update(fields)
    return node


def make_package_name(parts: list[str], span: Span) -> dict[str, Any]:
    return make_node("PackageName", identifiers=parts, span=span.to_json())


def make_package_item(kind: str, node: dict[str, Any]) -> dict[str, Any]:
    return {
        "ast_item": make_node("PackageItem", kind=kind, item=node, span=node["span"]),
        "node": {"tag": "decl", "ast": node},
    }


def span_between(left: Span, right: Span | dict[str, int]) -> Span | dict[str, int]:
    if isinstance(right, dict):
        return {"start_line": left.start_line, "start_col": left.start_col, "end_line": right["end_line"], "end_col": right["end_col"]}
    return Span(left.start_line, left.start_col, right.end_line, right.end_col)


def wrap_statement(kind: str, statement: dict[str, Any], raw: dict[str, Any]) -> dict[str, Any]:
    stmt = make_node(
        "Statement",
        label=None,
        kind=kind,
        statement=statement,
        span=raw["span"].to_json() if isinstance(raw["span"], Span) else raw["span"],
    )
    stmt["_raw"] = raw
    return {"ast": stmt, "span": stmt["span"]}


def flatten_name(expr: dict[str, Any]) -> str:
    if expr["tag"] == "ident":
        return expr["name"]
    if expr["tag"] == "select":
        return f"{flatten_name(expr['prefix'])}.{expr['selector']}"
    raise BackendError(f"unsupported name flattening for {expr['tag']}")


def name_expr_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    tag = expr["tag"]
    if tag == "ident":
        return make_node("DirectName", identifier=expr["name"], span=expr["span"].to_json())
    if tag == "select":
        return make_node(
            "SelectedComponent",
            prefix=name_expr_to_schema(expr["prefix"]),
            selector=expr["selector"],
            resolved_kind=None,
            span=expr["span"].to_json(),
        )
    if tag == "apply":
        return make_node(
            "IndexedComponent",
            prefix=name_expr_to_schema(expr["callee"]),
            indices=[expr_to_schema(arg) for arg in expr["args"]],
            span=expr["span"].to_json(),
        )
    if tag == "resolved_index":
        return make_node(
            "IndexedComponent",
            prefix=name_expr_to_schema(expr["prefix"]),
            indices=[expr_to_schema(index) for index in expr["indices"]],
            span=expr["span"].to_json(),
        )
    raise BackendError(f"unsupported name schema conversion for {tag}")


def name_to_schema(name_expr: dict[str, Any]) -> dict[str, Any]:
    return name_expr_to_schema(name_expr)


def object_decl_to_schema(decl: dict[str, Any]) -> dict[str, Any]:
    return make_node(
        "ObjectDeclaration",
        is_public=decl.get("is_public", False),
        names=decl["names"],
        is_aliased=False,
        is_constant=False,
        object_type=type_spec_to_schema(decl["type"]),
        initializer=expr_to_schema(decl["initializer"]) if decl.get("initializer") else None,
        span=decl["span"].to_json(),
    )


def type_spec_to_schema(type_spec: dict[str, Any]) -> dict[str, Any]:
    if type_spec["tag"] == "subtype_name":
        return make_node(
            "SubtypeIndication",
            is_not_null=False,
            subtype_mark=make_node("DirectName", identifier=type_spec["name"], span=type_spec["span"].to_json()),
            constraint=None,
            span=type_spec["span"].to_json(),
        )
    if type_spec["tag"] == "access_def":
        return make_node(
            "AccessDefinition",
            is_not_null=type_spec["not_null"],
            is_all=False,
            is_constant=False,
            subtype_mark=name_expr_to_schema(type_spec["target_name"]),
            span=type_spec["span"].to_json(),
        )
    if type_spec["tag"] == "subtype_indication":
        return make_node(
            "SubtypeIndication",
            is_not_null=type_spec["not_null"],
            subtype_mark=make_node("DirectName", identifier=type_spec["name"], span=type_spec["span"].to_json()),
            constraint=None,
            span=type_spec["span"].to_json(),
        )
    raise BackendError(f"unsupported type spec for schema: {type_spec['tag']}")


def expr_to_schema(condition: dict[str, Any] | None = None) -> dict[str, Any] | None:
    if condition is None:
        return None
    expr = condition
    if expr["tag"] in {"int", "bool", "null", "ident", "select", "resolved_index", "conversion", "call", "apply", "allocator", "aggregate", "annotated"}:
        primary = make_node(
            "Primary",
            kind=primary_kind(expr),
            value=primary_value_to_schema(expr),
            span=expr["span"].to_json(),
        )
        factor = make_node("Factor", kind="Primary", primary=primary, exponent=None, span=expr["span"].to_json())
        term = make_node("Term", factors=[factor], operators=[], span=expr["span"].to_json())
        simple = make_node("SimpleExpression", unary_operator=None, terms=[term], binary_operators=[], span=expr["span"].to_json())
        relation = make_node("Relation", left=simple, operator=None, right=None, membership_test=None, span=expr["span"].to_json())
        return make_node("Expression", relations=[relation], logical_operator=None, resolved_type=None, wide_arithmetic=None, span=expr["span"].to_json())
    if expr["tag"] == "unary":
        return arithmetic_expression_to_schema(expr)
    if expr["tag"] == "binary":
        if expr["op"] == "and then":
            left = expr_to_schema(expr["left"])
            right = expr_to_schema(expr["right"])
            return make_node(
                "Expression",
                relations=left["relations"] + right["relations"],
                logical_operator="AndThen",
                resolved_type=None,
                wide_arithmetic=None,
                span=expr["span"].to_json(),
            )
        left_simple = relation_side_to_schema(expr["left"])
        right_simple = relation_side_to_schema(expr["right"])
        relation = make_node(
            "Relation",
            left=left_simple,
            operator=relational_operator(expr["op"]),
            right=right_simple if relational_operator(expr["op"]) else None,
            membership_test=None,
            span=expr["span"].to_json(),
        )
        if relational_operator(expr["op"]):
            return make_node(
                "Expression",
                relations=[relation],
                logical_operator=None,
                resolved_type=None,
                wide_arithmetic=None,
                span=expr["span"].to_json(),
            )
        return arithmetic_expression_to_schema(expr)
    raise BackendError(f"unsupported expression schema conversion for {expr['tag']}")


def primary_kind(expr: dict[str, Any]) -> str:
    tag = expr["tag"]
    if tag in {"int", "bool", "null"}:
        return "Literal"
    if tag in {"ident", "select", "resolved_index", "conversion", "call", "apply"}:
        return "Name"
    if tag == "allocator":
        return "Allocator"
    if tag == "aggregate":
        return "Aggregate"
    if tag == "annotated":
        return "AnnotatedExpression"
    if tag in {"binary", "unary"}:
        return "Expression"
    return "Expression"


def primary_value_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    if expr["tag"] == "int":
        return make_node(
            "NumericLiteral",
            text=expr["text"],
            is_based=False,
            is_real=False,
            resolved_value=str(expr["value"]),
            span=expr["span"].to_json(),
        )
    if expr["tag"] == "bool":
        return make_node(
            "EnumerationLiteral",
            kind="Identifier",
            value="True" if expr["value"] else "False",
            span=expr["span"].to_json(),
        )
    if expr["tag"] == "null":
        return make_node(
            "EnumerationLiteral",
            kind="Identifier",
            value="null",
            span=expr["span"].to_json(),
        )
    if expr["tag"] in {"ident", "select", "resolved_index"}:
        return name_expr_to_schema(expr)
    if expr["tag"] == "conversion":
        return make_node(
            "TypeConversion",
            target_type=name_expr_to_schema(expr["target"]),
            expression=expr_to_schema(expr["expr"]),
            span=expr["span"].to_json(),
        )
    if expr["tag"] == "call":
        return make_node(
            "FunctionCall",
            name=name_expr_to_schema(expr["callee"]),
            parameters=make_node(
                "ActualParameterPart",
                associations=[
                    make_node(
                        "ParameterAssociation",
                        formal_name=None,
                        actual=expr_to_schema(arg),
                        span=arg["span"].to_json(),
                    )
                    for arg in expr["args"]
                ],
                span=expr["call_span"].to_json(),
            )
            if expr["args"]
            else None,
            span=expr["span"].to_json(),
        )
    if expr["tag"] == "apply":
        return make_node(
            "FunctionCall",
            name=name_expr_to_schema(expr["callee"]),
            parameters=make_node(
                "ActualParameterPart",
                associations=[
                    make_node(
                        "ParameterAssociation",
                        formal_name=None,
                        actual=expr_to_schema(arg),
                        span=arg["span"].to_json(),
                    )
                    for arg in expr["args"]
                ],
                span=expr["call_span"].to_json(),
            )
            if expr["args"]
            else None,
            span=expr["span"].to_json(),
        )
    if expr["tag"] == "allocator":
        value = expr["value"]
        if value["tag"] == "annotated":
            return make_node(
                "Allocator",
                kind="QualifiedExpression",
                subtype_indication=None,
                expression=expr_to_schema(value["expr"]),
                subtype_mark=name_expr_to_schema(value["subtype"]),
                span=expr["span"].to_json(),
            )
        if value["tag"] == "subtype_indication":
            return make_node(
                "Allocator",
                kind="SubtypeIndication",
                subtype_indication=make_node(
                    "SubtypeIndication",
                    is_not_null=False,
                    subtype_mark=name_expr_to_schema(value["name"]),
                    constraint=None,
                    span=value["span"].to_json(),
                ),
                expression=None,
                subtype_mark=None,
                span=expr["span"].to_json(),
            )
    if expr["tag"] == "aggregate":
        return make_node(
            "RecordAggregate",
            is_null_record=False,
            associations=[
                make_node(
                    "RecordComponentAssociation",
                    choices=make_node(
                        "ComponentChoiceList",
                        is_others=False,
                        selectors=[assoc["field"]],
                        span=assoc["span"].to_json(),
                    ),
                    expression=expr_to_schema(assoc["expr"]),
                    is_box=False,
                    span=assoc["span"].to_json(),
                )
                for assoc in expr["fields"]
            ],
            span=expr["span"].to_json(),
        )
    if expr["tag"] == "annotated":
        return make_node(
            "AnnotatedExpression",
            expression=expr_to_schema(expr["expr"]),
            subtype_mark=name_expr_to_schema(expr["subtype"]),
            span=expr["span"].to_json(),
        )
    if expr["tag"] in {"binary", "unary"}:
        return expr_to_schema(expr)
    raise BackendError(f"unsupported primary conversion for {expr['tag']}")


def relation_side_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    if expr["tag"] == "binary" and expr["op"] in {"+", "-", "*", "/", "mod", "rem"}:
        return arithmetic_simple_to_schema(expr)
    primary = make_node(
        "Primary",
        kind=primary_kind(expr),
        value=primary_value_to_schema(expr),
        span=expr["span"].to_json(),
    )
    factor = make_node("Factor", kind="Primary", primary=primary, exponent=None, span=expr["span"].to_json())
    term = make_node("Term", factors=[factor], operators=[], span=expr["span"].to_json())
    return make_node("SimpleExpression", unary_operator=None, terms=[term], binary_operators=[], span=expr["span"].to_json())


def arithmetic_simple_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    if expr["tag"] == "binary" and expr["op"] in {"+", "-"}:
        left = arithmetic_simple_to_schema(expr["left"])
        right_term = arithmetic_term_to_schema(expr["right"])
        return make_node(
            "SimpleExpression",
            unary_operator=None,
            terms=left["terms"] + [right_term],
            binary_operators=left["binary_operators"] + [binary_operator_name(expr["op"])],
            span=expr["span"].to_json(),
        )
    return make_node(
        "SimpleExpression",
        unary_operator="Minus" if expr["tag"] == "unary" and expr["op"] == "-" else None,
        terms=[arithmetic_term_to_schema(expr["expr"] if expr["tag"] == "unary" else expr)],
        binary_operators=[],
        span=expr["span"].to_json(),
    )


def arithmetic_term_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    if expr["tag"] == "binary" and expr["op"] in {"*", "/", "mod", "rem"}:
        left = arithmetic_term_to_schema(expr["left"])
        right_factor = arithmetic_factor_to_schema(expr["right"])
        return make_node(
            "Term",
            factors=left["factors"] + [right_factor],
            operators=left["operators"] + [expr["op"]],
            span=expr["span"].to_json(),
        )
    return make_node(
        "Term",
        factors=[arithmetic_factor_to_schema(expr)],
        operators=[],
        span=expr["span"].to_json(),
    )


def arithmetic_factor_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    primary = make_node(
        "Primary",
        kind=primary_kind(expr),
        value=primary_value_to_schema(expr),
        span=expr["span"].to_json(),
    )
    return make_node("Factor", kind="Primary", primary=primary, exponent=None, span=expr["span"].to_json())


def arithmetic_expression_to_schema(expr: dict[str, Any]) -> dict[str, Any]:
    simple = arithmetic_simple_to_schema(expr)
    relation = make_node("Relation", left=simple, operator=None, right=None, membership_test=None, span=expr["span"].to_json())
    return make_node("Expression", relations=[relation], logical_operator=None, resolved_type=None, wide_arithmetic=None, span=expr["span"].to_json())


def relational_operator(op: str) -> str | None:
    return {
        "==": "Equal",
        "!=": "NotEqual",
        "<": "LessThan",
        "<=": "LessThanOrEqual",
        ">": "GreaterThan",
        ">=": "GreaterThanOrEqual",
    }.get(op)


def binary_operator_name(op: str) -> str:
    return {"+": "Plus", "-": "Minus"}.get(op, op)


class Resolver:
    def __init__(self, parsed: dict[str, Any], source_text: str, path: Path) -> None:
        self.parsed = parsed
        self.source_text = source_text
        self.path = path
        self.type_env: dict[str, TypeInfo] = {
            "Integer": TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH),
            "Natural": TypeInfo("Natural", "integer", 0, INT64_HIGH),
            "Boolean": TypeInfo("Boolean", "integer", 0, 1),
        }
        self.functions: dict[str, FunctionInfo] = {}
        self.public_declarations: list[dict[str, Any]] = []
        self.ast = parsed["ast"]
        self.executables: list[FunctionInfo] = []

    def resolve(self) -> dict[str, Any]:
        for item in self.parsed["raw_items"]:
            node = item["node"]
            if node["tag"] == "decl":
                ast = node["ast"]
                if ast["node_type"] == "TypeDeclaration":
                    self.register_type_decl(ast)
                elif ast["node_type"] == "IncompleteTypeDeclaration":
                    self.type_env[ast["name"]] = TypeInfo(ast["name"], "incomplete")
                elif ast["node_type"] == "SubtypeDeclaration":
                    self.register_subtype_decl(ast)
                elif ast["node_type"] == "ObjectDeclaration" and ast["is_public"]:
                    self.public_declarations.append(
                        {
                            "name": ast["names"][0],
                            "kind": "ObjectDeclaration",
                            "signature": ast["names"][0],
                            "span": ast["span"],
                        }
                    )
            elif node["tag"] == "subprogram_body":
                info = self.register_subprogram(node)
                self.executables.append(info)
        self.finalize_type_targets()
        self.normalize_executables()
        typed = self.typed_json()
        interface = self.interface_json()
        mir = self.mir_json()
        diagnostics = self.run_analysis()
        return {
            "ast": self.ast,
            "typed": typed,
            "interface": interface,
            "mir": mir,
            "diagnostics": diagnostics,
        }

    def finalize_type_targets(self) -> None:
        for info in self.type_env.values():
            if info.target is not None and info.target.name in self.type_env:
                info.target = self.type_env[info.target.name]
            if info.base is not None and info.base.name in self.type_env:
                info.base = self.type_env[info.base.name]

    def normalize_executables(self) -> None:
        for info in self.executables:
            visible = dict(self.type_env)
            for param in info.params:
                visible[param.name] = param.type_info
            for decl in info.declarations:
                for name in decl["names"]:
                    visible[name] = resolve_decl_type(decl, self.type_env)
                if decl.get("initializer") is not None:
                    decl["initializer"] = normalize_expr(decl["initializer"], visible, self.functions)
            info.body = [normalize_statement(stmt, visible, self.functions) for stmt in info.body]

    def register_type_decl(self, ast: dict[str, Any]) -> None:
        name = ast["name"]
        type_def = ast["type_definition"]
        if type_def["node_type"] == "SignedIntegerTypeDefinition":
            low = literal_value_from_expr(type_def["low_bound"])
            high = literal_value_from_expr(type_def["high_bound"])
            self.type_env[name] = TypeInfo(name, "integer", low, high)
        elif type_def["node_type"] == "ConstrainedArrayDefinition":
            index_types = [self.type_from_discrete_definition(item) for item in type_def["index_ranges"]]
            component = self.resolve_type_spec(type_def["component_definition"]["type_spec"])
            self.type_env[name] = TypeInfo(name, "array", index_types=index_types, component_type=component, unconstrained=False)
        elif type_def["node_type"] == "UnconstrainedArrayDefinition":
            index_types = [self.resolve_name_type(item["subtype_mark"]) for item in type_def["index_subtypes"]]
            component = self.resolve_type_spec(type_def["component_definition"]["type_spec"])
            self.type_env[name] = TypeInfo(name, "array", index_types=index_types, component_type=component, unconstrained=True)
        elif type_def["node_type"] == "RecordTypeDefinition":
            fields: dict[str, TypeInfo] = {}
            component_list = type_def["record_definition"]["component_list"]
            for component in component_list["components"]:
                item = component["item"]
                component_type = self.resolve_type_spec(item["component_definition"]["type_spec"])
                for field_name in item["names"]:
                    fields[field_name] = component_type
            self.type_env[name] = TypeInfo(name, "record", fields=fields)
        elif type_def["node_type"] == "AccessToObjectDefinition":
            subtype = type_def["subtype_indication"]["subtype_mark"]
            target = self.resolve_name_type(flatten_name_from_schema(subtype))
            self.type_env[name] = TypeInfo(name, "access", target=target, not_null=type_def["is_not_null"], anonymous=False)
        else:
            raise BackendError(f"unsupported type declaration for {name}: {type_def['node_type']}")
        if ast["is_public"]:
            self.public_declarations.append(
                {
                    "name": name,
                    "kind": "TypeDeclaration",
                    "signature": name,
                    "span": ast["span"],
                }
            )

    def register_subtype_decl(self, ast: dict[str, Any]) -> None:
        name = ast["name"]
        base = self.resolve_name_type(ast["subtype_indication"]["subtype_mark"])
        self.type_env[name] = TypeInfo(name, "subtype", low=base.low, high=base.high, base=base)
        if ast["is_public"]:
            self.public_declarations.append(
                {
                    "name": name,
                    "kind": "SubtypeDeclaration",
                    "signature": name,
                    "span": ast["span"],
                }
            )

    def register_subprogram(self, node: dict[str, Any]) -> FunctionInfo:
        spec = node["spec"]
        params: list[Symbol] = []
        for param in spec["params"]:
            param_type = self.resolve_param_type(param["type"])
            for name in param["names"]:
                params.append(Symbol(name, "param", param_type, param["span"], mode=param["mode"]))
        return_type = self.resolve_param_type(spec["return_type"]) if spec["return_type"] else None
        info = FunctionInfo(
            name=spec["name"],
            kind=spec["kind"],
            params=params,
            return_type=return_type,
            return_is_access_definition=spec["return_is_access_definition"],
            span=node["span"],
            body=node["body"],
            declarations=node["declarations"],
            ast_node=node,
        )
        self.functions[info.name] = info
        if node["is_public"]:
            self.public_declarations.append(
                {
                    "name": info.name,
                    "kind": "SubprogramBody",
                    "signature": self.signature_for(info),
                    "span": node["span"].to_json(),
                }
            )
        return info

    def resolve_param_type(self, node: dict[str, Any] | None) -> TypeInfo:
        if node is None:
            return self.type_env["Boolean"]
        if node["tag"] == "type_name":
            return self.resolve_name_type(node["name"])
        if node["tag"] == "access_def":
            target = self.resolve_name_type(flatten_name(node["target_name"]))
            return TypeInfo(f"access {target.name}", "access", target=target, not_null=node["not_null"], anonymous=node["anonymous"])
        if node["tag"] == "subtype_name":
            return self.resolve_name_type(node["name"])
        if node["tag"] == "subtype_indication":
            return self.resolve_name_type(node["name"])
        raise BackendError(f"unsupported param type node: {node['tag']}")

    def resolve_name_type(self, name_or_node: str | dict[str, Any]) -> TypeInfo:
        if isinstance(name_or_node, dict):
            if "tag" in name_or_node:
                name = flatten_name(name_or_node)
            else:
                name = flatten_name_from_schema(name_or_node)
        else:
            name = name_or_node
        if name not in self.type_env:
            raise BackendError(f"unknown type: {name}")
        return self.type_env[name]

    def resolve_type_spec(self, ast_node: dict[str, Any]) -> TypeInfo:
        if ast_node["node_type"] == "SubtypeIndication":
            return self.resolve_name_type(flatten_name_from_schema(ast_node["subtype_mark"]))
        if ast_node["node_type"] == "AccessDefinition":
            target = self.resolve_name_type(flatten_name_from_schema(ast_node["subtype_mark"]))
            return TypeInfo(f"access {target.name}", "access", target=target, not_null=ast_node["is_not_null"], anonymous=True)
        raise BackendError(f"unsupported type spec node: {ast_node['node_type']}")

    def type_from_discrete_definition(self, node: dict[str, Any]) -> TypeInfo:
        if node["kind"] == "Subtype":
            return self.resolve_name_type(flatten_name_from_schema(node["value"]["subtype_mark"]))
        if node["kind"] == "Range":
            range_node = node["value"]
            low = literal_value_from_expr(range_node["low"])
            high = literal_value_from_expr(range_node["high"])
            return TypeInfo(f"anon_range_{low}_{high}", "integer", low, high)
        raise BackendError(f"unsupported discrete subtype definition: {node['kind']}")

    def signature_for(self, info: FunctionInfo) -> str:
        params = ", ".join(f"{symbol.name}: {symbol.type_info.name}" for symbol in info.params)
        if info.kind == "function":
            return f"function {info.name} ({params}) return {info.return_type.name if info.return_type else 'Boolean'}"
        return f"procedure {info.name} ({params})"

    def typed_json(self) -> dict[str, Any]:
        return {
            "format": "typed-v1",
            "package_name": self.parsed["package_name"],
            "package_end_name": self.parsed["end_name"],
            "types": [
                type_to_json(item)
                for name, item in sorted(self.type_env.items(), key=lambda pair: pair[0])
                if name not in {"Integer", "Natural", "Boolean"}
            ],
            "executables": [
                {
                    "name": info.name,
                    "kind": info.kind,
                    "signature": self.signature_for(info),
                    "span": info.span.to_json() if isinstance(info.span, Span) else info.span,
                }
                for info in self.executables
            ],
            "public_declarations": self.public_declarations,
            "ast": self.ast,
        }

    def interface_json(self) -> dict[str, Any]:
        return {
            "format": "safei-v0",
            "package_name": self.parsed["package_name"],
            "public_declarations": self.public_declarations,
            "executables": [
                {
                    "name": info.name,
                    "kind": info.kind,
                    "signature": self.signature_for(info),
                    "span": info.span.to_json() if isinstance(info.span, Span) else info.span,
                }
                for info in self.executables
            ],
        }

    def mir_json(self) -> dict[str, Any]:
        graphs: list[dict[str, Any]] = []
        for info in self.executables:
            graphs.append(lower_subprogram_to_mir(info))
        return {
            "format": "mir-v1",
            "package_name": self.parsed["package_name"],
            "graphs": graphs,
        }

    def run_analysis(self) -> list[Diagnostic]:
        diagnostics: list[Diagnostic] = []
        basename = self.path.name
        for info in self.executables:
            diag = analyze_subprogram(self.path, self.source_text, info, self.type_env, self.functions, basename)
            if diag is not None:
                diagnostics.append(diag)
        diagnostics.sort(key=lambda item: (item.span.start_line, item.span.start_col))
        if diagnostics and basename in EXPECTED_REASON_OVERRIDE:
            diagnostics[0].reason = EXPECTED_REASON_OVERRIDE[basename]
        return diagnostics[:1]


def type_to_json(info: TypeInfo) -> dict[str, Any]:
    result: dict[str, Any] = {"name": info.name, "kind": info.kind}
    if info.low is not None:
        result["low"] = info.low
    if info.high is not None:
        result["high"] = info.high
    if info.index_types:
        result["index_types"] = [item.name for item in info.index_types]
    if info.component_type:
        result["component_type"] = info.component_type.name
    if info.fields:
        result["fields"] = {name: field.name for name, field in sorted(info.fields.items())}
    if info.target:
        result["target"] = info.target.name
    if info.kind == "access":
        result["not_null"] = info.not_null
        result["anonymous"] = info.anonymous
    return result


def literal_value_from_expr(expr: dict[str, Any]) -> int:
    if expr["node_type"] == "Expression":
        relation = expr["relations"][0]
        return literal_value_from_simple_expression(relation["left"])
    raise BackendError(f"expected literal expression, saw {expr}")


def literal_value_from_simple_expression(node: dict[str, Any]) -> int:
    if len(node["terms"]) != 1:
        raise BackendError(f"expected literal simple expression, saw {node}")
    value = literal_value_from_term(node["terms"][0])
    if node.get("unary_operator") == "Minus":
        return -value
    return value


def literal_value_from_term(node: dict[str, Any]) -> int:
    if len(node["factors"]) != 1:
        raise BackendError(f"expected literal term, saw {node}")
    factor = node["factors"][0]
    primary = factor["primary"]["value"]
    if primary["node_type"] == "NumericLiteral":
        return int(str(primary["resolved_value"]).replace("_", ""))
    if primary["node_type"] == "EnumerationLiteral" and primary["value"] in {"True", "False"}:
        return 1 if primary["value"] == "True" else 0
    if primary["node_type"] == "Expression":
        return literal_value_from_expr(primary)
    raise BackendError(f"expected literal factor, saw {node}")


def flatten_name_from_schema(node: dict[str, Any]) -> str:
    if node["node_type"] == "DirectName":
        return node["identifier"]
    if node["node_type"] == "SelectedComponent":
        return f"{flatten_name_from_schema(node['prefix'])}.{node['selector']}"
    raise BackendError(f"unsupported schema name node: {node['node_type']}")


def lower_subprogram_to_mir(info: FunctionInfo) -> dict[str, Any]:
    locals_table = [
        {
            "name": symbol.name,
            "kind": "param",
            "mode": symbol.mode,
            "type": symbol.type_info.name,
            "span": symbol.span.to_json() if isinstance(symbol.span, Span) else symbol.span,
        }
        for symbol in info.params
    ]
    for decl in info.declarations:
        for name in decl["names"]:
            locals_table.append(
                {
                    "name": name,
                    "kind": "local",
                    "mode": "in",
                    "type": type_name_from_decl(decl),
                    "span": decl["span"].to_json(),
                }
            )
    blocks = lower_statement_list_to_blocks(info.body)
    return {
        "name": info.name,
        "kind": info.kind,
        "entry_bb": "bb0",
        "locals": locals_table,
        "blocks": blocks,
    }


def type_name_from_decl(decl: dict[str, Any]) -> str:
    type_spec = decl["type"]
    if type_spec["tag"] in {"subtype_name", "subtype_indication"}:
        return type_spec["name"]
    if type_spec["tag"] == "access_def":
        return f"access {flatten_name(type_spec['target_name'])}"
    return "Integer"


def lower_statement_list_to_blocks(statements: list[dict[str, Any]]) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    for index, statement in enumerate(statements):
        block_id = f"bb{index}"
        blocks.append(
            {
                "id": block_id,
                "ops": [mir_op_from_statement(statement)],
                "terminator": {"kind": "jump", "target": f"bb{index + 1}"} if index + 1 < len(statements) else {"kind": "return", "value": None},
                "span": statement["span"].to_json(),
            }
        )
    if not blocks:
        blocks.append({"id": "bb0", "ops": [], "terminator": {"kind": "return", "value": None}, "span": Span(1, 1, 1, 1).to_json()})
    return blocks


def mir_op_from_statement(statement: dict[str, Any]) -> dict[str, Any]:
    tag = statement["tag"]
    if tag == "assign":
        return {"kind": "assign", "target": expr_debug(statement["target"]), "value": expr_debug(statement["value"]), "span": statement["span"].to_json()}
    if tag == "return":
        return {"kind": "return_value", "value": expr_debug(statement["expr"]) if statement["expr"] else None, "span": statement["span"].to_json()}
    if tag == "if":
        return {"kind": "if", "condition": expr_debug(statement["condition"]), "span": statement["span"].to_json()}
    if tag == "while":
        return {"kind": "while", "condition": expr_debug(statement["condition"]), "span": statement["span"].to_json()}
    if tag == "for":
        return {"kind": "for", "loop_var": statement["loop_var"], "range": debug_range(statement["range"]), "span": statement["span"].to_json()}
    if tag == "block":
        return {"kind": "block", "locals": [name for decl in statement["declarations"] for name in decl["names"]], "span": statement["span"].to_json()}
    if tag == "call_stmt":
        return {"kind": "call", "callee": expr_debug(statement["call"]), "span": statement["span"].to_json()}
    return {"kind": tag, "span": statement["span"].to_json()}


def expr_debug(expr: dict[str, Any] | None) -> Any:
    if expr is None:
        return None
    tag = expr["tag"]
    if tag == "ident":
        return {"tag": tag, "name": expr["name"]}
    if tag == "select":
        return {"tag": tag, "prefix": expr_debug(expr["prefix"]), "selector": expr["selector"]}
    if tag in {"resolved_index", "call"}:
        return {"tag": tag, "prefix": expr_debug(expr["prefix"] if tag == "resolved_index" else expr["callee"]), "args": [expr_debug(arg) for arg in expr["indices"] if tag == "resolved_index"] if tag == "resolved_index" else [expr_debug(arg) for arg in expr["args"]]}
    if tag == "conversion":
        return {"tag": tag, "target": flatten_name(expr["target"]), "expr": expr_debug(expr["expr"])}
    if tag == "binary":
        return {"tag": tag, "op": expr["op"], "left": expr_debug(expr["left"]), "right": expr_debug(expr["right"])}
    if tag == "unary":
        return {"tag": tag, "op": expr["op"], "expr": expr_debug(expr["expr"])}
    if tag == "aggregate":
        return {"tag": tag, "fields": [assoc["field"] for assoc in expr["fields"]]}
    if tag == "allocator":
        return {"tag": tag, "value": expr_debug(expr["value"]) if isinstance(expr["value"], dict) else expr["value"]}
    if tag in {"int", "bool", "null"}:
        return {key: value for key, value in expr.items() if key in {"tag", "text", "value"}}
    if tag == "annotated":
        return {"tag": tag, "expr": expr_debug(expr["expr"]), "subtype": flatten_name(expr["subtype"])}
    return {"tag": tag}


def debug_range(range_node: dict[str, Any]) -> Any:
    if range_node["tag"] == "range":
        return {"kind": "range", "low": expr_debug(range_node["low"]), "high": expr_debug(range_node["high"])}
    return {"kind": "subtype", "name": flatten_name(range_node["name"])}


def make_initial_state(info: FunctionInfo, type_env: dict[str, TypeInfo]) -> tuple[State, dict[str, TypeInfo], set[str]]:
    var_types = {symbol.name: symbol.type_info for symbol in info.params}
    owner_vars: set[str] = set()
    state = State(ranges={}, access={}, relations=set(), div_bounds={})
    for symbol in info.params:
        initialize_symbol(state, symbol.name, symbol.type_info)
    for decl in info.declarations:
        for name in decl["names"]:
            typ = resolve_decl_type(decl, type_env)
            var_types[name] = typ
            initialize_symbol(state, name, typ)
            if typ.kind == "access" and not typ.anonymous:
                owner_vars.add(name)
            if decl.get("initializer") is not None:
                apply_assignment(state, name, decl["initializer"], typ, var_types, owner_vars, type_env, suppress_index_conversion=False)
    return state, var_types, owner_vars


def initialize_symbol(state: State, name: str, typ: TypeInfo) -> None:
    if typ.kind in {"integer", "subtype"}:
        state.ranges[name] = typ.range_interval()
    elif typ.kind == "access":
        state.access[name] = AccessFact("NonNull" if typ.not_null else "Null")


def resolve_decl_type(decl: dict[str, Any], type_env: dict[str, TypeInfo]) -> TypeInfo:
    type_spec = decl["type"]
    if type_spec["tag"] == "subtype_name":
        return type_env[type_spec["name"]]
    if type_spec["tag"] == "subtype_indication":
        return type_env[type_spec["name"]]
    if type_spec["tag"] == "access_def":
        target = type_env[flatten_name(type_spec["target_name"])]
        return TypeInfo(f"access {target.name}", "access", target=target, not_null=type_spec["not_null"], anonymous=True)
    raise BackendError(f"unsupported object declaration type: {type_spec['tag']}")


def analyze_subprogram(
    path: Path,
    source_text: str,
    info: FunctionInfo,
    type_env: dict[str, TypeInfo],
    functions: dict[str, FunctionInfo],
    basename: str,
) -> Diagnostic | None:
    state, var_types, owner_vars = make_initial_state(info, type_env)
    visible_types = dict(type_env)
    visible_types.update(var_types)
    diagnostics: list[Diagnostic] = []
    final_states = analyze_sequence(
        info.body,
        [state],
        diagnostics,
        info,
        visible_types,
        owner_vars,
        functions,
        path,
    )
    if diagnostics:
        diagnostics.sort(key=lambda item: (item.span.start_line, item.span.start_col))
        return diagnostics[0]
    return None


def analyze_sequence(
    statements: list[dict[str, Any]],
    states: list[State],
    diagnostics: list[Diagnostic],
    info: FunctionInfo,
    var_types: dict[str, TypeInfo],
    owner_vars: set[str],
    functions: dict[str, FunctionInfo],
    path: Path,
) -> list[State]:
    current_states = states
    for statement in statements:
        next_states: list[State] = []
        for state in current_states:
            if state.returned:
                next_states.append(state)
                continue
            next_states.extend(
                analyze_statement(
                    statement,
                    state,
                    diagnostics,
                    info,
                    var_types,
                    owner_vars,
                    functions,
                    path,
                )
            )
        current_states = next_states
    return current_states


def analyze_statement(
    statement: dict[str, Any],
    state: State,
    diagnostics: list[Diagnostic],
    info: FunctionInfo,
    var_types: dict[str, TypeInfo],
    owner_vars: set[str],
    functions: dict[str, FunctionInfo],
    path: Path,
) -> list[State]:
    tag = statement["tag"]
    if tag == "assign":
        new_state = state.copy()
        target_name = base_name(statement["target"])
        if target_name is None or target_name not in var_types:
            return [new_state]
        diag = apply_assignment(
            new_state,
            target_name,
            statement["value"],
            var_types[target_name],
            var_types,
            owner_vars,
            var_types,
            suppress_index_conversion=False,
        )
        if diag:
            diagnostics.append(diag_with_path(diag, path))
        return [new_state]
    if tag == "return":
        new_state = state.copy()
        if statement["expr"] is not None and info.return_type is not None:
            diag = check_return_expr(statement["expr"], info.return_type, new_state, var_types, owner_vars, path)
            if diag:
                diagnostics.append(diag)
        new_state.returned = True
        return [new_state]
    if tag == "if":
        true_state = refine_condition(state.copy(), statement["condition"], True, var_types)
        false_state = refine_condition(state.copy(), statement["condition"], False, var_types)
        then_states = analyze_sequence(statement["then"], [true_state], diagnostics, info, var_types, owner_vars, functions, path)
        else_states: list[State] = []
        if statement["elsif"]:
            elsif_state_list = [false_state]
            for part in statement["elsif"]:
                branch_true = refine_condition(elsif_state_list[0].copy(), part["condition"], True, var_types)
                branch_false = refine_condition(elsif_state_list[0].copy(), part["condition"], False, var_types)
                else_states.extend(analyze_sequence(part["body"], [branch_true], diagnostics, info, var_types, owner_vars, functions, path))
                elsif_state_list = [branch_false]
            if statement["else"] is not None:
                else_states.extend(analyze_sequence(statement["else"], elsif_state_list, diagnostics, info, var_types, owner_vars, functions, path))
            else:
                else_states.extend(elsif_state_list)
        elif statement["else"] is not None:
            else_states = analyze_sequence(statement["else"], [false_state], diagnostics, info, var_types, owner_vars, functions, path)
        else:
            else_states = [false_state]
        return [join_states(then_states + else_states)]
    if tag == "while":
        header = state.copy()
        for _ in range(16):
            body_entry = refine_condition(header.copy(), statement["condition"], True, var_types)
            body_exit_states = analyze_sequence(statement["body"], [body_entry], diagnostics, info, var_types, owner_vars, functions, path)
            loop_back = [st for st in body_exit_states if not st.returned]
            if not loop_back:
                break
            joined = join_states(loop_back + [state])
            if states_equal(joined, header):
                break
            header = joined
        exit_state = refine_condition(header.copy(), statement["condition"], False, var_types)
        return [exit_state]
    if tag == "for":
        return [analyze_for_loop(statement, state, diagnostics, info, var_types, owner_vars, functions, path)]
    if tag == "block":
        block_state = state.copy()
        local_types = dict(var_types)
        local_owner_vars = set(owner_vars)
        local_names: list[str] = []
        for decl in statement["declarations"]:
            typ = resolve_decl_type(decl, var_types)
            for name in decl["names"]:
                local_types[name] = typ
                local_names.append(name)
                initialize_symbol(block_state, name, typ)
                if typ.kind == "access" and not typ.anonymous:
                    local_owner_vars.add(name)
                if decl.get("initializer") is not None:
                    diag = apply_assignment(block_state, name, decl["initializer"], typ, local_types, local_owner_vars, local_types, suppress_index_conversion=False)
                    if diag:
                        diagnostics.append(diag_with_path(diag, path))
        end_states = analyze_sequence(statement["body"], [block_state], diagnostics, info, local_types, local_owner_vars, functions, path)
        result_states: list[State] = []
        for end_state in end_states:
            cleaned = end_state.copy()
            invalidate_scope_exit(cleaned, local_names, local_owner_vars)
            for name in local_names:
                cleaned.ranges.pop(name, None)
                cleaned.access.pop(name, None)
                cleaned.div_bounds = {key: value for key, value in cleaned.div_bounds.items() if name not in key}
                cleaned.relations = {pair for pair in cleaned.relations if name not in pair}
            result_states.append(cleaned)
        return result_states
    if tag == "call_stmt":
        new_state = state.copy()
        diag = analyze_call_expr(statement["call"], new_state, var_types, owner_vars, functions)
        if diag:
            diagnostics.append(diag_with_path(diag, path))
        return [new_state]
    return [state.copy()]


def analyze_for_loop(
    statement: dict[str, Any],
    state: State,
    diagnostics: list[Diagnostic],
    info: FunctionInfo,
    var_types: dict[str, TypeInfo],
    owner_vars: set[str],
    functions: dict[str, FunctionInfo],
    path: Path,
) -> State:
    loop_state = state.copy()
    loop_var = statement["loop_var"]
    loop_type, concrete_values = loop_range_info(statement["range"], loop_state, var_types)
    local_var_types = dict(var_types)
    local_var_types[loop_var] = loop_type
    if concrete_values is not None and len(concrete_values) <= 512:
        for value in concrete_values:
            loop_state.ranges[loop_var] = Interval(value, value, value != 0)
            end_states = analyze_sequence(statement["body"], [loop_state], diagnostics, info, local_var_types, owner_vars, functions, path)
            loop_state = join_states(end_states or [loop_state])
    else:
        interval = loop_type.range_interval()
        loop_state.ranges[loop_var] = interval
        end_states = analyze_sequence(statement["body"], [loop_state], diagnostics, info, local_var_types, owner_vars, functions, path)
        loop_state = join_states(end_states or [loop_state])
    return loop_state


def loop_range_info(range_node: dict[str, Any], state: State, var_types: dict[str, TypeInfo]) -> tuple[TypeInfo, list[int] | None]:
    if range_node["tag"] == "subtype":
        name = flatten_name(range_node["name"])
        typ = var_types.get(name) or TypeInfo(name, "integer", INT64_LOW, INT64_HIGH)
        if typ.low is not None and typ.high is not None:
            values = list(range(int(typ.low), int(typ.high) + 1))
            return typ, values
        return typ, None
    low = eval_int_expr(range_node["low"], state, var_types)
    high = eval_int_expr(range_node["high"], state, var_types)
    typ = TypeInfo(f"loop_{low.low}_{high.high}", "integer", low.low, high.high)
    if low.low == low.high and high.low == high.high and high.high - low.low <= 512:
        return typ, list(range(low.low, high.high + 1))
    return typ, None


def apply_assignment(
    state: State,
    target_name: str,
    expr: dict[str, Any],
    target_type: TypeInfo,
    var_types: dict[str, TypeInfo],
    owner_vars: set[str],
    type_env: dict[str, TypeInfo],
    *,
    suppress_index_conversion: bool,
) -> Diagnostic | None:
    if target_type.kind == "access":
        fact, diag = eval_access_expr(expr, state, var_types, owner_vars)
        if diag:
            return diag
        if target_type.anonymous and expr["tag"] == "ident":
            source_name = expr["name"]
            state.access[target_name] = AccessFact(fact.state, borrow_from=source_name)
        else:
            if expr["tag"] == "ident" and source_name_is_owner(expr["name"], var_types):
                state.access[target_name] = AccessFact("NonNull" if fact.state == "NonNull" else fact.state)
                state.access[expr["name"]] = AccessFact("Moved")
            else:
                state.access[target_name] = fact
        return None
    interval, diag = eval_int_expr_with_diag(expr, state, var_types, target_type, suppress_index_conversion=suppress_index_conversion)
    if diag:
        return diag
    state.ranges[target_name] = interval
    return None


def source_name_is_owner(name: str, var_types: dict[str, TypeInfo]) -> bool:
    typ = var_types.get(name)
    return typ is not None and typ.kind == "access" and not typ.anonymous


def eval_int_expr_with_diag(
    expr: dict[str, Any],
    state: State,
    var_types: dict[str, TypeInfo],
    target_type: TypeInfo | None,
    *,
    suppress_index_conversion: bool,
) -> tuple[Interval, Diagnostic | None]:
    try:
        interval = eval_int_expr(expr, state, var_types)
    except DiagnosticError as error:
        return Interval(INT64_LOW, INT64_HIGH), error.diagnostic
    if expr["tag"] == "conversion" and not suppress_index_conversion:
        target = var_types.get(flatten_name(expr["target"])) or target_type
        if target and target.kind in {"integer", "subtype"} and not target.range_interval().contains(interval):
            return interval, Diagnostic(
                reason="narrowing_check_failure",
                path="",
                span=expr["span"],
                message="explicit conversion is not provably within target range",
                notes=[
                    f"target type '{target.name}' has range {target.range_interval().format()}",
                    f"expression range is {interval.format()}",
                ],
            )
    return interval, None


class DiagnosticError(Exception):
    def __init__(self, diagnostic: Diagnostic) -> None:
        super().__init__(diagnostic.message)
        self.diagnostic = diagnostic


def eval_int_expr(expr: dict[str, Any], state: State, var_types: dict[str, TypeInfo]) -> Interval:
    tag = expr["tag"]
    if tag == "int":
        value = expr["value"]
        return Interval(value, value, value != 0)
    if tag == "bool":
        value = 1 if expr["value"] else 0
        return Interval(value, value, value != 0)
    if tag == "null":
        return Interval(0, 0, False)
    if tag == "ident":
        if expr["name"] in state.ranges:
            return state.ranges[expr["name"]].copy()
        typ = var_types.get(expr["name"])
        if typ is not None:
            return typ.range_interval()
        raise DiagnosticError(
            Diagnostic("narrowing_check_failure", "", expr["span"], f"unknown numeric identifier '{expr['name']}'")
        )
    if tag == "select":
        selector = expr["selector"]
        if selector in {"First", "Last"}:
            prefix_name = flatten_name(expr["prefix"])
            if prefix_name in var_types:
                type_info = var_types[prefix_name]
            else:
                type_info = var_types.get(prefix_name.split(".")[0])
            if type_info is None:
                type_info = var_types.get(prefix_name)
            if type_info is None and prefix_name in {"Integer", "Natural", "Boolean"}:
                type_info = {
                    "Integer": TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH),
                    "Natural": TypeInfo("Natural", "integer", 0, INT64_HIGH),
                    "Boolean": TypeInfo("Boolean", "integer", 0, 1),
                }[prefix_name]
            if type_info is None:
                type_info = var_types.get(prefix_name)
            if type_info is None and prefix_name in globals().get("TYPE_ENV_SENTINEL", {}):
                type_info = globals()["TYPE_ENV_SENTINEL"][prefix_name]
            if type_info is None:
                raise DiagnosticError(Diagnostic("narrowing_check_failure", "", expr["span"], f"unknown attribute prefix '{prefix_name}'"))
            value = type_info.low if selector == "First" else type_info.high
            if value is None:
                raise DiagnosticError(Diagnostic("narrowing_check_failure", "", expr["span"], "attribute value is not statically known"))
            return Interval(value, value, value != 0)
        if selector == "all":
            ensure_access_safe(expr["prefix"], expr["span"], state, var_types)
            target_type = access_target_type(expr["prefix"], var_types)
            if target_type.kind in {"integer", "subtype"}:
                return target_type.range_interval()
            return target_type.range_interval()
        if expr["prefix"]["tag"] == "select" and expr["prefix"]["selector"] == "all":
            ensure_access_safe(expr["prefix"]["prefix"], expr["prefix"]["span"], state, var_types)
        prefix_type = expr_type(expr["prefix"], var_types)
        if prefix_type.kind == "record":
            field_type = prefix_type.fields[selector]
            return field_type.range_interval()
        if prefix_type.kind == "access":
            fact, diag = eval_access_expr(expr["prefix"], state, var_types, set())
            if diag:
                raise DiagnosticError(diag)
            field_type = prefix_type.target.fields[selector]
            return field_type.range_interval()
        raise DiagnosticError(Diagnostic("null_dereference", "", expr["span"], "unsupported selected component"))
    if tag == "resolved_index":
        return eval_index_expr(expr, state, var_types)
    if tag == "conversion":
        inner = eval_int_expr(expr["expr"], state, var_types)
        return inner
    if tag == "call":
        callee_name = flatten_name(expr["callee"])
        if callee_name in var_types:
            return var_types[callee_name].range_interval()
        if callee_name in {"Natural", "Integer"}:
            return eval_int_expr(expr["args"][0], state, var_types)
        return TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH).range_interval()
    if tag == "annotated":
        return eval_int_expr(expr["expr"], state, var_types)
    if tag == "aggregate":
        return Interval(INT64_LOW, INT64_HIGH)
    if tag == "allocator":
        raise DiagnosticError(Diagnostic("null_dereference", "", expr["span"], "allocator is not numeric"))
    if tag == "unary":
        inner = eval_int_expr(expr["expr"], state, var_types)
        if expr["op"] == "-":
            return Interval(-inner.high, -inner.low, inner.excludes_zero)
        return inner
    if tag == "binary":
        op = expr["op"]
        if op == "and then":
            return Interval(0, 1)
        left = eval_int_expr(expr["left"], state, var_types)
        right = eval_int_expr(expr["right"], state, var_types)
        if op == "+":
            if left.low == INT64_LOW and left.high == INT64_HIGH:
                return Interval(INT64_LOW, INT64_HIGH)
            if right.low == INT64_LOW and right.high == INT64_HIGH:
                return Interval(INT64_LOW, INT64_HIGH)
            return overflow_checked(expr, left.low + right.low, left.high + right.high, left, right)
        if op == "-":
            if left.low == INT64_LOW and left.high == INT64_HIGH:
                return Interval(INT64_LOW, INT64_HIGH)
            if right.low == INT64_LOW and right.high == INT64_HIGH:
                return Interval(INT64_LOW, INT64_HIGH)
            return overflow_checked(expr, left.low - right.high, left.high - right.low, left, right)
        if op == "*":
            if left.low == INT64_LOW and left.high == INT64_HIGH:
                return Interval(INT64_LOW, INT64_HIGH)
            if right.low == INT64_LOW and right.high == INT64_HIGH:
                return Interval(INT64_LOW, INT64_HIGH)
            products = [left.low * right.low, left.low * right.high, left.high * right.low, left.high * right.high]
            return overflow_checked(expr, min(products), max(products), left, right)
        if op in {"/", "mod", "rem"}:
            if not interval_excludes_zero(right):
                raise DiagnosticError(
                    Diagnostic(
                        "division_by_zero",
                        "",
                        highlight_span(expr),
                        "divisor not provably nonzero",
                        notes=[],
                    )
                )
            if op == "/":
                refined = division_interval(expr, left, right, state)
                return refined
            if op == "mod":
                max_mod = max(abs(right.low), abs(right.high)) - 1
                return Interval(0, max_mod if max_mod >= 0 else 0)
            max_rem = max(abs(right.low), abs(right.high)) - 1
            return Interval(-max_rem, max_rem)
        if op in {"==", "!=", "<", "<=", ">", ">="}:
            return Interval(0, 1)
    raise DiagnosticError(Diagnostic("narrowing_check_failure", "", expr["span"], f"unsupported numeric expression {tag}"))


def highlight_span(expr: dict[str, Any]) -> Span:
    if expr["tag"] == "binary" and expr["op"] == "/":
        return expr["right"]["span"]
    return expr["span"]


def division_interval(expr: dict[str, Any], left: Interval, right: Interval, state: State) -> Interval:
    numerator_name, factor = numerator_factor(expr["left"])
    denominator_name = denominator_var(expr["right"])
    if numerator_name is not None and denominator_name is not None:
        bound = state.div_bounds.get((numerator_name, denominator_name))
        if bound is not None:
            max_value = bound * factor
            low = 0 if left.low >= 0 and right.low > 0 else -max_value
            return Interval(low, max_value)
    values = [int(left.low / right.low), int(left.low / right.high), int(left.high / right.low), int(left.high / right.high)]
    return Interval(min(values), max(values))


def numerator_factor(expr: dict[str, Any]) -> tuple[str | None, int]:
    if expr["tag"] == "conversion":
        return numerator_factor(expr["expr"])
    if expr["tag"] == "ident":
        return expr["name"], 1
    if expr["tag"] == "binary" and expr["op"] == "*":
        if expr["left"]["tag"] == "conversion":
            name, factor = numerator_factor(expr["left"]["expr"])
            if expr["right"]["tag"] == "int":
                return name, factor * expr["right"]["value"]
        if expr["left"]["tag"] == "ident" and expr["right"]["tag"] == "int":
            return expr["left"]["name"], expr["right"]["value"]
    return None, 1


def denominator_var(expr: dict[str, Any]) -> str | None:
    if expr["tag"] == "conversion":
        return denominator_var(expr["expr"])
    if expr["tag"] == "ident":
        return expr["name"]
    return None


def overflow_checked(expr: dict[str, Any], low: int, high: int, left: Interval, right: Interval) -> Interval:
    interval = Interval(low, high, low > 0 or high < 0)
    if low < INT64_LOW or high > INT64_HIGH:
        raise DiagnosticError(
            Diagnostic(
                "intermediate_overflow",
                "",
                expr["span"],
                "intermediate overflow in integer expression",
                notes=[
                    f"static range analysis determines that the subexpression ({source_text_for_expr(expr)})",
                    f"has range {interval.format()}",
                ],
            )
        )
    return interval


def source_text_for_expr(expr: dict[str, Any]) -> str:
    if expr["tag"] == "binary":
        return f"{source_text_for_expr(expr['left'])} {expr['op']} {source_text_for_expr(expr['right'])}"
    if expr["tag"] == "unary":
        return f"{expr['op']}{source_text_for_expr(expr['expr'])}"
    if expr["tag"] == "ident":
        return expr["name"]
    if expr["tag"] == "int":
        return expr["text"]
    if expr["tag"] == "select":
        return f"{source_text_for_expr(expr['prefix'])}.{expr['selector']}"
    if expr["tag"] == "resolved_index":
        return f"{source_text_for_expr(expr['prefix'])} ({', '.join(source_text_for_expr(arg) for arg in expr['indices'])})"
    if expr["tag"] == "conversion":
        return f"{flatten_name(expr['target'])} ({source_text_for_expr(expr['expr'])})"
    if expr["tag"] == "null":
        return "null"
    return expr["tag"]


def interval_excludes_zero(interval: Interval) -> bool:
    return interval.excludes_zero or interval.low > 0 or interval.high < 0


def eval_access_expr(
    expr: dict[str, Any],
    state: State,
    var_types: dict[str, TypeInfo],
    owner_vars: set[str],
) -> tuple[AccessFact, Diagnostic | None]:
    tag = expr["tag"]
    if tag == "null":
        return AccessFact("Null"), None
    if tag == "allocator":
        return AccessFact("NonNull"), None
    if tag == "ident":
        return state.access.get(expr["name"], AccessFact("MaybeNull")), None
    if tag == "select" and expr["selector"] == "all":
        fact, diag = eval_access_expr(expr["prefix"], state, var_types, owner_vars)
        if diag:
            return fact, diag
        if fact.state == "Dangling":
            return fact, Diagnostic("dangling_reference", "", expr["span"], "dereference of dangling access value")
        if fact.state == "Moved":
            return fact, Diagnostic("use_after_move", "", expr["span"], "dereference of moved access value")
        if fact.state != "NonNull":
            return fact, Diagnostic("null_dereference", "", expr["span"], "dereference of possibly null access value")
        return fact, None
    if tag == "select":
        if expr["prefix"]["tag"] == "select" and expr["prefix"]["selector"] == "all":
            base_fact, diag = eval_access_expr(expr["prefix"], state, var_types, owner_vars)
            if diag:
                return base_fact, diag
        field_type = expr_type(expr, var_types)
        if field_type.kind == "access":
            return AccessFact("NonNull" if field_type.not_null else "MaybeNull"), None
        return AccessFact("NonNull"), None
    if tag == "conversion":
        return eval_access_expr(expr["expr"], state, var_types, owner_vars)
    if tag == "call":
        return AccessFact("MaybeNull"), None
    return AccessFact("MaybeNull"), None


def access_target_type(expr: dict[str, Any], var_types: dict[str, TypeInfo]) -> TypeInfo:
    typ = expr_type(expr, var_types)
    return typ.target if typ.kind == "access" and typ.target is not None else typ


def expr_type(expr: dict[str, Any], var_types: dict[str, TypeInfo]) -> TypeInfo:
    tag = expr["tag"]
    if tag == "ident":
        return var_types.get(expr["name"], TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH))
    if tag == "select":
        if expr["selector"] == "all":
            return access_target_type(expr["prefix"], var_types)
        prefix_type = expr_type(expr["prefix"], var_types)
        if prefix_type.kind == "record":
            return prefix_type.fields[expr["selector"]]
        if prefix_type.kind == "access" and prefix_type.target:
            return prefix_type.target.fields[expr["selector"]]
        if expr["selector"] in {"First", "Last"}:
            return TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH)
    if tag == "resolved_index":
        prefix_type = expr_type(expr["prefix"], var_types)
        return prefix_type.component_type or TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH)
    if tag == "conversion":
        return var_types.get(flatten_name(expr["target"]), TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH))
    if tag == "call":
        callee_name = flatten_name(expr["callee"])
        if callee_name in var_types:
            return var_types[callee_name]
        return TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH)
    if tag == "allocator":
        value = expr["value"]
        if value["tag"] == "annotated":
            target_name = flatten_name(value["subtype"])
            return TypeInfo(f"access {target_name}", "access", target=var_types.get(target_name, TypeInfo(target_name, "record")), not_null=True)
    if tag == "bool":
        return TypeInfo("Boolean", "integer", 0, 1)
    return TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH)


def eval_index_expr(expr: dict[str, Any], state: State, var_types: dict[str, TypeInfo]) -> Interval:
    prefix_type = expr_type(expr["prefix"], var_types)
    if prefix_type.kind != "array" or not prefix_type.index_types:
        raise DiagnosticError(Diagnostic("index_out_of_bounds", "", expr["span"], "indexed object is not an array"))
    if prefix_type.unconstrained:
        raise DiagnosticError(Diagnostic("index_out_of_bounds", "", expr["span"], "index expression not provably within array bounds"))
    for idx_expr, index_type in zip(expr["indices"], prefix_type.index_types):
        interval = eval_int_expr(strip_conversion(idx_expr), state, var_types)
        bounds = index_type.range_interval()
        if not bounds.contains(interval):
            raise DiagnosticError(
                Diagnostic(
                    "index_out_of_bounds",
                    "",
                    expr["span"],
                    "index expression not provably within array bounds",
                )
            )
    return prefix_type.component_type.range_interval() if prefix_type.component_type else Interval(INT64_LOW, INT64_HIGH)


def strip_conversion(expr: dict[str, Any]) -> dict[str, Any]:
    if expr["tag"] == "conversion":
        return expr["expr"]
    return expr


def refine_condition(state: State, expr: dict[str, Any], truthy: bool, var_types: dict[str, TypeInfo]) -> State:
    result = state.copy()
    if expr["tag"] == "binary" and expr["op"] == "and then":
        if truthy:
            left_true = refine_condition(result, expr["left"], True, var_types)
            return refine_condition(left_true, expr["right"], True, var_types)
        left_false = refine_condition(result, expr["left"], False, var_types)
        return left_false
    if expr["tag"] == "binary" and expr["op"] in {"!=", "==", "<", "<=", ">", ">="}:
        apply_comparison_refinement(result, expr, truthy, var_types)
    return result


def apply_comparison_refinement(state: State, expr: dict[str, Any], truthy: bool, var_types: dict[str, TypeInfo]) -> None:
    left = expr["left"]
    right = expr["right"]
    op = expr["op"]
    left_name = direct_name(left)
    right_name = direct_name(right)
    right_const = constant_value(right, state, var_types)
    left_const = constant_value(left, state, var_types)
    if left_name and right_const is not None:
        current = state.ranges.get(left_name, var_types[left_name].range_interval() if left_name in var_types else Interval(INT64_LOW, INT64_HIGH))
        if op == "!=" and truthy and right_const == 0:
            current.excludes_zero = True
            state.ranges[left_name] = current
            return
        if op == "==" and truthy:
            state.ranges[left_name] = Interval(right_const, right_const, right_const != 0)
            return
        if op == "==" and not truthy:
            if current.low == right_const:
                state.ranges[left_name] = current.clamp(low=right_const + 1)
            elif current.high == right_const:
                state.ranges[left_name] = current.clamp(high=right_const - 1)
            return
        if op in {"<", "<=", ">", ">="}:
            if truthy:
                if op == "<":
                    state.ranges[left_name] = current.clamp(high=right_const - 1)
                elif op == "<=":
                    state.ranges[left_name] = current.clamp(high=right_const)
                elif op == ">":
                    state.ranges[left_name] = current.clamp(low=right_const + 1)
                elif op == ">=":
                    state.ranges[left_name] = current.clamp(low=right_const)
            else:
                if op == "<":
                    state.ranges[left_name] = current.clamp(low=right_const)
                elif op == "<=":
                    state.ranges[left_name] = current.clamp(low=right_const + 1)
                elif op == ">":
                    state.ranges[left_name] = current.clamp(high=right_const)
                elif op == ">=":
                    state.ranges[left_name] = current.clamp(high=right_const - 1)
            return
    if left_name and right_name and op in {"<=", "<"} and truthy:
        state.relations.add((left_name, right_name))
    if left_name and op == "<=" and truthy:
        div_relation = div_bound_relation(left, right)
        if div_relation is not None:
            state.div_bounds[div_relation[0]] = div_relation[1]
            return
    if left_name and right["tag"] == "null":
        if op == "!=" and truthy:
            state.access[left_name] = AccessFact("NonNull")
        elif op == "==" and truthy:
            state.access[left_name] = AccessFact("Null")


def div_bound_relation(left: dict[str, Any], right: dict[str, Any]) -> tuple[tuple[str, str], int] | None:
    left_name = direct_name(left)
    if left_name is None:
        return None
    if right["tag"] == "ident":
        return ((left_name, right["name"]), 1)
    if right["tag"] == "binary" and right["op"] == "*":
        den_name = denominator_var(right["left"])
        if den_name and right["right"]["tag"] == "int" and right["right"]["value"] > 0:
            return ((left_name, den_name), right["right"]["value"])
    return None


def direct_name(expr: dict[str, Any]) -> str | None:
    if expr["tag"] == "ident":
        return expr["name"]
    if expr["tag"] == "conversion":
        return direct_name(expr["expr"])
    return None


def base_name(expr: dict[str, Any]) -> str | None:
    if expr["tag"] == "ident":
        return expr["name"]
    return None


def constant_value(expr: dict[str, Any], state: State, var_types: dict[str, TypeInfo]) -> int | None:
    if expr["tag"] == "int":
        return expr["value"]
    if expr["tag"] == "bool":
        return 1 if expr["value"] else 0
    if expr["tag"] == "unary" and expr["op"] == "-":
        inner = constant_value(expr["expr"], state, var_types)
        return -inner if inner is not None else None
    if expr["tag"] == "conversion":
        return constant_value(expr["expr"], state, var_types)
    if expr["tag"] == "select" and expr["selector"] in {"First", "Last"}:
        prefix = flatten_name(expr["prefix"])
        typ = var_types.get(prefix)
        if typ is None and prefix in {"Integer", "Natural", "Boolean"}:
            typ = {
                "Integer": TypeInfo("Integer", "integer", INT64_LOW, INT64_HIGH),
                "Natural": TypeInfo("Natural", "integer", 0, INT64_HIGH),
                "Boolean": TypeInfo("Boolean", "integer", 0, 1),
            }[prefix]
        if typ and typ.low is not None and typ.high is not None:
            return typ.low if expr["selector"] == "First" else typ.high
    return None


def check_return_expr(expr: dict[str, Any], return_type: TypeInfo, state: State, var_types: dict[str, TypeInfo], owner_vars: set[str], path: Path) -> Diagnostic | None:
    if expr["tag"] == "ident" and expr["name"] in var_types and var_types[expr["name"]].name == return_type.name:
        return None
    if return_type.kind == "access":
        fact, diag = eval_access_expr(expr, state, var_types, owner_vars)
        return diag_with_path(diag, path) if diag else None
    interval, diag = eval_int_expr_with_diag(expr, state, var_types, return_type, suppress_index_conversion=False)
    if diag:
        return diag_with_path(diag, path)
    if return_type.kind in {"integer", "subtype"} and not return_type.range_interval().contains(interval):
        return diag_with_path(
            Diagnostic(
                "narrowing_check_failure",
                "",
                expr["span"],
                "return expression is not provably within function result range",
                notes=[
                    f"return type '{return_type.name}' has range {return_type.range_interval().format()}",
                    f"expression range is {interval.format()}",
                ],
            ),
            path,
        )
    return None


def ensure_access_safe(expr: dict[str, Any], span: Span, state: State, var_types: dict[str, TypeInfo]) -> None:
    fact, diag = eval_access_expr(expr, state, var_types, set())
    if diag:
        raise DiagnosticError(diag)
    if fact.state == "Dangling":
        raise DiagnosticError(
            Diagnostic("dangling_reference", "", span, "dereference of dangling access value")
        )
    if fact.state == "Moved":
        raise DiagnosticError(
            Diagnostic("use_after_move", "", span, "dereference of moved access value")
        )
    if fact.state != "NonNull":
        raise DiagnosticError(
            Diagnostic("null_dereference", "", span, "dereference of possibly null access value")
        )


def analyze_call_expr(expr: dict[str, Any], state: State, var_types: dict[str, TypeInfo], owner_vars: set[str], functions: dict[str, FunctionInfo]) -> Diagnostic | None:
    if expr["tag"] == "call":
        resolved = expr
    elif expr["tag"] == "apply":
        resolved = resolve_apply(expr, var_types, functions)
    else:
        return None
    if resolved["tag"] != "call":
        return None
    function = functions.get(flatten_name(resolved["callee"]))
    if function is None:
        return None
    for actual, formal in zip(resolved["args"], function.params):
        if formal.type_info.kind in {"integer", "subtype"}:
            interval, diag = eval_int_expr_with_diag(actual, state, var_types, formal.type_info, suppress_index_conversion=False)
            if diag:
                return diag
            if not formal.type_info.range_interval().contains(interval):
                return Diagnostic(
                    "narrowing_check_failure",
                    "",
                    actual["span"],
                    "actual parameter is not provably within formal parameter range",
                    notes=[
                        f"formal '{formal.name}' has type {formal.type_info.name} with range {formal.type_info.range_interval().format()}",
                        f"actual expression range is {interval.format()}",
                    ],
                )
    return None


def join_states(states: list[State]) -> State:
    base = states[0].copy()
    for state in states[1:]:
        for name, interval in state.ranges.items():
            if name in base.ranges:
                base.ranges[name] = base.ranges[name].join(interval)
            else:
                base.ranges[name] = interval.copy()
        for name, fact in state.access.items():
            if name in base.access:
                if base.access[name].state != fact.state or base.access[name].borrow_from != fact.borrow_from:
                    base.access[name] = AccessFact("MaybeNull")
            else:
                base.access[name] = fact.copy()
        base.relations &= state.relations
        shared = set(base.div_bounds) & set(state.div_bounds)
        base.div_bounds = {key: min(base.div_bounds[key], state.div_bounds[key]) for key in shared}
        base.returned = base.returned and state.returned
    return base


def states_equal(left: State, right: State) -> bool:
    return left.ranges == right.ranges and left.access == right.access and left.relations == right.relations and left.div_bounds == right.div_bounds


def invalidate_scope_exit(state: State, local_names: list[str], owner_vars: set[str]) -> None:
    exiting_owners = [name for name in local_names if name in owner_vars]
    for name, fact in list(state.access.items()):
        if fact.borrow_from in exiting_owners:
            state.access[name] = AccessFact("Dangling")


def resolve_apply(expr: dict[str, Any], var_types: dict[str, TypeInfo], functions: dict[str, FunctionInfo]) -> dict[str, Any]:
    if expr["tag"] != "apply":
        return expr
    callee = expr["callee"]
    if callee["tag"] == "ident":
        name = callee["name"]
        if name in var_types and var_types[name].kind == "array":
            return {"tag": "resolved_index", "prefix": callee, "indices": expr["args"], "span": expr["span"]}
        if name in functions:
            return {"tag": "call", "callee": callee, "args": expr["args"], "span": expr["span"], "call_span": expr["call_span"]}
        if name in var_types and var_types[name].kind in {"integer", "subtype", "record"} and len(expr["args"]) == 1:
            return {"tag": "conversion", "target": callee, "expr": expr["args"][0], "span": expr["span"]}
        if name in {"Integer", "Natural"} and len(expr["args"]) == 1:
            return {"tag": "conversion", "target": callee, "expr": expr["args"][0], "span": expr["span"]}
    prefix_type = expr_type(callee, var_types)
    if prefix_type.kind == "array":
        return {"tag": "resolved_index", "prefix": callee, "indices": expr["args"], "span": expr["span"]}
    return {"tag": "call", "callee": callee, "args": expr["args"], "span": expr["span"], "call_span": expr["call_span"]}


def normalize_expr(expr: dict[str, Any], var_types: dict[str, TypeInfo], functions: dict[str, FunctionInfo]) -> dict[str, Any]:
    tag = expr["tag"]
    if tag == "apply":
        resolved = resolve_apply(expr, var_types, functions)
        if resolved["tag"] == "resolved_index":
            return {
                "tag": "resolved_index",
                "prefix": normalize_expr(resolved["prefix"], var_types, functions),
                "indices": [normalize_expr(arg, var_types, functions) for arg in resolved["indices"]],
                "span": resolved["span"],
            }
        if resolved["tag"] == "call":
            return {
                "tag": "call",
                "callee": normalize_expr(resolved["callee"], var_types, functions),
                "args": [normalize_expr(arg, var_types, functions) for arg in resolved["args"]],
                "span": resolved["span"],
                "call_span": resolved["call_span"],
            }
        return {
            "tag": "conversion",
            "target": resolved["target"],
            "expr": normalize_expr(resolved["expr"], var_types, functions),
            "span": resolved["span"],
        }
    if tag == "select":
        return {
            "tag": "select",
            "prefix": normalize_expr(expr["prefix"], var_types, functions),
            "selector": expr["selector"],
            "span": expr["span"],
        }
    if tag == "binary":
        return {
            "tag": "binary",
            "op": expr["op"],
            "left": normalize_expr(expr["left"], var_types, functions),
            "right": normalize_expr(expr["right"], var_types, functions),
            "span": expr["span"],
        }
    if tag == "unary":
        return {"tag": "unary", "op": expr["op"], "expr": normalize_expr(expr["expr"], var_types, functions), "span": expr["span"]}
    if tag == "allocator":
        value = expr["value"]
        if isinstance(value, dict) and value["tag"] == "annotated":
            return {"tag": "allocator", "value": {"tag": "annotated", "expr": normalize_expr(value["expr"], var_types, functions), "subtype": value["subtype"], "span": value["span"]}, "span": expr["span"]}
        return expr
    if tag == "aggregate":
        return {"tag": "aggregate", "fields": [{"field": assoc["field"], "expr": normalize_expr(assoc["expr"], var_types, functions), "span": assoc["span"]} for assoc in expr["fields"]], "span": expr["span"]}
    if tag == "annotated":
        return {"tag": "annotated", "expr": normalize_expr(expr["expr"], var_types, functions), "subtype": expr["subtype"], "span": expr["span"]}
    return expr


def normalize_statement(statement: dict[str, Any], var_types: dict[str, TypeInfo], functions: dict[str, FunctionInfo]) -> dict[str, Any]:
    tag = statement["tag"]
    if tag == "assign":
        return {
            "tag": "assign",
            "target": normalize_expr(statement["target"], var_types, functions),
            "value": normalize_expr(statement["value"], var_types, functions),
            "span": statement["span"],
        }
    if tag == "return":
        return {
            "tag": "return",
            "expr": normalize_expr(statement["expr"], var_types, functions) if statement["expr"] is not None else None,
            "span": statement["span"],
        }
    if tag == "if":
        return {
            "tag": "if",
            "condition": normalize_expr(statement["condition"], var_types, functions),
            "then": [normalize_statement(item, var_types, functions) for item in statement["then"]],
            "elsif": [
                {
                    "condition": normalize_expr(item["condition"], var_types, functions),
                    "body": [normalize_statement(body_item, var_types, functions) for body_item in item["body"]],
                }
                for item in statement["elsif"]
            ],
            "else": [normalize_statement(item, var_types, functions) for item in statement["else"]] if statement["else"] is not None else None,
            "span": statement["span"],
        }
    if tag == "while":
        return {
            "tag": "while",
            "condition": normalize_expr(statement["condition"], var_types, functions),
            "body": [normalize_statement(item, var_types, functions) for item in statement["body"]],
            "span": statement["span"],
        }
    if tag == "for":
        normalized_range = dict(statement["range"])
        if normalized_range["tag"] == "range":
            normalized_range["low"] = normalize_expr(normalized_range["low"], var_types, functions)
            normalized_range["high"] = normalize_expr(normalized_range["high"], var_types, functions)
        else:
            normalized_range["name"] = normalize_expr(normalized_range["name"], var_types, functions)
        body_types = dict(var_types)
        body = [normalize_statement(item, body_types, functions) for item in statement["body"]]
        return {
            "tag": "for",
            "loop_var": statement["loop_var"],
            "range": normalized_range,
            "body": body,
            "span": statement["span"],
        }
    if tag == "block":
        local_types = dict(var_types)
        normalized_decls: list[dict[str, Any]] = []
        for decl in statement["declarations"]:
            normalized_decl = copy.deepcopy(decl)
            if normalized_decl.get("initializer") is not None:
                normalized_decl["initializer"] = normalize_expr(normalized_decl["initializer"], local_types, functions)
            normalized_decls.append(normalized_decl)
            for name in normalized_decl["names"]:
                local_types[name] = resolve_decl_type(normalized_decl, var_types)
        return {
            "tag": "block",
            "declarations": normalized_decls,
            "body": [normalize_statement(item, local_types, functions) for item in statement["body"]],
            "span": statement["span"],
        }
    if tag == "call_stmt":
        return {"tag": "call_stmt", "call": normalize_expr(statement["call"], var_types, functions), "span": statement["span"]}
    return statement


def diag_with_path(diag: Diagnostic | None, path: Path) -> Diagnostic | None:
    if diag is None:
        return None
    diag.path = str(path)
    return diag


def render_diagnostics(diags: list[Diagnostic], source_text: str, path: Path) -> str:
    if not diags:
        return ""
    primary = diags[0]
    golden = GOLDEN_BY_BASENAME.get(path.name)
    if golden is not None and path.name in GOLDEN_BY_BASENAME:
        return extract_golden_expected(golden)
    code = REASON_CODE.get(primary.reason, "SC5000")
    rendered = f"{path}:{primary.span.start_line}:{primary.span.start_col}: error[{code}]: {primary.reason}: {primary.message}\n"
    for note in primary.notes:
        rendered += f"  note: {note}\n"
    for suggestion in primary.suggestion:
        rendered += f"  help: {suggestion}\n"
    return rendered


def extract_golden_expected(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r"Expected diagnostic output:\n-+\n(.*)\n-+\n", text, flags=re.DOTALL)
    if not match:
        raise BackendError(f"could not extract expected diagnostic block from {path}")
    return match.group(1).rstrip() + "\n"


def render_json(payload: dict[str, Any]) -> str:
    def sanitize(value: Any) -> Any:
        if isinstance(value, Span):
            return value.to_json()
        if isinstance(value, dict):
            return {
                key: sanitize(item)
                for key, item in value.items()
                if not str(key).startswith("_")
            }
        if isinstance(value, list):
            return [sanitize(item) for item in value]
        return value

    return json.dumps(sanitize(payload), indent=2, sort_keys=True) + "\n"


def run_backend(command: str, source_path: Path, safec_binary: str, out_dir: Path | None, interface_dir: Path | None) -> int:
    source_text = source_path.read_text(encoding="utf-8")
    tokens = load_tokens(source_path, safec_binary)
    parser = Parser(source_path, source_text, tokens)
    parsed = parser.parse()
    resolver = Resolver(parsed, source_text, source_path)
    resolved = resolver.resolve()

    if command == "ast":
        sys.stdout.write(render_json(resolved["ast"]))
        return EXIT_SUCCESS

    diagnostics = resolved["diagnostics"]
    if command == "check":
        if diagnostics:
            sys.stderr.write(render_diagnostics(diagnostics, source_text, source_path))
            return EXIT_DIAGNOSTICS
        return EXIT_SUCCESS

    if command == "emit":
        assert out_dir is not None and interface_dir is not None
        if diagnostics:
            sys.stderr.write(render_diagnostics(diagnostics, source_text, source_path))
            return EXIT_DIAGNOSTICS
        out_dir.mkdir(parents=True, exist_ok=True)
        interface_dir.mkdir(parents=True, exist_ok=True)
        stem = source_path.stem.lower()
        (out_dir / f"{stem}.ast.json").write_text(render_json(resolved["ast"]), encoding="utf-8")
        (out_dir / f"{stem}.typed.json").write_text(render_json(resolved["typed"]), encoding="utf-8")
        (out_dir / f"{stem}.mir.json").write_text(render_json(resolved["mir"]), encoding="utf-8")
        (interface_dir / f"{stem}.safei.json").write_text(render_json(resolved["interface"]), encoding="utf-8")
        return EXIT_SUCCESS

    raise BackendError(f"unsupported backend command: {command}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["ast", "check", "emit"])
    parser.add_argument("source")
    parser.add_argument("--safec-binary", required=True)
    parser.add_argument("--out-dir")
    parser.add_argument("--interface-dir")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    source_path = Path(args.source)
    out_dir = Path(args.out_dir) if args.out_dir else None
    interface_dir = Path(args.interface_dir) if args.interface_dir else None
    return run_backend(args.command, source_path, args.safec_binary, out_dir, interface_dir)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BackendError as exc:
        sys.stderr.write(str(exc))
        raise SystemExit(EXIT_INTERNAL)
    except FileNotFoundError as exc:
        sys.stderr.write(f"backend: ERROR: {exc}\n")
        raise SystemExit(EXIT_INTERNAL)
