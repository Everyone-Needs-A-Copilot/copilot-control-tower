"""collectors/knowledge_soul.py — Knowledge-SOUL collector (S-3 / TASK-109).

Measures Knowledge Copilot against its OWN SOUL promise
(``/Volumes/Dev/Sites/COPILOT/knowledge-copilot/SOUL.md``): never become a
stale content dump, a marketing-only narrative, or a place where
contradictory product facts quietly coexist; quality bar "cross-linked
where decisions depend"; anti-patterns "updating a product description
while leaving the ecosystem registry stale" and "rewriting company voice
into generic consultant language." Serves PRD-9 (CSE Verification &
Benchmark Program), phase-2-prd.md task S-3.

This collector computes six metrics, read-only, against a live checkout of
knowledge-copilot on this machine:

1. **registry_integrity** — forward check: every backtick-wrapped absolute
   ``/Volumes/Dev/Sites/COPILOT/...`` path in ``ECOSYSTEM.md`` (its "Local
   path" column values) resolves on disk. Reverse check: every top-level
   directory under ``/Volumes/Dev/Sites/COPILOT/`` that ``ECOSYSTEM.md``
   does not cover with a literal Local-path entry (the stale-clone problem
   — a directory sitting on disk that the registry's actual path table
   never points at, whether or not the name is discussed in prose).
2. **cross_link_integrity** — every relative markdown link found in scope
   (non-archive) ``.md`` files: % resolving on disk, broken-link count,
   top-10 offending source files by broken-link count.
3. **contradictory_facts** — v1 heuristic: for each product dossier under
   ``02-products/``, extracts ``v?\\d+\\.\\d+(\\.\\d+)?``-shaped version
   strings from lines that are "near" the product's name (same line) or,
   inside the product's own dossier, near the bare word "version"; flags a
   product when 2+ *different* versions are stated across non-archive
   files.
4. **staleness_archive_honesty** — % of scope files carrying frontmatter
   with a freshness-signaling key; git last-touch distribution bucketed by
   quarter; count of active files whose prose references ``_archive/``;
   count of specific archived files/dirs that active files actually LINK
   to (the "dishonest archival signal" — content the repo still leans on
   that it also calls archived).
5. **orphan_rate** — scope files whose full relative path (falling back to
   bare basename) appears in no other knowledge file, the manifest, or the
   registry; reported rate is documented as a **floor**, not a
   measurement (see `_metric_5_orphan_rate` docstring).
6. **voice_preservation** — runs the compiled voice-conformance linter
   (``benches/voice_lint/lint.py``, TASK-93/B-10) over every ``.md`` under
   ``01-company/`` — the content that *defines* the company's voice,
   checked against its own rubric (anti-pattern: consultant language).

Scope (unless a metric states otherwise): ``*.md`` under knowledge-copilot,
excluding ``.git``, ``node_modules``, ``storybook-static``, and
``_archive/``. Metric 4 explicitly widens scope to include ``_archive/``
(that is what "archive honesty" means to check); metric 3 records archive
hits too, but only uses non-archive hits to decide whether a product is
flagged.

Design notes
------------
- Every filesystem/subprocess call is individually wrapped; a failure
  anywhere produces a per-item entry in the returned ``errors`` list and a
  degraded (``"available": False`` or empty) result in ``metrics`` rather
  than raising out of ``collect()`` — same contract as
  ``collectors/tasksdb.py`` and ``collectors/parity.py``.
- File contents are read once into an in-memory cache and reused across
  all six metrics rather than re-read per metric.
- Every heuristic (link extraction, version-string proximity, orphan
  basename fallback) is v1 and documented as such in its own metric's
  ``definition``/``limitations`` field, per the task's own instruction to
  "document precision limits" rather than overstate precision.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.parse
from collections import Counter, defaultdict
from pathlib import Path
from typing import Callable, Optional

from collectors.paths import COPILOT_ROOT_CANDIDATES, resolve_copilot_root

COLLECTOR_NAME = "knowledge_soul"

COPILOT_ROOT = resolve_copilot_root()
KNOWLEDGE_ROOT = COPILOT_ROOT / "knowledge-copilot"
ECOSYSTEM_MD = KNOWLEDGE_ROOT / "ECOSYSTEM.md"

# ECOSYSTEM.md's prose hardcodes the owner's primary-machine root
# (/Volumes/Dev/Sites/COPILOT) regardless of which root THIS machine
# actually resolved (collectors.paths.resolve_copilot_root()) -- on a
# secondary machine where /Volumes/Dev is never mounted, matching only
# against the resolved COPILOT_ROOT silently produced a vacuous "0/0"
# forward check (nothing in the doc starts with /Users/pabs/...) and a
# reverse check that over-flagged every top-level directory as
# "uncovered" (the doc's own /Volumes/Dev/... paths never textually
# matched an /Users/pabs/... comparison string). Fix: match against BOTH
# known root prefixes, then translate whichever one matched to this
# machine's actually-resolved COPILOT_ROOT before checking existence.
_KNOWN_ROOT_PREFIXES = [str(root) + "/" for root in COPILOT_ROOT_CANDIDATES]


def _resolve_against_known_root(val: str) -> Path:
    """Translate a path written against ANY known COPILOT_ROOT candidate
    into the equivalent path under THIS machine's actually-resolved
    COPILOT_ROOT, so existence checks are honest even when the doc's
    prose hardcodes a different machine's root than the one that resolved
    here."""
    for prefix in _KNOWN_ROOT_PREFIXES:
        if val.startswith(prefix):
            return COPILOT_ROOT / val[len(prefix):]
    return Path(val)
MANIFEST_JSON = KNOWLEDGE_ROOT / "knowledge-manifest.json"

SCRIPT_DIR = Path(__file__).resolve().parent
CSE_BENCH_ROOT = SCRIPT_DIR.parent
VOICE_LINT_DIR = CSE_BENCH_ROOT / "benches" / "voice_lint"

EXCLUDE_DIR_NAMES = {".git", "node_modules", "storybook-static"}
ARCHIVE_DIR_NAME = "_archive"

_DOSSIER_LAYERS = ["02-foundational", "03-work", "04-applications"]

_MD_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
_LINK_TITLE_RE = re.compile(r'^(\S+)(?:\s+"[^"]*"|\s+\'[^\']*\')?$')
_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")

_VERSION_RE = re.compile(r"\b[vV]?(\d+\.\d+(?:\.\d+)?)\b")

_FRONTMATTER_KEY_RE = re.compile(r"^([A-Za-z_][\w-]*):", re.MULTILINE)
FRESHNESS_KEYS = {"last_updated", "last_reviewed", "updated", "created"}


# ---------------------------------------------------------------------------
# Shared filesystem helpers
# ---------------------------------------------------------------------------


def _iter_md_files(root: Path, exclude_archive: bool) -> list[Path]:
    exclude = set(EXCLUDE_DIR_NAMES)
    if exclude_archive:
        exclude.add(ARCHIVE_DIR_NAME)
    files = []
    for p in root.rglob("*.md"):
        if any(part in exclude for part in p.parts):
            continue
        files.append(p)
    return sorted(files)


def _read_text_safe(path: Path, errors: list[dict]) -> Optional[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        errors.append({"item": "read_file", "path": str(path), "error": f"{type(exc).__name__}: {exc}"})
        return None


def _rel(path: Path) -> str:
    return str(path.relative_to(KNOWLEDGE_ROOT))


# ---------------------------------------------------------------------------
# Metric 1 — registry integrity
# ---------------------------------------------------------------------------


def _metric_1_registry_integrity(errors: list[dict]) -> dict:
    text = _read_text_safe(ECOSYSTEM_MD, errors)
    if text is None:
        return {"available": False, "reason": f"{ECOSYSTEM_MD} not readable"}

    entries: list[dict] = []
    seen: set[str] = set()
    for line_no, line in enumerate(text.splitlines(), start=1):
        for m in re.finditer(r"`([^`]+)`", line):
            val = m.group(1).strip()
            if not any(val.startswith(prefix) for prefix in _KNOWN_ROOT_PREFIXES):
                continue
            if "<" in val or ">" in val:  # template placeholders, e.g. `.../COPILOT/<name>`
                continue
            if val in seen:
                continue
            seen.add(val)
            entries.append(
                {"path": val, "line": line_no, "resolves": _resolve_against_known_root(val).exists()}
            )

    n_total = len(entries)
    n_resolving = sum(1 for e in entries if e["resolves"])
    broken = [e for e in entries if not e["resolves"]]

    reverse = _registry_reverse_check(text)

    return {
        "forward_check": {
            "definition": (
                "every backtick-wrapped absolute path in ECOSYSTEM.md (its Local-path column "
                "values) matching either known COPILOT root prefix -- /Volumes/Dev/Sites/COPILOT "
                "or /Users/pabs/Sites/COPILOT, see collectors/paths.py -- deduped in document "
                "order, translated to this machine's actually-resolved root, and checked with "
                "Path.exists()"
            ),
            "n_paths": n_total,
            "n_resolving": n_resolving,
            "headline": f"{n_resolving}/{n_total}",
            "broken": broken,
        },
        "reverse_check": reverse,
    }


def _registry_reverse_check(ecosystem_text: str) -> dict:
    entries = []
    for entry in sorted(COPILOT_ROOT.iterdir(), key=lambda p: p.name):
        name = entry.name
        if name.startswith(".") or name == ARCHIVE_DIR_NAME:
            continue
        if not entry.is_dir():  # follows symlinks -> a symlink to a dir counts
            continue
        literal_path = f"{COPILOT_ROOT}/{name}"
        # "Covered" means the doc's prose contains the literal path under
        # EITHER known root prefix, not just this machine's resolved one --
        # ECOSYSTEM.md hardcodes the owner's primary-machine root regardless
        # of which root actually resolved here.
        covered = any(f"{prefix}{name}" in ecosystem_text for prefix in _KNOWN_ROOT_PREFIXES)
        name_mentioned = bool(re.search(r"\b" + re.escape(name) + r"\b", ecosystem_text))
        entries.append(
            {
                "name": name,
                "path": literal_path,
                "covered_by_local_path": covered,
                "name_mentioned_in_doc": name_mentioned,
            }
        )

    uncovered = [e for e in entries if not e["covered_by_local_path"]]
    unmentioned = [e["name"] for e in uncovered if not e["name_mentioned_in_doc"]]
    named_but_uncovered = [e["name"] for e in uncovered if e["name_mentioned_in_doc"]]

    return {
        "definition": (
            "top-level entries under this machine's actually-resolved COPILOT_ROOT that resolve "
            "to a directory (symlinks followed), excluding dotfiles and _archive itself; "
            "'covered' means the literal absolute path string, under EITHER known root prefix "
            "(/Volumes/Dev/Sites/COPILOT or /Users/pabs/Sites/COPILOT), appears in ECOSYSTEM.md "
            "as an actual Local-path table entry -- a bare name mention in prose does not count "
            "as covered"
        ),
        "n_top_level_dirs": len(entries),
        "n_uncovered": len(uncovered),
        "uncovered_and_unmentioned_anywhere": sorted(unmentioned),
        "uncovered_but_named_in_prose_only": sorted(named_but_uncovered),
        "note": (
            "uncovered_but_named_in_prose_only are directories the doc discusses (e.g. marks "
            "'archived'/'out of scope') without a Local-path row pointing at their real on-disk "
            "location -- includes the known stale-clone cases (conversations-copilot, "
            "shared-docs) plus, if present, knowledge-copilot itself never listing its own "
            "Local path"
        ),
    }


# ---------------------------------------------------------------------------
# Shared link extraction (used by metric 2 and metric 4c)
# ---------------------------------------------------------------------------


def _extract_link_targets(text: str) -> list[str]:
    targets = []
    for raw in _MD_LINK_RE.findall(text):
        raw = raw.strip()
        if not raw:
            continue
        m = _LINK_TITLE_RE.match(raw)
        targets.append(m.group(1) if m else raw)
    return targets


def _is_checkable_relative_link(target: str) -> bool:
    if not target or target.startswith("#"):
        return False
    if _SCHEME_RE.match(target):
        return False
    return True


def _resolve_link(file_path: Path, target: str) -> Optional[Path]:
    clean = target.split("#", 1)[0]
    clean = urllib.parse.unquote(clean)
    if clean == "":
        return None
    try:
        if clean.startswith("/"):
            return (KNOWLEDGE_ROOT / clean.lstrip("/")).resolve()
        return (file_path.parent / clean).resolve()
    except (OSError, ValueError):
        return None


def _extract_all_links(scope_files: list[Path], texts: dict[Path, str]) -> list[dict]:
    """One link-extraction pass shared by metric 2 (cross-link integrity)
    and metric 4c (archive files referenced by active files), so the
    same v1 heuristic backs both numbers instead of two subtly-different
    reimplementations.
    """
    links: list[dict] = []
    for p in scope_files:
        text = texts.get(p)
        if text is None:
            continue
        source_rel = _rel(p)
        for raw_target in _extract_link_targets(text):
            if not _is_checkable_relative_link(raw_target):
                continue
            resolved = _resolve_link(p, raw_target)
            exists = bool(resolved and resolved.exists())
            is_archive_target = bool(resolved and ARCHIVE_DIR_NAME in resolved.parts)
            links.append(
                {
                    "source_file": source_rel,
                    "link": raw_target,
                    "resolved_path": str(resolved) if resolved else None,
                    "exists": exists,
                    "is_archive_target": is_archive_target,
                }
            )
    return links


# ---------------------------------------------------------------------------
# Metric 2 — cross-link integrity
# ---------------------------------------------------------------------------


def _metric_2_cross_link_integrity(all_links: list[dict]) -> dict:
    total = len(all_links)
    broken = [link for link in all_links if not link["exists"]]
    n_broken = len(broken)

    per_file_broken: Counter = Counter()
    for link in broken:
        per_file_broken[link["source_file"]] += 1

    pct_resolving = round((total - n_broken) / total * 100, 2) if total else None
    top_offenders = [{"file": f, "broken_count": n} for f, n in per_file_broken.most_common(10)]

    return {
        "definition": (
            "[text](target) and ![alt](target) links found in scope (non-archive) .md files; "
            "external-scheme (http(s)/mailto/etc.) and pure-anchor (#frag) links excluded; a "
            "leading '/' target resolves against the knowledge-copilot root, otherwise relative "
            "to the source file's directory; #fragments stripped before the existence check; "
            "existence is checked live on disk, so a link into _archive/ resolves fine as long "
            "as the archived target itself still exists"
        ),
        "n_links_checked": total,
        "n_broken": n_broken,
        "pct_resolving": pct_resolving,
        "headline": (f"{pct_resolving}% resolving ({total - n_broken}/{total})" if total else "no relative links found"),
        "top_10_offender_files": top_offenders,
        "limitations": (
            "v1 regex-based extraction: does not handle reference-style [text][ref] links, "
            "targets containing literal parentheses, or markdown link syntax appearing inside "
            "fenced code blocks (those are counted as if real, which is a source of "
            "false-positive breakage in template/how-to documents)"
        ),
    }


# ---------------------------------------------------------------------------
# Metric 3 — contradictory facts (v1 heuristic)
# ---------------------------------------------------------------------------


def _discover_products() -> dict[str, Path]:
    """Returns {product_dir_name: dossier_path} for every leaf directory
    under 02-products/{02-foundational,03-work,04-applications}/. Layer 1
    (01-ecosystem, meta index) and the 99-innovation-roadmap layer
    (ideation, not shipped dossiers) are intentionally excluded.
    """
    products: dict[str, Path] = {}
    products_root = KNOWLEDGE_ROOT / "02-products"
    for layer in _DOSSIER_LAYERS:
        layer_dir = products_root / layer
        if not layer_dir.is_dir():
            continue
        for child in sorted(layer_dir.iterdir()):
            if child.is_dir():
                products[child.name] = child
    return products


def _name_pattern(product: str) -> re.Pattern:
    parts = [re.escape(part) for part in product.split("-")]
    body = r"[- ]".join(parts)
    return re.compile(r"\b" + body + r"s?\b", re.IGNORECASE)


def _metric_3_contradictory_facts(all_files: list[Path], texts: dict[Path, str], errors: list[dict]) -> dict:
    dossiers = _discover_products()
    if not dossiers:
        errors.append({"item": "contradictory_facts", "error": "no product dossiers found under 02-products/"})
        return {"available": False}

    name_patterns = {name: _name_pattern(name) for name in dossiers}
    hits_by_product: dict[str, list[dict]] = defaultdict(list)

    for path in all_files:
        text = texts.get(path)
        if text is None:
            continue
        rel = _rel(path)
        is_archive = ARCHIVE_DIR_NAME in path.parts
        dossier_product = next((name for name, d in dossiers.items() if path.is_relative_to(d)), None)

        for line_no, line in enumerate(text.splitlines(), start=1):
            if not _VERSION_RE.search(line):  # cheap prefilter: skip lines with no version-shaped number at all
                continue
            has_version_word = "version" in line.lower()
            matched_products = {name for name, pat in name_patterns.items() if pat.search(line)}
            if dossier_product and has_version_word:
                matched_products.add(dossier_product)
            if not matched_products:
                continue

            for m in _VERSION_RE.finditer(line):
                end = m.end()
                if end < len(line) and line[end] == "%":  # "3.5%" is a percentage, not a version
                    continue
                raw = m.group(0)
                normalized = m.group(1).lower().lstrip("v")
                for product in matched_products:
                    hits_by_product[product].append(
                        {
                            "file": rel,
                            "line": line_no,
                            "raw": raw,
                            "normalized": normalized,
                            "is_archive": is_archive,
                            "excerpt": line.strip()[:160],
                        }
                    )

    per_product_summary: dict[str, dict] = {}
    flagged: list[str] = []
    for product, hits in hits_by_product.items():
        non_archive_versions = sorted({h["normalized"] for h in hits if not h["is_archive"]})
        all_versions = sorted({h["normalized"] for h in hits})
        evidence = sorted(hits, key=lambda h: (h["file"], h["line"]))[:20]
        per_product_summary[product] = {
            "n_hits": len(hits),
            "distinct_versions_non_archive": non_archive_versions,
            "distinct_versions_all": all_versions,
            "evidence": evidence,
            "evidence_truncated": len(hits) > len(evidence),
        }
        if len(non_archive_versions) >= 2:
            flagged.append(product)

    return {
        "definition": (
            "regex v?\\d+\\.\\d+(\\.\\d+)? applied to every line of every knowledge .md file "
            "(incl. _archive, for context) that either contains the product's hyphen/space-"
            "tolerant name (matched across ALL files mentioning that product, not just its own "
            "dossier) or -- for lines inside the product's OWN dossier only -- contains the bare "
            "word 'version'; a percentage-suffixed match (e.g. '3.5%') is excluded. A product is "
            "flagged when 2+ DIFFERENT normalized version strings are found across its "
            "non-archive hits."
        ),
        "n_products_scanned": len(dossiers),
        "n_flagged": len(flagged),
        "flagged_products": sorted(flagged),
        "per_product": per_product_summary,
        "precision_limits": [
            "same-line proximity only: a version stated on the line below/above a product name is missed (recall limit, undercounts contradictions)",
            "digit-dot-digit patterns that are not versions (section numbers like '10.1', Python/Postgres/TLS runtime versions, IP-octet fragments, port numbers) can false-positive as a product's own version if they share a line with the product name (precision limit, inflates n_hits and can spuriously flag a product)",
            "no semver canonicalization: '1.1' and '1.1.0' are treated as two DIFFERENT versions even when an author means the same release; some flagged products below are flagged partly or wholly on this shorthand-vs-full-form gap rather than a real contradiction -- read distinct_versions_non_archive per product before treating a flag as a real fact conflict",
            "product-name matching is a hyphen/space-tolerant literal match on the dossier directory name; a product referred to only by a different alias/prose name elsewhere is missed entirely",
        ],
    }


# ---------------------------------------------------------------------------
# Metric 4 — staleness / archive honesty
# ---------------------------------------------------------------------------


def _parse_frontmatter_keys(text: str) -> Optional[set[str]]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_idx = i
            break
    if end_idx is None:
        return None
    block = "\n".join(lines[1:end_idx])
    return set(_FRONTMATTER_KEY_RE.findall(block))


def _git_last_touch_by_quarter(errors: list[dict]) -> dict[str, Optional[str]]:
    """Returns {repo-relative .md path: 'YYYY-QN'} for the most recent
    commit that touched each file, via one `git log --name-only` pass
    (newest commit first, so the first time a path is seen is its latest
    touch). Files git has never seen (untracked/new) are simply absent
    from the returned map -- the caller buckets those as 'untracked'.
    """
    try:
        result = subprocess.run(
            ["git", "-C", str(KNOWLEDGE_ROOT), "log", "--format=%x00%cI", "--name-only"],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        errors.append({"item": "git_last_touch", "error": f"{type(exc).__name__}: {exc}"})
        return {}
    if result.returncode != 0:
        errors.append({"item": "git_last_touch", "error": f"git log exited {result.returncode}: {result.stderr.strip()[:300]}"})
        return {}

    last_touch: dict[str, str] = {}
    current_iso: Optional[str] = None
    for line in result.stdout.split("\n"):
        if line.startswith("\x00"):
            current_iso = line[1:]
            continue
        fname = line.strip()
        if not fname or not fname.endswith(".md") or current_iso is None:
            continue
        if fname not in last_touch:
            try:
                year = int(current_iso[0:4])
                month = int(current_iso[5:7])
            except (ValueError, IndexError):
                continue
            quarter = (month - 1) // 3 + 1
            last_touch[fname] = f"{year}-Q{quarter}"
    return last_touch


def _metric_4_staleness_archive_honesty(
    scope_files: list[Path],
    archive_files: list[Path],
    texts: dict[Path, str],
    all_links: list[dict],
    errors: list[dict],
) -> dict:
    # (a) frontmatter freshness coverage over scope (non-archive) files.
    n_scope = len(scope_files)
    frontmatter_present = 0
    freshness_key_present = 0
    literal_last_updated = 0
    key_counter: Counter = Counter()

    for p in scope_files:
        text = texts.get(p)
        if text is None:
            continue
        keys = _parse_frontmatter_keys(text)
        if keys is None:
            continue
        frontmatter_present += 1
        key_counter.update(keys)
        if "last_updated" in keys:
            literal_last_updated += 1
        if keys & FRESHNESS_KEYS:
            freshness_key_present += 1

    def _pct(n: int) -> Optional[float]:
        return round(n / n_scope * 100, 2) if n_scope else None

    frontmatter_metrics = {
        "definition": (
            "% of scope (non-archive) .md files that open with a '---' YAML frontmatter block; "
            "freshness_key_pct additionally requires at least one of "
            f"{sorted(FRESHNESS_KEYS)} inside that block; literal_last_updated_pct checks the "
            "exact key 'last_updated' as named in the SOUL/architecture docs"
        ),
        "n_scope_files": n_scope,
        "any_frontmatter_pct": _pct(frontmatter_present),
        "freshness_key_pct": _pct(freshness_key_present),
        "literal_last_updated_key_pct": _pct(literal_last_updated),
        "frontmatter_keys_observed": dict(key_counter.most_common()),
        "note": "the literal key 'last_updated' was not observed in this run's frontmatter at all -- see frontmatter_keys_observed for what actually appears (last_reviewed/status/updated/created)",
    }

    # (b) git last-touch distribution, bucketed by quarter.
    last_touch = _git_last_touch_by_quarter(errors)
    quarter_counter: Counter = Counter()
    untracked = 0
    for p in scope_files:
        rel = _rel(p)
        quarter = last_touch.get(rel)
        if quarter is None:
            untracked += 1
        else:
            quarter_counter[quarter] += 1

    git_distribution = {
        "definition": "most recent git commit that touched each scope file, bucketed to calendar quarter (git log --name-only, newest-first, first-seen wins); files git has never committed are bucketed 'untracked'",
        "by_quarter": dict(sorted(quarter_counter.items())),
        "untracked_count": untracked,
        "n_scope_files": n_scope,
    }

    # (c) active files referencing _archive/ in prose.
    active_archive_ref_files = []
    for p in scope_files:
        text = texts.get(p)
        if text and "_archive/" in text:
            active_archive_ref_files.append(_rel(p))

    # (d) archive files/dirs actually LINKED TO by active files (the
    # "dishonest archival signal": content the repo still leans on that it
    # also calls archived), reusing the shared link-extraction pass.
    archive_links = [
        link for link in all_links if link["is_archive_target"] and link["exists"] and not link["source_file"].startswith(f"{ARCHIVE_DIR_NAME}/")
    ]
    archive_targets_referenced = sorted({link["resolved_path"] for link in archive_links})

    archive_honesty = {
        "active_files_referencing_archive_path_in_prose": {
            "definition": "count of non-archive .md files containing the literal substring '_archive/' anywhere in their text (prose about the archiving convention counts here, not just links)",
            "count": len(active_archive_ref_files),
            "files": sorted(active_archive_ref_files),
        },
        "archive_targets_linked_by_active_files": {
            "definition": "distinct files/dirs under _archive/ that a resolving markdown LINK from a non-archive file actually points at -- unlike the prose count above, this is content the active docs still structurally depend on despite calling it archived",
            "count": len(archive_targets_referenced),
            "targets": archive_targets_referenced,
        },
        "n_archive_files_total": len(archive_files),
    }

    return {
        "frontmatter_freshness": frontmatter_metrics,
        "git_last_touch_distribution": git_distribution,
        "archive_honesty": archive_honesty,
    }


# ---------------------------------------------------------------------------
# Metric 5 — orphan rate
# ---------------------------------------------------------------------------


def _metric_5_orphan_rate(
    scope_files: list[Path],
    all_files: list[Path],
    texts: dict[Path, str],
    manifest_text: Optional[str],
) -> dict:
    """"Every document earns its place in the knowledge map": a scope file
    is NOT an orphan if its full relative path -- or, failing that, its
    bare basename -- appears anywhere else in the corpus (any other
    knowledge file, including _archive, or the manifest).

    The basename fallback is deliberately permissive: a generic filename
    like '00-overview.md' mentioned anywhere counts as "referenced" even
    when the mention is actually about a *different* file that happens to
    share the same basename. That inflates the referenced count and
    deflates the orphan count -- so orphan_rate_pct here is a FLOOR (the
    best case), matching the same basename-fallback logic, and the same
    "floor, not a measurement" caveat, the phase-1 re-audit used for its
    own >=20% orphan figure.
    """
    combined_parts = [texts[p] for p in all_files if p in texts]
    if manifest_text:
        combined_parts.append(manifest_text)
    combined_corpus = "\n".join(combined_parts)

    orphans: list[str] = []
    referenced_by_path = 0
    referenced_by_basename_fallback = 0

    for p in scope_files:
        text = texts.get(p)
        if text is None:
            continue
        rel_path = _rel(p)
        basename = p.name

        total_path_hits = combined_corpus.count(rel_path)
        self_path_hits = text.count(rel_path)
        mentioned_by_path = (total_path_hits - self_path_hits) > 0

        mentioned_by_basename = False
        if not mentioned_by_path:
            total_base_hits = combined_corpus.count(basename)
            self_base_hits = text.count(basename)
            mentioned_by_basename = (total_base_hits - self_base_hits) > 0

        if mentioned_by_path:
            referenced_by_path += 1
        elif mentioned_by_basename:
            referenced_by_basename_fallback += 1
        else:
            orphans.append(rel_path)

    n_scope = len(scope_files)
    n_orphans = len(orphans)
    orphan_rate = round(n_orphans / n_scope * 100, 2) if n_scope else None

    return {
        "definition": (
            "a scope file is 'referenced' if its full repo-relative path appears as a substring "
            "in any OTHER knowledge file (incl. _archive) or in knowledge-manifest.json; failing "
            "that, it falls back to a bare-basename substring match anywhere else in the same "
            "corpus. A file matching neither is counted an orphan."
        ),
        "n_candidates": n_scope,
        "n_referenced_by_full_relative_path": referenced_by_path,
        "n_referenced_by_basename_fallback_only": referenced_by_basename_fallback,
        "n_orphans": n_orphans,
        "orphan_rate_pct": orphan_rate,
        "headline": f"{orphan_rate}% ({n_orphans}/{n_scope})" if n_scope else "no scope files found",
        "orphan_files": sorted(orphans),
        "floor_caveat": (
            "basename fallback is permissive and structurally undercounts orphans (see this "
            "function's docstring) -- orphan_rate_pct is a FLOOR on the true orphan rate, not a "
            "point measurement, matching the phase-1 re-audit's own caveat on its >=20% figure"
        ),
    }


# ---------------------------------------------------------------------------
# Metric 6 — voice preservation of the repo's own content
# ---------------------------------------------------------------------------


def _load_voice_linter(errors: list[dict]) -> tuple[Optional[Callable[[Path, object], Optional[dict]]], object, str]:
    """Returns (lint_fn, rules, mode). lint_fn(path, rules) -> report dict
    or None (per-file failure, already logged to errors). Tries a direct
    import of benches/voice_lint/lint.py first (fast: no subprocess per
    file); falls back to subprocessing its CLI (`lint.py <file> --json`)
    if the import doesn't come up cleanly, per the task's own fallback
    instruction. lint.py itself is read-only here -- never modified.
    """
    try:
        if str(VOICE_LINT_DIR) not in sys.path:
            sys.path.insert(0, str(VOICE_LINT_DIR))
        import lint as voice_lint_module  # type: ignore

        rules = voice_lint_module.load_rules(voice_lint_module.DEFAULT_RULES_PATH)

        def _lint_via_import(path: Path, rules_obj: object) -> Optional[dict]:
            text = path.read_text(encoding="utf-8", errors="replace")
            return voice_lint_module.lint_text(text, rules_obj)

        return _lint_via_import, rules, "import"
    except Exception as exc:  # noqa: BLE001 -- any import/parse failure falls back to subprocess
        errors.append(
            {
                "item": "voice_lint_import",
                "error": f"direct import failed, falling back to subprocess CLI: {type(exc).__name__}: {exc}",
            }
        )

    lint_script = VOICE_LINT_DIR / "lint.py"
    if not lint_script.exists():
        errors.append({"item": "voice_lint_subprocess", "error": f"lint.py not found at {lint_script}"})
        return None, None, "unavailable"

    def _lint_via_subprocess(path: Path, _rules_unused: object) -> Optional[dict]:
        try:
            result = subprocess.run(
                ["python3", str(lint_script), str(path), "--json"],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
            errors.append({"item": "voice_lint_subprocess_call", "path": str(path), "error": f"{type(exc).__name__}: {exc}"})
            return None
        if result.returncode != 0:
            errors.append(
                {
                    "item": "voice_lint_subprocess_call",
                    "path": str(path),
                    "error": f"exit {result.returncode}: {result.stderr.strip()[:300]}",
                }
            )
            return None
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            errors.append({"item": "voice_lint_subprocess_call", "path": str(path), "error": f"invalid JSON: {exc}"})
            return None

    return _lint_via_subprocess, None, "subprocess"


def _metric_6_voice_preservation(errors: list[dict]) -> dict:
    company_root = KNOWLEDGE_ROOT / "01-company"
    company_files = sorted(company_root.rglob("*.md")) if company_root.is_dir() else []
    if not company_files:
        errors.append({"item": "voice_preservation", "error": f"no .md files found under {company_root}"})
        return {"available": False}

    lint_fn, rules, mode = _load_voice_linter(errors)
    if lint_fn is None:
        return {"available": False, "mode": mode}

    per_file: list[dict] = []
    total_violations = 0
    total_words = 0

    for p in company_files:
        rel = _rel(p)
        try:
            report = lint_fn(p, rules)
        except Exception as exc:  # noqa: BLE001 -- one bad file must not crash the whole metric
            errors.append({"item": "voice_lint_file", "path": rel, "error": f"{type(exc).__name__}: {exc}"})
            continue
        if report is None:
            continue
        per_file.append(
            {
                "file": rel,
                "word_count": report["word_count"],
                "total_violations": report["total_violations"],
                "total_violations_per_100_words": report["total_violations_per_100_words"],
                "categories": {k: v["count"] for k, v in report["categories"].items()},
            }
        )
        total_violations += report["total_violations"]
        total_words += report["word_count"]

    aggregate_per_100 = round(total_violations / total_words * 100, 3) if total_words else None
    top5 = sorted(
        per_file,
        key=lambda e: (-e["total_violations"], -(e["total_violations_per_100_words"] or 0.0)),
    )[:5]

    return {
        "definition": (
            "runs the compiled voice rubric linter (benches/voice_lint/lint.py, TASK-93/B-10) "
            "over every .md under 01-company/ -- the content that DEFINES company voice -- "
            "checked against its own rules (anti-pattern: rewriting company voice into generic "
            "consultant language)"
        ),
        "mode": mode,
        "n_files": len(per_file),
        "n_files_found": len(company_files),
        "total_words": total_words,
        "total_violations": total_violations,
        "aggregate_violations_per_100_words": aggregate_per_100,
        "top_5_offending_files": top5,
        "per_file": per_file,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def collect() -> dict:
    """Returns {"metrics": {...}, "errors": [...]}. The schema_version /
    collector / generated_at envelope is added by cse_bench.py, not here.
    """
    errors: list[dict] = []

    if not KNOWLEDGE_ROOT.is_dir():
        errors.append({"item": "knowledge_root", "path": str(KNOWLEDGE_ROOT), "error": "not a directory / not found"})
        return {"metrics": {"knowledge_root": str(KNOWLEDGE_ROOT), "available": False}, "errors": errors}

    scope_files = _iter_md_files(KNOWLEDGE_ROOT, exclude_archive=True)
    all_files = _iter_md_files(KNOWLEDGE_ROOT, exclude_archive=False)
    archive_files = sorted(set(all_files) - set(scope_files))

    texts: dict[Path, str] = {}
    for p in all_files:
        text = _read_text_safe(p, errors)
        if text is not None:
            texts[p] = text

    manifest_text = _read_text_safe(MANIFEST_JSON, errors) if MANIFEST_JSON.exists() else None

    all_links = _extract_all_links(scope_files, texts)

    registry = _metric_1_registry_integrity(errors)
    cross_link = _metric_2_cross_link_integrity(all_links)
    contradictions = _metric_3_contradictory_facts(all_files, texts, errors)
    staleness = _metric_4_staleness_archive_honesty(scope_files, archive_files, texts, all_links, errors)
    orphans = _metric_5_orphan_rate(scope_files, all_files, texts, manifest_text)
    voice = _metric_6_voice_preservation(errors)

    metrics = {
        "knowledge_root": str(KNOWLEDGE_ROOT),
        "scope": {
            "definition": (
                "*.md under knowledge-copilot, excluding .git/node_modules/storybook-static; "
                "_archive is excluded by default (metrics 1's forward check content, 2, 5, 6) "
                "and included where stated (metric 3 records archive hits for context; metric "
                "4 is specifically about active-vs-archive honesty)"
            ),
            "scope_file_count_excl_archive": len(scope_files),
            "all_file_count_incl_archive": len(all_files),
            "archive_file_count": len(archive_files),
        },
        "registry_integrity": registry,
        "cross_link_integrity": cross_link,
        "contradictory_facts": contradictions,
        "staleness_archive_honesty": staleness,
        "orphan_rate": orphans,
        "voice_preservation": voice,
    }
    return {"metrics": metrics, "errors": errors}
