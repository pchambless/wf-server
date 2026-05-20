#!/usr/bin/env bash
set -euo pipefail

token="${N8N_MCP_BEARER_TOKEN:-${N8N_MCP_SERVER_TOKEN:-${N8N_API_KEY:-}}}"

if [[ -z "$token" ]]; then
  echo "Set N8N_MCP_BEARER_TOKEN, N8N_MCP_SERVER_TOKEN, or N8N_API_KEY in .env before starting the n8n MCP server." >&2
  exit 1
fi

exec npx -y supergateway \
  --streamableHttp https://n8n.whatsfresh.app/mcp-server/http \
  --header "authorization:Bearer ${token}"