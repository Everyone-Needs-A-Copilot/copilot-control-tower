#!/bin/zsh
set -euo pipefail

script_dir=${0:a:h}
source_file="$script_dir/2026-08-12-progress-evidence-review.md"
output_file="$script_dir/2026-08-12-progress-evidence-review.html"

pandoc "$source_file" \
  --standalone \
  --from=gfm \
  --to=html5 \
  --template="$script_dir/progress-report-template.html" \
  --css="$script_dir/progress-report.css" \
  --embed-resources \
  --metadata pagetitle="Initiative 06 — Progress and Acceptance Evidence" \
  --output="$output_file"

print "Built ${output_file#$script_dir/} from ${source_file#$script_dir/}"
