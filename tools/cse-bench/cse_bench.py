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
    python3 cse_bench.py render [--out DIR] [--claims PATH]

Stdlib only for collect/list. `render` (B-8, tools/cse-bench/render/) reads
PyYAML if importable for the claims register and falls back gracefully
(see render/dashboard.py's load_claims) — no hard new dependency either way.
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


def cmd_render(args: argparse.Namespace) -> int:
    """Render the static dashboard.html (B-8) from whatever collector
    output and claims-register state currently exist. Lazily imports the
    render/ package (same pattern discover_collectors() uses for
    collectors/) so a bug in render/ can never affect `collect`/`list`.
    """
    out_dir = Path(args.out).expanduser().resolve() if args.out else DEFAULT_OUT_DIR
    try:
        from render.dashboard import DEFAULT_CLAIMS_PATH as RENDER_DEFAULT_CLAIMS_PATH
        from render.dashboard import render_dashboard
    except Exception as exc:
        print(f"cse_bench: render module failed to import: {exc}", file=sys.stderr)
        return 1

    claims_path = Path(args.claims).expanduser().resolve() if args.claims else RENDER_DEFAULT_CLAIMS_PATH

    try:
        html_text = render_dashboard(out_dir=out_dir, claims_path=claims_path)
    except Exception as exc:  # render_dashboard already degrades internally; this is a last-resort guard
        print(f"cse_bench: render failed: {exc}", file=sys.stderr)
        return 1

    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / "dashboard.html"
    dest.write_text(html_text, encoding="utf-8")
    print(f"cse_bench: wrote {dest} ({dest.stat().st_size:,} bytes)")
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

    render_parser = subparsers.add_parser(
        "render",
        help="Render output/dashboard.html (B-8) from collector *-latest.json output plus claims.yaml.",
    )
    render_parser.add_argument(
        "--out",
        help=f"Directory to read <collector>-latest.json from and write dashboard.html into (default: {DEFAULT_OUT_DIR}).",
    )
    render_parser.add_argument(
        "--claims",
        help="Path to claims.yaml (default: docs/40-initiatives/01-cse-auditability/claims.yaml).",
    )
    render_parser.set_defaults(func=cmd_render)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
