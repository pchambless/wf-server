#!/bin/bash
# Shared helper, sourced by the other deploy-lib scripts. Runs one SQL
# statement against the droplet postgres via the server-query n8n webhook
# and prints the JSON body. Same contract as
# wf-agents/agents/tools/investigate/server-query: HTTP 200 with an empty
# body means the query FAILED, not "no rows" - a valid query with no rows
# comes back as the literal [{}].
pg_query() {
  local sql="$1"
  local payload response http_code body
  payload=$(jq -n --arg q "$sql" '{query: $q, params: {}, source: "deploy-lib"}')
  response=$(curl -s -w '\n%{http_code}' -X POST https://n8n.whatsfresh.app/webhook/server-query \
    -H "Content-Type: application/json" -d "$payload")
  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [ "$http_code" != "200" ]; then
    echo "pg_query: webhook returned HTTP $http_code: $body" >&2
    return 1
  fi
  if [ -z "${body//[[:space:]]/}" ]; then
    echo "pg_query: query failed (empty body) - $sql" >&2
    return 1
  fi
  printf '%s\n' "$body"
}

# Single-quote-escapes a value for embedding directly in SQL text.
esc_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}
