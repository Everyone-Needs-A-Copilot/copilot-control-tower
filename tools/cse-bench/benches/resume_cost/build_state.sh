#!/bin/bash
# build_state.sh — regenerates fixture/state_block.txt (TASK-107/S-1).
#
# Captures the WITH-STATE arm's injected context as REAL Task Copilot (tc)
# and Memory Copilot (cc memory) CLI output, not invented prose. Mirrors
# what .claude/commands/continue.md's Step 1 ("Load Context (Slim)")
# actually runs: `tc progress` for Task Copilot status, plus Memory Copilot
# entries (a decision, a lesson, a current-focus context entry, using the
# exact "Focus: <what>. Next: TASK-xxx — <next step>" format continue.md's
# "End of Session" section specifies).
#
# Runs entirely inside a throwaway temp directory: `git init` there first
# so `cc memory store`'s default project-scope resolves to that temp repo's
# own .claude/memory, never this repo's or the global ~/.claude/memory
# store. Nothing here touches this repo's real Task/Memory Copilot state.
#
# Usage: ./build_state.sh   (writes fixture/state_block.txt, overwriting it)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="$SCRIPT_DIR/fixture/state_block.txt"

TMP_DIR="$(mktemp -d /tmp/cse-bench-resume-cost-state.XXXXXX)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

cd "$TMP_DIR"
git init -q

tc init >/dev/null

TASK_JSON="$(tc task create \
  --title "Refactor invoice_tools: split utils.py into validators/transformers/exporters modules" \
  --description "Step 1 done: extracted validate_invoice_row() and normalize_currency() out of utils.py into new validators.py; main.py now imports from validators. Next: step 2: extract aggregate_totals() and dedupe_invoices() out of utils.py into a new transformers.py module. Step 3 (later): move write_report() into exporters.py." \
  --priority 1 \
  --json)"
TASK_ID="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['id'])" "$TASK_JSON")"

tc task update "$TASK_ID" --status in_progress --agent claude --json >/dev/null

cc memory store --type context \
  "Focus: refactoring invoice_tools out of the monolithic utils.py into single-responsibility modules (validators.py done). Next: TASK-${TASK_ID} — extract aggregate_totals() and dedupe_invoices() out of utils.py into a new transformers.py module." \
  --json >/dev/null

cc memory store --type decision \
  "Extract validators before transformers: validators.py has no dependency on aggregation state, so pulling it out first keeps main.py's import chain stable while utils.py still holds the yet-to-be-extracted aggregate_totals()/dedupe_invoices() functions." \
  --json >/dev/null

cc memory store --type lesson \
  "utils.py's old validate_invoice_row() mutated the row dict it validated in place — dedupe_invoices(), which runs right after validation in main.py's pipeline, was seeing already-mutated rows. Fixed by having validators.py return a new dict instead. [context: invoice_tools refactor; the same non-mutating discipline applies to the step-2 extraction of aggregate_totals()/dedupe_invoices() into transformers.py.]" \
  --json >/dev/null

{
  echo "## Task Copilot — progress (\`tc progress\`)"
  echo '```'
  tc progress
  echo '```'
  echo
  echo "## Memory Copilot — current focus (\`cc memory list --type context --json\`)"
  echo '```json'
  cc memory list --type context --json
  echo '```'
  echo
  echo "## Memory Copilot — recent decision (\`cc memory list --type decision --json\`)"
  echo '```json'
  cc memory list --type decision --json
  echo '```'
  echo
  echo "## Memory Copilot — lesson learned (\`cc memory list --type lesson --json\`)"
  echo '```json'
  cc memory list --type lesson --json
  echo '```'
} > "$OUT_FILE"

echo "build_state.sh: wrote $OUT_FILE (from throwaway store at $TMP_DIR, task id $TASK_ID)"
