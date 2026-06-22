#!/usr/bin/env bash

if ! command -v secret-tool >/dev/null 2>&1; then
  echo '{"error":"install libsecret (secret-tool missing)"}'
  exit 0
fi

tok_json=$(timeout 5 secret-tool lookup service gemini username antigravity 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$tok_json" ]; then
  echo '{"error":"not signed in (run: agy auth login)"}'
  exit 0
fi

tok=$(echo "$tok_json" | jq -r '.token.access_token // empty' 2>/dev/null)
if [ -z "$tok" ]; then
  echo '{"error":"not signed in (no access_token in keyring)"}'
  exit 0
fi

expiry=$(echo "$tok_json" | jq -r '.token.expiry // empty' 2>/dev/null)
if [ -n "$expiry" ]; then
  expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
  now_epoch=$(date +%s)
  if [ "$expiry_epoch" -le "$now_epoch" ]; then
    echo '{"error":"token expired (reopen Antigravity IDE to refresh)"}'
    exit 0
  fi
fi

UA='antigravity/cli/1.0.9 linux/x86_64'
resp=$(curl -s --max-time 10 \
  -X POST \
  -H "Authorization: Bearer $tok" \
  -H "User-Agent: $UA" \
  -H 'Content-Type: application/json' \
  -d '{}' \
  'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary' 2>/dev/null)

if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
  err_msg=$(echo "$resp" | jq -r '.error.message // .error.code // "API error"' 2>/dev/null)
  echo "{\"error\":\"${err_msg}\"}"
else
  echo "$resp" | jq -c '{groups: (.groups // [])}'
fi 2>/dev/null || echo '{"error":"unavailable (parse failed)"}'
