#!/usr/bin/env bash
set -euo pipefail

direction="${1:-next}"
state_file="${XDG_RUNTIME_DIR:-/tmp}/hypr-alt-tab-state"
state_timeout_ms=1500

active_address="$(hyprctl activewindow -j | jq -r '.address // empty')"
mapfile -t windows < <(
  hyprctl clients -j | jq -r '
    [.[]
      | select(.mapped == true)
      | select(.hidden == false)
      | select(.workspace.name | startswith("special:") | not)
      | select(.address != "")]
    | sort_by(.focusHistoryID)
    | .[].address
  '
)

if (( ${#windows[@]} < 2 )); then
  rm -f "$state_file"
  exit 0
fi

now_ms="$(date +%s%3N)"
current_set="$(printf '%s\n' "${windows[@]}" | sort)"

use_state=false
if [[ -f "$state_file" ]]; then
  mapfile -t state_lines < "$state_file"
  last_ms="${state_lines[0]:-0}"
  saved_index="${state_lines[1]:-0}"
  saved_windows=("${state_lines[@]:2}")
  saved_set="$(printf '%s\n' "${saved_windows[@]}" | sort)"

  if (( now_ms - last_ms <= state_timeout_ms )) && [[ "$saved_set" == "$current_set" ]]; then
    windows=("${saved_windows[@]}")
    current_index="$saved_index"
    use_state=true
  fi
fi

if [[ "$use_state" == false ]]; then
  current_index=0
  for i in "${!windows[@]}"; do
    if [[ "${windows[$i]}" == "$active_address" ]]; then
      current_index="$i"
      break
    fi
  done
fi

if [[ "$direction" == "prev" ]]; then
  target_index=$(( (current_index - 1 + ${#windows[@]}) % ${#windows[@]} ))
else
  target_index=$(( (current_index + 1) % ${#windows[@]} ))
fi

target_address="${windows[$target_index]}"
{
  printf '%s\n' "$now_ms"
  printf '%s\n' "$target_index"
  printf '%s\n' "${windows[@]}"
} > "$state_file"

hyprctl dispatch "hl.dsp.focus({ window = 'address:${target_address}' })" >/dev/null
