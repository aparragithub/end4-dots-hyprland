#!/usr/bin/env bash

base="$HOME/.codex/sessions"
f=$(find "$base" -type f -name 'rollout-*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)

if [ -z "$f" ]; then
  echo '{"error":"no codex sessions"}'
  exit 0
fi

last=$(grep -F '"type":"token_count"' "$f" | tail -1)

if [ -z "$last" ]; then
  echo '{"error":"no usage yet"}'
  exit 0
fi

echo "$last" | jq -c '{
  rate_limits: .payload.rate_limits,
  session_tokens: .payload.info.total_token_usage,
  model_id: (.payload.info.model_id // .payload.model_id // "gpt-5-codex")
}'
