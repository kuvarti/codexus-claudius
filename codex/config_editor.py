#!/usr/bin/env python3
"""Safely edit only the Codex TOML keys managed by claudius-sculptus."""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import tempfile
import tomllib
from typing import Any, Iterable


STATUS_PATHS = [("tui", "status_line")]
NOTIFICATION_PATHS = [
    ("notify",),
    ("tui", "notifications"),
    ("tui", "notification_condition"),
]


class ConfigEditError(RuntimeError):
    pass


def selected_paths(components: Iterable[str]) -> list[tuple[str, ...]]:
    paths: list[tuple[str, ...]] = []
    component_set = set(components)
    if "status-line" in component_set:
        paths.extend(STATUS_PATHS)
    if "notifications" in component_set:
        paths.extend(NOTIFICATION_PATHS)
    return paths


def get_nested(data: dict[str, Any], path: tuple[str, ...]) -> tuple[bool, Any]:
    current: Any = data
    for part in path:
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def parse_key_path(key_text: str) -> tuple[str, ...] | None:
    try:
        parsed = tomllib.loads(f"{key_text} = 0")
    except tomllib.TOMLDecodeError:
        return None

    path: list[str] = []
    current: Any = parsed
    while isinstance(current, dict) and len(current) == 1:
        key, current = next(iter(current.items()))
        path.append(key)
    return tuple(path) if current == 0 else None


def split_statements(text: str) -> list[tuple[int, int]]:
    """Split TOML into complete top-level statements, including multiline values."""

    spans: list[tuple[int, int]] = []
    start = 0
    square_depth = 0
    curly_depth = 0
    quote: str | None = None
    escaped = False
    comment = False
    index = 0

    while index < len(text):
        char = text[index]
        triple = text[index : index + 3]

        if comment:
            if char == "\n":
                comment = False
                if quote is None and square_depth == 0 and curly_depth == 0:
                    spans.append((start, index + 1))
                    start = index + 1
            index += 1
            continue

        if quote == '"""':
            if triple == '"""' and not escaped:
                quote = None
                index += 3
                continue
            if char == "\\" and not escaped:
                escaped = True
            else:
                escaped = False
            index += 1
            continue

        if quote == "'''":
            if triple == "'''":
                quote = None
                index += 3
            else:
                index += 1
            continue

        if quote == '"':
            if char == '"' and not escaped:
                quote = None
            if char == "\\" and not escaped:
                escaped = True
            else:
                escaped = False
            index += 1
            continue

        if quote == "'":
            if char == "'":
                quote = None
            index += 1
            continue

        if triple in {'"""', "'''"}:
            quote = triple
            escaped = False
            index += 3
            continue
        if char in {'"', "'"}:
            quote = char
            escaped = False
            index += 1
            continue
        if char == "#":
            comment = True
            index += 1
            continue
        if char == "[":
            square_depth += 1
        elif char == "]":
            square_depth = max(0, square_depth - 1)
        elif char == "{":
            curly_depth += 1
        elif char == "}":
            curly_depth = max(0, curly_depth - 1)
        elif char == "\n" and square_depth == 0 and curly_depth == 0:
            spans.append((start, index + 1))
            start = index + 1
        index += 1

    if start < len(text):
        spans.append((start, len(text)))
    return spans


def find_unquoted_equals(statement: str) -> int:
    quote: str | None = None
    escaped = False
    for index, char in enumerate(statement):
        if quote == '"':
            if char == '"' and not escaped:
                quote = None
            if char == "\\" and not escaped:
                escaped = True
            else:
                escaped = False
        elif quote == "'":
            if char == "'":
                quote = None
        elif char in {'"', "'"}:
            quote = char
        elif char == "=":
            return index
        elif char == "#":
            return -1
    return -1


