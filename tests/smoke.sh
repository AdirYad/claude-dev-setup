#!/usr/bin/env bash
# Smoke test: the installer must parse and complete a dry run with exit 0,
# without touching the system.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
script="$here/install.sh"

echo "== bash -n (syntax) =="
bash -n "$script"

echo "== --help =="
bash "$script" --help >/dev/null

echo "== --dry-run =="
out="$(bash "$script" --dry-run 2>&1)"
echo "$out"

echo "$out" | grep -qi "DRY RUN" || { echo "FAIL: dry-run banner missing"; exit 1; }

echo "PASS: install.sh dry run completed cleanly"
