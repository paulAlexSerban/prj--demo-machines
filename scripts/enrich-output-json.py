#!/usr/bin/env python3
"""Overlay profile tfvars onto terraform output JSON for passthrough fields (no AWS change)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ENV_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def parse_hcl_list(raw: str) -> list[int]:
    inner = raw.strip()
    if not inner:
        return []
    parts = [p.strip() for p in inner.split(",")]
    out: list[int] = []
    for part in parts:
        if not part:
            continue
        out.append(int(part))
    return out


def read_tfvars_list(tfvars: Path, key: str) -> list[int] | None:
    text = tfvars.read_text(encoding="utf-8")
    match = re.search(
        rf"^[ \t]*{key}[ \t]*=[ \t]*\[([^\]]*)\]",
        text,
        re.MULTILINE,
    )
    if not match:
        return None
    return parse_hcl_list(match.group(1))


def read_tfvars_string(tfvars: Path, key: str) -> str | None:
    text = tfvars.read_text(encoding="utf-8")
    match = re.search(
        rf'^[ \t]*{key}[ \t]*=[ \t]*"([^"]*)"',
        text,
        re.MULTILINE,
    )
    if not match:
        return None
    return match.group(1)


def read_tfvars_bool(tfvars: Path, key: str) -> bool | None:
    text = tfvars.read_text(encoding="utf-8")
    match = re.search(
        rf"^[ \t]*{key}[ \t]*=[ \t]*(true|false)",
        text,
        re.MULTILINE | re.IGNORECASE,
    )
    if not match:
        return None
    return match.group(1).lower() == "true"


def read_tfvars_map(tfvars: Path, key: str) -> dict[str, str] | None:
    text = tfvars.read_text(encoding="utf-8")
    match = re.search(
        rf"^[ \t]*{re.escape(key)}[ \t]*=[ \t]*\{{",
        text,
        re.MULTILINE,
    )
    if not match:
        return None
    rest = text[match.end() :]
    end = rest.find("}")
    if end < 0:
        raise ValueError(f"{key} map is missing a closing brace")
    out: dict[str, str] = {}
    for raw_line in rest[:end].splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parsed = re.fullmatch(
            r'([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*"([^"]*)"[ \t]*(#.*)?',
            line,
        )
        if not parsed:
            raise ValueError(f'{key} entries must be KEY = "value" (got {line!r})')
        out[parsed.group(1)] = parsed.group(2)
    return out


def emit_dotenv(env: dict[str, str]) -> str:
    lines: list[str] = []
    for name in sorted(env):
        if not ENV_KEY_RE.fullmatch(name):
            raise ValueError(f"invalid env key: {name}")
        value = env[name]
        if "\n" in value or "\r" in value:
            raise ValueError(f"env {name} must be a single line")
        escaped = (
            value.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("$", "\\$")
            .replace("`", "\\`")
        )
        lines.append(f'{name}="{escaped}"')
    return "\n".join(lines) + ("\n" if lines else "")


def overlay(data: dict, tfvars: Path) -> dict:
    ports = read_tfvars_list(tfvars, "forward_ports")
    if ports is not None:
        data.setdefault("forward_ports", {})["value"] = ports

    startup = read_tfvars_string(tfvars, "startup_command")
    if startup is not None:
        data.setdefault("startup_command", {})["value"] = startup

    autostart = read_tfvars_bool(tfvars, "autostart")
    if autostart is not None:
        data.setdefault("autostart", {})["value"] = autostart

    repo_url = read_tfvars_string(tfvars, "repo_url")
    if repo_url is not None:
        data.setdefault("repo_url", {})["value"] = repo_url

    repo_ref = read_tfvars_string(tfvars, "repo_ref")
    if repo_ref is not None:
        data.setdefault("repo_ref", {})["value"] = repo_ref

    env = read_tfvars_map(tfvars, "env")
    if env is None:
        env = {}
    data.setdefault("env", {})["value"] = env
    return data


def self_test() -> None:
    from tempfile import TemporaryDirectory

    with TemporaryDirectory() as raw:
        tfvars = Path(raw) / "p.tfvars"
        tfvars.write_text(
            'env = {\n  FOO = "bar"\n  # skip\n  BAZ = "a b" # trailing\n}\n',
            encoding="utf-8",
        )
        parsed = read_tfvars_map(tfvars, "env")
        if parsed != {"FOO": "bar", "BAZ": "a b"}:
            raise AssertionError(parsed)
        tfvars.write_text("env = {}\n", encoding="utf-8")
        if read_tfvars_map(tfvars, "env") != {}:
            raise AssertionError("empty map")
        if emit_dotenv({"FOO": r'x$y`z"'} ) != 'FOO="x\\$y\\`z\\""\n':
            raise AssertionError(emit_dotenv({"FOO": r'x$y`z"'}))
        if read_tfvars_map(tfvars, "missing") is not None:
            raise AssertionError("missing key")
    print("ok")


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--dotenv":
        data = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
        env = data.get("env", {}).get("value") or {}
        if not isinstance(env, dict):
            print("env.value must be an object", file=sys.stderr)
            sys.exit(1)
        sys.stdout.write(emit_dotenv({str(k): str(v) for k, v in env.items()}))
        return
    if len(sys.argv) != 3:
        print(
            "usage: enrich-output-json.py <terraform-output.json> <profile.tfvars>",
            file=sys.stderr,
        )
        sys.exit(2)
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    tfvars = Path(sys.argv[2])
    if not tfvars.is_file():
        print(f"missing profile: {tfvars}", file=sys.stderr)
        sys.exit(1)
    json.dump(overlay(data, tfvars), sys.stdout)


if __name__ == "__main__":
    main()
