#!/bin/bash
# Verify every {{{template:field}}} dropdown-enrichment token actually renders
# with populated <select> options, using the exact same hydrate-guide webhook
# wf-server (and the Appsmith Templates tool) already call to render a form.
#
# WHY THIS EXISTS (found 2026-08-21, task 270 follow-on): a dropdown can go
# silently empty for reasons that live at completely different layers - a
# workflow node hardcoded to the wrong environment's webhook, a missing
# page_components row, a hydrate query that legitimately returns zero rows
# for the test account - and the render path (styled-html's L03-html node)
# swallows ALL of them the same way: either the <select> comes back empty,
# or the whole token silently vanishes with no <select> at all. Nothing
# errors, nothing logs. f_n8n_diff cannot catch this class of bug by design
# (see import-n8n-workflows.sh's header) - a workflow can be byte-identical
# between dev and prod and still be wrong for prod specifically, because
# dev's own copy is correctly self-referencing and prod's isn't.
#
# For every studio.html_templates row containing a {{{template:field}}} token:
#   1. count expected tokens from the template's own html column
#   2. POST {template_name, source:'wf-server', email} to hydrate-guide
#   3. count actual <select> elements in the response, and <option>s per select
#   4. FAIL if select count < expected token count (a dropdown vanished)
#      FAIL if any select has zero <option> elements (a dropdown is empty)
#
# Usage: check-dropdown-health.sh [dev|prod|all] [test-email]
#   Default: all, testbed@whatsfresh.app (account 3 "Test Bed" - a dedicated
#   fixture account seeded by setup-test-bed.sh, deliberately labeled and
#   scoped to account_id=3 only. Previously defaulted to pc7900@gmail.com,
#   which only worked because that real account happened to already have
#   every context key populated from ordinary use - not a fixture, a
#   coincidence. Run setup-test-bed.sh first if this account is missing.
#
# Requires: curl, jq

set -e

SCOPE="${1:-all}"
TEST_EMAIL="${2:-testbed@whatsfresh.app}"
SERVER_QUERY_URL="https://n8n.whatsfresh.app/webhook/server-query"

declare -A ENV_URLS=( [dev]="https://n8n.whatsfresh.app" [prod]="https://v2-n8n.whatsfresh.app" )

case "$SCOPE" in
  dev|prod) TARGETS=("$SCOPE") ;;
  all)      TARGETS=(dev prod) ;;
  *) echo "Usage: check-dropdown-health.sh [dev|prod|all] [test-email]" >&2; exit 1 ;;
esac

echo "[dropdown-check] Finding templates with {{{template:field}}} tokens..."
SQL='SELECT name, html FROM studio.html_templates WHERE html ~ '"'"'\{\{\{[a-zA-Z0-9_]+:[a-zA-Z0-9_]+\}\}\}'"'"''
TEMPLATES_QUERY=$(jq -n --arg q "$SQL" '{query: $q, params: {}, source: "check-dropdown-health"}')
TEMPLATES=$(curl -s -X POST "$SERVER_QUERY_URL" -H "Content-Type: application/json" -d "$TEMPLATES_QUERY")

TEMPLATE_NAMES=$(echo "$TEMPLATES" | jq -r '.[].name' 2>/dev/null)
if [ -z "$TEMPLATE_NAMES" ]; then
  echo "[dropdown-check] No templates with dropdown tokens found (or query failed): $TEMPLATES"
  exit 1
fi

TOTAL_FAIL=0
TOTAL_CHECKED=0

for TPL in $TEMPLATE_NAMES; do
  HTML_SRC=$(echo "$TEMPLATES" | jq -r --arg n "$TPL" '.[] | select(.name==$n) | .html')
  EXPECTED=$(echo "$HTML_SRC" | grep -oE '\{\{\{[a-zA-Z0-9_]+:[a-zA-Z0-9_]+\}\}\}' | wc -l)

  for ENV in "${TARGETS[@]}"; do
    BASE_URL="${ENV_URLS[$ENV]}"
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    PAYLOAD=$(jq -n --arg t "$TPL" --arg e "$TEST_EMAIL" '{template_name: $t, source: "wf-server", email: $e}')
    RESPONSE=$(curl -s -X POST "$BASE_URL/webhook/hydrate-guide" -H "Content-Type: application/json" -d "$PAYLOAD")
    HTML_OUT=$(echo "$RESPONSE" | jq -r '.[0].html // empty')

    if [ -z "$HTML_OUT" ]; then
      echo "[dropdown-check] FAIL  $TPL ($ENV): hydrate-guide returned no html - $(echo "$RESPONSE" | head -c 200)"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      continue
    fi

    ACTUAL_SELECTS=$(echo "$HTML_OUT" | grep -oE '<select[^>]*>' | wc -l)

    if [ "$ACTUAL_SELECTS" -lt "$EXPECTED" ]; then
      echo "[dropdown-check] FAIL  $TPL ($ENV): expected $EXPECTED dropdown(s), only $ACTUAL_SELECTS <select> rendered - one or more vanished"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      continue
    fi

    EMPTY_SELECTS=$(echo "$HTML_OUT" | python3 -c "
import sys, re
html = sys.stdin.read()
empties = []
for m in re.finditer(r'<select[^>]*id=\"([^\"]*)\"[^>]*>(.*?)</select>', html, re.S):
    if '<option' not in m.group(2):
        empties.append(m.group(1))
print(','.join(empties))
")

    if [ -n "$EMPTY_SELECTS" ]; then
      echo "[dropdown-check] FAIL  $TPL ($ENV): empty <select> with no options: $EMPTY_SELECTS"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      continue
    fi

    echo "[dropdown-check] OK    $TPL ($ENV): $ACTUAL_SELECTS/$EXPECTED dropdowns rendered, all populated"
  done
done

echo ""
echo "[dropdown-check] Done. Checked: $TOTAL_CHECKED, Failed: $TOTAL_FAIL"
[ "$TOTAL_FAIL" -eq 0 ]
