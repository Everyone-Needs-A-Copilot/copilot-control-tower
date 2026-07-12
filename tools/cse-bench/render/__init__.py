"""render — cse-bench dashboard renderer package (TASK-91 / B-8).

Single public entry point: render_dashboard(out_dir, claims_path) -> str,
called by cse_bench.py's `render` subcommand. This package computes
nothing about the CSE itself — it only formats what the collectors under
../collectors/ already wrote and what docs/40-initiatives/01-cse-auditability/
claims.yaml already declares (Control Tower invariant #1: the CLI/collectors
compute, the view renders). See dashboard.py for the implementation.
"""
from .dashboard import DEFAULT_CLAIMS_PATH, render_dashboard

__all__ = ["render_dashboard", "DEFAULT_CLAIMS_PATH"]
