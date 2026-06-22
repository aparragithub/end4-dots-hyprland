#!/usr/bin/env bash

creds="$HOME/.claude/.credentials.json"

if [ ! -f "$creds" ]; then
  echo '{"error":"credentials file missing"}'
  exit 0
fi

tok=$(jq -r '.claudeAiOauth.accessToken' "$creds" 2>/dev/null)
sub=$(jq -r '.claudeAiOauth.subscriptionType' "$creds" 2>/dev/null)

if [ -z "$tok" ] || [ "$tok" = "null" ]; then
  echo '{"error":"no Claude token"}'
  exit 0
fi

curl -s --max-time 10 \
  -H "Authorization: Bearer $tok" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" \
  https://api.anthropic.com/api/oauth/usage \
  | jq -c --arg sub "$sub" '. + {subscriptionType:$sub}'
