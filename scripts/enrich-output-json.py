#!/usr/bin/env python3
"""Overlay profile tfvars onto terraform output JSON for passthrough fields (no AWS change)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


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


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: enrich-output-json.py <terraform-output.json> <profile.tfvars>", file=sys.stderr)
        sys.exit(2)
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    tfvars = Path(sys.argv[2])
    if not tfvars.is_file():
        print(f"missing profile: {tfvars}", file=sys.stderr)
        sys.exit(1)

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

    json.dump(data, sys.stdout)


if __name__ == "__main__":
    main()