def document_entries(text: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    assignments: list[dict[str, Any]] = []
    tables: list[dict[str, Any]] = []
    table_path: tuple[str, ...] = ()

    for start, end in split_statements(text):
        raw = text[start:end]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue

        array_table_match = re.match(r"^\[\[(.*?)\]\]\s*(?:#.*)?$", stripped, re.S)
        if array_table_match:
            parsed_path = parse_key_path(array_table_match.group(1).strip())
            if parsed_path is not None:
                table_path = parsed_path
            continue

        table_match = re.match(r"^\[(.*?)\]\s*(?:#.*)?$", stripped, re.S)
        if table_match:
            parsed_path = parse_key_path(table_match.group(1).strip())
            if parsed_path is not None:
                table_path = parsed_path
                tables.append({"path": table_path, "start": start, "end": end})
            continue

        equals = find_unquoted_equals(raw)
        if equals < 0:
            continue
        lhs = raw[:equals].strip()
        key_path = parse_key_path(lhs)
        if key_path is None:
            continue
        assignments.append(
            {
                "path": table_path + key_path,
                "table": table_path,
                "lhs": lhs,
                "start": start,
                "end": end,
            }
        )
    return assignments, tables


def toml_literal(value: Any) -> str:
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ConfigEditError("non-finite TOML values are not supported")
        return repr(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_literal(item) for item in value) + "]"
    if isinstance(value, dict):
        pairs = [f"{key} = {toml_literal(item)}" for key, item in value.items()]
        return "{ " + ", ".join(pairs) + " }"
    raise ConfigEditError(f"unsupported TOML value type: {type(value).__name__}")


def replace_range(text: str, start: int, end: int, replacement: str) -> str:
    return text[:start] + replacement + text[end:]


def set_path(text: str, path: tuple[str, ...], value: Any) -> str:
    assignments, tables = document_entries(text)
    for entry in assignments:
        if entry["path"] == path:
            newline = "\n" if text[entry["start"] : entry["end"]].endswith("\n") else ""
            indent_match = re.match(r"\s*", text[entry["start"] : entry["end"]])
            indent = indent_match.group(0).replace("\n", "") if indent_match else ""
            replacement = f"{indent}{entry['lhs']} = {toml_literal(value)}{newline}"
            return replace_range(text, entry["start"], entry["end"], replacement)

    parsed = parse_toml(text)
    present, _ = get_nested(parsed, path)
    if present:
        raise ConfigEditError(
            f"refusing to rewrite unsupported TOML representation for {'.'.join(path)}"
        )

    if path == ("notify",):
        insert_at = next((table["start"] for table in tables), len(text))
        prefix = "" if insert_at == 0 or text[:insert_at].endswith("\n") else "\n"
        return text[:insert_at] + f"{prefix}notify = {toml_literal(value)}\n" + text[insert_at:]

    if path[0] != "tui" or len(path) != 2:
        raise ConfigEditError(f"unsupported managed path: {'.'.join(path)}")

    tui_table = next((table for table in tables if table["path"] == ("tui",)), None)
    if tui_table is not None:
        return (
            text[: tui_table["end"]]
            + f"{path[1]} = {toml_literal(value)}\n"
            + text[tui_table["end"] :]
        )

    dotted_tui = any(entry["path"][:1] == ("tui",) for entry in assignments)
    inline_tui = any(entry["path"] == ("tui",) for entry in assignments)
    if inline_tui:
        raise ConfigEditError(
            "refusing to modify an inline top-level tui table; convert it to [tui] first"
        )
    if dotted_tui:
        insert_at = next((table["start"] for table in tables), len(text))
        prefix = "" if insert_at == 0 or text[:insert_at].endswith("\n") else "\n"
        assignment = f"tui.{path[1]} = {toml_literal(value)}\n"
        return text[:insert_at] + prefix + assignment + text[insert_at:]

    prefix = "" if not text or text.endswith("\n\n") else ("\n" if text.endswith("\n") else "\n\n")
    return text + f"{prefix}[tui]\n{path[1]} = {toml_literal(value)}\n"


def remove_path(text: str, path: tuple[str, ...]) -> str:
    assignments, _ = document_entries(text)
    for entry in assignments:
        if entry["path"] == path:
            return replace_range(text, entry["start"], entry["end"], "")

    parsed = parse_toml(text)
    present, _ = get_nested(parsed, path)
    if present:
        raise ConfigEditError(
            f"refusing to remove unsupported TOML representation for {'.'.join(path)}"
        )
    return text


def parse_toml(text: str) -> dict[str, Any]:
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise ConfigEditError(f"invalid config.toml: {error}") from error


def load_text(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, ""
    if path.is_symlink():
        raise ConfigEditError(f"refusing to edit symbolic link: {path}")
    return True, path.read_text(encoding="utf-8")


def write_validated(path: Path, text: str) -> None:
    parse_toml(text)
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode if path.exists() else None
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    if mode is not None:
        os.chmod(temporary, mode)
    os.replace(temporary, path)


def desired_values(snippet_path: Path, notify_script: str) -> dict[tuple[str, ...], Any]:
    parsed = parse_toml(snippet_path.read_text(encoding="utf-8"))
    notify_value = parsed.get("notify")
    if not isinstance(notify_value, list) or len(notify_value) != 2:
        raise ConfigEditError("snippet notify command must contain two argv entries")
    notify_value[1] = notify_script
    desired: dict[tuple[str, ...], Any] = {}
    for path in STATUS_PATHS + NOTIFICATION_PATHS:
        present, value = get_nested(parsed, path)
        if not present:
            raise ConfigEditError(f"snippet is missing {'.'.join(path)}")
        desired[path] = value
    return desired


def snapshot(config_path: Path, components: list[str]) -> None:
    existed, text = load_text(config_path)
    parsed = parse_toml(text)
    result: dict[str, Any] = {"fileExisted": existed, "values": {}}
    for path in selected_paths(components):
        present, value = get_nested(parsed, path)
        result["values"][".".join(path)] = {"present": present, "value": value}
    print(json.dumps(result, ensure_ascii=False))


def apply_values(
    config_path: Path,
    snippet_path: Path,
    notify_script: str,
    components: list[str],
) -> None:
    _, text = load_text(config_path)
    parse_toml(text)
    desired = desired_values(snippet_path, notify_script)
    for path in selected_paths(components):
        text = set_path(text, path, desired[path])
        parse_toml(text)
    write_validated(config_path, text)


def restore_values(
    config_path: Path,
    snippet_path: Path,
    notify_script: str,
    snapshot_path: Path | None,
    components: list[str],
) -> None:
    if not config_path.exists():
        return
    _, text = load_text(config_path)
    parsed = parse_toml(text)
    desired = desired_values(snippet_path, notify_script)
    if snapshot_path is None:
        original = {"values": {}}
    else:
        original = json.loads(snapshot_path.read_text(encoding="utf-8"))

    changed = False
    for path in selected_paths(components):
        key = ".".join(path)
        current_present, current_value = get_nested(parsed, path)
        if not current_present or current_value != desired[path]:
            if current_present:
                print(
                    f"warning: left modified Codex setting unchanged -> {key}",
                    file=os.sys.stderr,
                )
            continue

        saved = original.get("values", {}).get(key, {"present": False, "value": None})
        if saved.get("present"):
            text = set_path(text, path, saved.get("value"))
        else:
            text = remove_path(text, path)
        parsed = parse_toml(text)
        changed = True

    if changed:
        write_validated(config_path, text)


def is_semantically_empty(config_path: Path) -> int:
    if not config_path.exists():
        return 0
    _, text = load_text(config_path)
    parsed = parse_toml(text)

    def contains_value(value: Any) -> bool:
        if isinstance(value, dict):
            return any(contains_value(item) for item in value.values())
        return True

    return 1 if contains_value(parsed) else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot_parser = subparsers.add_parser("snapshot")
    snapshot_parser.add_argument("config", type=Path)
    snapshot_parser.add_argument("components", nargs="+", choices=["status-line", "notifications"])

    for command in ("apply", "restore", "remove-managed"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("config", type=Path)
        subparser.add_argument("snippet", type=Path)
        subparser.add_argument("notify_script")
        if command == "restore":
            subparser.add_argument("snapshot", type=Path)
        subparser.add_argument("components", nargs="+", choices=["status-line", "notifications"])

    empty_parser = subparsers.add_parser("is-empty")
    empty_parser.add_argument("config", type=Path)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "snapshot":
            snapshot(args.config, args.components)
        elif args.command == "apply":
            apply_values(args.config, args.snippet, args.notify_script, args.components)
        elif args.command == "restore":
            restore_values(
                args.config,
                args.snippet,
                args.notify_script,
                args.snapshot,
                args.components,
            )
        elif args.command == "remove-managed":
            restore_values(
                args.config,
                args.snippet,
                args.notify_script,
                None,
                args.components,
            )
        elif args.command == "is-empty":
            return is_semantically_empty(args.config)
    except (ConfigEditError, OSError, TypeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
