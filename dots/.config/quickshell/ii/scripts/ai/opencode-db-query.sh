#!/usr/bin/env bash

db="$HOME/.local/share/opencode/opencode.db"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo '{"error":"sqlite3 not found — install sqlite"}'
  exit 0
fi

if [ ! -f "$db" ]; then
  echo '{"error":"no OpenCode usage data (~/.local/share/opencode/opencode.db not found)"}'
  exit 0
fi

t0=$(date -d 'today 00:00' +%s 2>/dev/null || date -v0H -v0M -v0S +%s)000
w0=$(date -d '7 days ago 00:00' +%s 2>/dev/null || date -v-7d -v0H -v0M -v0S +%s)000
m0=$(date -d 'this month 00:00' +%s 2>/dev/null || date -v1d -v0H -v0M -v0S +%s)000

sel="SELECT json_extract(data,'$.modelID') AS model, MIN(json_extract(data,'$.providerID')) AS provider, ROUND(SUM(COALESCE(json_extract(data,'$.cost'),0)),6) AS cost, CAST(SUM(COALESCE(json_extract(data,'$.tokens.total'),0)) AS INTEGER) AS tokens, SUM(COALESCE(json_extract(data,'$.tokens.input'),0)) AS tok_input, SUM(COALESCE(json_extract(data,'$.tokens.output'),0)) AS tok_output, SUM(COALESCE(json_extract(data,'$.tokens.reasoning'),0)) AS tok_reasoning, SUM(COALESCE(json_extract(data,'$.tokens.cache.read'),0)) AS tok_cache_read, SUM(COALESCE(json_extract(data,'$.tokens.cache.write'),0)) AS tok_cache_write FROM message WHERE json_extract(data,'$.modelID') IS NOT NULL"

q_today="$sel AND time_created >= $t0 GROUP BY model ORDER BY cost DESC"
q_week="$sel AND time_created >= $w0 GROUP BY model ORDER BY cost DESC"
q_month="$sel AND time_created >= $m0 GROUP BY model ORDER BY cost DESC"

today_json=$(sqlite3 -json "file:${db}?mode=ro" "$q_today" 2>/dev/null)
today_json=${today_json:-[]}

week_json=$(sqlite3 -json "file:${db}?mode=ro" "$q_week" 2>/dev/null)
week_json=${week_json:-[]}

month_json=$(sqlite3 -json "file:${db}?mode=ro" "$q_month" 2>/dev/null)
month_json=${month_json:-[]}

printf '{"today":%s,"week":%s,"month":%s}' "$today_json" "$week_json" "$month_json"
