#!/usr/bin/env python3
"""cse_bench.py — CSE Verification & Benchmark Program measurement harness.

Single entry point for running one or more collectors and writing
schema-versioned, timestamped JSON output. Serves PRD-9 (CSE Verification
& Benchmark Program), tasks B-4 (tasksdb collector) and B-7 (this CLI).

Registry pattern: collectors are plain modules dropped into collectors/
that expose COLLECTOR_NAME (str) and collect() (callable) — see
collectors/__init__.py and README.md. Nothing in this file needs to
change to add a new collector (transcripts, parity, health, ...).

Usage:
    python3 cse_bench.py collect [--only tasksdb[,other]] [--out DIR]
    python3 cse_bench.py list

Stdlib only. No third-party dependencies.
"""
from __future__ import annotations

import argparse
import importlib
import json
import pkgutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

SCHEMA_VERSION = "cse-bench/1"
HOST_SCOPE = "single-machine-single-user"

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_OUT_DIR = SCRIPT_DIR / "output"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _utc_stamp() -> str:
    """Filename-safe UTC timestamp, e.g. 20260712T170000Z."""
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def discover_collectors() -> dict[str, Callable[..., dict]]:
    """Auto-discover collectors under the collectors/ package.

    Any module that defines both COLLECTOR_NAME (str) and a callable
    collect() is registered under COLLECTOR_NAME. This is the "registry
    pattern" the harness is built around: dropping a new file into
    collectors/ is sufficient to make it runnable, with zero edits here.
    """
    import collectors as collectors_pkg

    registry: dict[str, Callable[..., dict]] = {}
    for _, mod_name, _ in pkgutil.iter_modules(collectors_pkg.__path__):
        module = importlib.import_module(f"collectors.{mod_name}")
        collector_name = getattr(module, "COLLECTOR_NAME", None)
        collect_fn = getattr(module, "collect", None)
        if collector_name and callable(collect_fn):
            registry[collector_name] = collect_fn
    return registry


def run_collector(name: str, collect_fn: Callable[..., dict], out_dir: Path) -> Path:
    """Run one collector, wrap its result in the cse-bench envelope, and
    write both the timestamped file and the stable -latest.json pointer.
    """
    result = collect_fn()

    envelope = {
        "schema_version": SCHEMA_VERSION,
        "collector": name,
        "generated_at": _utc_now_iso(),
        "host_scope": HOST_SCOPE,
        "metrics": result.get("metrics", {}),
        "errors": result.get("errors", []),
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    stamped_path = out_dir / f"{name}-{_utc_stamp()}.json"
    latest_path = out_dir / f"{name}-latest.json"

    payload = json.dumps(envelope, indent=2, sort_keys=True) + "\n"
    stamped_path.write_text(payload, encoding="utf-8")
    latest_path.write_text(payload, encoding="utf-8")
    return stamped_path


def cmd_collect(args: argparse.Namespace) -> int:
    registry = discover_collectors()
    if not registry:
        print("cse_bench: no collectors registered under collectors/", file=sys.stderr)
        return 1

    requested = (
        [name.strip() for name in args.only.split(",") if name.strip()]
        if args.only
        else sorted(registry.keys())
    )
    out_dir = Path(args.out).expanduser().resolve() if args.out else DEFAULT_OUT_DIR

    exit_code = 0
    for name in requested:
        if name not in registry:
            available = ", ".join(sorted(registry.keys()))
            print(
                f"cse_bench: unknown collector '{name}' (available: {available})",
                file=sys.stderr,
            )
            exit_code = 1
            continue
        try:
            path = run_collector(name, registry[name], out_dir)
            print(f"cse_bench: wrote {path}")
        except Exception as exc:  # a collector crashing must not crash the run
            print(f"cse_bench: collector '{name}' failed: {exc}", file=sys.stderr)
            exit_code = 1

    return exit_code


def cmd_list(args: argparse.Namespace) -> int:
    registry = discover_collectors()
    if not registry:
        print("(no collectors registered)")
        return 0
    for name in sorted(registry.keys()):
        print(name)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="cse_bench.py",
        description="CSE Verification & Benchmark Program measurement harness.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    collect_parser = subparsers.add_parser(
        "collect", help="Run one or more collectors and write versioned JSON output."
    )
    collect_parser.add_argument(
        "--only",
        help="Comma-separated collector names to run (default: all registered collectors).",
    )
    collect_parser.add_argument(
        "--out",
        help=f"Output directory (default: {DEFAULT_OUT_DIR}).",
    )
    collect_parser.set_defaults(func=cmd_collect)

    list_parser = subparsers.add_parser("list", help="List registered collectors and exit.")
    list_parser.set_defaults(func=cmd_list)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
