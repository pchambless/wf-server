#!/bin/bash
# commit-export.sh <path> <message>
# Commit ONLY <path> (an export script's output folder) when the export changed it.
# Export files are machine-generated copies of live dev, so they get their own commit
# and can never sweep up anyone's unrelated work: other changes in the checkout,
# staged or not, are left exactly as they were. Does not push.
#
# Opt out for one run: EXPORT_NO_COMMIT=1 <export script> ...
set -e
P="$1"; MSG="$2"
[ -n "$P" ] && [ -n "$MSG" ] || { echo "usage: commit-export.sh <path> <message>" >&2; exit 1; }
if [ "${EXPORT_NO_COMMIT:-}" = "1" ]; then
  echo "[commit-export] skipped (EXPORT_NO_COMMIT=1) - remember to commit $P"
  exit 0
fi
cd "$(git -C "$(dirname "$P")" rev-parse --show-toplevel)"
git add -A -- "$P"
if git diff --cached --quiet -- "$P"; then
  echo "[commit-export] $P unchanged - nothing to commit"
  exit 0
fi
git commit -q -m "$MSG" -- "$P"
echo "[commit-export] committed $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD): $MSG (not pushed)"
