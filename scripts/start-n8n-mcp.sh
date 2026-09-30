#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
AGENTS_ENV="$(dirname "$REPO_DIR")/wf-agents/.env"

if [ -f "$AGENTS_ENV" ]; then
  export $(grep -v '^#' "$AGENTS_ENV" | grep -E '^(DEV_N8N_MCP_SERVER_TOKEN|PROD_N8N_MCP_SERVER_TOKEN)=' | xargs)
fi

token="${N8N_MCP_BEARER_TOKEN:-${DEV_N8N_MCP_SERVER_TOKEN:-${N8N_MCP_SERVER_TOKEN:-${N8N_API_KEY:-}}}}"

if [[ -z "$token" ]]; then
  echo "Set DEV_N8N_MCP_SERVER_TOKEN in wf-agents/.env (or N8N_MCP_BEARER_TOKEN/N8N_MCP_SERVER_TOKEN/N8N_API_KEY in .env) before starting the n8n MCP server." >&2
  exit 1
fi

exec npx -y supergateway \
  --streamableHttp https://n8n.whatsfresh.app/mcp-server/http \
  --header "authorization:Bearer ${token}"