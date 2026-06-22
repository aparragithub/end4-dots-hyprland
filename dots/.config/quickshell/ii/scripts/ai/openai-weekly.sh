#!/usr/bin/env bash

base="$HOME/.codex/sessions"

find "$base" -type f -name 'rollout-*.jsonl' -mtime -8 -printf '%p\n' 2>/dev/null |
while read f; do
  d=$(echo "$f" | grep -oE '[0-9]{4}/[0-9]{2}/[0-9]{2}' | head -1 | tr / -)
  last=$(grep -F '"type":"token_count"' "$f" | tail -1)
  [ -n "$d" ] && [ -n "$last" ] && echo "$last" | jq -c --arg date "$d" '(.payload.info.total_token_usage // {}) + {date: $date, model_id: (.payload.info.model_id // .payload.model_id // "gpt-5-codex")}'
done | jq -s '.'
